/**
 * BUG-006 — sales order lines carry tax and discount.
 *
 * The Flutter order form already collects a tax rate and a discount per
 * line, but `sales_order_items` had no columns for them, so the server
 * silently dropped both. This suite pins the fixed contract.
 *
 * Rounding parity: the server recomputes every line with the shared
 * `decomposeLineAmount` (round at each boundary). The Dart client must
 * produce the same number for the same input — see the shared fixture in
 * `test/features/sales/sales_order_tax_discount_parity_test.dart`, which
 * reads the same table below. Do not change the numbers on one side
 * alone.
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { createCustomer, createItem, getAuthCookie, purchaseStock } from './helpers/invoiceReturnSpec';
import { computeInvoiceTotal } from '../utils/currency';

const IDEMPOTENCY_KEY = 'so-tax-discount-key';

interface SoLine {
  item_id: number;
  quantity: number;
  unit_price: number;
  tax_rate?: number;
  discount_type?: string;
  discount_value?: number;
}

async function createOrder(
  cookie: string,
  customerId: number,
  items: SoLine[],
  key = IDEMPOTENCY_KEY,
): Promise<{ status: number; body: Record<string, unknown> }> {
  const res = await request(app)
    .post('/api/sales-orders')
    .set('Cookie', cookie)
    .set('Idempotency-Key', key)
    .send({ customer_id: customerId, so_date: '2026-11-01', items });
  return { status: res.status, body: res.body as Record<string, unknown> };
}

async function readOrder(
  cookie: string,
  id: number,
): Promise<{ total_amount: number; items: Array<Record<string, number | string>> }> {
  const res = await request(app)
    .get(`/api/sales-orders/${id}`)
    .set('Cookie', cookie);
  if (res.status !== 200) throw new Error(`so read ${res.status}`);
  return res.body as { total_amount: number; items: Array<Record<string, number | string>> };
}

describe('sales order line tax and discount (BUG-006)', () => {
  let cookie: string;
  let itemId: number;
  let customerId: number;

  beforeAll(async () => {
    cookie = await getAuthCookie();
    itemId = await createItem('SO Tax Item', cookie);
    customerId = await createCustomer('SO Tax Co', cookie);
    // The conversion path deducts stock, so the fixture item needs some.
    const wh = db.prepare('SELECT id FROM warehouses WHERE is_active = 1 LIMIT 1').get() as { id: number };
    await purchaseStock(itemId, wh.id, 500, 40, cookie);
  });

  describe('schema', () => {
    it('sales_order_items has tax_rate, discount_type and discount_value', () => {
      const cols = (db.prepare('PRAGMA table_info(sales_order_items)').all() as Array<{ name: string }>)
        .map((c) => c.name);
      expect(cols).toEqual(expect.arrayContaining(['tax_rate', 'discount_type', 'discount_value']));
    });

    it('an old-shaped insert reads back 0 / none / 0', () => {
      const so = db
        .prepare(
          `INSERT INTO sales_orders (so_no, customer_id, so_date, status, total_amount, created_by)
           VALUES ('SO-BUG006-OLD', ?, '2026-11-01', 'Draft', 10, 1)`,
        )
        .run(customerId);
      const soId = Number(so.lastInsertRowid);
      db.prepare(
        `INSERT INTO sales_order_items (so_id, item_id, quantity, unit_price, amount)
         VALUES (?, ?, 1, 10, 10)`,
      ).run(soId, itemId);
      const row = db
        .prepare('SELECT tax_rate, discount_type, discount_value FROM sales_order_items WHERE so_id = ?')
        .get(soId) as { tax_rate: number; discount_type: string; discount_value: number };
      expect(Number(row.tax_rate)).toBe(0);
      expect(row.discount_type).toBe('none');
      expect(Number(row.discount_value)).toBe(0);
    });
  });

  describe('round trip', () => {
    it('stores and returns a tax rate on the line', async () => {
      const created = await createOrder(cookie, customerId, [
        { item_id: itemId, quantity: 2, unit_price: 100, tax_rate: 17 },
      ], 'so-tax-only');
      expect(created.status).toBe(201);
      const order = await readOrder(cookie, created.body.id as number);
      expect(Number(order.items[0].tax_rate)).toBe(17);
    });

    it('stores a percentage discount on the line', async () => {
      const created = await createOrder(cookie, customerId, [
        {
          item_id: itemId, quantity: 1, unit_price: 200,
          discount_type: 'percentage', discount_value: 10,
        },
      ], 'so-disc-pct');
      expect(created.status).toBe(201);
      const order = await readOrder(cookie, created.body.id as number);
      expect(order.items[0].discount_type).toBe('percentage');
      expect(Number(order.items[0].discount_value)).toBe(10);
    });

    it('the order total is the tax-inclusive, post-discount grand total, not qty x price', async () => {
      // gross 200, 10% off = 180 net, 17% tax = 30.60, total 210.60
      const created = await createOrder(cookie, customerId, [
        {
          item_id: itemId, quantity: 2, unit_price: 100,
          tax_rate: 17, discount_type: 'percentage', discount_value: 10,
        },
      ], 'so-grand-total');
      const order = await readOrder(cookie, created.body.id as number);
      expect(Number(order.total_amount)).toBeCloseTo(210.6, 2);
    });
  });

  describe('old clients keep working', () => {
    it('an order with only {item_id, quantity, unit_price} still creates and totals plainly', async () => {
      const created = await createOrder(cookie, customerId, [
        { item_id: itemId, quantity: 3, unit_price: 50 },
      ], 'so-legacy-shape');
      expect(created.status).toBe(201);
      const order = await readOrder(cookie, created.body.id as number);
      expect(Number(order.total_amount)).toBeCloseTo(150, 2);
      expect(Number(order.items[0].tax_rate)).toBe(0);
      expect(order.items[0].discount_type).toBe('none');
    });
  });

  describe('validation', () => {
    it('rejects a negative tax rate', async () => {
      const created = await createOrder(cookie, customerId, [
        { item_id: itemId, quantity: 1, unit_price: 10, tax_rate: -1 },
      ], 'so-bad-tax');
      expect(created.status).toBe(400);
    });

    it('rejects a percentage discount of 100 or more', async () => {
      const created = await createOrder(cookie, customerId, [
        {
          item_id: itemId, quantity: 1, unit_price: 10,
          discount_type: 'percentage', discount_value: 100,
        },
      ], 'so-bad-disc');
      expect(created.status).toBe(400);
    });
  });

  describe('rounding parity', () => {
    // Each row is duplicated in
    // test/features/sales/sales_order_tax_discount_parity_test.dart. Both
    // sides must produce the same number, or a converted order can fail the
    // total check. Change one table, change the other.
    const cases: Array<[string, SoLine, number]> = [
      ['plain', { item_id: 1, quantity: 3, unit_price: 50 }, 150],
      ['tax only', { item_id: 1, quantity: 2, unit_price: 100, tax_rate: 17 }, 234],
      ['percent discount only', {
        item_id: 1, quantity: 1, unit_price: 200,
        discount_type: 'percentage', discount_value: 10,
      }, 180],
      ['flat discount only', {
        item_id: 1, quantity: 1, unit_price: 200,
        discount_type: 'flat', discount_value: 25,
      }, 175],
      ['tax and percent discount', {
        item_id: 1, quantity: 2, unit_price: 100,
        tax_rate: 17, discount_type: 'percentage', discount_value: 10,
      }, 210.6],
      ['rounding boundary three thirds', {
        item_id: 1, quantity: 3, unit_price: 33.333, tax_rate: 17,
      }, 117],
    ];

    it.each(cases)('%s', (_name, line, expected) => {
      expect(computeInvoiceTotal([line])).toBeCloseTo(expected, 2);
    });
  });

  describe('conversion to invoice', () => {
    async function convert(soId: number, key: string) {
      const res = await request(app)
        .post(`/api/sales-orders/${soId}/convert`)
        .set('Cookie', cookie)
        .set('Idempotency-Key', key)
        .send({});
      return { status: res.status, body: res.body as Record<string, unknown> };
    }

    it('carries the line rates and discount onto the invoice', async () => {
      const created = await createOrder(cookie, customerId, [
        {
          item_id: itemId, quantity: 2, unit_price: 100,
          tax_rate: 17, discount_type: 'percentage', discount_value: 10,
        },
      ], 'so-conv-taxed');
      const conv = await convert(created.body.id as number, 'so-conv-taxed-k');
      expect(conv.status).toBe(201);

      const row = db.prepare(
        `SELECT ii.tax_rate, ii.discount_type, ii.discount_value, i.total_amount
         FROM invoice_items ii JOIN invoices i ON i.id = ii.invoice_id
         WHERE i.id = ?`,
      ).get(conv.body.invoiceId) as {
        tax_rate: number; discount_type: string; discount_value: number; total_amount: number;
      };
      expect(Number(row.tax_rate)).toBe(17);
      expect(row.discount_type).toBe('percentage');
      expect(Number(row.discount_value)).toBe(10);
      // 200 gross -> 180 net -> 30.60 tax -> 210.60 total.
      expect(Number(row.total_amount)).toBeCloseTo(210.6, 2);
    });

    it('a pre-migration order (no tax/discount) converts as it always did', async () => {
      // Insert an old-shaped order directly - no tax/discount values.
      const so = db.prepare(
        `INSERT INTO sales_orders (so_no, customer_id, so_date, status, total_amount, created_by)
         VALUES ('SO-BUG006-CONV', ?, '2026-11-01', 'Confirmed', 150, 1)`,
      ).run(customerId);
      const soId = Number(so.lastInsertRowid);
      db.prepare(
        `INSERT INTO sales_order_items (so_id, item_id, quantity, unit_price, amount)
         VALUES (?, ?, 3, 50, 150)`,
      ).run(soId, itemId);

      const conv = await convert(soId, 'so-conv-legacy-k');
      expect(conv.status).toBe(201);
      const row = db.prepare(
        `SELECT ii.tax_rate, ii.discount_type, i.total_amount
         FROM invoice_items ii JOIN invoices i ON i.id = ii.invoice_id WHERE i.id = ?`,
      ).get(conv.body.invoiceId) as { tax_rate: number; discount_type: string; total_amount: number };
      expect(Number(row.tax_rate)).toBe(0);
      expect(row.discount_type).toBe('none');
      expect(Number(row.total_amount)).toBeCloseTo(150, 2);
    });

    it('a fixed discount converts with an exact invoice total', async () => {
      // 1 x 200, flat 25 -> 175 net, no tax -> 175.00.
      const created = await createOrder(cookie, customerId, [
        {
          item_id: itemId, quantity: 1, unit_price: 200,
          tax_rate: 0, discount_type: 'flat', discount_value: 25,
        },
      ], 'so-conv-flat');
      const conv = await convert(created.body.id as number, 'so-conv-flat-k');
      expect(conv.status).toBe(201);

      const inv = db.prepare(
        `SELECT i.total_amount, ii.discount_type, ii.discount_value
         FROM invoices i JOIN invoice_items ii ON ii.invoice_id = i.id
         WHERE i.id = ?`,
      ).get(conv.body.invoiceId) as {
        total_amount: number; discount_type: string; discount_value: number;
      };
      expect(inv.discount_type).toBe('flat');
      expect(Number(inv.discount_value)).toBe(25);
      expect(Number(inv.total_amount)).toBeCloseTo(175, 2);
    });

    it('a multi-line taxed and discounted order converts to the exact total', async () => {
      // 210.60 + 175.00 = 385.60, matching the parity table's own example.
      const created = await createOrder(cookie, customerId, [
        {
          item_id: itemId, quantity: 2, unit_price: 100,
          tax_rate: 17, discount_type: 'percentage', discount_value: 10,
        },
        {
          item_id: itemId, quantity: 1, unit_price: 200,
          tax_rate: 0, discount_type: 'flat', discount_value: 25,
        },
      ], 'so-conv-multi');
      const conv = await convert(created.body.id as number, 'so-conv-multi-k');
      expect(conv.status).toBe(201);

      const inv = db.prepare('SELECT total_amount FROM invoices WHERE id = ?')
        .get(conv.body.invoiceId) as { total_amount: number };
      const expected = computeInvoiceTotal([
        { quantity: 2, unit_price: 100, tax_rate: 17, discount_type: 'percentage' as const, discount_value: 10 },
        { quantity: 1, unit_price: 200, tax_rate: 0, discount_type: 'flat' as const, discount_value: 25 },
      ]);
      expect(expected).toBeCloseTo(385.6, 2);
      // Exact match: the invoice total is the order total is the parity total.
      expect(Number(inv.total_amount)).toBeCloseTo(expected, 2);
      expect(Number(created.body.total_amount)).toBeCloseTo(expected, 2);
    });
  });

  describe('the server owns the numbers', () => {
    it('ignores a client-sent total_amount and recomputes from the lines', async () => {
      // A lying client: one line of 2 x 100 with 17% tax is 234.00, not 1.00.
      const res = await request(app)
        .post('/api/sales-orders')
        .set('Cookie', cookie)
        .set('Idempotency-Key', 'so-ignore-total')
        .send({
          customer_id: customerId,
          so_date: '2026-11-01',
          total_amount: 1,
          items: [{ item_id: itemId, quantity: 2, unit_price: 100, tax_rate: 17 }],
        });
      expect(res.status).toBe(201);
      expect(Number(res.body.total_amount)).toBeCloseTo(234, 2);

      const read = await readOrder(cookie, res.body.id as number);
      expect(Number(read.total_amount)).toBeCloseTo(234, 2);
      const line = read.items[0] as Record<string, number | string>;
      expect(Number(line.amount)).toBeCloseTo(234, 2);
      expect(Number(line.tax_rate)).toBe(17);
    });

    it('ignores a client-sent line amount and recomputes from the inputs', async () => {
      const res = await request(app)
        .post('/api/sales-orders')
        .set('Cookie', cookie)
        .set('Idempotency-Key', 'so-ignore-line-amount')
        .send({
          customer_id: customerId,
          so_date: '2026-11-01',
          items: [
            { item_id: itemId, quantity: 1, unit_price: 200, amount: 5, tax_rate: 0, discount_type: 'flat', discount_value: 25 },
          ],
        });
      expect(res.status).toBe(201);
      const line = (res.body.items as Array<Record<string, number | string>>)[0];
      expect(Number(line.amount)).toBeCloseTo(175, 2);
    });
  });
});
