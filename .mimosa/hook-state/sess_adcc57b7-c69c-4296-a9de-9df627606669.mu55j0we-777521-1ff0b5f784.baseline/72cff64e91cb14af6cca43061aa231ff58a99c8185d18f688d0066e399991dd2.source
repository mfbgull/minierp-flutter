/**
 * Reversal-rules Phase 4 regression tests — count-correction workflow.
 *
 * POSTED counts are immutable. `correctCount` reverses the original
 * completion's stock + GL effects and re-applies corrected variances in
 * one transaction:
 *   1. Correction nets stock to the recounted quantity, appends reversal +
 *      re-application ADJUSTMENT movements, voids the original journal
 *      lines, and posts fresh GL at actual consumed costs.
 *   2. Double correction is rejected (single-shot idempotency).
 *   3. Non-Completed counts cannot be corrected.
 *   4. Unknown item id is refused (snapshot rule).
 *   5. Surplus already consumed → correction refused, state untouched.
 */
import request from 'supertest';
import bcrypt from 'bcrypt';
import app from '../app';
import db from '../config/database';
import PhysicalCountModel from '../models/PhysicalCount';
import AccountingService from '../services/accountingService';

const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD) {
  throw new Error('TEST_ADMIN_PASSWORD environment variable must be set for integration tests.');
}

let token: string;
let seq = 0;

beforeAll(async () => {
  const admin = db.prepare(`SELECT id FROM users WHERE username = 'pcc-admin'`).get() as
    | { id: number }
    | undefined;
  if (!admin) {
    db.prepare(`
      INSERT INTO users (username, email, password_hash, full_name, role, is_active)
      VALUES ('pcc-admin', 'pcc-admin@test.local', ?, 'PCC Admin', 'admin', 1)
    `).run(bcrypt.hashSync(TEST_PASSWORD, 10));
  }
  const login = await request(app)
    .post('/api/auth/login')
    .send({ username: 'pcc-admin', password: TEST_PASSWORD });
  if (login.status !== 200) {
    throw new Error(`Admin login failed: ${login.status} ${JSON.stringify(login.body)}`);
  }
  const cookies = login.headers['set-cookie'] ?? [];
  const cookieList = Array.isArray(cookies) ? cookies : [cookies];
  const tokenCookie = cookieList.find((c: string) => c.startsWith('token='));
  if (!tokenCookie) throw new Error('Login did not return a token cookie');
  token = tokenCookie.split(';')[0];
});

interface CountFixture {
  countId: number;
  warehouseId: number;
  itemId: number;
}

/** Create a warehouse + item with 20 units in stock, and a count session. */
function setup(): CountFixture {
  seq += 1;
  const warehouse = db.prepare(`
    INSERT INTO warehouses (warehouse_name, warehouse_code, is_active)
    VALUES (?, ?, 1)
  `).run(`PCC WH ${seq}`, `PCC-WH-${seq}`);
  const warehouseId = warehouse.lastInsertRowid as number;

  const item = db.prepare(`
    INSERT INTO items (item_code, item_name, unit_of_measure, current_stock, is_active)
    VALUES (?, ?, 'pcs', 0, 1)
  `).run(`PCC-ITEM-${seq}`, `PCC Item ${seq}`);
  const itemId = item.lastInsertRowid as number;

  // Seed a batch so shortages consume real FIFO layers.
  db.prepare(`
    INSERT INTO stock_batches (
      batch_no, item_id, warehouse_id, source_type, source_id,
      quantity_original, quantity_remaining, unit_cost, received_date
    ) VALUES (?, ?, ?, 'OPENING', 0, 20, 20, 10, '2026-09-01')
  `).run(`PCC-BATCH-${seq}`, itemId, warehouseId);
  db.prepare(`
    INSERT INTO stock_balances (item_id, warehouse_id, quantity) VALUES (?, ?, 20)
  `).run(itemId, warehouseId);

  const countId = PhysicalCountModel.create({ warehouse_id: warehouseId }, 1, db);
  return { countId, warehouseId, itemId };
}

function completeWith(count: CountFixture, counted: number): void {
  PhysicalCountModel.recordCount(count.countId, count.itemId, counted, 1, null, db);
  PhysicalCountModel.completeCount(count.countId, 1, db);
}

const balanceOf = (itemId: number, warehouseId: number): number =>
  (db.prepare(
    `SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?`
  ).get(itemId, warehouseId) as { quantity: number }).quantity;

/** Total debit posted against a stock_adjustment reference (voided excluded). */
const postedDebitOf = (referenceId: number): number => {
  const row = db.prepare(`
    SELECT COALESCE(SUM(debit), 0) AS total
    FROM journal_lines WHERE reference_type = 'stock_adjustment' AND reference_id = ? AND voided = 0
  `).get(referenceId) as { total: number } | undefined;
  return row ? Number(row.total) : 0;
};

describe('Count correction workflow (Phase 4)', () => {
  it('reverses the original adjustment and applies the corrected count', async () => {
    const count = setup();
    completeWith(count, 12); // original: shortage −8, GL shrinkage 80 @10

    const originalMovements = db.prepare(`
      SELECT id FROM stock_movements
      WHERE reference_doctype = 'PhysicalCount' AND reference_docno = (
        SELECT count_no FROM physical_counts WHERE id = ?
      )
    `).all(count.countId) as Array<{ id: number }>;
    expect(originalMovements.length).toBe(1);
    const originalMovementId = originalMovements[0].id;

    // Original GL posted (shrinkage 8 × 10 = 80).
    expect(postedDebitOf(originalMovementId)).toBeCloseTo(80, 6);

    const res = await request(app)
      .post(`/api/inventory/physical-counts/${count.countId}/correct`)
      .set('Cookie', token)
      .send({ corrections: [{ item_id: count.itemId, counted_quantity: 18 }] });
    expect(res.status).toBe(200);
    expect(res.body.corrected_at).not.toBeNull();

    // Stock nets to the corrected count.
    expect(balanceOf(count.itemId, count.warehouseId)).toBeCloseTo(18, 6);

    // Three movements on the count: original −8, reversal +8, re-applied −2.
    const movements = db.prepare(`
      SELECT quantity FROM stock_movements
      WHERE reference_doctype IN ('PhysicalCount', 'PhysicalCountCorrection')
        AND reference_docno = (
          SELECT count_no FROM physical_counts WHERE id = ?
        )
      ORDER BY id
    `).all(count.countId) as Array<{ quantity: number }>;
    expect(movements.map((m) => m.quantity).reduce((s, q) => s + q, 0)).toBeCloseTo(-2, 6);
    expect(movements.length).toBe(3);

    // Original journal lines voided; re-application posts fresh GL (2 × 10 = 20).
    expect(postedDebitOf(originalMovementId)).toBeCloseTo(0, 6); // original voided

    // The re-applied movement posted fresh GL.
    const reapplied = db.prepare(`
      SELECT id FROM stock_movements
      WHERE reference_doctype = 'PhysicalCountCorrection' AND quantity < 0
        AND reference_docno = (SELECT count_no FROM physical_counts WHERE id = ?)
    `).get(count.countId) as { id: number };
    expect(postedDebitOf(reapplied.id)).toBeCloseTo(20, 6);

    // Item current_stock rebuilt.
    const itemStock = (db.prepare(`SELECT current_stock FROM items WHERE id = ?`)
      .get(count.itemId) as { current_stock: number }).current_stock;
    expect(itemStock).toBeCloseTo(18, 6);
  });

  it('rejects double correction (single-shot)', async () => {
    const count = setup();
    completeWith(count, 15);
    PhysicalCountModel.correctCount(
      { countId: count.countId, corrections: [{ item_id: count.itemId, counted_quantity: 17 }] },
      1, db
    );
    expect(() =>
      PhysicalCountModel.correctCount(
        { countId: count.countId, corrections: [{ item_id: count.itemId, counted_quantity: 19 }] },
        1, db
      )
    ).toThrow(/already been corrected/i);
  });

  it('refuses to correct a non-Completed count', () => {
    const count = setup(); // stays Draft
    expect(() =>
      PhysicalCountModel.correctCount(
        { countId: count.countId, corrections: [{ item_id: count.itemId, counted_quantity: 10 }] },
        1, db
      )
    ).toThrow(/Only Completed/i);
  });

  it('refuses a correction for an item without a snapshot row', () => {
    const count = setup();
    completeWith(count, 20);
    expect(() =>
      PhysicalCountModel.correctCount(
        { countId: count.countId, corrections: [{ item_id: 999999, counted_quantity: 5 }] },
        1, db
      )
    ).toThrow(/snapshot row/i);
    // Whole transaction rolled back — nothing stamped.
    const c = db.prepare(`SELECT corrected_at FROM physical_counts WHERE id = ?`)
      .get(count.countId) as { corrected_at: string | null };
    expect(c.corrected_at).toBeNull();
  });

  it('refuses correction when surplus units were already consumed', () => {
    const count = setup();
    completeWith(count, 25); // surplus +5 → ADJUSTMENT batch of 5

    // Consume the surplus batch (simulates a sale drawing from FIFO).
    db.prepare(`
      UPDATE stock_batches SET quantity_remaining = 0
      WHERE source_type = 'ADJUSTMENT' AND source_id = ?
    `).run(count.countId);

    expect(() =>
      PhysicalCountModel.correctCount(
        { countId: count.countId, corrections: [{ item_id: count.itemId, counted_quantity: 24 }] },
        1, db
      )
    ).toThrow(/already consumed/i);

    // State untouched.
    const c = db.prepare(`SELECT corrected_at FROM physical_counts WHERE id = ?`)
      .get(count.countId) as { corrected_at: string | null };
    expect(c.corrected_at).toBeNull();
  });
});
