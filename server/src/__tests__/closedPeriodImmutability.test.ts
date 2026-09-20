/**
 * Closed accounting period immutability regression (H6).
 *
 * Once a period is closed, no server-side operation may silently rewrite
 * accounting history (GL, customer ledger, supplier ledger, payments,
 * invoices, expenses, returns, purchases, or owner transactions) inside
 * that period. The server must enforce this; UI hiding is insufficient.
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { getAuthCookie, createItem, purchaseStock, createCustomer, createInvoice } from './helpers/invoiceReturnSpec';

const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD) {
  throw new Error('TEST_ADMIN_PASSWORD environment variable must be set for integration tests.');
}

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

function api(method: 'get' | 'post' | 'put' | 'delete', url: string, body?: Record<string, unknown>) {
  return request(app)[method](url)
    .set('Cookie', token)
    .send(body);
}

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

describe('Closed accounting period immutability (H6)', () => {
  it('blocks payment void in closed period', async () => {
    const customer = await createCustomer('Closed Period Cust', token);
    const item = await createItem('Closed Period Item', token);
    await purchaseStock(item, warehouseId, 10, 100, token);
    const inv = await createInvoice({
      customerId: customer,
      itemId: item,
      lines: [{ quantity: 10, unitPrice: 200 }],
      invoiceDate: '2026-09-10',
    }, token);
    const payRes = await api('post', '/api/payments', {
      customer_id: customer,
      amount: 200,
      payment_method: 'Cash',
      payment_date: '2026-09-10',
      invoice_allocations: [{ invoice_id: inv.invoiceId, amount: 200 }],
    });
    expect(payRes.status).toBe(201);
    const paymentId = payRes.body.data.id;

    closePeriodFor('2026-09-10');
    const voidRes = await api('delete', `/api/payments/${paymentId}`);
    expect(voidRes.status).toBe(409);
    expect(JSON.stringify(voidRes.body)).toMatch(/closed|period/i);

    const p = db.prepare('SELECT voided_at FROM payments WHERE id = ?').get(paymentId) as { voided_at: string | null };
    expect(p.voided_at).toBeNull();
  });

  it('blocks payment date edit in closed period', async () => {
    const customer = await createCustomer('Closed Period Cust2', token);
    const item = await createItem('Closed Period Item2', token);
    await purchaseStock(item, warehouseId, 10, 100, token);
    const inv = await createInvoice({
      customerId: customer,
      itemId: item,
      lines: [{ quantity: 10, unitPrice: 200 }],
      invoiceDate: '2026-09-10',
    }, token);
    const payRes = await api('post', '/api/payments', {
      customer_id: customer,
      amount: 200,
      payment_method: 'Cash',
      payment_date: '2026-09-10',
      invoice_allocations: [{ invoice_id: inv.invoiceId, amount: 200 }],
    });
    expect(payRes.status).toBe(201);
    const paymentId = payRes.body.data.id;

    closePeriodFor('2026-09-10');
    const editRes = await api('put', `/api/payments/${paymentId}`, {
      payment_date: '2026-09-15',
      reference_no: 'changed',
    });
    expect(editRes.status).toBe(409);
    expect(JSON.stringify(editRes.body)).toMatch(/closed|period/i);

    const p = db.prepare('SELECT payment_date, reference_no FROM payments WHERE id = ?').get(paymentId) as { payment_date: string; reference_no: string };
    expect(p.payment_date).toBe('2026-09-10');
    expect(p.reference_no).toBe('');
  });

  it('blocks payment method edit in closed period', async () => {
    const customer = await createCustomer('Closed Period Cust3', token);
    const item = await createItem('Closed Period Item3', token);
    await purchaseStock(item, warehouseId, 10, 100, token);
    const inv = await createInvoice({
      customerId: customer,
      itemId: item,
      lines: [{ quantity: 10, unitPrice: 200 }],
      invoiceDate: '2026-09-10',
    }, token);
    const payRes = await api('post', '/api/payments', {
      customer_id: customer,
      amount: 200,
      payment_method: 'Cash',
      payment_date: '2026-09-10',
      invoice_allocations: [{ invoice_id: inv.invoiceId, amount: 200 }],
    });
    expect(payRes.status).toBe(201);
    const paymentId = payRes.body.data.id;

    closePeriodFor('2026-09-10');
    const editRes = await api('put', `/api/payments/${paymentId}`, {
      payment_method: 'Bank',
    });
    expect(editRes.status).toBe(409);
    expect(JSON.stringify(editRes.body)).toMatch(/closed|period/i);

    const p = db.prepare('SELECT payment_method FROM payments WHERE id = ?').get(paymentId) as { payment_method: string };
    expect(p.payment_method).toBe('Cash');
  });

  it('blocks invoice cancellation in closed period', async () => {
    const customer = await createCustomer('Closed Period Cust4', token);
    const item = await createItem('Closed Period Item4', token);
    await purchaseStock(item, warehouseId, 10, 100, token);
    const inv = await createInvoice({
      customerId: customer,
      itemId: item,
      lines: [{ quantity: 10, unitPrice: 200 }],
      invoiceDate: '2026-09-10',
    }, token);
    const invoiceId = inv.invoiceId;

    closePeriodFor('2026-09-10');
    const cancelRes = await api('put', `/api/invoices/${invoiceId}/cancel`);
    expect(cancelRes.status).toBe(409);
    expect(JSON.stringify(cancelRes.body)).toMatch(/closed|period/i);

    const invRow = db.prepare('SELECT status FROM invoices WHERE id = ?').get(invoiceId) as { status: string };
    expect(invRow.status).not.toBe('Cancelled');
  });

  it('blocks expense edit in closed period', async () => {
    const expenseId = db.prepare(`
      INSERT INTO expenses (expense_no, expense_category, description, amount, expense_date, payment_method, status, created_by)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `).run('EXP-CLOSED-1', 'Utilities', 'Electricity', 500, '2026-09-10', 'Cash', 'Paid', 1).lastInsertRowid as number;

    closePeriodFor('2026-09-10');
    const editRes = await api('put', `/api/expenses/${expenseId}`, {
      amount: 600,
      expense_date: '2026-09-10',
    });
    expect(editRes.status).toBe(409);
    expect(JSON.stringify(editRes.body)).toMatch(/closed|period/i);

    const e = db.prepare('SELECT amount FROM expenses WHERE id = ?').get(expenseId) as { amount: number };
    expect(e.amount).toBe(500);
  });

  it('blocks purchase void in closed period', async () => {
    const purchaseId = db.prepare(`
      INSERT INTO purchases (purchase_no, item_id, warehouse_id, quantity, unit_cost, total_cost, purchase_date, supplier_name, created_by)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run('PO-CLOSED-1', 1, warehouseId, 10, 100, 1000, '2026-09-10', 'Test Supplier', 1).lastInsertRowid as number;

    closePeriodFor('2026-09-10');
    const voidRes = await api('post', `/api/purchases/${purchaseId}/void`, { reason: 'test' });
    expect(voidRes.status).toBe(409);
    expect(JSON.stringify(voidRes.body)).toMatch(/closed|period/i);

    const p = db.prepare('SELECT voided_at FROM purchases WHERE id = ?').get(purchaseId) as { voided_at: string | null };
    expect(p.voided_at).toBeNull();
  });

  it('blocks sales return void in closed period', async () => {
    const customer = await createCustomer('Closed Period Cust5', token);
    const item = await createItem('Closed Period Item5', token);
    await purchaseStock(item, warehouseId, 10, 100, token);
    const inv = await createInvoice({
      customerId: customer,
      itemId: item,
      lines: [{ quantity: 10, unitPrice: 200 }],
      invoiceDate: '2026-09-10',
    }, token);
    const retRes = await api('post', `/api/invoices/${inv.invoiceId}/return`, {
      items: [{ invoice_item_id: inv.invoiceItemIds[0], return_quantity: 2 }],
      disposition: 'credit',
      return_date: '2026-09-10',
    });
    expect(retRes.status).toBe(200);
    const returnId = retRes.body.data.returnId;

    closePeriodFor('2026-09-10');
    const voidRes = await api('post', `/api/invoice-returns/${returnId}/void`, { reason: 'test' });
    expect(voidRes.status).toBe(409);
    expect(JSON.stringify(voidRes.body)).toMatch(/closed|period/i);
  });

  it('allows the same operations in an open period', async () => {
    const customer = await createCustomer('Open Period Cust', token);
    const item = await createItem('Open Period Item', token);
    await purchaseStock(item, warehouseId, 10, 100, token);
    const inv = await createInvoice({
      customerId: customer,
      itemId: item,
      lines: [{ quantity: 10, unitPrice: 200 }],
      invoiceDate: '2026-09-20',
    }, token);

    const payRes = await api('post', '/api/payments', {
      customer_id: customer,
      amount: 200,
      payment_method: 'Cash',
      payment_date: '2026-09-20',
      invoice_allocations: [{ invoice_id: inv.invoiceId, amount: 200 }],
    });
    expect(payRes.status).toBe(201);
    const paymentId = payRes.body.data.id;
    const voidRes = await api('delete', `/api/payments/${paymentId}`);
    expect(voidRes.status).toBe(200);

    const cancelRes = await api('put', `/api/invoices/${inv.invoiceId}/cancel`);
    expect(cancelRes.status).toBe(200);
  });
});
