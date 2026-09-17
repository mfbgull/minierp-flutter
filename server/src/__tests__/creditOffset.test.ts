/**
 * Customer credit offset on invoice create
 * (openspec/changes/use-cr-balance-in-invoice).
 *
 * Seed a real customer credit the way the app does — sell on account,
 * pay in full, then return the goods with `disposition: 'credit'` — and
 * then apply that credit to a second invoice via `credit_offset`.
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

describe('invoice create with credit_offset', () => {
  let authCookie: string;
  let itemId: number;
  let customerId: number;
  let warehouseId: number;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');

    const wh = db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number };
    warehouseId = wh.id;

    const item = await request(app).post('/api/inventory/items')
      .set('Cookie', authCookie)
      .send({ item_code: `CRO-${Date.now()}`, item_name: 'Credit Offset Item' });
    expect(item.status).toBe(201);
    itemId = item.body.id;

    await request(app).post('/api/purchases')
      .set('Cookie', authCookie)
      .send({
        item_id: itemId,
        warehouse_id: warehouseId,
        quantity: 20,
        unit_cost: 10,
        purchase_date: '2026-08-01',
        supplier_name: 'Credit Offset Supplier',
      });

    const customer = await request(app).post('/api/customers')
      .set('Cookie', authCookie)
      .send({ customer_name: 'Credit Offset Customer', phone: '555-0909' });
    expect(customer.status).toBe(201);
    customerId = customer.body.data?.id ?? customer.body.id;
  });

  /// Sell `qty` units at 100, collect cash in full, then return them all
  /// with `credit` disposition so the customer ends with a credit balance.
  async function seedCustomerCredit(qty: number): Promise<number> {
    const created = await request(app).post('/api/invoices')
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId,
        invoice_date: '2026-09-01',
        due_date: '2026-09-15',
        items: [{
          item_id: itemId,
          description: 'Credit Offset Item',
          quantity: qty,
          unit_price: 100,
          tax_rate: 0,
          discount_type: 'none',
          discount_value: 0,
        }],
        total_amount: qty * 100,
        record_payment: true,
        payment: {
          payment_date: '2026-09-01',
          amount: qty * 100,
          payment_method: 'Cash',
        },
      });
    expect(created.status).toBe(201);

    const invoiceItem = db.prepare(
      'SELECT id FROM invoice_items WHERE invoice_id = ?'
    ).get(created.body.id) as { id: number };

    const returned = await request(app)
      .post(`/api/invoices/${created.body.id}/return`)
      .set('Cookie', authCookie)
      .send({
        reason: 'Credit offset seed',
        disposition: 'credit',
        warehouse_id: warehouseId,
        items: [{ invoice_item_id: invoiceItem.id, return_quantity: qty }],
      });
    expect(returned.status).toBe(200);

    const balance = db.prepare(
      'SELECT current_balance FROM customers WHERE id = ?'
    ).get(customerId) as { current_balance: number };
    return balance.current_balance;
  }

  function buildInvoice(creditOffset: number) {
    return {
      customer_id: customerId,
      invoice_date: '2026-09-10',
      due_date: '2026-09-24',
      items: [{
        item_id: itemId,
        description: 'Credit Offset Item',
        quantity: 2,
        unit_price: 100,
        tax_rate: 0,
        discount_type: 'none',
        discount_value: 0,
      }],
      total_amount: 200,
      credit_offset: creditOffset,
    };
  }

  it('creates the invoice when the customer has enough credit', async () => {
    const balance = await seedCustomerCredit(2);
    expect(balance).toBe(-200);

    const res = await request(app).post('/api/invoices')
      .set('Cookie', authCookie)
      .send(buildInvoice(200));

    expect(res.status).toBe(201);

    const afterBalance = db.prepare(
      'SELECT current_balance FROM customers WHERE id = ?'
    ).get(customerId) as { current_balance: number };
    expect(afterBalance.current_balance).toBe(0);
  });

  it('posts a balanced Dr Customer Credit / Cr AR journal entry', async () => {
    await seedCustomerCredit(2);

    const res = await request(app).post('/api/invoices')
      .set('Cookie', authCookie)
      .send(buildInvoice(200));
    expect(res.status).toBe(201);

    const lines = db.prepare(
      `SELECT account_id, debit, credit FROM journal_lines
       WHERE reference_type = 'CREDIT_OFFSET' AND reference_id = ? AND voided = 0`
    ).all(res.body.id) as Array<{ account_id: number; debit: number; credit: number }>;

    const totalDebit = lines.reduce((s, l) => s + l.debit, 0);
    const totalCredit = lines.reduce((s, l) => s + l.credit, 0);
    expect(totalDebit).toBe(200);
    expect(totalDebit).toBeCloseTo(totalCredit, 2);
  });

  it('rejects a credit offset larger than the available balance', async () => {
    const res = await request(app).post('/api/invoices')
      .set('Cookie', authCookie)
      .send(buildInvoice(9999));

    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/credit/i);
  });
});