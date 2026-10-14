/**
 * The FIFO allocator must never fabricate stock.
 *
 * When an item HAS batches in a warehouse but every one of them is
 * exhausted, while stock_balances still carries a quantity, the allocator
 * used to fall through to its "legacy unbatched stock" branch and return
 * the full requested quantity at the item's standard cost. That invented
 * stock out of a balance no batch could back, then deducted it from
 * stock_balances — driving the balance negative and posting COGS against
 * goods that were never there.
 *
 * Genuine legacy stock (NO batch rows at all for the item in that
 * warehouse) is a different condition and must keep working.
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { getAuthCookie, createItem, purchaseStock, createCustomer, resolveSupplierByName } from './helpers/invoiceReturnSpec';

const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD) throw new Error('TEST_ADMIN_PASSWORD environment variable must be set.');

let authCookie: string;
let warehouseId: number;
let customerId: number;
let supId: number;
let seq = 0;

beforeAll(async () => {
  authCookie = await getAuthCookie();
  warehouseId = (db.prepare('SELECT id FROM warehouses WHERE is_active = 1 ORDER BY id LIMIT 1').get() as { id: number }).id;
  customerId = await createCustomer(`FABRICATED-${Date.now()}`, authCookie);
  supId = await resolveSupplierByName('Fabricated Stock Supplier', authCookie);
});

describe('allocator must not fabricate stock', () => {
  it('refuses to sell when the item has batches but all are exhausted', async () => {
    seq += 1;
    const itemId = await createItem(`FAB-EXHAUSTED-${Date.now()}`, authCookie);
    await purchaseStock(itemId, warehouseId, 10, 5, authCookie);

    // Exhaust every batch for this item while leaving stock_balances intact —
    // the exact shape the fallback used to fabricate against.
    db.prepare(
      `UPDATE stock_batches SET quantity_remaining = 0
       WHERE item_id = ? AND warehouse_id = ?`,
    ).run(itemId, warehouseId);
    db.prepare(
      `UPDATE batch_stock_by_location SET quantity_physical = 0, quantity_available = 0
       WHERE batch_id IN (SELECT id FROM stock_batches WHERE item_id = ?)`,
    ).run(itemId);

    const balanceBefore = (db
      .prepare(`SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?`)
      .get(itemId, warehouseId) as { quantity: number }).quantity;

    const res = await request(app)
      .post('/api/invoices')
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId,
        invoice_date: '2026-09-15',
        items: [{ item_id: itemId, quantity: 3, unit_price: 20, amount: 60 }],
      });

    expect(res.status).toBeGreaterThanOrEqual(400);

    // The whole point: the balance must not be debited for stock that does
    // not exist, and must certainly not go negative.
    const balanceAfter = (db
      .prepare(`SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?`)
      .get(itemId, warehouseId) as { quantity: number }).quantity;
    expect(Number(balanceAfter)).toBe(Number(balanceBefore));
    expect(Number(balanceAfter)).toBeGreaterThanOrEqual(0);

    const invoices = db
      .prepare(`SELECT COUNT(*) AS c FROM invoices WHERE customer_id = ?`)
      .get(customerId) as { c: number };
    expect(Number(invoices.c)).toBe(0);
  });

  it('still supports genuine legacy stock that has no batch rows', async () => {
    seq += 1;
    const itemId = await createItem(`FAB-LEGACY-${Date.now()}`, authCookie);

    // A balance with no batches at all is the real legacy case: opening
    // stock that predates batch costing. It must remain sellable.
    db.prepare(
      `INSERT INTO stock_balances (item_id, warehouse_id, quantity) VALUES (?, ?, 10)
       ON CONFLICT(item_id, warehouse_id) DO UPDATE SET quantity = 10`,
    ).run(itemId, warehouseId);

    const res = await request(app)
      .post('/api/invoices')
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId,
        invoice_date: '2026-09-16',
        items: [{ item_id: itemId, quantity: 2, unit_price: 20, amount: 40 }],
      });

    expect(res.status).toBe(201);
    const balanceAfter = (db
      .prepare(`SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?`)
      .get(itemId, warehouseId) as { quantity: number }).quantity;
    expect(Number(balanceAfter)).toBe(8);
  });
});