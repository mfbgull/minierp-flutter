/**
 * Expired-stock plan Phase 2 — recordExpiryTransfer unit tests.
 *
 * The helper is the single code path shared by the boot task
 * (expiryDetection.ts) and the write-off endpoint's auto-transfer. Covers:
 *   1. Paired EXPIRY_TRANSFER legs with correct sign/warehouse/batch linkage
 *   2. Source batch zeroed exactly once; mirror batch minted at destination
 *   3. stock_balances + items.current_stock synced by recordMovement
 *   4. Idempotency: a batch with an existing EXPIRY_TRANSFER is refused
 *   5. Guards: no quantity, already at destination, missing batch
 *   6. System actor: userId = null → created_by NULL + source=SYSTEM remark
 */
import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';
import StockMovementModel from '../models/StockMovement';

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

  db.prepare(`INSERT INTO users (username,email,password_hash,full_name,role,is_active) VALUES ('admin','a@b.c','x','A','admin',1)`).run();
  db.prepare(`INSERT INTO items (item_code,item_name,unit_of_measure,standard_cost,is_purchased,is_active) VALUES ('IT-1','Widget','Nos',10,1,1)`).run();
  db.prepare(`INSERT INTO warehouses (warehouse_code,warehouse_name,is_active) VALUES ('WH-1','Main',1)`).run();
  db.prepare(`INSERT INTO warehouses (warehouse_code,warehouse_name,is_active) VALUES ('EXPIRED','Expired Stock',1)`).run();
  return db;
}

function seedExpiredBatch(db: Database.Database, batchNo: string, qty: number, cost = 5): number {
  const r = db.prepare(`
    INSERT INTO stock_batches (batch_no,item_id,warehouse_id,source_type,source_id,quantity_original,quantity_remaining,unit_cost,received_date,expiry_date)
    VALUES (?,1,1,'PURCHASE',1,?,?,?,'2026-01-01','2026-08-01')
  `).run(batchNo, qty, qty, cost);
  const batchId = r.lastInsertRowid as number;
  db.prepare(`INSERT INTO stock_balances (item_id,warehouse_id,quantity) VALUES (1,1,?)`).run(qty);
  return batchId;
}

describe('recordExpiryTransfer (batch-targeted paired legs)', () => {
  it('creates paired legs, zeroes the source batch, mints a mirror batch at EXPIRED, syncs balances', () => {
    const db = createFixture();
    const qty = 7;
    const batchId = seedExpiredBatch(db, 'EXP-B1', qty, 5);
    const expiredWh = (db.prepare(`SELECT id FROM warehouses WHERE warehouse_code = 'EXPIRED'`).get() as { id: number }).id;

    const result = StockMovementModel.recordExpiryTransfer(
      { batchId, toWarehouseId: expiredWh },
      null, // system actor (boot task)
      db
    );

    // OUT leg: negative at source, batch-linked, EXPIRY_TRANSFER doctype
    const out = db.prepare(`SELECT * FROM stock_movements WHERE movement_no = ?`).get(result.out.movement_no) as {
      warehouse_id: number; quantity: number; movement_type: string; batch_id: number; reference_docno: string; created_by: number | null; remarks: string;
    };
    expect(out.movement_type).toBe('EXPIRY_TRANSFER');
    expect(out.warehouse_id).toBe(1);
    expect(out.quantity).toBe(-qty);
    expect(out.batch_id).toBe(batchId);
    expect(out.reference_docno).toBe('EXP-B1');
    expect(out.created_by).toBeNull(); // system actor
    expect(out.remarks).toContain('source=SYSTEM');

    // IN leg: positive at EXPIRED, mirror-batch-linked, references OUT movement_no
    const into = db.prepare(`SELECT * FROM stock_movements WHERE movement_no = ?`).get(result.in.movement_no) as {
      warehouse_id: number; quantity: number; batch_id: number; reference_docno: string;
    };
    expect(into.warehouse_id).toBe(expiredWh);
    expect(into.quantity).toBe(qty);
    expect(into.batch_id).toBe(result.mirrorBatchId);
    expect(into.reference_docno).toBe(result.out.movement_no);

    // Source batch zeroed exactly once; mirror batch holds the qty at cost
    const src = db.prepare(`SELECT quantity_remaining FROM stock_batches WHERE id = ?`).get(batchId) as { quantity_remaining: number };
    expect(src.quantity_remaining).toBe(0);
    const mirror = db.prepare(`SELECT quantity_remaining, unit_cost, warehouse_id, source_type FROM stock_batches WHERE id = ?`).get(result.mirrorBatchId) as {
      quantity_remaining: number; unit_cost: number; warehouse_id: number; source_type: string;
    };
    expect(mirror.quantity_remaining).toBe(qty);
    expect(mirror.unit_cost).toBe(5);
    expect(mirror.warehouse_id).toBe(expiredWh);
    expect(mirror.source_type).toBe('TRANSFER'); // plan 1.5 decision

    // Balances: source drained, destination gained (recordMovement's job)
    const srcBal = db.prepare(`SELECT quantity FROM stock_balances WHERE item_id = 1 AND warehouse_id = 1`).get() as { quantity: number };
    expect(srcBal.quantity).toBe(0);
    const dstBal = db.prepare(`SELECT quantity FROM stock_balances WHERE item_id = 1 AND warehouse_id = ?`).get(expiredWh) as { quantity: number };
    expect(dstBal.quantity).toBe(qty);
    const item = db.prepare(`SELECT current_stock FROM items WHERE id = 1`).get() as { current_stock: number };
    expect(item.current_stock).toBe(qty); // conserved across the move

    db.close();
  });

  it('refuses a batch that already has an EXPIRY_TRANSFER (idempotency)', () => {
    const db = createFixture();
    const batchId = seedExpiredBatch(db, 'EXP-B2', 3);
    const expiredWh = (db.prepare(`SELECT id FROM warehouses WHERE warehouse_code = 'EXPIRED'`).get() as { id: number }).id;

    StockMovementModel.recordExpiryTransfer({ batchId, toWarehouseId: expiredWh }, null, db);
    // The source batch now has qty 0; simulate a re-scan of the same batch
    // with quantity artificially restored (the boot task's NOT EXISTS would
    // filter it, but the helper must also refuse defensively).
    db.prepare(`UPDATE stock_batches SET quantity_remaining = 3 WHERE id = ?`).run(batchId);
    expect(() =>
      StockMovementModel.recordExpiryTransfer({ batchId, toWarehouseId: expiredWh }, null, db)
    ).toThrow(/already has an EXPIRY_TRANSFER/);
    db.close();
  });

  it('refuses transfers with no remaining quantity, wrong destination, or unknown batch', () => {
    const db = createFixture();
    const expiredWh = (db.prepare(`SELECT id FROM warehouses WHERE warehouse_code = 'EXPIRED'`).get() as { id: number }).id;

    // No quantity
    const empty = seedExpiredBatch(db, 'EXP-B3', 4);
    db.prepare(`UPDATE stock_batches SET quantity_remaining = 0 WHERE id = ?`).run(empty);
    expect(() =>
      StockMovementModel.recordExpiryTransfer({ batchId: empty, toWarehouseId: expiredWh }, null, db)
    ).toThrow(/no remaining quantity/);

    // Already at destination
    const atDest = db.prepare(`
      INSERT INTO stock_batches (batch_no,item_id,warehouse_id,source_type,source_id,quantity_original,quantity_remaining,unit_cost,received_date,expiry_date)
      VALUES ('EXP-B4',1,?,'TRANSFER',1,2,2,5,'2026-01-01','2026-08-01')
    `).run(expiredWh);
    expect(() =>
      StockMovementModel.recordExpiryTransfer({ batchId: atDest.lastInsertRowid as number, toWarehouseId: expiredWh }, null, db)
    ).toThrow(/already at the destination/);

    // Unknown batch
    expect(() =>
      StockMovementModel.recordExpiryTransfer({ batchId: 99999, toWarehouseId: expiredWh }, null, db)
    ).toThrow(/not found/);
    db.close();
  });

  it('with a human userId, records created_by and omits the SYSTEM remark', () => {
    const db = createFixture();
    const batchId = seedExpiredBatch(db, 'EXP-B5', 2);
    const expiredWh = (db.prepare(`SELECT id FROM warehouses WHERE warehouse_code = 'EXPIRED'`).get() as { id: number }).id;

    const result = StockMovementModel.recordExpiryTransfer({ batchId, toWarehouseId: expiredWh }, 1, db);
    const out = db.prepare(`SELECT created_by, remarks FROM stock_movements WHERE movement_no = ?`).get(result.out.movement_no) as {
      created_by: number | null; remarks: string;
    };
    expect(out.created_by).toBe(1);
    expect(out.remarks).not.toContain('source=SYSTEM');
    db.close();
  });
});
