/**
 * ACCT-008 / D19 — the Idempotency-Key mandate.
 *
 * A missing key is a 400 on the canonical financial writes: invoice create,
 * customer and supplier payments, payment allocation, purchase-order goods
 * receipts, sales returns and return settlement. The deprecated
 * /api/mobile-invoices/* surface stays keyless-compatible (D13's promise to
 * the external mobile app). Supplier-refund writes were already mandatory
 * (PRET-002) and are covered by supplierRefundValidation.test.ts.
 *
 * Written FAILING-FIRST against the D19 decision: every mandate case below
 * returned 201/200 keyless before the flip.
 */
import request from 'supertest';
import { beforeAll, describe, expect, it, jest } from '@jest/globals';
import app from '../app';
import db from '../config/database';
import logger from '../utils/logger';
import { createCustomer, createItem, getAuthCookie, purchaseStock, resolveSupplierByName } from './helpers/invoiceReturnSpec';

const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD) {
  throw new Error('TEST_ADMIN_PASSWORD environment variable must be set.');
}

const MANDATE_MESSAGE = /idempotency-key header is required/i;

let seq = 0;
function key(): string {
  seq += 1;
  return `mandate-${Date.now()}-${seq}`;
}

describe('ACCT-008 D19 — Idempotency-Key is mandatory on canonical financial writes', () => {
  let authCookie: string;
  let warehouseId: number;
  let itemId: number;
  let customerId: number;
  let supplierId: number;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
    itemId = await createItem('Idem Mandate Item', authCookie);
    await purchaseStock(itemId, warehouseId, 500, 10, authCookie);
    customerId = await createCustomer('Idem Mandate Customer', authCookie);
  });

  it('rejects a keyless invoice creation with 400 and accepts a keyed one', async () => {
    const payload = {
      customer_id: customerId,
      invoice_date: '2026-11-01',
      warehouse_id: warehouseId,
      items: [{ item_id: itemId, quantity: 1, unit_price: 50, tax_rate: 0 }],
    };
    const keyless = await request(app).post('/api/invoices').set('Cookie', authCookie).send(payload);
    expect(keyless.status).toBe(400);
    expect((keyless.body as { error: string }).error).toMatch(MANDATE_MESSAGE);

    const keyed = await request(app)
      .post('/api/invoices')
      .set('Cookie', authCookie)
      .set('Idempotency-Key', key())
      .send(payload);
    expect(keyed.status).toBe(201);
  });

  it('keeps /api/mobile-invoices keyless-compatible (D13 exemption)', async () => {
    const res = await request(app).post('/api/mobile-invoices/submit').set('Cookie', authCookie).send({
      customer_id: customerId,
      invoice_date: '2026-11-01',
      items: [{ item_id: itemId, quantity: 1, unit_price: 50, tax_rate: 0 }],
    });
    expect(res.status).toBe(201);
  });

  it('still accepts a keyless POS sale but logs the stage-1 observation', async () => {
    // ACCT-008 staged rollout for POST /api/pos/sale. The key is NOT mandatory
    // yet: older desktop builds and external callers may omit it. The server
    // must accept the sale and record that it was keyless, so the next release
    // can prove compatibility before enforcing.
    const warn = jest.spyOn(logger, 'warn').mockImplementation(() => logger);
    try {
      const res = await request(app).post('/api/pos/sale').set('Cookie', authCookie).send({
        warehouse_id: warehouseId,
        sale_date: '2026-11-01',
        customer_id: customerId,
        items: [{ item_id: itemId, quantity: 1, unit_price: 40 }],
      });
      expect(res.status).toBe(201);
      const observed = warn.mock.calls.some(call =>
        String(call[0]).includes('keyless write') && String(call[0]).includes('pos_sale'));
      expect(observed).toBe(true);
    } finally {
      warn.mockRestore();
    }
  });

  it('rejects a keyless customer payment with 400 and accepts a keyed one', async () => {
    const invoice = await request(app)
      .post('/api/invoices')
      .set('Cookie', authCookie)
      .set('Idempotency-Key', key())
      .send({
        customer_id: customerId,
        invoice_date: '2026-11-01',
        warehouse_id: warehouseId,
        items: [{ item_id: itemId, quantity: 2, unit_price: 50, tax_rate: 0 }],
      });
    expect(invoice.status).toBe(201);

    const payload = {
      customer_id: customerId,
      payment_date: '2026-11-02',
      amount: 100,
      payment_method: 'Cash',
      invoice_allocations: [{ invoice_id: invoice.body.id, amount: 100 }],
    };
    const keyless = await request(app).post('/api/payments').set('Cookie', authCookie).send(payload);
    expect(keyless.status).toBe(400);
    expect((keyless.body as { error: string }).error).toMatch(MANDATE_MESSAGE);

    const keyed = await request(app)
      .post('/api/payments')
      .set('Cookie', authCookie)
      .set('Idempotency-Key', key())
      .send(payload);
    expect(keyed.status).toBe(201);
  });

  it('rejects a keyless payment allocation with 400', async () => {
    // A real unallocated customer payment row (same pattern as
    // idempotencyRound1): the payment lookup runs before the mandate check,
    // so a fabricated id would 404 first.
    const invoice = await request(app)
      .post('/api/invoices')
      .set('Cookie', authCookie)
      .set('Idempotency-Key', key())
      .send({
        customer_id: customerId,
        invoice_date: '2026-11-01',
        warehouse_id: warehouseId,
        items: [{ item_id: itemId, quantity: 1, unit_price: 30, tax_rate: 0 }],
      });
    expect(invoice.status).toBe(201);
    const paymentNo = `MANDATE-ALLOC-${Date.now()}-${Math.floor(Math.random() * 1e4)}`;
    const paymentId = Number(db.prepare(`
      INSERT INTO payments (payment_no, customer_id, payment_date, amount, payment_method, created_by)
      VALUES (?, ?, '2026-11-02', 30, 'Cash', 1)
    `).run(paymentNo, customerId).lastInsertRowid);

    const res = await request(app)
      .post(`/api/payments/${paymentId}/allocate`)
      .set('Cookie', authCookie)
      .send({ allocations: [{ invoice_id: invoice.body.id, amount: 30 }] });
    expect(res.status).toBe(400);
    expect((res.body as { error: string }).error).toMatch(MANDATE_MESSAGE);
  });

  it('rejects a keyless supplier payment with 400', async () => {
    const res = await request(app).post('/api/payments').set('Cookie', authCookie).send({
      supplier_id: 999999,
      payment_date: '2026-11-02',
      amount: 50,
      payment_method: 'Cash',
    });
    expect(res.status).toBe(400);
    expect((res.body as { error: string }).error).toMatch(MANDATE_MESSAGE);
  });

  it('rejects a keyless purchase-order goods receipt with 400 and accepts a keyed one', async () => {
    supplierId = await resolveSupplierByName(`Mandate Supplier ${Date.now()}`, authCookie);
    const po = await request(app).post('/api/purchase-orders').set('Cookie', authCookie).send({
      supplier_id: supplierId,
      po_date: '2026-11-01',
      items: [{ item_id: itemId, quantity: 5, unit_price: 10 }],
    });
    expect(po.status).toBe(201);
    const poId = po.body.data?.id ?? po.body.id;
    await request(app).post(`/api/purchase-orders/${poId}/status`)
      .set('Cookie', authCookie).send({ status: 'Submitted' });
    const poItem = db.prepare('SELECT id FROM purchase_order_items WHERE po_id = ?').get(poId) as { id: number };

    const receiptPayload = {
      receipt_date: '2026-11-02',
      warehouse_id: warehouseId,
      items: [{ po_item_id: poItem.id, received_quantity: 5 }],
    };
    const keyless = await request(app)
      .post(`/api/purchase-orders/${poId}/receipts`)
      .set('Cookie', authCookie)
      .send(receiptPayload);
    expect(keyless.status).toBe(400);
    expect((keyless.body as { error: string }).error).toMatch(MANDATE_MESSAGE);

    const keyed = await request(app)
      .post(`/api/purchase-orders/${poId}/receipts`)
      .set('Cookie', authCookie)
      .set('Idempotency-Key', key())
      .send(receiptPayload);
    expect(keyed.status).toBe(201);
  });

  it('rejects a keyless sales return with 400 and accepts a keyed one', async () => {
    // Paid invoice so the return has an entitlement; the return is the
    // mandated write, the settlement comes in its own case.
    const invoice = await request(app)
      .post('/api/invoices')
      .set('Cookie', authCookie)
      .set('Idempotency-Key', key())
      .send({
        customer_id: customerId,
        invoice_date: '2026-11-01',
        warehouse_id: warehouseId,
        items: [{ item_id: itemId, quantity: 4, unit_price: 50, tax_rate: 0 }],
        record_payment: true,
        payment: { payment_date: '2026-11-01', amount: 200, payment_method: 'Cash' },
      });
    expect(invoice.status).toBe(201);
    const invoiceId = invoice.body.id;
    const invoiceItemId = (db.prepare(
      'SELECT id FROM invoice_items WHERE invoice_id = ? ORDER BY id LIMIT 1'
    ).get(invoiceId) as { id: number }).id;

    const payload = {
      reason: 'mandate probe',
      warehouse_id: warehouseId,
      items: [{ invoice_item_id: invoiceItemId, return_quantity: 1 }],
    };
    const keyless = await request(app)
      .post(`/api/invoices/${invoiceId}/return`)
      .set('Cookie', authCookie)
      .send(payload);
    expect(keyless.status).toBe(400);
    expect((keyless.body as { error: string }).error).toMatch(MANDATE_MESSAGE);

    const keyed = await request(app)
      .post(`/api/invoices/${invoiceId}/return`)
      .set('Cookie', authCookie)
      .set('Idempotency-Key', key())
      .send(payload);
    expect(keyed.status).toBe(200);
    const returnId = (keyed.body as { data?: { returnId?: number } }).data?.returnId;
    expect(returnId).toBeDefined();
  });

  it('rejects a keyless return settlement with 400', async () => {
    const invoice = await request(app)
      .post('/api/invoices')
      .set('Cookie', authCookie)
      .set('Idempotency-Key', key())
      .send({
        customer_id: customerId,
        invoice_date: '2026-11-01',
        warehouse_id: warehouseId,
        items: [{ item_id: itemId, quantity: 4, unit_price: 50, tax_rate: 0 }],
        record_payment: true,
        payment: { payment_date: '2026-11-01', amount: 200, payment_method: 'Cash' },
      });
    expect(invoice.status).toBe(201);
    const invoiceId = invoice.body.id;
    const invoiceItemId = (db.prepare(
      'SELECT id FROM invoice_items WHERE invoice_id = ? ORDER BY id LIMIT 1'
    ).get(invoiceId) as { id: number }).id;

    // No disposition: the legacy shim is what leaves a remainder to settle.
    const created = await request(app)
      .post(`/api/invoices/${invoiceId}/return`)
      .set('Cookie', authCookie)
      .set('Idempotency-Key', key())
      .send({
        reason: 'settle mandate probe',
        warehouse_id: warehouseId,
        items: [{ invoice_item_id: invoiceItemId, return_quantity: 4 }],
      });
    expect(created.status).toBe(200);
    const returnId = (created.body as { data?: { returnId?: number } }).data?.returnId;
    expect(returnId).toBeDefined();

    const res = await request(app)
      .post(`/api/invoice-returns/${returnId}/settle`)
      .set('Cookie', authCookie)
      .send({ allocations: [{ type: 'refund', amount: 200, method: 'Cash' }] });
    expect(res.status).toBe(400);
    expect((res.body as { error: string }).error).toMatch(MANDATE_MESSAGE);
  });

  it('rejects a keyless purchase return with 400 and replays a keyed one', async () => {
    // ACCT-008: the return is a stock + GL + credit-note write. A retry must
    // replay, not double-return.
    const prepared = await (async () => {
      const item2 = await createItem(`Mandate PR Item ${++seq}`, authCookie);
      await purchaseStock(item2, warehouseId, 10, 100, authCookie, '2026-10-01');
      const purchaseId = (db.prepare('SELECT id FROM purchases WHERE item_id = ? ORDER BY id DESC LIMIT 1')
        .get(item2) as { id: number }).id;
      return { item2, purchaseId };
    })();
    const body = {
      return_date: '2026-10-05',
      source_type: 'PURCHASE',
      source_id: prepared.purchaseId,
      warehouse_id: warehouseId,
      items: [{ source_item_id: prepared.purchaseId, quantity: 1 }],
    };

    const keyless = await request(app).post('/api/purchase-returns').set('Cookie', authCookie).send(body);
    expect(keyless.status).toBe(400);
    expect((keyless.body as { error: string }).error).toMatch(MANDATE_MESSAGE);

    const k = key();
    const first = await request(app).post('/api/purchase-returns').set('Cookie', authCookie)
      .set('Idempotency-Key', k).send(body);
    expect(first.status).toBe(201);
    const firstId = (first.body as { data: { id: number } }).data.id;

    const second = await request(app).post('/api/purchase-returns').set('Cookie', authCookie)
      .set('Idempotency-Key', k).send(body);
    expect(second.status).toBe(201);
    expect((second.body as { data: { id: number } }).data.id).toBe(firstId);
    expect(db.prepare('SELECT COUNT(*) n FROM purchase_returns WHERE source_id = ?').get(prepared.purchaseId))
      .toEqual({ n: 1 });
  });

  it('rejects a keyless production run with 400 and replays a keyed one', async () => {
    // ACCT-008: production consumes inputs and posts the output. A retry must
    // replay, never double-consume.
    const raw = await createItem(`Mandate Raw ${++seq}`, authCookie);
    const out = await createItem(`Mandate Out ${++seq}`, authCookie);
    await purchaseStock(raw, warehouseId, 10, 5, authCookie, '2026-10-01');
    const body = {
      warehouse_id: warehouseId,
      production_date: '2026-10-05',
      input_items: [{ item_id: raw, quantity: 2 }],
      outputs: [{ item_id: out, quantity: 1 }],
    };

    const keyless = await request(app).post('/api/productions').set('Cookie', authCookie).send(body);
    expect(keyless.status).toBe(400);
    expect((keyless.body as { error: string }).error).toMatch(MANDATE_MESSAGE);

    const k = key();
    const first = await request(app).post('/api/productions').set('Cookie', authCookie)
      .set('Idempotency-Key', k).send(body);
    expect(first.status).toBe(201);
    const firstId = (first.body as { id: number }).id;

    const second = await request(app).post('/api/productions').set('Cookie', authCookie)
      .set('Idempotency-Key', k).send(body);
    expect(second.status).toBe(201);
    expect((second.body as { id: number }).id).toBe(firstId);
    expect(db.prepare('SELECT COUNT(*) n FROM productions WHERE output_item_id = ?').get(out)).toEqual({ n: 1 });
  });

  it('rejects keyless supplier bill and prepayment writes with 400', async () => {
    // ACCT-008: both are AP + GL writes (bill posts expense/AP, prepayment
    // moves cash to a supplier advance). Keys were optional; now mandatory.
    const sup = await resolveSupplierByName(`Mandate Keyless Supplier ${Date.now()}`, authCookie);

    const billKeyless = await request(app).post('/api/supplier-bills').set('Cookie', authCookie).send({
      supplier_id: sup, bill_no: `K-${++seq}`, bill_date: '2026-10-01', net_amount: 100, input_tax_amount: 15, description: 'Mandate probe',
    });
    expect(billKeyless.status).toBe(400);
    expect((billKeyless.body as { error: string }).error).toMatch(MANDATE_MESSAGE);

    const prepayKeyless = await request(app).post('/api/supplier-prepayments').set('Cookie', authCookie).send({
      supplier_id: sup, prepay_date: '2026-10-01', amount: 50, payment_method: 'Cash',
    });
    expect(prepayKeyless.status).toBe(400);
    expect((prepayKeyless.body as { error: string }).error).toMatch(MANDATE_MESSAGE);
  });

  it('rejects keyless stock write-off and stock transfer with 400, and replays a keyed transfer', async () => {
    // ACCT-008: a write-off posts GL; a transfer consumes FIFO stock. Both
    // must refuse a keyless call and replay a retried key.
    const raw = await createItem(`Mandate Inv ${++seq}`, authCookie);
    await purchaseStock(raw, warehouseId, 20, 7, authCookie, '2026-10-01');

    const writeOffKeyless = await request(app).post('/api/inventory/stock-movements').set('Cookie', authCookie).send({
      item_id: raw, warehouse_id: warehouseId, quantity: -2, movement_type: 'ADJUSTMENT', remarks: 'damage',
    });
    expect(writeOffKeyless.status).toBe(400);
    expect((writeOffKeyless.body as { error: string }).error).toMatch(MANDATE_MESSAGE);

    const toWarehouse = (db.prepare('SELECT id FROM warehouses WHERE id != ? ORDER BY id LIMIT 1').get(warehouseId) as { id: number } | undefined)?.id;
    if (toWarehouse === undefined) throw new Error('Need a second warehouse for the transfer case');
    const transferBody = { item_id: raw, from_warehouse_id: warehouseId, to_warehouse_id: toWarehouse, quantity: 3 };

    const transferKeyless = await request(app).post('/api/inventory/stock-transfers').set('Cookie', authCookie).send(transferBody);
    expect(transferKeyless.status).toBe(400);
    expect((transferKeyless.body as { error: string }).error).toMatch(MANDATE_MESSAGE);

    const k = key();
    const first = await request(app).post('/api/inventory/stock-transfers').set('Cookie', authCookie)
      .set('Idempotency-Key', k).send(transferBody);
    expect(first.status).toBe(201);
    const firstId = (first.body as { data: { out: { id: number } } }).data.out.id;
    const before = db.prepare('SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?')
      .get(raw, warehouseId) as { quantity: number };

    const second = await request(app).post('/api/inventory/stock-transfers').set('Cookie', authCookie)
      .set('Idempotency-Key', k).send(transferBody);
    expect(second.status).toBe(201);
    expect((second.body as { data: { out: { id: number } } }).data.out.id).toBe(firstId);
    const after = db.prepare('SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?')
      .get(raw, warehouseId) as { quantity: number };
    expect(after.quantity).toBe(before.quantity);
  });
});
