/**
 * Expired-stock plan Phase 2 — boot task unit tests.
 *
 * Covers the rewritten expiryDetection.ts:
 *   1. Sweeps expired batches into the EXPIRED warehouse via the shared
 *      paired-leg helper (movements + mirror batch + balances)
 *   2. Is idempotent — a second run moves nothing
 *   3. Skips batches already at EXPIRED, not-yet-expired, and zero-qty
 *   4. Per-batch isolation: one bad batch doesn't roll back the sweep
 *   5. Throws loud when the EXPIRED warehouse is missing (migration bug)
 */
import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';
import { runExpiryDetection } from '../boot/expiryDetection';

function createFixture(): Database.Database {
  const db = new Database(':memory:');
  db.pragma('foreign_keys = ON');
  const migrations = [
    'init.sql',
    'add-purchases-table.sql',
    'add-batch-costing.sql',
    'add-stock-adjustment-financial.sql',
    'add-production-tables.sql',
    'add-item-expiry-tracking.sql',
    'add-gl-foundation.sql',
  ];
  for (const file of migrations) {
    const p = path.join(__dirname, '..', 'migrations', file);
    if (fs.existsSync(p)) db.exec(fs.readFileSync(p, 'utf8'));
    else throw new Error(`MISSING migration fixture: ${file}`);
  }
  // stock_movements.batch_id (+ financial columns) is added programmatically
  // at boot — must exist BEFORE add-expired-stock.sql, which indexes
  // stock_movements(batch_id, movement_type).
  const cols = db.prepare(`SELECT name FROM pragma_table_info('stock_movements')`).all() as { name: string }[];
  const has = (n: string) => cols.some(c => c.name === n);
  if (!has('batch_id'))
    db.exec('ALTER TABLE stock_movements ADD COLUMN batch_id INTEGER REFERENCES stock_batches(id)');
  if (!has('financial_value'))
    db.exec('ALTER TABLE stock_movements ADD COLUMN financial_value DECIMAL(15,4) DEFAULT 0');
  if (!has('financial_posted'))
    db.exec('ALTER TABLE stock_movements ADD COLUMN financial_posted BOOLEAN DEFAULT FALSE');
  if (!has('journal_entry_id'))
    db.exec('ALTER TABLE stock_movements ADD COLUMN journal_entry_id INTEGER REFERENCES journal_entries(id)');

  // Seed users/items/warehouses BEFORE add-expired-stock.sql so the
  // EXPIRED/DAMAGED seeds get higher ids — mirrors production, where WH-001
  // is created by runtime code at init time and the migration only runs
  // after. (Seed order also affects id assignment in the fixture.)
  db.prepare(`INSERT INTO users (username,email,password_hash,full_name,role,is_active) VALUES ('admin','a@b.c','x','A','admin',1)`).run();
  db.prepare(`INSERT INTO items (item_code,item_name,unit_of_measure,standard_cost,is_purchased,is_active) VALUES ('IT-1','Widget','Nos',10,1,1)`).run();
  // WH-001 is created by runtime code in database.ts, not init.sql — seed it.
  db.prepare(`INSERT INTO warehouses (warehouse_code,warehouse_name,is_active) VALUES ('WH-001','Main',1)`).run();

  // The expired-stock migration — last, after all prerequisites AND the
  // runtime-seeded WH-001.
  db.exec(fs.readFileSync(path.join(__dirname, '..', 'migrations', 'add-expired-stock.sql'), 'utf8'));
  return db;
}

function seedBatch(
  db: Database.Database,
  batchNo: string,
  opts: { qty: number; expiry: string; warehouseId?: number }
): number {
  const wh = opts.warehouseId ?? (db.prepare(`SELECT id FROM warehouses WHERE warehouse_code = 'WH-001'`).get() as { id: number }).id;
  const r = db.prepare(`
    INSERT INTO stock_batches (batch_no,item_id,warehouse_id,source_type,source_id,quantity_original,quantity_remaining,unit_cost,received_date,expiry_date)
    VALUES (?,1,?,'PURCHASE',1,?,?,5,'2026-01-01',?)
  `).run(batchNo, wh, opts.qty, opts.qty, opts.expiry);
  const batchId = r.lastInsertRowid as number;
  // Item-level balance is UNIQUE(item_id, warehouse_id) — accumulate.
  db.prepare(`
    INSERT INTO stock_balances (item_id,warehouse_id,quantity) VALUES (1,?,?)
    ON CONFLICT(item_id, warehouse_id) DO UPDATE SET quantity = quantity + excluded.quantity
  `).run(wh, opts.qty);
  return batchId;
}

describe('expiryDetection boot task', () => {
  it('sweeps expired batches to EXPIRED with paired legs and mirror batch', () => {
    const db = createFixture();
    const expiredWhId = (db.prepare(`SELECT id FROM warehouses WHERE warehouse_code = 'EXPIRED'`).get() as { id: number }).id;
    const b1 = seedBatch(db, 'BOOT-B1', { qty: 5, expiry: '2026-08-01' });
    const b2 = seedBatch(db, 'BOOT-B2', { qty: 3, expiry: '2026-07-15' });

    const result = runExpiryDetection(db);
    expect(result.candidates).toBe(2);
    expect(result.moved).toBe(2);
    expect(result.failed).toBe(0);

    // Both batches zeroed at source; mirrored at EXPIRED with same cost
    for (const id of [b1, b2]) {
      const src = db.prepare(`SELECT quantity_remaining FROM stock_batches WHERE id = ?`).get(id) as { quantity_remaining: number };
      expect(src.quantity_remaining).toBe(0);
    }
    const mirrors = db.prepare(
      `SELECT COUNT(*) AS n FROM stock_batches WHERE warehouse_id = ? AND source_type = 'TRANSFER'`
    ).get(expiredWhId) as { n: number };
    expect(mirrors.n).toBe(2);

    // Paired movement legs exist for each source batch (OUT −qty on the
    // source batch id; the IN leg rides the mirror batch, verified via the
    // mirror count above).
    for (const id of [b1, b2]) {
      const legs = db.prepare(
        `SELECT quantity FROM stock_movements WHERE batch_id = ? AND movement_type = 'EXPIRY_TRANSFER'`
      ).all(id) as Array<{ quantity: number }>;
      expect(legs).toHaveLength(1);
      expect(legs[0].quantity).toBeLessThan(0); // OUT leg
    }
    const inLegs = (db.prepare(
      `SELECT COUNT(*) AS n FROM stock_movements WHERE movement_type = 'EXPIRY_TRANSFER' AND quantity > 0`
    ).get() as { n: number }).n;
    expect(inLegs).toBe(2); // IN leg per moved batch, on the mirror batches

    // Balance conservation: item total unchanged (5 + 3)
    const total = db.prepare(`SELECT COALESCE(SUM(quantity),0) AS q FROM stock_balances WHERE item_id = 1`).get() as { q: number };
    expect(total.q).toBe(8);

    db.close();
  });

  it('is idempotent — a second run moves nothing', () => {
    const db = createFixture();
    seedBatch(db, 'BOOT-B3', { qty: 4, expiry: '2026-08-01' });

    const first = runExpiryDetection(db);
    expect(first.moved).toBe(1);

    const second = runExpiryDetection(db);
    expect(second.candidates).toBe(0);
    expect(second.moved).toBe(0);

    // No duplicated movement legs
    const legs = (db.prepare(
      `SELECT COUNT(*) AS n FROM stock_movements WHERE movement_type = 'EXPIRY_TRANSFER'`
    ).get() as { n: number }).n;
    expect(legs).toBe(2); // one OUT + one IN total
    db.close();
  });

  it('skips not-yet-expired, zero-quantity, and already-EXPIRED batches', () => {
    const db = createFixture();
    const expiredWhId = (db.prepare(`SELECT id FROM warehouses WHERE warehouse_code = 'EXPIRED'`).get() as { id: number }).id;
    seedBatch(db, 'BOOT-FUTURE', { qty: 5, expiry: '2099-01-01' }); // not expired
    seedBatch(db, 'BOOT-ZERO', { qty: 0, expiry: '2026-08-01' }); // no qty
    seedBatch(db, 'BOOT-ATDEST', { qty: 2, expiry: '2026-08-01', warehouseId: expiredWhId }); // already there
    seedBatch(db, 'BOOT-GOOD', { qty: 6, expiry: '2026-08-01' }); // should move

    const result = runExpiryDetection(db);
    expect(result.candidates).toBe(1);
    expect(result.moved).toBe(1);
    db.close();
  });

  it('isolates a bad batch — the rest of the sweep still completes', () => {
    const db = createFixture();
    seedBatch(db, 'BOOT-OK', { qty: 2, expiry: '2026-08-01' });

    // Orphan the item reference of another expired batch to break its legs
    // (FK enforcement inside recordExpiryTransfer will fail for it).
    db.pragma('foreign_keys = OFF');
    const bad = db.prepare(`
      INSERT INTO stock_batches (batch_no,item_id,warehouse_id,source_type,source_id,quantity_original,quantity_remaining,unit_cost,received_date,expiry_date)
      VALUES ('BOOT-BAD', 99999, 1, 'PURCHASE', 1, 3, 3, 5, '2026-01-01', '2026-08-01')
    `).run();
    db.pragma('foreign_keys = ON');

    const result = runExpiryDetection(db);
    expect(result.moved).toBe(1); // the good batch moved
    expect(result.failed).toBe(1); // the bad one failed
    expect(result.failures[0].batchNo).toBe('BOOT-BAD');
    expect(result.failures[0].batchId).toBe(bad.lastInsertRowid as number);

    // The good batch is fully processed despite the bad one
    const ok = db.prepare(`SELECT quantity_remaining FROM stock_batches WHERE batch_no = 'BOOT-OK'`).get() as { quantity_remaining: number };
    expect(ok.quantity_remaining).toBe(0);
    db.close();
  });

  it('throws loud when the EXPIRED warehouse is missing (migration bug)', () => {
    const db = createFixture();
    // Drop the delete-guard trigger — this test simulates a DB where the
    // migration never ran (so neither the trigger nor the warehouse exists).
    db.exec(`DROP TRIGGER IF EXISTS trg_warehouses_no_delete_system`);
    db.prepare(`DELETE FROM warehouses WHERE warehouse_code = 'EXPIRED'`).run();
    seedBatch(db, 'BOOT-NOWH', { qty: 1, expiry: '2026-08-01' });

    expect(() => runExpiryDetection(db)).toThrow(/add-expired-stock\.sql migration did not run/);
    db.close();
  });
});
