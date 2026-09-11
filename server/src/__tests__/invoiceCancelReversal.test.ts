/**
 * Reversal-rules Phase 1 regression tests — C1 (invoice cancellation)
 * and C4 (sales-order cancellation sharing the same primitive).
 *
 * Audit cases covered:
 *   1. Cancel unpaid invoice → stock restored, GL voided, ledger net 0
 *   2. Cancel paid invoice → blocked (400), zero state change
 *   3. Cancel partially-paid invoice → blocked, GL still active
 *   5. SO.cancel on invoiced+paid → blocked; invoiced+unpaid → reversed
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';

const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD) {
  throw new Error('TEST_ADMIN_PASSWORD environment variable must be set.');
}

async function getAuthCookie(): Promise<string> {
  const res = await request(app)
    .post('/api/auth/login')
    .send({ username: 'admin', password: TEST_PASSWORD });
  const cookies = res.headers['set-cookie'];
  if (!cookies) return '';
  const tokenCookie = (Array.isArray(cookies) ? cookies : [cookies])
    .find((c: string) => c.startsWith('token='));
  return tokenCookie ? tokenCookie.split(';')[0] : '';
}

describe('Invoice/SO cancellation reversal (C1 + C4)', () => {
  let authCookie: string;
  let itemId: number;
  let customerId: number;
  let warehouseId: number;
  let counter = 0;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');

    warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;

    const item = await request(app)
      .post('/api/inventory/items')
      .set('Cookie', authCookie)
      .send({ item_code: `C1C4-${Date.now()}`, item_name: 'C1/C4 Test Item' });
    expect(item.status).toBe(201);
    itemId = item.body.id;

    // Stock: several invoices' worth of sales.
    await request(app)
      .post('/api/purchases')
      .set('Cookie', authCookie)
      .send({
        item_id: itemId,
        warehouse_id: warehouseId,
        quantity: 50,
        unit_cost: 10,
        purchase_date: '2026-08-01',
        supplier_name: 'C1/C4 Stock Supplier',
      });

    const customer = await request(app)
      .post('/api/customers')
      .set('Cookie', authCookie)
      .send({ customer_name: `C1/C4 Customer ${Date.now()}`, phone: '555-0810' });
    expect(customer.status).toBe(201);
    customerId = customer.body.data.id;
  });

  async function createInvoice(): Promise<{ invoiceId: number; invoiceNo: string }> {
    counter += 1;
    const res = await request(app)
      .post('/api/invoices')
      .set('Cookie', authCookie)
      .send({
        invoice_no: `INV-C1C4-${Date.now()}-${counter}`,
        customer_id: customerId,
        invoice_date: '2026-08-10',
        due_date: '2026-08-20',
        status: 'Unpaid',
        total_amount: 100,
        items: [{ item_id: itemId, quantity: 2, unit_price: 50, warehouse_id: warehouseId }],
      });
    expect(res.status).toBe(201);
    return { invoiceId: res.body.id as number, invoiceNo: res.body.invoice_no as string };
  }

  async function recordPayment(invoiceId: number, amount = 100): Promise<void> {
    const inv = db.prepare(
      'SELECT customer_id, invoice_date, due_date, total_amount FROM invoices WHERE id = ?'
    ).get(invoiceId) as { customer_id: number; invoice_date: string; due_date: string; total_amount: number };
    const res = await request(app)
      .put(`/api/invoices/${invoiceId}`)
      .set('Cookie', authCookie)
      .send({
        customer_id: inv.customer_id,
        invoice_date: inv.invoice_date.slice(0, 10),
        due_date: inv.due_date.slice(0, 10),
        total_amount: inv.total_amount,
        items: [{ item_id: itemId, quantity: 2, unit_price: 50, warehouse_id: warehouseId }],
        record_payment: true,
        payment: { amount, payment_date: '2026-08-11', payment_method: 'Cash' },
      });
    expect(res.status).toBe(200);
  }

  function activeLines(refType: string, refId: number): number {
    return (db.prepare(
      'SELECT COUNT(*) AS c FROM journal_lines WHERE reference_type = ? AND reference_id = ? AND voided = 0'
    ).get(refType, refId) as { c: number }).c;
  }

  it('case 1: cancelling an unpaid invoice reverses stock, voids GL, nets the ledger to 0', async () => {
    const { invoiceId, invoiceNo } = await createInvoice();

    const stockBefore = (db.prepare(
      'SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?'
    ).get(itemId, warehouseId) as { quantity: number }).quantity;

    const balanceBefore = (db.prepare(
      'SELECT current_balance FROM customers WHERE id = ?'
    ).get(customerId) as { current_balance: number }).current_balance;

    const res = await request(app)
      .post(`/api/invoices/${invoiceId}/cancel`)
      .set('Cookie', authCookie);
    expect(res.status).toBe(200);

    // Status
    const inv = db.prepare('SELECT status FROM invoices WHERE id = ?').get(invoiceId) as { status: string };
    expect(inv.status).toBe('Cancelled');

    // Stock restored (+2 units back)
    const stockAfter = (db.prepare(
      'SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?'
    ).get(itemId, warehouseId) as { quantity: number }).quantity;
    expect(stockAfter - stockBefore).toBeCloseTo(2, 2);

    // All canonical GL lines voided (invoice + COGS share reference_type INVOICE)
    expect(activeLines('INVOICE', invoiceId)).toBe(0);
    expect(activeLines('INVOICE_RETURN', invoiceId)).toBe(0);
    // But rows retained for audit (voided = 1)
    const voidedLines = (db.prepare(
      'SELECT COUNT(*) AS c FROM journal_lines WHERE reference_type = ? AND reference_id = ? AND voided = 1'
    ).get('INVOICE', invoiceId) as { c: number }).c;
    expect(voidedLines).toBeGreaterThan(0);

    // Ledger: DEBIT (INVOICE) + CANCELLATION credit → net 0
    const rows = db.prepare(
      'SELECT debit, credit FROM customer_ledger WHERE reference_no = ? AND voided = 0'
    ).all(invoiceNo) as Array<{ debit: number; credit: number }>;
    const debit = rows.filter(r => r.debit > 0).reduce((s, r) => s + Number(r.debit), 0);
    const credit = rows.filter(r => r.credit > 0).reduce((s, r) => s + Number(r.credit), 0);
    expect(debit).toBeCloseTo(100, 2);
    expect(credit).toBeCloseTo(100, 2);

    // Customer balance unchanged from before the invoice existed
    const balanceAfter = (db.prepare(
      'SELECT current_balance FROM customers WHERE id = ?'
    ).get(customerId) as { current_balance: number }).current_balance;
    expect(balanceAfter).toBeCloseTo(balanceBefore, 2);

    // CANCELLATION reversal movement exists
    const cancelMovement = db.prepare(
      `SELECT COUNT(*) AS c FROM stock_movements WHERE reference_doctype = 'INVOICE_CANCEL' AND reference_docno = ?`
    ).get(invoiceNo) as { c: number };
    expect(cancelMovement.c).toBeGreaterThan(0);
  });

  it('case 2: cancelling a fully paid invoice is blocked with 400 and no state changes', async () => {
    const { invoiceId, invoiceNo } = await createInvoice();
    await recordPayment(invoiceId, 100);

    const paidLines = activeLines('INVOICE', invoiceId);
    expect(paidLines).toBeGreaterThan(0);

    const res = await request(app)
      .post(`/api/invoices/${invoiceId}/cancel`)
      .set('Cookie', authCookie);
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/payments/i);

    // Nothing changed
    const inv = db.prepare('SELECT status FROM invoices WHERE id = ?').get(invoiceId) as { status: string };
    expect(inv.status).not.toBe('Cancelled');
    expect(activeLines('INVOICE', invoiceId)).toBe(paidLines);
    const cancelMovement = db.prepare(
      `SELECT COUNT(*) AS c FROM stock_movements WHERE reference_doctype = 'INVOICE_CANCEL' AND reference_docno = ?`
    ).get(invoiceNo) as { c: number };
    expect(cancelMovement.c).toBe(0);
  });

  it('case 3: cancelling a partially paid invoice is blocked and keeps GL active', async () => {
    const { invoiceId, invoiceNo } = await createInvoice();
    await recordPayment(invoiceId, 40);

    const res = await request(app)
      .post(`/api/invoices/${invoiceId}/cancel`)
      .set('Cookie', authCookie);
    expect(res.status).toBe(400);

    const inv = db.prepare('SELECT status, paid_amount FROM invoices WHERE id = ?').get(invoiceId) as { status: string; paid_amount: number };
    expect(inv.status).not.toBe('Cancelled');
    expect(inv.paid_amount).toBeGreaterThan(0);
    expect(activeLines('INVOICE', invoiceId)).toBeGreaterThan(0);
    const cancelMovement = db.prepare(
      `SELECT COUNT(*) AS c FROM stock_movements WHERE reference_doctype = 'INVOICE_CANCEL' AND reference_docno = ?`
    ).get(invoiceNo) as { c: number };
    expect(cancelMovement.c).toBe(0);
  });

  it('case 5a: SO.cancel on an invoiced + paid order is blocked (invoice guard propagates)', async () => {
    const so = await request(app)
      .post('/api/sales-orders')
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId,
        so_date: '2026-08-10',
        delivery_date: '2026-08-15',
        status: 'Confirmed',
        warehouse_id: warehouseId,
        items: [{ item_id: itemId, quantity: 1, unit_price: 100, warehouse_id: warehouseId }],
      });
    expect(so.status).toBe(201);
    const soId = so.body.id as number;

    const conv = await request(app)
      .post(`/api/sales-orders/${soId}/convert`)
      .set('Cookie', authCookie)
      .send({ invoice_date: '2026-08-12', due_date: '2026-08-22' });
    expect(conv.status).toBe(201);
    const invoiceId = conv.body.invoiceId as number;
    expect(invoiceId).toBeDefined();

    await recordPayment(invoiceId, 100);

    const res = await request(app)
      .post(`/api/sales-orders/${soId}/cancel`)
      .set('Cookie', authCookie);
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/payments/i);

    // Invoice + SO both unchanged
    const inv = db.prepare('SELECT status FROM invoices WHERE id = ?').get(invoiceId) as { status: string };
    expect(inv.status).not.toBe('Cancelled');
    const soRow = db.prepare('SELECT status FROM sales_orders WHERE id = ?').get(soId) as { status: string };
    expect(soRow.status).not.toBe('Cancelled');
    expect(activeLines('INVOICE', invoiceId)).toBeGreaterThan(0);
  });

  it('case 5b: SO.cancel on an invoiced + unpaid order runs the full reversal', async () => {
    const so = await request(app)
      .post('/api/sales-orders')
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId,
        so_date: '2026-08-10',
        delivery_date: '2026-08-15',
        status: 'Confirmed',
        warehouse_id: warehouseId,
        items: [{ item_id: itemId, quantity: 1, unit_price: 100, warehouse_id: warehouseId }],
      });
    expect(so.status).toBe(201);
    const soId = so.body.id as number;

    const conv = await request(app)
      .post(`/api/sales-orders/${soId}/convert`)
      .set('Cookie', authCookie)
      .send({ invoice_date: '2026-08-12', due_date: '2026-08-22' });
    expect(conv.status).toBe(201);
    const invoiceId = conv.body.invoiceId as number;
    const invoiceNo = db.prepare('SELECT invoice_no FROM invoices WHERE id = ?').get(invoiceId) as { invoice_no: string };

    const stockBefore = (db.prepare(
      'SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?'
    ).get(itemId, warehouseId) as { quantity: number }).quantity;

    const res = await request(app)
      .post(`/api/sales-orders/${soId}/cancel`)
      .set('Cookie', authCookie);
    expect(res.status).toBe(200);

    // Both SO and invoice cancelled
    const soRow = db.prepare('SELECT status FROM sales_orders WHERE id = ?').get(soId) as { status: string };
    expect(soRow.status).toBe('Cancelled');
    const inv = db.prepare('SELECT status FROM invoices WHERE id = ?').get(invoiceId) as { status: string };
    expect(inv.status).toBe('Cancelled');

    // Full reversal: GL voided + stock restored + ledger cancellation row
    expect(activeLines('INVOICE', invoiceId)).toBe(0);
    const stockAfter = (db.prepare(
      'SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?'
    ).get(itemId, warehouseId) as { quantity: number }).quantity;
    expect(stockAfter - stockBefore).toBeCloseTo(1, 2);
    const cancelLedger = db.prepare(
      `SELECT credit FROM customer_ledger WHERE reference_no = ? AND transaction_type = 'CANCELLATION' AND voided = 0`
    ).get(invoiceNo) as { credit: number };
    expect(Number(cancelLedger?.credit ?? 0)).toBeCloseTo(100, 2);
  });
});
