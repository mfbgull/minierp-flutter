/**
 * TASK 16 — P11: invoice creation must be idempotent.
 *
 * A client timeout after the server committed must not double-create:
 * same Idempotency-Key + same payload replays the original invoice (one
 * document, one stock consumption, one GL group, one ledger row, one
 * payment); same key + different payload is rejected; distinct keys
 * create distinct legitimate invoices.
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { getAuthCookie, createItem, purchaseStock, createCustomer } from './helpers/invoiceReturnSpec';

function count(sql: string, ...params: unknown[]): number {
  return (db.prepare(sql).get(...params) as { c: number }).c;
}

function stockOnHand(itemId: number): number {
  return (db.prepare('SELECT COALESCE(SUM(quantity_remaining), 0) as s FROM stock_batches WHERE item_id = ?')
    .get(itemId) as { s: number }).s;
}

describe('P11: idempotent invoice creation', () => {
  let authCookie: string;
  let itemId: number;
  let customerId: number;
  let warehouseId: number;
  const runId = Date.now();
  const key1 = `p11-${runId}-one`;
  const key2 = `p11-${runId}-two`;

  function body(qty: number) {
    return {
      customer_id: customerId,
      invoice_date: '2026-09-05',
      due_date: '2026-09-19',
      items: [{
        item_id: itemId,
        description: 'P11 Item',
        quantity: qty,
        unit_price: 100,
        tax_rate: 0,
        discount_type: 'none',
        discount_value: 0,
      }],
      total_amount: qty * 100,
      record_payment: true,
      payment: { payment_date: '2026-09-05', amount: qty * 100, payment_method: 'Cash' },
    };
  }

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    const wh = db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number };
    warehouseId = wh.id;
    itemId = await createItem('Widget P11', authCookie);
    await purchaseStock(itemId, warehouseId, 10, 10, authCookie);
    customerId = await createCustomer('P11 Customer', authCookie);
  });

  it('replays the original result for the same key + payload, touching nothing twice', async () => {
    const first = await request(app).post('/api/invoices')
      .set('Idempotency-Key', key1)
      .set('Cookie', authCookie)
      .send(body(2));
    expect(first.status).toBe(201);
    const invoiceId: number = first.body.id;
    const invoiceNo: string = first.body.invoice_no;

    const movements = count('SELECT COUNT(*) as c FROM stock_movements WHERE reference_doctype = ? AND reference_docno = ?', 'INVOICE', invoiceNo);
    const glLines = count("SELECT COUNT(*) as c FROM journal_lines WHERE reference_type = 'INVOICE' AND reference_id = ? AND voided = 0", invoiceId);
    const ledgerRows = count('SELECT COUNT(*) as c FROM customer_ledger WHERE reference_no = ? AND transaction_type = ?', invoiceNo, 'INVOICE');
    const payments = count('SELECT COUNT(*) as c FROM payments p JOIN payment_allocations pa ON pa.payment_id = p.id WHERE pa.invoice_id = ? AND pa.voided_at IS NULL', invoiceId);
    const stock = stockOnHand(itemId);
    expect(movements).toBeGreaterThan(0);
    expect(glLines).toBeGreaterThan(0);

    // Simulated retry: the client timed out but the commit succeeded.
    const retry = await request(app).post('/api/invoices')
      .set('Idempotency-Key', key1)
      .set('Cookie', authCookie)
      .send(body(2));

    expect(retry.status).toBe(201);
    expect(retry.body.id).toBe(invoiceId);
    expect(retry.headers['x-idempotent-replay']).toBe('true');

    expect(count('SELECT COUNT(*) as c FROM invoices WHERE customer_id = ?', customerId)).toBe(1);
    expect(stockOnHand(itemId)).toBe(stock);                 // stock consumed once
    expect(count('SELECT COUNT(*) as c FROM stock_movements WHERE reference_doctype = ? AND reference_docno = ?', 'INVOICE', invoiceNo)).toBe(movements);
    expect(count("SELECT COUNT(*) as c FROM journal_lines WHERE reference_type = 'INVOICE' AND reference_id = ? AND voided = 0", invoiceId)).toBe(glLines); // GL posted once
    expect(count('SELECT COUNT(*) as c FROM customer_ledger WHERE reference_no = ? AND transaction_type = ?', invoiceNo, 'INVOICE')).toBe(ledgerRows);
    expect(count('SELECT COUNT(*) as c FROM payments p JOIN payment_allocations pa ON pa.payment_id = p.id WHERE pa.invoice_id = ? AND pa.voided_at IS NULL', invoiceId)).toBe(payments);
    // The replay response carries the same monetary payload.
    expect(retry.body.total_amount).toBe(first.body.total_amount);
    expect(retry.body.paid_amount).toBe(first.body.paid_amount);
  });

  it('rejects the same key with a materially different payload', async () => {
    const res = await request(app).post('/api/invoices')
      .set('Idempotency-Key', key1)
      .set('Cookie', authCookie)
      .send(body(3));
    expect(res.status).toBe(409);
    expect(String(res.body.error)).toMatch(/idempotency/i);
    // Nothing created.
    expect(count('SELECT COUNT(*) as c FROM invoices WHERE customer_id = ?', customerId)).toBe(1);
  });

  it('creates separate invoices under two different keys', async () => {
    const stockBefore = stockOnHand(itemId);

    const a = await request(app).post('/api/invoices')
      .set('Idempotency-Key', key2)
      .set('Cookie', authCookie)
      .send(body(2));
    expect(a.status).toBe(201);
    expect(a.body.id).not.toBe(
      (db.prepare('SELECT id FROM invoices WHERE customer_id = ? ORDER BY id LIMIT 1').get(customerId) as { id: number }).id,
    );

    const b = await request(app).post('/api/invoices')
      .set('Cookie', authCookie)
      .send(body(2)); // keyless legacy client — still works
    expect(b.status).toBe(201);

    expect(count('SELECT COUNT(*) as c FROM invoices WHERE customer_id = ?', customerId)).toBe(3);
    expect(stockOnHand(itemId)).toBe(stockBefore - 4); // key2 + keyless each consumed 2
  });

  it('rejects a malformed idempotency key with 400', async () => {
    const res = await request(app).post('/api/invoices')
      .set('Idempotency-Key', 'short')
      .set('Cookie', authCookie)
      .send(body(1));
    expect(res.status).toBe(400);
    expect(String(res.body.error)).toMatch(/Idempotency-Key/);
    expect(count('SELECT COUNT(*) as c FROM invoices WHERE customer_id = ?', customerId)).toBe(3);
  });

  it('a failed create leaves the key unclaimed so a corrected retry runs', async () => {
    const key = `p11-${runId}-failthenfix`;
    // More stock than exists → the sellable-stock guard aborts the whole
    // transaction, so the key must not be claimed.
    const bad = await request(app).post('/api/invoices')
      .set('Idempotency-Key', key)
      .set('Cookie', authCookie)
      .send(body(10000));
    expect(bad.status).toBeGreaterThanOrEqual(400);
    expect(count('SELECT COUNT(*) as c FROM idempotency_keys WHERE key = ?', key)).toBe(0);

    const good = await request(app).post('/api/invoices')
      .set('Idempotency-Key', key)
      .set('Cookie', authCookie)
      .send(body(2));
    expect(good.status).toBe(201);
    const replay = await request(app).post('/api/invoices')
      .set('Idempotency-Key', key)
      .set('Cookie', authCookie)
      .send(body(2));
    expect(replay.status).toBe(201);
    expect(replay.body.id).toBe(good.body.id);
  });
});

describe('P11: idempotent mobile invoice submit', () => {
  let authCookie: string;
  let itemId: number;
  let customerId: number;
  const runId = Date.now();
  const mKey1 = `p11m-${runId}-one`;
  const mKey2 = `p11m-${runId}-two`;

  function mobileBody(qty: number) {
    return {
      customer_id: customerId,
      invoice_date: '2026-09-05',
      due_date: '2026-09-19',
      items: [{
        item_id: itemId,
        quantity: qty,
        unit_price: 100,
        tax_rate: 0,
        discount_type: 'percentage',
        discount_value: 0,
      }],
      record_payment: true,
      payment: { payment_date: '2026-09-05', amount: qty * 100, payment_method: 'Cash' },
    };
  }

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    const wh = db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number };
    itemId = await createItem('Widget P11 Mobile', authCookie);
    await purchaseStock(itemId, wh.id, 10, 10, authCookie);
    customerId = await createCustomer('P11 Mobile Customer', authCookie);
  });

  it('replays the original result for the same key + payload, touching nothing twice', async () => {
    const first = await request(app).post('/api/mobile-invoices/submit')
      .set('Idempotency-Key', mKey1)
      .set('Cookie', authCookie)
      .send(mobileBody(2));
    expect(first.status).toBe(201);
    const invoiceId: number = first.body.data.id;
    const invoiceNo: string = first.body.data.invoice_no;

    // TASK 17: stock movements now key to invoice_no on every path
    // (mobile wrote the invoice ID before, which the cancel/return
    // reversal never resolved), so the replay check reads the same key
    // as the desktop case above.
    const movements = count('SELECT COUNT(*) as c FROM stock_movements WHERE reference_doctype = ? AND reference_docno = ?', 'INVOICE', invoiceNo);
    const glLines = count("SELECT COUNT(*) as c FROM journal_lines WHERE reference_type = 'INVOICE' AND reference_id = ? AND voided = 0", invoiceId);
    const ledgerRows = count('SELECT COUNT(*) as c FROM customer_ledger WHERE reference_no = ? AND transaction_type = ?', invoiceNo, 'INVOICE');
    const payments = count('SELECT COUNT(*) as c FROM payments WHERE invoice_id = ?', invoiceId);
    const stock = stockOnHand(itemId);
    expect(movements).toBeGreaterThan(0);
    expect(glLines).toBeGreaterThan(0);

    // Simulated retry: the client timed out but the commit succeeded.
    const retry = await request(app).post('/api/mobile-invoices/submit')
      .set('Idempotency-Key', mKey1)
      .set('Cookie', authCookie)
      .send(mobileBody(2));

    expect(retry.status).toBe(201);
    expect(retry.body.data.id).toBe(invoiceId);
    expect(retry.headers['x-idempotent-replay']).toBe('true');

    expect(count('SELECT COUNT(*) as c FROM invoices WHERE customer_id = ?', customerId)).toBe(1);
    expect(stockOnHand(itemId)).toBe(stock); // stock consumed once
    expect(count('SELECT COUNT(*) as c FROM stock_movements WHERE reference_doctype = ? AND reference_docno = ?', 'INVOICE', invoiceNo)).toBe(movements);
    expect(count("SELECT COUNT(*) as c FROM journal_lines WHERE reference_type = 'INVOICE' AND reference_id = ? AND voided = 0", invoiceId)).toBe(glLines);
    expect(count('SELECT COUNT(*) as c FROM customer_ledger WHERE reference_no = ? AND transaction_type = ?', invoiceNo, 'INVOICE')).toBe(ledgerRows);
    expect(count('SELECT COUNT(*) as c FROM payments WHERE invoice_id = ?', invoiceId)).toBe(payments);
    expect(retry.body.data.total_amount).toBe(first.body.data.total_amount);
    expect(retry.body.data.paid_amount).toBe(first.body.data.paid_amount);
  });

  it('rejects the same key with a materially different payload', async () => {
    const res = await request(app).post('/api/mobile-invoices/submit')
      .set('Idempotency-Key', mKey1)
      .set('Cookie', authCookie)
      .send(mobileBody(3));
    expect(res.status).toBe(409);
    expect(String(res.body.error)).toMatch(/idempotency/i);
    expect(count('SELECT COUNT(*) as c FROM invoices WHERE customer_id = ?', customerId)).toBe(1);
  });

  it('creates separate invoices under two different keys', async () => {
    const stockBefore = stockOnHand(itemId);

    const a = await request(app).post('/api/mobile-invoices/submit')
      .set('Idempotency-Key', mKey2)
      .set('Cookie', authCookie)
      .send(mobileBody(2));
    expect(a.status).toBe(201);

    const b = await request(app).post('/api/mobile-invoices/submit')
      .set('Cookie', authCookie)
      .send(mobileBody(2)); // keyless legacy client — still works
    expect(b.status).toBe(201);
    expect(b.body.data.id).not.toBe(a.body.data.id);

    expect(count('SELECT COUNT(*) as c FROM invoices WHERE customer_id = ?', customerId)).toBe(3);
    expect(stockOnHand(itemId)).toBe(stockBefore - 4); // key2 + keyless each consumed 2
  });
});

describe('P11: idempotent POS sale', () => {
  let authCookie: string;
  let itemId: number;
  let warehouseId: number;
  const runId = Date.now();
  const pKey1 = `p11p-${runId}-one`;
  const pKey2 = `p11p-${runId}-two`;

  function posBody(qty: number) {
    return {
      warehouse_id: warehouseId,
      sale_date: '2026-09-05',
      items: [{ item_id: itemId, quantity: qty, unit_price: 100 }],
      cash_received: qty * 100,
    };
  }

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    const wh = db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number };
    warehouseId = wh.id;
    itemId = await createItem('Widget P11 POS', authCookie);
    await purchaseStock(itemId, warehouseId, 10, 10, authCookie);
  });

  it('replays the original result for the same key + payload, touching nothing twice', async () => {
    const first = await request(app).post('/api/pos/sale')
      .set('Idempotency-Key', pKey1)
      .set('Cookie', authCookie)
      .send(posBody(2));
    expect(first.status).toBe(201);
    const transactionNo: string = first.body.data.transaction_no;
    const invoiceId: number = first.body.data.sale_ids[0];

    const movements = count('SELECT COUNT(*) as c FROM stock_movements WHERE reference_doctype = ? AND reference_docno = ?', 'POS', transactionNo);
    const glLines = count("SELECT COUNT(*) as c FROM journal_lines WHERE reference_type = 'INVOICE' AND reference_id = ? AND voided = 0", invoiceId);
    const ledgerRows = count('SELECT COUNT(*) as c FROM customer_ledger WHERE reference_no = ? AND transaction_type = ?', transactionNo, 'INVOICE');
    const payments = count('SELECT COUNT(*) as c FROM payments p JOIN payment_allocations pa ON pa.payment_id = p.id WHERE pa.invoice_id = ? AND pa.voided_at IS NULL', invoiceId);
    const stock = stockOnHand(itemId);
    expect(movements).toBeGreaterThan(0);
    expect(glLines).toBeGreaterThan(0);

    // Simulated retry: the client timed out but the commit succeeded.
    const retry = await request(app).post('/api/pos/sale')
      .set('Idempotency-Key', pKey1)
      .set('Cookie', authCookie)
      .send(posBody(2));

    expect(retry.status).toBe(201);
    expect(retry.headers['x-idempotent-replay']).toBe('true');
    expect(retry.body.data.transaction_no).toBe(transactionNo);
    expect(retry.body.data.sale_ids[0]).toBe(invoiceId);

    expect(count("SELECT COUNT(*) as c FROM invoices WHERE source_type = 'POS' AND invoice_no = ?", transactionNo)).toBe(1);
    expect(stockOnHand(itemId)).toBe(stock); // stock consumed once
    expect(count('SELECT COUNT(*) as c FROM stock_movements WHERE reference_doctype = ? AND reference_docno = ?', 'POS', transactionNo)).toBe(movements);
    expect(count("SELECT COUNT(*) as c FROM journal_lines WHERE reference_type = 'INVOICE' AND reference_id = ? AND voided = 0", invoiceId)).toBe(glLines);
    expect(count('SELECT COUNT(*) as c FROM customer_ledger WHERE reference_no = ? AND transaction_type = ?', transactionNo, 'INVOICE')).toBe(ledgerRows);
    expect(count('SELECT COUNT(*) as c FROM payments p JOIN payment_allocations pa ON pa.payment_id = p.id WHERE pa.invoice_id = ? AND pa.voided_at IS NULL', invoiceId)).toBe(payments);
    // The replayed response carries the same money, including change.
    expect(retry.body.data.total).toBe(first.body.data.total);
    expect(retry.body.data.cash_received).toBe(first.body.data.cash_received);
    expect(retry.body.data.change).toBe(first.body.data.change);
  });

  it('rejects the same key with a materially different payload', async () => {
    const res = await request(app).post('/api/pos/sale')
      .set('Idempotency-Key', pKey1)
      .set('Cookie', authCookie)
      .send(posBody(3));
    expect(res.status).toBe(409);
    expect(String(res.body.error)).toMatch(/idempotency/i);
    expect(count("SELECT COUNT(*) as c FROM invoices WHERE source_type = 'POS'")).toBe(1);
  });

  it('creates separate sales under two different keys', async () => {
    const stockBefore = stockOnHand(itemId);

    const a = await request(app).post('/api/pos/sale')
      .set('Idempotency-Key', pKey2)
      .set('Cookie', authCookie)
      .send(posBody(2));
    expect(a.status).toBe(201);

    const b = await request(app).post('/api/pos/sale')
      .set('Cookie', authCookie)
      .send(posBody(2)); // keyless legacy client — still works
    expect(b.status).toBe(201);
    expect(b.body.data.transaction_no).not.toBe(a.body.data.transaction_no);

    expect(count("SELECT COUNT(*) as c FROM invoices WHERE source_type = 'POS'")).toBe(3);
    expect(stockOnHand(itemId)).toBe(stockBefore - 4); // key2 + keyless each consumed 2
  });
});
