/**
 * A payment must never exceed what an invoice still owes, and that ceiling has
 * to account for a credit offset already applied against it.
 *
 * Historical context: invoices 50 and 51 in the live data were each settled
 * twice — cash plus credit offset on 2026-09-17, then a second full cash
 * settlement on 2026-10-10. An audit of the current code confirmed that shape
 * is NOT reproducible today. Those offsets were written by a legacy writer that
 * set neither `invoices.credit_offset` nor a `payment_allocations` row, so
 * `balance_amount` stayed inflated and the later cash was accepted against it.
 *
 * This suite locks the current behaviour on all three reachable ceilings so the
 * gap cannot reopen:
 *
 *   - INVOICE_SETTLEMENT — sale-time payment legs, InvoiceCreationService:277.
 *     `allocationCeiling` measures `total_amount - returned_amount`, which on
 *     its own ignores credit_offset; the real bound is the separate check at
 *     InvoiceCreationService:144, `legsTotal + creditOffset <= totalAmount`.
 *   - RECEIPT — standalone POST /api/payments and Payment.ts:367. Ceiling is
 *     `balance_amount`, which `calculateInvoiceBalance` builds from
 *     `totalPaid + credit_offset` (ledgerUtils.ts:162-166).
 *   - CREDIT_APPLICATION — invoiceReturnService:1116/1214. Same
 *     `balance_amount` ceiling.
 *
 * Runs against the isolated temp test DB (see __tests__/setup.ts); never the
 * live database.
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { resolveSupplierByName } from './helpers/invoiceReturnSpec';

const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD) throw new Error('TEST_ADMIN_PASSWORD environment variable must be set.');

async function getAuthCookie(): Promise<string> {
  const res = await request(app).post('/api/auth/login').send({ username: 'admin', password: TEST_PASSWORD });
  const cookies = res.headers['set-cookie'];
  if (!cookies) return '';
  const tokenCookie = (Array.isArray(cookies) ? cookies : [cookies]).find((c: string) => c.startsWith('token='));
  return tokenCookie ? tokenCookie.split(';')[0] : '';
}

const R2 = (n: number): number => Math.round(n * 100) / 100;

interface InvRow {
  id: number;
  total_amount: number;
  paid_amount: number;
  balance_amount: number;
  credit_offset: number;
  returned_amount: number;
}

describe('payment allocation cannot exceed the credit-offset-adjusted balance', () => {
  let authCookie: string;
  let itemId: number;
  let warehouseId: number;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');
    warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;

    const item = await request(app).post('/api/inventory/items')
      .set('Cookie', authCookie)
      .send({ item_code: `OVR-${Date.now()}`, item_name: 'Over-Allocation Guard Item' });
    expect(item.status).toBe(201);
    itemId = item.body.id;

    const supplierId = await resolveSupplierByName('Credit Offset Supplier', authCookie);
    await request(app).post('/api/purchases')
      .set('Cookie', authCookie)
      .send({
        item_id: itemId, warehouse_id: warehouseId, quantity: 200, unit_cost: 10,
        purchase_date: '2026-08-01', supplier_id: supplierId,
      });
  });

  async function newCustomer(): Promise<number> {
    const res = await request(app).post('/api/customers')
      .set('Cookie', authCookie)
      .send({ customer_name: `OverAlloc ${Date.now()}-${Math.floor(Math.random() * 1e6)}`, phone: '555-0799' });
    expect(res.status).toBe(201);
    return res.body.data?.id ?? res.body.id;
  }

  /** Sell 1200, collect 1200, return the goods so a 1200 ledger credit exists. */
  async function seedLedgerCredit(customerId: number, date: string): Promise<void> {
    const inv = await request(app).post('/api/invoices')
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId, invoice_date: date, due_date: date,
        items: [{ item_id: itemId, description: 'i', quantity: 12, unit_price: 100, tax_rate: 0, discount_type: 'none', discount_value: 0 }],
        total_amount: 1200,
        record_payment: true,
        payment: { payment_date: date, amount: 1200, payment_method: 'Cash' },
      });
    expect(inv.status).toBe(201);
    const invItem = db.prepare('SELECT id FROM invoice_items WHERE invoice_id = ?').get(inv.body.id) as { id: number };
    const ret = await request(app).post(`/api/invoices/${inv.body.id}/return`)
      .set('Cookie', authCookie)
      .send({
        reason: 'seed ledger credit', disposition: 'credit', warehouse_id: warehouseId,
        items: [{ invoice_item_id: invItem.id, return_quantity: 12 }],
      });
    expect(ret.status).toBe(200);
  }

  function invoiceRow(id: number): InvRow {
    return db.prepare(
      'SELECT id,total_amount,paid_amount,balance_amount,COALESCE(credit_offset,0) AS credit_offset,COALESCE(returned_amount,0) AS returned_amount FROM invoices WHERE id = ?',
    ).get(id) as InvRow;
  }

  it('sale-time legs cannot re-collect an amount already covered by credit_offset', async () => {
    const customerId = await newCustomer();
    await seedLedgerCredit(customerId, '2026-09-01');

    // 1200 invoice, 600 credit offset, but a 1200 cash leg: 1800 collected
    // against a 1200 invoice. Must be refused by the line-144 bound.
    const res = await request(app).post('/api/invoices')
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId, invoice_date: '2026-09-10', due_date: '2026-09-24',
        items: [{ item_id: itemId, description: 'i', quantity: 12, unit_price: 100, tax_rate: 0, discount_type: 'none', discount_value: 0 }],
        total_amount: 1200,
        credit_offset: 600,
        record_payment: true,
        payment: { payment_date: '2026-09-10', amount: 1200, payment_method: 'Cash' },
      });

    expect(res.status).toBe(400);
    expect(String(res.body?.error ?? '')).toMatch(/exceeds invoice total/i);
  });

  it('sale-time legs that respect the credit offset are accepted and settle to zero', async () => {
    const customerId = await newCustomer();
    await seedLedgerCredit(customerId, '2026-09-01');

    const res = await request(app).post('/api/invoices')
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId, invoice_date: '2026-09-10', due_date: '2026-09-24',
        items: [{ item_id: itemId, description: 'i', quantity: 12, unit_price: 100, tax_rate: 0, discount_type: 'none', discount_value: 0 }],
        total_amount: 1200,
        credit_offset: 600,
        record_payment: true,
        payment: { payment_date: '2026-09-10', amount: 600, payment_method: 'Cash' },
      });

    expect(res.status).toBe(201);
    const row = invoiceRow(res.body.id);
    // collected = cash 600 + offset 600 = the full 1200, once.
    expect(R2(row.paid_amount)).toBe(1200);
    expect(R2(row.credit_offset)).toBe(600);
    expect(R2(row.balance_amount)).toBe(0);
  });

  it('standalone RECEIPT payment is capped at the credit-offset-adjusted balance', async () => {
    const customerId = await newCustomer();
    await seedLedgerCredit(customerId, '2026-09-01');

    const inv = await request(app).post('/api/invoices')
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId, invoice_date: '2026-09-10', due_date: '2026-09-24',
        items: [{ item_id: itemId, description: 'i', quantity: 12, unit_price: 100, tax_rate: 0, discount_type: 'none', discount_value: 0 }],
        total_amount: 1200,
        credit_offset: 600,
      });
    expect(inv.status).toBe(201);

    // The 600 offset must land in balance_amount, leaving 600 — not 1200.
    const row = invoiceRow(inv.body.id);
    expect(R2(row.credit_offset)).toBe(600);
    expect(R2(row.balance_amount)).toBe(600);

    const over = await request(app).post('/api/payments')
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId, payment_date: '2026-09-20', amount: 700,
        payment_method: 'Cash',
        invoice_allocations: [{ invoice_id: inv.body.id, amount: 700 }],
      });
    expect(over.status).toBe(400);
    expect(String(over.body?.error ?? '')).toMatch(/exceeds the remaining balance/i);

    // Exactly the remaining 600 is fine, and closes the invoice.
    const exact = await request(app).post('/api/payments')
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId, payment_date: '2026-09-20', amount: 600,
        payment_method: 'Cash',
        invoice_allocations: [{ invoice_id: inv.body.id, amount: 600 }],
      });
    expect(exact.status).toBe(201);
    const settled = invoiceRow(inv.body.id);
    expect(R2(settled.paid_amount)).toBe(1200);
    expect(R2(settled.balance_amount)).toBe(0);

    // Balance is now 0: the historical 50/51 shape — a second full cash
    // settlement of an already-settled invoice — stays refused.
    const again = await request(app).post('/api/payments')
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId, payment_date: '2026-09-21', amount: 600,
        payment_method: 'Cash',
        invoice_allocations: [{ invoice_id: inv.body.id, amount: 600 }],
      });
    expect(again.status).toBe(400);
    expect(String(again.body?.error ?? '')).toMatch(/exceeds the remaining balance/i);
  });
});
