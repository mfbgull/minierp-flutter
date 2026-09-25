/**
 * TASK 24 — business-rule errors must surface as 4xx (409 for state
 * conflicts), never as generic 500, with a human-readable message and
 * no stack/SQL leakage. Also pins that a rejected operation leaves no
 * partial database mutation.
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { classifyError, handleBusinessError, BusinessRuleError } from '../utils/businessRuleError';
import { getAuthCookie, createItem, purchaseStock, createCustomer, createInvoice } from './helpers/invoiceReturnSpec';

const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD) {
  throw new Error('TEST_ADMIN_PASSWORD environment variable must be set for integration tests.');
}

describe('classifyError (unit)', () => {
  it('maps closed accounting period to 409', () => {
    const r = classifyError(new Error('Cannot update Payment PAY-1: date is inside closed accounting period 2026-08'));
    expect(r).toEqual({
      status: 409,
      message: expect.stringMatching(/closed accounting period/i),
    });
  });

  it('maps already cancelled / already returned / already voided to 409', () => {
    for (const msg of [
      'Invoice is already cancelled',
      'Invoice already returned in full',
      'Payment is already voided',
      'Settlement is already settled',
      'Idempotency key already used',
    ]) {
      const r = classifyError(new Error(msg));
      expect(r?.status).toBe(409);
      expect(r?.message).toBe(msg);
    }
  });

  it('maps invalid state transition (Cannot cancel/return/void) to 409', () => {
    expect(classifyError(new Error('Cannot cancel invoice with open returns'))?.status).toBe(409);
    expect(classifyError(new Error('Cannot return a cancelled invoice'))?.status).toBe(409);
    expect(classifyError(new Error('Cannot void a settled settlement'))?.status).toBe(409);
  });

  it('maps not found to 404 and refusing to delete to 400', () => {
    expect(classifyError(new Error('Invoice not found'))?.status).toBe(404);
    expect(classifyError(new Error('Record does not exist'))?.status).toBe(404);
    expect(classifyError(new Error('refusing to delete unallocated payments'))?.status).toBe(400);
  });

  it('maps Insufficient funds to 400 with the actionable message', () => {
    const r = classifyError(new Error(
      'Insufficient funds in Cash: available 0.00, required 100.00 — opening balance missing. ' +
      'Record your starting cash (Dashboard → Opening balance) or owner capital first.',
    ));
    expect(r?.status).toBe(400);
    expect(r?.message).toMatch(/Insufficient funds/i);
    expect(r?.message).toMatch(/Opening balance/);
  });

  it('honours typed errors that carry their own status', () => {
    const e = new BusinessRuleError(409, 'custom conflict');
    expect(classifyError(e)).toEqual({ status: 409, message: 'custom conflict' });
  });

  it('returns null for genuine server errors', () => {
    expect(classifyError(new Error('SQLITE_CORRUPT: database disk image is malformed'))).toBeNull();
    expect(classifyError(new Error('undefined is not a function'))).toBeNull();
  });
});

describe('handleBusinessError (unit via mock res)', () => {
  function mockRes() {
    const res = {
      statusCode: 0,
      body: undefined as unknown,
      status(code: number) { this.statusCode = code; return this; },
      json(payload: unknown) { this.body = payload; return this; },
    };
    return res as unknown as { statusCode: number; body: unknown } & Parameters<typeof handleBusinessError>[0];
  }

  it('responds classified status with the service message and no stack', () => {
    const res = mockRes();
    handleBusinessError(res, new Error('Invoice is already cancelled'), 'Cancel invoice', 'Failed to cancel invoice');
    expect(res.statusCode).toBe(409);
    expect(res.body).toEqual({ error: 'Invoice is already cancelled' });
    expect(JSON.stringify(res.body)).not.toMatch(/stack|at Object\.|\.ts:\d+/);
  });

  it('wraps as { success: false, error } when opts.success is set', () => {
    const res = mockRes();
    handleBusinessError(res, new Error('inside closed accounting period'), 'Create expense', 'Failed', { success: true });
    expect(res.statusCode).toBe(409);
    expect(res.body).toEqual({ success: false, error: expect.stringMatching(/closed accounting period/i) });
  });

  it('falls back to 500 with only the fallback message for unknown errors', () => {
    const res = mockRes();
    handleBusinessError(res, new Error('SELECT * FROM secret_table failed'), 'Create invoice', 'Failed to create invoice');
    expect(res.statusCode).toBe(500);
    expect(res.body).toEqual({ error: 'Failed to create invoice' });
    expect(JSON.stringify(res.body)).not.toMatch(/SELECT|secret_table|stack/i);
  });
});

describe('TASK 24 integration — 409 closed period, no partial mutation, no stack leak', () => {
  let token: string;
  let warehouseId: number;

  beforeAll(async () => {
    token = await getAuthCookie();
    const wh = db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number };
    warehouseId = wh.id;
  });

  afterEach(() => {
    db.prepare(`UPDATE accounting_periods SET status = 'open' WHERE status = 'closed' AND period_name = '2026-09-closed-for-test'`).run();
    db.prepare(`DELETE FROM accounting_periods WHERE period_name = '2026-09-closed-for-test'`).run();
  });

  function closePeriodFor(date: string, name = '2026-09-closed-for-test') {
    const start = `${date.slice(0, 7)}-01`;
    const end = `${date.slice(0, 7)}-31`;
    db.prepare(`
      INSERT INTO accounting_periods (period_name, start_date, end_date, status)
      VALUES (?, ?, ?, 'open')
      ON CONFLICT(period_name) DO NOTHING
    `).run(name, start, end);
    db.prepare(`UPDATE accounting_periods SET status = 'closed' WHERE period_name = ?`).run(name);
  }

  it('payment edit in closed period → 409, readable message, no stack, payment unchanged', async () => {
    const customer = await createCustomer('T24 Cust', token);
    const item = await createItem('T24 Item', token);
    await purchaseStock(item, warehouseId, 10, 100, token);
    const inv = await createInvoice({
      customerId: customer,
      itemId: item,
      lines: [{ quantity: 5, unitPrice: 50 }],
      invoiceDate: '2026-09-10',
    }, token);
    const payRes = await request(app).post('/api/payments')
      .set('Cookie', token)
      .send({
        customer_id: customer,
        amount: 250,
        payment_method: 'Cash',
        payment_date: '2026-09-10',
        invoice_allocations: [{ invoice_id: inv.invoiceId, amount: 250 }],
      });
    expect(payRes.status).toBe(201);
    const paymentId = payRes.body.data.id;

    const before = db.prepare('SELECT amount, payment_date FROM payments WHERE id = ?').get(paymentId);

    closePeriodFor('2026-09-10');
    const res = await request(app).put(`/api/payments/${paymentId}`)
      .set('Cookie', token)
      .send({ payment_date: '2026-09-12', amount: 1 });

    expect(res.status).toBe(409);
    const raw = JSON.stringify(res.body);
    expect(raw).toMatch(/closed accounting period/i);
    expect(raw).not.toMatch(/stack|at Object\.|SQLITE_|SELECT /i);

    const after = db.prepare('SELECT amount, payment_date FROM payments WHERE id = ?').get(paymentId);
    expect(after).toEqual(before);
  });

  it('double-cancel invoice → 409, readable message, stock not restored twice', async () => {
    const customer = await createCustomer('T24 Cancel Cust', token);
    const item = await createItem('T24 Cancel Item', token);
    await purchaseStock(item, warehouseId, 10, 100, token);
    const qtyBefore = (db.prepare(
      'SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?'
    ).get(item, warehouseId) as { quantity: number }).quantity;

    const inv = await createInvoice({
      customerId: customer,
      itemId: item,
      lines: [{ quantity: 4, unitPrice: 30 }],
      invoiceDate: '2026-09-12',
    }, token);

    const first = await request(app).put(`/api/invoices/${inv.invoiceId}/cancel`).set('Cookie', token);
    expect(first.status).toBe(200);

    const qtyAfterFirst = (db.prepare(
      'SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?'
    ).get(item, warehouseId) as { quantity: number }).quantity;

    const second = await request(app).put(`/api/invoices/${inv.invoiceId}/cancel`).set('Cookie', token);
    expect(second.status).toBe(409);
    const raw = JSON.stringify(second.body);
    expect(raw).toMatch(/already cancelled/i);
    expect(raw).not.toMatch(/stack|at Object\.|SQLITE_/i);

    const qtyAfterSecond = (db.prepare(
      'SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?'
    ).get(item, warehouseId) as { quantity: number }).quantity;
    expect(qtyAfterSecond).toBe(qtyAfterFirst);
    expect(qtyAfterFirst).toBeCloseTo(qtyBefore, 6);

    const row = db.prepare('SELECT status FROM invoices WHERE id = ?').get(inv.invoiceId) as { status: string };
    expect(row.status).toBe('Cancelled');
  });
});
