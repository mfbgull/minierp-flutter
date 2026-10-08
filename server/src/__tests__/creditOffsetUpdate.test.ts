/**
 * Store credit on the invoice UPDATE path (audit-3 task 06).
 *
 * Two defects lived here:
 *
 *  1. `paid_amount` was recomputed from payments alone, so editing a
 *     credited invoice silently dropped the applied credit from the
 *     invoice while its GL entry and the customer's decremented
 *     `credit_balance` both survived — AR drifted upward by that amount.
 *
 *  2. `credit_offset` sent on update was never read at all. The Flutter
 *     form re-sends it on every edit, so a genuine change was accepted
 *     with a 200 and discarded.
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
import { resolveSupplierByName } from './helpers/invoiceReturnSpec';

type InvoiceState = {
  total_amount: number;
  paid_amount: number;
  balance_amount: number;
  credit_offset: number | null;
};

describe('invoice update with applied store credit', () => {
  let authCookie: string;
  let itemId: number;
  let customerId: number;
  let warehouseId: number;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');

    warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;

    const item = await request(app).post('/api/inventory/items')
      .set('Cookie', authCookie)
      .send({ item_code: `UPDCR-${Date.now()}`, item_name: 'Update Credit Item' });
    expect(item.status).toBe(201);
    itemId = item.body.id;
    // ACCT-005: purchases must name an identified supplier.
    const supplierId = await resolveSupplierByName('Update Credit Supplier', authCookie);
    await request(app).post('/api/purchases')
      .set('Cookie', authCookie)
      .send({
        item_id: itemId,
        warehouse_id: warehouseId,
        quantity: 40,
        unit_cost: 10,
        purchase_date: '2026-08-01',
        supplier_id: supplierId,
      });

    const customer = await request(app).post('/api/customers')
      .set('Cookie', authCookie)
      .send({ customer_name: `Update Credit Customer ${Date.now()}`, phone: '555-0777' });
    expect(customer.status).toBe(201);
    customerId = customer.body.data?.id ?? customer.body.id;
  });

  /**
   * Give the customer a real 400 credit pool the way the app does: sell on
   * account, pay in full, return the goods with `disposition: 'credit'`.
   *
   * Called once per credited invoice rather than memoized — each invoice
   * consumes the whole pool, so a shared seed would make every test after
   * the first fail on insufficient credit.
   */
  async function seedCreditPool(): Promise<void> {
    const created = await request(app).post('/api/invoices')
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId,
        invoice_date: '2026-09-01',
        due_date: '2026-09-15',
        items: [{
          item_id: itemId,
          description: 'Update Credit Item',
          quantity: 4,
          unit_price: 100,
          tax_rate: 0,
          discount_type: 'none',
          discount_value: 0,
        }],
        total_amount: 400,
        record_payment: true,
        payment: {
          payment_date: '2026-09-01',
          amount: 400,
          payment_method: 'Cash',
        },
      });
    expect(created.status).toBe(201);

    const invoiceItem = db.prepare('SELECT id FROM invoice_items WHERE invoice_id = ?')
      .get(created.body.id) as { id: number };

    const returned = await request(app)
      .post(`/api/invoices/${created.body.id}/return`)
      .set('Cookie', authCookie)
      .send({
        reason: 'seed credit pool',
        disposition: 'credit',
        warehouse_id: warehouseId,
        items: [{ invoice_item_id: invoiceItem.id, return_quantity: 4 }],
      });
    expect(returned.status).toBe(200);
  }

  /** Create a 600 invoice settled with 400 of store credit and 200 cash. */
  async function createCreditedInvoice(): Promise<number> {
    await seedCreditPool();

    const res = await request(app).post('/api/invoices')
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId,
        invoice_date: '2026-09-10',
        due_date: '2026-09-24',
        items: [{
          item_id: itemId,
          description: 'Update Credit Item',
          quantity: 3,
          unit_price: 200,
          tax_rate: 0,
          discount_type: 'none',
          discount_value: 0,
        }],
        total_amount: 600,
        credit_offset: 400,
        record_payment: true,
        payment: {
          payment_date: '2026-09-10',
          amount: 200,
          payment_method: 'Cash',
        },
      });
    expect(res.status).toBe(201);
    expect(res.body.paid_amount).toBeCloseTo(600, 2);
    expect(res.body.balance_amount).toBeCloseTo(0, 2);
    return res.body.id as number;
  }

  function state(invoiceId: number): InvoiceState {
    const row = db.prepare(
      'SELECT total_amount, paid_amount, balance_amount, credit_offset FROM invoices WHERE id = ?',
    ).get(invoiceId) as InvoiceState;
    return {
      total_amount: Number(row.total_amount),
      paid_amount: Number(row.paid_amount),
      balance_amount: Number(row.balance_amount),
      credit_offset: row.credit_offset === null ? null : Number(row.credit_offset),
    };
  }

  function glOffsetTotal(invoiceId: number): number {
    const row = db.prepare(`
      SELECT COALESCE(SUM(jl.debit), 0) AS total
      FROM journal_lines jl
      JOIN journal_entries je ON je.id = jl.journal_entry_id
      WHERE je.reference_type = 'CREDIT_OFFSET'
        AND je.reference_id = ?
        AND jl.voided = 0
    `).get(invoiceId) as { total: number };
    return Number(row.total);
  }

  function updateBody(invoiceId: number, extra: Record<string, unknown> = {}) {
    return {
      customer_id: customerId,
      invoice_date: '2026-09-10',
      due_date: '2026-09-24',
      items: [{
        item_id: itemId,
        description: 'Update Credit Item',
        quantity: 3,
        unit_price: 200,
        tax_rate: 0,
        discount_type: 'none',
        discount_value: 0,
      }],
      total_amount: 600,
      ...extra,
    };
  }

  it('keeps the applied credit in paid_amount when the invoice is edited', async () => {
    const invoiceId = await createCreditedInvoice();
    const before = state(invoiceId);

    const res = await request(app).put(`/api/invoices/${invoiceId}`)
      .set('Cookie', authCookie)
      .send(updateBody(invoiceId));
    expect(res.status).toBe(200);

    const after = state(invoiceId);
    expect(after.paid_amount).toBeCloseTo(before.paid_amount, 2);
    expect(after.paid_amount).toBeCloseTo(600, 2);
    expect(after.balance_amount).toBeCloseTo(0, 2);
    // The defect: paid_amount collapsed to the 200 cash payment alone,
    // stranding the 400 credit and overstating AR by the same amount.
    expect(after.paid_amount).toBeGreaterThan(200);
  });

  it('does not lose the credit across several successive edits', async () => {
    const invoiceId = await createCreditedInvoice();

    for (let i = 0; i < 3; i += 1) {
      const res = await request(app).put(`/api/invoices/${invoiceId}`)
        .set('Cookie', authCookie)
        .send(updateBody(invoiceId));
      expect(res.status).toBe(200);
      expect(state(invoiceId).paid_amount).toBeCloseTo(600, 2);
    }
  });

  it('still accepts the unchanged credit_offset the form re-sends on every edit', async () => {
    const invoiceId = await createCreditedInvoice();

    const res = await request(app).put(`/api/invoices/${invoiceId}`)
      .set('Cookie', authCookie)
      .send(updateBody(invoiceId, { credit_offset: 400 }));
    expect(res.status).toBe(200);
    expect(state(invoiceId).credit_offset).toBeCloseTo(400, 2);
    expect(state(invoiceId).paid_amount).toBeCloseTo(600, 2);
  });

  it('rejects a changed credit_offset instead of silently discarding it', async () => {
    const invoiceId = await createCreditedInvoice();
    const before = state(invoiceId);

    const res = await request(app).put(`/api/invoices/${invoiceId}`)
      .set('Cookie', authCookie)
      .send(updateBody(invoiceId, { credit_offset: 100 }));
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/cannot be changed/i);

    const after = state(invoiceId);
    expect(after.credit_offset).toBeCloseTo(before.credit_offset as number, 2);
    expect(after.paid_amount).toBeCloseTo(before.paid_amount, 2);
  });

  it('leaves the GL offset entry and the credit pool consistent with the invoice', async () => {
    const invoiceId = await createCreditedInvoice();

    const poolBefore = (db.prepare('SELECT credit_balance FROM customers WHERE id = ?')
      .get(customerId) as { credit_balance: number }).credit_balance;

    const res = await request(app).put(`/api/invoices/${invoiceId}`)
      .set('Cookie', authCookie)
      .send(updateBody(invoiceId, { credit_offset: 400 }));
    expect(res.status).toBe(200);

    const poolAfter = (db.prepare('SELECT credit_balance FROM customers WHERE id = ?')
      .get(customerId) as { credit_balance: number }).credit_balance;

    expect(Number(poolAfter)).toBeCloseTo(Number(poolBefore), 2);
    expect(glOffsetTotal(invoiceId)).toBeCloseTo(400, 2);
    expect(state(invoiceId).credit_offset).toBeCloseTo(400, 2);
  });

  it('rejects raising credit above the invoice total', async () => {
    const invoiceId = await createCreditedInvoice();

    const res = await request(app).put(`/api/invoices/${invoiceId}`)
      .set('Cookie', authCookie)
      .send({
        ...updateBody(invoiceId),
        total_amount: 600,
        items: [{
          item_id: itemId,
          description: 'Update Credit Item',
          quantity: 3,
          unit_price: 200,
          tax_rate: 0,
          discount_type: 'none',
          discount_value: 0,
        }],
        record_payment: true,
        payment: { payment_date: '2026-09-10', amount: 500, payment_method: 'Cash' },
      });
    expect(res.status).toBe(400);
    expect(state(invoiceId).balance_amount).toBeCloseTo(0, 2);
  });
});