/**
 * H2 historical repair — backfillInvoiceHeaderDiscount.
 *
 * Invoices created before the fix stored discount_value = 0 on a total
 * that was already discounted. The gap between the tax-inclusive line
 * sum and the stored total IS the flat discount; the repair writes it
 * back so returns give it back. Idempotent, and it leaves cancelled and
 * undiscounted invoices alone.
 */
import db from '../config/database';
import { runBackfillInvoiceHeaderDiscount } from '../migrations/backfillInvoiceHeaderDiscount';
import request from 'supertest';
import app from '../app';
import {
  getAuthCookie, createItem, purchaseStock, createCustomer,
  processReturn,
} from './helpers/invoiceReturnSpec';
import { parseCurrency } from '../utils/currency';

function invoiceRow(invoiceId: number): {
  total_amount: number; discount_scope: string; discount_type: string;
  discount_value: number; status: string;
} {
  return db.prepare(
    'SELECT total_amount, discount_scope, discount_type, discount_value, status FROM invoices WHERE id = ?'
  ).get(invoiceId) as {
    total_amount: number; discount_scope: string; discount_type: string;
    discount_value: number; status: string;
  };
}

function returnsCredited(invoiceId: number): number {
  const row = db.prepare(
    'SELECT COALESCE(SUM(returned_amount), 0) AS s FROM invoice_returns WHERE invoice_id = ? AND voided_at IS NULL'
  ).get(invoiceId) as { s: number };
  return parseCurrency(row.s);
}

async function seedDiscountedInvoice(): Promise<{ invoiceId: number; invoiceItemIds: number[] }> {
  const res = await request(app).post('/api/invoices')
    .set('Cookie', authCookie)
    .send({
      customer_id: customerId,
      invoice_date: '2026-09-15',
      due_date: '2026-09-30',
      discount_scope: 'invoice',
      discount_type: 'flat',
      discount_value: 100,
      items: [{ item_id: itemId, quantity: 2, unit_price: 500, tax_rate: 0, discount_type: 'none', discount_value: 0 }],
    });
  if (res.status !== 201 && res.status !== 200) {
    throw new Error(`seed failed: ${res.status} ${JSON.stringify(res.body)}`);
  }
  const invoiceId: number = res.body.id;
  const rows = db.prepare('SELECT id FROM invoice_items WHERE invoice_id = ? ORDER BY id')
    .all(invoiceId) as Array<{ id: number }>;
  return { invoiceId, invoiceItemIds: rows.map((r) => r.id) };
}

let authCookie: string;
let itemId: number;
let customerId: number;
let warehouseId: number;

describe('H2 repair migration — backfillInvoiceHeaderDiscount', () => {
  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');
    const wh = db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number };
    warehouseId = wh.id;
    itemId = await createItem('Header Discount Repair Widget (H2)', authCookie);
    await purchaseStock(itemId, warehouseId, 100, 100, authCookie);
    customerId = await createCustomer('Header Discount Repair Customer (H2)', authCookie);
  });

  it('recovers the discount as a flat value equal to the line-sum gap', async () => {
    const { invoiceId } = await seedDiscountedInvoice();
    expect(invoiceRow(invoiceId).total_amount).toBeCloseTo(900, 2);

    // Simulate the pre-H2 stored state: total already discounted, but the
    // discount column never written.
    db.prepare('UPDATE invoices SET discount_value = 0, discount_type = ? WHERE id = ?')
      .run('percentage', invoiceId);

    runBackfillInvoiceHeaderDiscount(db);

    const row = invoiceRow(invoiceId);
    expect(row.discount_type).toBe('flat');
    expect(row.discount_value).toBeCloseTo(100, 2);
  });

  it('a full return after the repair credits exactly the grand total', async () => {
    const { invoiceId, invoiceItemIds } = await seedDiscountedInvoice();
    db.prepare('UPDATE invoices SET discount_value = 0 WHERE id = ?').run(invoiceId);

    runBackfillInvoiceHeaderDiscount(db);
    expect(invoiceRow(invoiceId).discount_value).toBeCloseTo(100, 2);

    const res = await processReturn(invoiceId, {
      invoiceItemIds, quantities: [2], feeType: 'none', warehouseId,
      returnDate: '2026-09-16',
    }, authCookie);
    expect(res.status).toBe(200);
    expect(returnsCredited(invoiceId)).toBeCloseTo(900, 2);
  });

  it('is idempotent: a second run changes nothing', async () => {
    const { invoiceId } = await seedDiscountedInvoice();
    db.prepare('UPDATE invoices SET discount_value = 0 WHERE id = ?').run(invoiceId);

    runBackfillInvoiceHeaderDiscount(db);
    const afterFirst = invoiceRow(invoiceId).discount_value;

    runBackfillInvoiceHeaderDiscount(db);
    expect(invoiceRow(invoiceId).discount_value).toBeCloseTo(afterFirst, 2);
  });

  it('undiscounted invoices are left alone', async () => {
    const res = await request(app).post('/api/invoices')
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId,
        invoice_date: '2026-09-15',
        due_date: '2026-09-30',
        items: [{ item_id: itemId, quantity: 1, unit_price: 500, tax_rate: 0, discount_type: 'none', discount_value: 0 }],
      });
    const invoiceId: number = res.body.id;
    expect(invoiceRow(invoiceId).total_amount).toBeCloseTo(500, 2);

    runBackfillInvoiceHeaderDiscount(db);
    expect(invoiceRow(invoiceId).discount_value).toBe(0);
  });

  it('cancelled invoices are not repaired', async () => {
    const { invoiceId } = await seedDiscountedInvoice();
    db.prepare('UPDATE invoices SET discount_value = 0, status = ? WHERE id = ?')
      .run('Cancelled', invoiceId);

    runBackfillInvoiceHeaderDiscount(db);
    expect(invoiceRow(invoiceId).discount_value).toBe(0);
  });
});
