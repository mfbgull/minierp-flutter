/**
 * Reversal-rules Phase 4 regression tests.
 *
 * Goods-receipt void:
 *   1. Void reverses stock balance, zeroes the receipt's batch layers,
 *      appends a GOODS_RECEIPT_VOID movement, rolls back received_quantity,
 *      and recomputes PO status.
 *   2. Double void is rejected (idempotency).
 *   3. Void is refused when receipt units were already consumed.
 *
 * FK-delete 400s:
 *   4. Supplier with direct purchases -> 400 (not 500).
 *   5. Warehouse with references -> 400 (not 500).
 */
import request from 'supertest';
import bcrypt from 'bcrypt';
import app from '../app';
import db from '../config/database';

const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD) {
  throw new Error('TEST_ADMIN_PASSWORD environment variable must be set for integration tests.');
}

let token: string;
let fixtureSeq = 0;

beforeAll(async () => {
  // Ensure an admin exists (seed may already have created one).
  const admin = db.prepare(`SELECT id FROM users WHERE username = 'grv-admin'`).get() as
    | { id: number }
    | undefined;
  if (!admin) {
    db.prepare(`
      INSERT INTO users (username, email, password_hash, full_name, role, is_active)
      VALUES ('grv-admin', 'grv-admin@test.local', ?, 'GRV Admin', 'admin', 1)
    `).run(bcrypt.hashSync(TEST_PASSWORD, 10));
  }

  const login = await request(app)
    .post('/api/auth/login')
    .send({ username: 'grv-admin', password: TEST_PASSWORD });
  if (login.status !== 200) {
    throw new Error(`Admin login failed: ${login.status} ${JSON.stringify(login.body)}`);
  }
  const cookies = login.headers['set-cookie'] ?? [];
  const cookieList = Array.isArray(cookies) ? cookies : [cookies];
  const tokenCookie = cookieList.find((c: string) => c.startsWith('token='));
  if (!tokenCookie) throw new Error('Login did not return a token cookie');
  token = tokenCookie.split(';')[0];
});

interface Fixture {
  supplierId: number;
  warehouseId: number;
  itemId: number;
  poId: number;
  poItemId: number;
}

async function createFixture(): Promise<Fixture> {
  fixtureSeq += 1;
  const seq = fixtureSeq;
  const supplier = db.prepare(`
    INSERT INTO suppliers (supplier_name, supplier_code, contact_person, is_active)
    VALUES (?, ?, 'Contact', 1)
  `).run(`GRV Supplier ${seq}`, `GRV-SUP-${seq}`);
  const warehouse = db.prepare(`
    INSERT INTO warehouses (warehouse_name, warehouse_code, is_active)
    VALUES (?, ?, 1)
  `).run(`GRV Warehouse ${seq}`, `GRV-WH-${seq}`);
  const item = db.prepare(`
    INSERT INTO items (item_code, item_name, unit_of_measure, current_stock, is_active)
    VALUES (?, ?, 'pcs', 0, 1)
  `).run(`GRV-ITEM-${seq}`, `GRV Item ${seq}`);

  const supplierId = supplier.lastInsertRowid as number;
  const warehouseId = warehouse.lastInsertRowid as number;
  const itemId = item.lastInsertRowid as number;

  const res = await request(app)
    .post('/api/purchase-orders')
    .set('Cookie', token)
    .send({
      supplier_id: supplierId,
      po_date: '2026-09-12',
      items: [{ item_id: itemId, quantity: 10, unit_price: 5 }]
    });
  if (res.status !== 201 && res.status !== 200) {
    throw new Error(`Failed to create PO: ${res.status} ${JSON.stringify(res.body)}`);
  }
  const po = res.body.data ?? res.body;
  const poItem = db.prepare(
    `SELECT id FROM purchase_order_items WHERE po_id = ?`
  ).get(po.id) as { id: number };

  return { supplierId, warehouseId, itemId, poId: po.id, poItemId: poItem.id };
}

async function receive(po: Fixture, qty: number): Promise<number> {
  const res = await request(app)
    .post(`/api/purchase-orders/${po.poId}/receipts`)
    .set('Cookie', token)
    .send({
      receipt_date: '2026-09-12',
      warehouse_id: po.warehouseId,
      items: [{ po_item_id: po.poItemId, received_quantity: qty }]
    });
  if (res.status !== 201 && res.status !== 200) {
    throw new Error(`Failed to create receipt: ${res.status} ${JSON.stringify(res.body)}`);
  }
  const receipt = res.body.data ?? res.body;
  return receipt.id as number;
}

describe('Goods receipt void (Phase 4)', () => {
  it('reverses stock, batches, received_quantity and PO status', async () => {
    const po = await createFixture();
    await request(app).post(`/api/purchase-orders/${po.poId}/status`)
      .set('Cookie', token).send({ status: 'Submitted' });

    const receiptId = await receive(po, 10);

    // Sanity: receipt added stock and completed the PO.
    const balBefore = (db.prepare(
      `SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?`
    ).get(po.itemId, po.warehouseId) as { quantity: number }).quantity;
    expect(balBefore).toBeCloseTo(10, 6);
    expect((db.prepare(`SELECT status FROM purchase_orders WHERE id = ?`).get(po.poId) as { status: string }).status)
      .toBe('Completed');

    const res = await request(app)
      .post(`/api/purchase-orders/${po.poId}/receipts/${receiptId}/void`)
      .set('Cookie', token)
      .send({ reason: 'wrong delivery' });

    expect(res.status).toBe(200);

    // Stock balance restored to 0.
    const balAfter = (db.prepare(
      `SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?`
    ).get(po.itemId, po.warehouseId) as { quantity: number }).quantity;
    expect(balAfter).toBeCloseTo(0, 6);

    // Batch layers zeroed but retained (append-only audit).
    const batch = db.prepare(`
      SELECT SUM(quantity_remaining) AS remaining, COUNT(*) AS n
      FROM stock_batches WHERE source_type = 'GOODS_RECEIPT'
        AND source_id IN (SELECT id FROM goods_receipt_items WHERE receipt_id = ?)
    `).get(receiptId) as { remaining: number; n: number };
    expect(batch.n).toBeGreaterThan(0);
    expect(batch.remaining).toBeCloseTo(0, 6);

    // Reversal movement appended (append-only, originals untouched).
    const reversal = db.prepare(`
      SELECT COUNT(*) AS c FROM stock_movements
      WHERE movement_type = 'PURCHASE_RETURN' AND reference_doctype = 'GOODS_RECEIPT_VOID'
    `).get() as { c: number };
    expect(reversal.c).toBe(1);

    // received_quantity rolled back and PO status recomputed.
    const poItem = db.prepare(
      `SELECT received_quantity FROM purchase_order_items WHERE id = ?`
    ).get(po.poItemId) as { received_quantity: number };
    expect(poItem.received_quantity).toBeCloseTo(0, 6);
    expect((db.prepare(`SELECT status FROM purchase_orders WHERE id = ?`).get(po.poId) as { status: string }).status)
      .toBe('Submitted');

    // Void stamped on the receipt.
    const gr = db.prepare(`SELECT voided_at FROM goods_receipts WHERE id = ?`).get(receiptId) as { voided_at: string | null };
    expect(gr.voided_at).not.toBeNull();

    // Item current_stock rebuilt.
    const itemStock = (db.prepare(`SELECT current_stock FROM items WHERE id = ?`).get(po.itemId) as { current_stock: number }).current_stock;
    expect(itemStock).toBeCloseTo(0, 6);
  });

  it('rejects double void (idempotency)', async () => {
    const po = await createFixture();
    await request(app).post(`/api/purchase-orders/${po.poId}/status`)
      .set('Cookie', token).send({ status: 'Submitted' });
    const receiptId = await receive(po, 5);

    const first = await request(app)
      .post(`/api/purchase-orders/${po.poId}/receipts/${receiptId}/void`)
      .set('Cookie', token).send({});
    expect(first.status).toBe(200);

    const second = await request(app)
      .post(`/api/purchase-orders/${po.poId}/receipts/${receiptId}/void`)
      .set('Cookie', token).send({});
    expect(second.status).toBe(400);
  });

  it('refuses void when receipt units were already consumed', async () => {
    const po = await createFixture();
    await request(app).post(`/api/purchase-orders/${po.poId}/status`)
      .set('Cookie', token).send({ status: 'Submitted' });
    const receiptId = await receive(po, 10);

    // Consume 4 units from the receipt batch directly (simulates a sale).
    const batch = db.prepare(`
      SELECT id FROM stock_batches
      WHERE source_type = 'GOODS_RECEIPT'
        AND source_id IN (SELECT id FROM goods_receipt_items WHERE receipt_id = ?)
    `).get(receiptId) as { id: number };
    db.prepare(`UPDATE stock_batches SET quantity_remaining = quantity_remaining - 4 WHERE id = ?`).run(batch.id);

    const res = await request(app)
      .post(`/api/purchase-orders/${po.poId}/receipts/${receiptId}/void`)
      .set('Cookie', token).send({});

    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/already consumed/i);

    // State untouched.
    const bal = (db.prepare(
      `SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?`
    ).get(po.itemId, po.warehouseId) as { quantity: number }).quantity;
    expect(bal).toBeCloseTo(10, 6);
    const gr = db.prepare(`SELECT voided_at FROM goods_receipts WHERE id = ?`).get(receiptId) as { voided_at: string | null };
    expect(gr.voided_at).toBeNull();
  });
});

describe('FK-delete 400s (Phase 4)', () => {
  it('supplier with a direct purchase returns 400 with a clear message', () => {
    const supplier = db.prepare(`
      INSERT INTO suppliers (supplier_name, supplier_code, is_active)
      VALUES ('FK Supplier', 'FK-SUP', 1)
    `).run();
    const warehouse = db.prepare(`
      INSERT INTO warehouses (warehouse_name, warehouse_code, is_active)
      VALUES ('FK Warehouse', 'FK-SUP-WH', 1)
    `).run();
    const item = db.prepare(`
      INSERT INTO items (item_code, item_name, unit_of_measure, current_stock, is_active)
      VALUES ('FK-SUP-ITEM', 'FK Item', 'pcs', 0, 1)
    `).run();
    db.prepare(`
      INSERT INTO purchases (purchase_no, item_id, warehouse_id, quantity, unit_cost, total_cost, supplier_name, supplier_id, purchase_date, created_by)
      VALUES ('FK-PO-1', ?, ?, 5, 20, 100, 'FK Supplier', ?, '2026-09-12', 1)
    `).run(item.lastInsertRowid, warehouse.lastInsertRowid, supplier.lastInsertRowid);

    return request(app)
      .delete(`/api/suppliers/${supplier.lastInsertRowid}`)
      .set('Cookie', token)
      .expect(400)
      .expect((res) => {
        expect(res.body.error).toMatch(/purchase/i);
      });
  });

  it('warehouse with references returns 400 with a clear message', async () => {
    const warehouse = db.prepare(`
      INSERT INTO warehouses (warehouse_name, warehouse_code, is_active)
      VALUES ('FK-WH2', 'FK-WH2', 1)
    `).run();
    const warehouseId = warehouse.lastInsertRowid as number;
    const item = db.prepare(`
      INSERT INTO items (item_code, item_name, unit_of_measure, current_stock, is_active)
      VALUES ('FK-ITEM', 'FK Item', 'pcs', 0, 1)
    `).run();
    db.prepare(`
      INSERT INTO stock_balances (item_id, warehouse_id, quantity)
      VALUES (?, ?, 3)
    `).run(item.lastInsertRowid, warehouseId);

    const res = await request(app)
      .delete(`/api/inventory/warehouses/${warehouseId}`)
      .set('Cookie', token);

    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/stock/i);

    // Untouched.
    expect(db.prepare(`SELECT id FROM warehouses WHERE id = ?`).get(warehouseId)).toBeTruthy();
  });
});
