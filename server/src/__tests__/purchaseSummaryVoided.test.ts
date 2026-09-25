import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { getAuthCookie, createItem } from './helpers/invoiceReturnSpec';

const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD) {
  throw new Error('TEST_ADMIN_PASSWORD environment variable must be set for integration tests.');
}

let token: string;

beforeAll(async () => {
  token = await getAuthCookie();
});

function insertPurchase(overrides: {
  item_id: number; warehouse_id: number; quantity: number;
  unit_cost: number; total_cost: number; purchase_date: string;
  supplier_name: string; purchase_no: string;
}) {
  return db.prepare(`
    INSERT INTO purchases (purchase_no, item_id, warehouse_id, quantity, unit_cost, total_cost, purchase_date, supplier_name, created_by)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)
  `).run(
    overrides.purchase_no, overrides.item_id, overrides.warehouse_id,
    overrides.quantity, overrides.unit_cost, overrides.total_cost,
    overrides.purchase_date, overrides.supplier_name,
  ).lastInsertRowid as number;
}

function voidPurchase(purchaseId: number) {
  db.prepare(`UPDATE purchases SET voided_at = datetime('now'), voided_by = 1, void_reason = 'P13 test' WHERE id = ?`).run(purchaseId);
}

describe('P13 — voided purchases excluded from summaries', () => {
  let itemId: number;
  let warehouseId: number;

  beforeAll(async () => {
    itemId = await createItem('P13 Summary Item', token);
    const wh = db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number };
    warehouseId = wh.id;
  });

  it('getSummaryByItem excludes voided purchases', () => {
    // 3 active purchases: 10 + 20 + 30 = 60 units, cost 3000
    const p1 = insertPurchase({ item_id: itemId, warehouse_id: warehouseId, quantity: 10, unit_cost: 50, total_cost: 500, purchase_date: '2026-10-01', supplier_name: 'P13 Supplier A', purchase_no: `P13-SUM1-${Date.now()}` });
    const p2 = insertPurchase({ item_id: itemId, warehouse_id: warehouseId, quantity: 20, unit_cost: 50, total_cost: 1000, purchase_date: '2026-10-02', supplier_name: 'P13 Supplier A', purchase_no: `P13-SUM2-${Date.now()}` });
    const p3 = insertPurchase({ item_id: itemId, warehouse_id: warehouseId, quantity: 30, unit_cost: 50, total_cost: 1500, purchase_date: '2026-10-03', supplier_name: 'P13 Supplier B', purchase_no: `P13-SUM3-${Date.now()}` });

    // void p2
    voidPurchase(p2);

    const summary = db.prepare(`
      SELECT COUNT(*) as cnt, SUM(quantity) as qty, SUM(total_cost) as cost
      FROM purchases WHERE item_id = ? AND voided_at IS NULL
    `).get(itemId) as { cnt: number; qty: number; cost: number };

    // only p1 (10) + p3 (30) = 40 units, cost 2000
    expect(summary.cnt).toBe(2);
    expect(summary.qty).toBe(40);
    expect(summary.cost).toBe(2000);

    // cleanup
    db.prepare('DELETE FROM purchases WHERE id IN (?, ?, ?)').run(p1, p2, p3);
  });

  it('getSummaryByDateRange excludes voided purchases', () => {
    const p1 = insertPurchase({ item_id: itemId, warehouse_id: warehouseId, quantity: 15, unit_cost: 50, total_cost: 750, purchase_date: '2026-10-05', supplier_name: 'P13 Supplier C', purchase_no: `P13-DR1-${Date.now()}` });
    const p2 = insertPurchase({ item_id: itemId, warehouse_id: warehouseId, quantity: 25, unit_cost: 50, total_cost: 1250, purchase_date: '2026-10-06', supplier_name: 'P13 Supplier C', purchase_no: `P13-DR2-${Date.now()}` });

    voidPurchase(p2);

    const summary = db.prepare(`
      SELECT COUNT(*) as cnt, SUM(quantity) as qty, SUM(total_cost) as cost
      FROM purchases WHERE purchase_date BETWEEN '2026-10-05' AND '2026-10-06' AND voided_at IS NULL
    `).get() as { cnt: number; qty: number; cost: number };

    expect(summary.cnt).toBe(1);
    expect(summary.qty).toBe(15);
    expect(summary.cost).toBe(750);

    db.prepare('DELETE FROM purchases WHERE id IN (?, ?)').run(p1, p2);
  });

  it('getTopSuppliers excludes voided purchases', () => {
    const p1 = insertPurchase({ item_id: itemId, warehouse_id: warehouseId, quantity: 10, unit_cost: 50, total_cost: 500, purchase_date: '2026-10-10', supplier_name: 'P13 TopSupp Active', purchase_no: `P13-TS1-${Date.now()}` });
    const p2 = insertPurchase({ item_id: itemId, warehouse_id: warehouseId, quantity: 40, unit_cost: 50, total_cost: 2000, purchase_date: '2026-10-11', supplier_name: 'P13 TopSupp Voided', purchase_no: `P13-TS2-${Date.now()}` });

    voidPurchase(p2);

    const suppliers = db.prepare(`
      SELECT supplier_name, SUM(total_cost) as cost
      FROM purchases WHERE supplier_name IS NOT NULL AND voided_at IS NULL
      GROUP BY supplier_name ORDER BY cost DESC
    `).all() as Array<{ supplier_name: string; cost: number }>;

    const voidedEntry = suppliers.find(s => s.supplier_name === 'P13 TopSupp Voided');
    expect(voidedEntry).toBeUndefined();

    const activeEntry = suppliers.find(s => s.supplier_name === 'P13 TopSupp Active');
    expect(activeEntry).toBeDefined();
    expect(activeEntry!.cost).toBe(500);

    db.prepare('DELETE FROM purchases WHERE id IN (?, ?)').run(p1, p2);
  });

  it('dashboard inventory_turnover excludes voided purchases', () => {
    const p1 = insertPurchase({ item_id: itemId, warehouse_id: warehouseId, quantity: 10, unit_cost: 50, total_cost: 500, purchase_date: '2026-10-15', supplier_name: 'P13 Dash', purchase_no: `P13-DASH1-${Date.now()}` });
    const p2 = insertPurchase({ item_id: itemId, warehouse_id: warehouseId, quantity: 50, unit_cost: 50, total_cost: 2500, purchase_date: '2026-10-16', supplier_name: 'P13 Dash', purchase_no: `P13-DASH2-${Date.now()}` });

    voidPurchase(p2);

    const total = db.prepare(`
      SELECT COALESCE(SUM(total_cost), 0) as total FROM purchases
      WHERE purchase_date >= '2026-10-15' AND voided_at IS NULL
    `).get() as { total: number };

    expect(total.total).toBe(500);

    db.prepare('DELETE FROM purchases WHERE id IN (?, ?)').run(p1, p2);
  });

  it('voided purchase still visible in raw list with include_voided', async () => {
    const p1 = insertPurchase({ item_id: itemId, warehouse_id: warehouseId, quantity: 5, unit_cost: 50, total_cost: 250, purchase_date: '2026-10-20', supplier_name: 'P13 List', purchase_no: `P13-LIST-${Date.now()}` });
    voidPurchase(p1);

    const withVoided = await request(app).get('/api/purchases?include_voided=1').set('Cookie', token);
    expect(withVoided.status).toBe(200);
    const found = withVoided.body.data?.find((p: { id: number }) => p.id === p1);
    expect(found).toBeDefined();

    const withoutVoided = await request(app).get('/api/purchases').set('Cookie', token);
    expect(withoutVoided.status).toBe(200);
    const notFound = withoutVoided.body.data?.find((p: { id: number }) => p.id === p1);
    expect(notFound).toBeUndefined();

    db.prepare('DELETE FROM purchases WHERE id = ?').run(p1);
  });
});
