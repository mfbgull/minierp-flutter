/**
 * REGRESSION: repeat partial returns must fully restock physical stock.
 *
 * Root cause: reverseStockForItems() subtracted already-returned quantity
 * from the current return quantity before computing the batch-restore ratio.
 * On a second partial return of 3 items (after a first return of 2), only
 * 1 item was restocked instead of 3. The GL posted correctly for the full
 * 3, so stock and GL drifted apart.
 *
 * The fix uses totalToReturn directly for the RETURN path, because the
 * caller passes this return's quantity only and tracks accumulation itself.
 */

import request from 'supertest';
import app from '../app';
import db from '../config/database';

async function api(method: 'get' | 'post' | 'put' | 'delete', url: string, body?: unknown) {
  let r = (request(app) as any)[method](url);
  if (global.authCookie) r = r.set('Cookie', global.authCookie);
  if (body !== undefined) r = r.send(body);
  const res = await r;
  return res;
}

function stockOf(itemId: number): number {
  return Number((db.prepare('SELECT COALESCE(SUM(quantity),0) q FROM stock_balances WHERE item_id = ?').get(itemId) as { q: number }).q);
}

describe('partial return restock regression', () => {
  let warehouseId: number;
  let customerId: number;
  let itemId: number;

  beforeAll(async () => {
    const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD as string;
    const login = await request(app)
      .post('/api/auth/login')
      .send({ username: 'admin', password: TEST_PASSWORD });
    const cookies = login.headers['set-cookie'] ?? [];
    const list = Array.isArray(cookies) ? cookies : [cookies];
    const tokenCookie = list.find((c: string) => c.startsWith('token='));
    if (!tokenCookie) throw new Error('Login failed: no token cookie');
    global.authCookie = tokenCookie.split(';')[0];

    warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
    customerId = (db.prepare('INSERT INTO customers (customer_name, customer_code, phone) VALUES (?, ?, ?) RETURNING id').get('Restock Test Cust', 'RESTOCK-CUST', '0300') as { id: number }).id;
    itemId = (db.prepare(`INSERT INTO items (item_code, item_name, unit_of_measure, standard_cost, standard_selling_price, current_stock)
      VALUES (?, ?, ?, ?, ?, ?) RETURNING id`.replace(/\n/g, '\n')).get('RESTOCK-ITEM', 'Restock Test Item', 'pcs', 100, 200, 100) as { id: number }).id;
  });

  it('two partial returns on same line fully restock physical stock', async () => {
    // Buy 10 units into stock
    const buy = await api('post', '/api/purchases', {
      warehouse_id: warehouseId,
      purchase_date: '2026-09-10',
      items: [{ item_id: itemId, quantity: 10, unit_cost: 100 }],
    });
    expect(buy.status).toBe(201);

    const initialStock = stockOf(itemId);
    expect(initialStock).toBe(10);

    // Sell 10 units (stock goes to 0)
    const inv = await api('post', '/api/invoices', {
      customer_id: customerId,
      invoice_date: '2026-09-11',
      warehouse_id: warehouseId,
      items: [{ item_id: itemId, quantity: 10, unit_price: 200 }],
    });
    expect(inv.status).toBe(201);
    const invoiceId = (inv.body as any).id;
    const invoiceItemId = (inv.body as any).items?.[0]?.id ?? (db.prepare('SELECT id FROM invoice_items WHERE invoice_id = ?').get(invoiceId) as any).id;

    expect(stockOf(itemId)).toBe(0);

    // First partial return: 2 units
    const r1 = await api('post', `/api/invoices/${invoiceId}/return`, {
      items: [{ invoice_item_id: invoiceItemId, return_quantity: 2 }],
      disposition: 'credit',
    });
    expect(r1.status).toBe(200);
    expect(stockOf(itemId)).toBeCloseTo(2, 5);

    // Second partial return: 3 units
    const r2 = await api('post', `/api/invoices/${invoiceId}/return`, {
      items: [{ invoice_item_id: invoiceItemId, return_quantity: 3 }],
      disposition: 'credit',
    });
    console.log('R2 status:', r2.status, 'body:', JSON.stringify(r2.body).slice(0, 200));
    expect(r2.status).toBe(200);

    // Total stock restored must equal sum of both returns (2 + 3 = 5)
    const finalStock = stockOf(itemId);
    console.log('finalStock:', finalStock, 'expected 5');
    expect(finalStock).toBeCloseTo(5, 5);

    // Verify GL inventory reflects the full return value
    const glInventory = db.prepare(`
      SELECT COALESCE(SUM(debit), 0) - COALESCE(SUM(credit), 0) AS net
      FROM journal_lines jl
      JOIN chart_of_accounts coa ON coa.id = jl.account_id
      WHERE jl.reference_type = 'INVOICE_RETURN'
        AND jl.voided = 0
        AND coa.code = '1200'
    `).get() as { net: number };
    // 5 units * 100 cost = 500 inventory restored
    expect(Number(glInventory.net)).toBeCloseTo(500, 1);
  });

  it('full return then partial return on same line restock correctly', async () => {
    const itemId2 = (db.prepare(`INSERT INTO items (item_code, item_name, unit_of_measure, standard_cost, standard_selling_price, current_stock)
      VALUES (?, ?, ?, ?, ?, ?) RETURNING id`.replace(/\n/g, '\n')).get('RESTOCK-ITEM-2', 'Restock Test Item 2', 'pcs', 100, 200, 0) as { id: number }).id;

    const buy = await api('post', '/api/purchases', {
      warehouse_id: warehouseId,
      purchase_date: '2026-09-12',
      items: [{ item_id: itemId2, quantity: 10, unit_cost: 100 }],
    });
    expect(buy.status).toBe(201);

    const inv = await api('post', '/api/invoices', {
      customer_id: customerId,
      invoice_date: '2026-09-13',
      warehouse_id: warehouseId,
      items: [{ item_id: itemId2, quantity: 10, unit_price: 200 }],
    });
    expect(inv.status).toBe(201);
    const invoiceId = (inv.body as any).id;
    const invoiceItemId = (db.prepare('SELECT id FROM invoice_items WHERE invoice_id = ?').get(invoiceId) as any).id;

    // Full return first
    const r1 = await api('post', `/api/invoices/${invoiceId}/return`, {
      items: [{ invoice_item_id: invoiceItemId, return_quantity: 6 }],
      disposition: 'credit',
    });
    expect(r1.status).toBe(200);
    expect(stockOf(itemId2)).toBeCloseTo(6, 5);

    // Second partial return
    const r2 = await api('post', `/api/invoices/${invoiceId}/return`, {
      items: [{ invoice_item_id: invoiceItemId, return_quantity: 2 }],
      disposition: 'credit',
    });
    expect(r2.status).toBe(200);

    // Total: 6 + 2 = 8
    expect(stockOf(itemId2)).toBeCloseTo(8, 5);
  });
});
