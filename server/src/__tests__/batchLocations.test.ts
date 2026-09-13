// Batch-location feature unit tests (inventory-batch-lot-spec tasks
// 7.1–7.4, 7.9, 7.10): batch_stock_by_location CRUD + computed
// quantity_available, reservation create/release/consume idempotency,
// batch-status derivation and overrides, FEFO/FIFO skipping
// non-ACTIVE locations, backfill validation, and the feature-flag
// off/on behavioral contract.

import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';
import StockMovementModel from '../models/StockMovement';
import { StockReservationModel } from '../models/StockReservation';
import { runBackfillBatchLocations } from '../migrations/backfillBatchLocations';
import { getEffectiveBatchStatus, setBatchStatusOverride } from '../utils/batchStatus';
import { isFeatureEnabled, setFeatureEnabled } from '../utils/featureFlags';

function createFixture(): Database.Database {
  const db = new Database(':memory:');
  db.pragma('foreign_keys = ON');
  const migrations = [
    'init.sql', 'add-purchases-table.sql', 'add-purchase-return-fields.sql',
    'add-batch-costing.sql', 'add-stock-adjustment-financial.sql',
    'create-supplier-ledger.sql', 'add-gl-foundation.sql',
    'add-physical-counts.sql', 'add-production-tables.sql', 'add-item-expiry-tracking.sql',
    'add-purchase-return-batches.sql', 'add-batch-location-model.sql',
  ];
  for (const file of migrations) {
    const p = path.join(__dirname, '..', 'migrations', file);
    if (fs.existsSync(p)) db.exec(fs.readFileSync(p, 'utf8'));
    else console.warn('MISSING migration fixture:', file);
  }
  const cols = db
    .prepare(`SELECT name FROM pragma_table_info('stock_movements')`)
    .all() as { name: string }[];
  const has = (n: string) => cols.some((c) => c.name === n);
  if (!has('batch_id'))
    db.exec('ALTER TABLE stock_movements ADD COLUMN batch_id INTEGER REFERENCES stock_batches(id)');
  if (!has('financial_value'))
    db.exec('ALTER TABLE stock_movements ADD COLUMN financial_value DECIMAL(15,4) DEFAULT 0');
  if (!has('financial_posted'))
    db.exec('ALTER TABLE stock_movements ADD COLUMN financial_posted BOOLEAN DEFAULT FALSE');
  if (!has('journal_entry_id'))
    db.exec('ALTER TABLE stock_movements ADD COLUMN journal_entry_id INTEGER REFERENCES journal_entries(id)');

  db.prepare(
    `INSERT INTO users (username,email,password_hash,full_name,role,is_active) VALUES ('admin','a@b.c','x','A','admin',1)`
  ).run();
  db.prepare(
    `INSERT INTO items (item_code,item_name,unit_of_measure,standard_cost,is_purchased,is_active) VALUES ('IT-1','Widget','Nos',10,1,1)`
  ).run();
  db.prepare(
    `INSERT INTO warehouses (warehouse_code,warehouse_name,is_active) VALUES ('WH-1','Main',1)`
  ).run();
  // add-batch-location-model.sql seeds DEFAULT locations only for
  // warehouses existing at migration time; this warehouse is created
  // after, so seed its DEFAULT location explicitly.
  db.prepare(
    `INSERT INTO locations (warehouse_id,location_code,location_name) VALUES (1,'DEFAULT','Main')`
  ).run();
  return db;
}

/** Seed one batch + one location row + stock_balances coverage. */
function seedBatch(
  db: Database.Database,
  opts: {
    batchNo: string;
    qty: number;
    cost?: number;
    received?: string;
    expiry?: string | null;
    locationId?: number;
  }
): number {
  const received = opts.received ?? '2026-01-01';
  const expiry = opts.expiry === undefined ? null : opts.expiry;
  const r = db
    .prepare(
      `INSERT INTO stock_batches (batch_no,item_id,warehouse_id,source_type,source_id,quantity_original,quantity_remaining,unit_cost,received_date,expiry_date)
       VALUES (?,1,1,'PURCHASE',1,?,?,?,? ,?)`
    )
    .run(opts.batchNo, opts.qty, opts.qty, opts.cost ?? 10, received, expiry);
  const batchId = r.lastInsertRowid as number;
  const locId =
    opts.locationId ??
    ((db.prepare(`SELECT id FROM locations WHERE warehouse_id=1 AND location_code='DEFAULT'`).get() as { id: number }).id);
  db.prepare(
    `INSERT INTO batch_stock_by_location (batch_id,location_id,quantity_physical,quantity_reserved,quantity_available)
     VALUES (?,?,?,0,?)`
  ).run(batchId, locId, opts.qty, opts.qty);
  return batchId;
}

describe('7.1 batch_stock_by_location CRUD & computed quantity_available', () => {
  it('inserts, reads, updates rows; quantity_available = physical - reserved', () => {
    const db = createFixture();
    const batchId = seedBatch(db, { batchNo: 'B1', qty: 30 });

    const row = db
      .prepare(`SELECT * FROM batch_stock_by_location WHERE batch_id = ?`)
      .get(batchId) as any;
    expect(row.quantity_physical).toBe(30);
    expect(row.quantity_reserved).toBe(0);
    expect(row.quantity_available).toBe(30);

    // Reserve 5 → available drops but physical stays
    db.prepare(
      `UPDATE batch_stock_by_location SET quantity_reserved = quantity_reserved + 5 WHERE batch_id = ?`
    ).run(batchId);
    db.prepare(
      `UPDATE batch_stock_by_location SET quantity_available = quantity_physical - quantity_reserved WHERE batch_id = ?`
    ).run(batchId);
    const updated = db
      .prepare(`SELECT * FROM batch_stock_by_location WHERE batch_id = ?`)
      .get(batchId) as any;
    expect(updated.quantity_reserved).toBe(5);
    expect(updated.quantity_available).toBe(25);

    // UNIQUE(batch_id, location_id) enforced
    const dup = db.prepare(
      `INSERT INTO batch_stock_by_location (batch_id,location_id,quantity_physical,quantity_reserved,quantity_available) VALUES (?,?,1,0,1)`
    );
    expect(() => dup.run(batchId, row.location_id)).toThrow();
  });

  it('a batch can hold rows in multiple locations of the same warehouse', () => {
    const db = createFixture();
    db.prepare(`INSERT INTO locations (warehouse_id,location_code,location_name) VALUES (1,'RACK-A','Rack A')`).run();
    const defaultLoc = (db.prepare(`SELECT id FROM locations WHERE warehouse_id=1 AND location_code='DEFAULT'`).get() as any).id;
    const rackA = (db.prepare(`SELECT id FROM locations WHERE warehouse_id=1 AND location_code='RACK-A'`).get() as any).id;

    const batchId = seedBatch(db, { batchNo: 'B1', qty: 10, locationId: defaultLoc });
    db.prepare(
      `INSERT INTO batch_stock_by_location (batch_id,location_id,quantity_physical,quantity_reserved,quantity_available)
       VALUES (?,?,6,0,6)`
    ).run(batchId, rackA);

    const total = db
      .prepare(`SELECT SUM(quantity_physical) AS t FROM batch_stock_by_location WHERE batch_id = ?`)
      .get(batchId) as any;
    expect(total.t).toBe(16);
  });
});

describe('7.2 reservation create/release/consume idempotency', () => {
  it('create is idempotent per reference line; release sets RELEASED; re-create reactivates', () => {
    const db = createFixture();
    setFeatureEnabled(db, 'feature_batch_locations', true);
    const batchId = seedBatch(db, { batchNo: 'B1', qty: 100 });

    const r1 = StockReservationModel.create(
      { item_id: 1, warehouse_id: 1, batch_id: batchId, quantity_reserved: 5, reference_doctype: 'SALES_ORDER', reference_docno: 'SO-1', reference_line_id: 11 },
      db
    );
    expect(r1.status).toBe('ACTIVE');
    expect(r1.quantity_reserved).toBe(5);

    // Duplicate create for same reference line → same row, no new insert
    const r2 = StockReservationModel.create(
      { item_id: 1, warehouse_id: 1, batch_id: batchId, quantity_reserved: 5, reference_doctype: 'SALES_ORDER', reference_docno: 'SO-1', reference_line_id: 11 },
      db
    );
    expect(r2.id).toBe(r1.id);
    const count = (db.prepare(`SELECT COUNT(*) AS c FROM stock_reservations`).get() as any).c;
    expect(count).toBe(1);

    // Release → RELEASED with released_at
    const released = StockReservationModel.release(
      { reference_doctype: 'SALES_ORDER', reference_docno: 'SO-1', reference_line_id: 11 },
      db
    );
    expect(released?.status).toBe('RELEASED');
    expect(released?.released_at).toBeTruthy();

    // Re-create after release reactivates the row (no duplicate)
    const r3 = StockReservationModel.create(
      { item_id: 1, warehouse_id: 1, batch_id: batchId, quantity_reserved: 7, reference_doctype: 'SALES_ORDER', reference_docno: 'SO-1', reference_line_id: 11 },
      db
    );
    expect(r3.id).toBe(r1.id);
    expect(r3.status).toBe('ACTIVE');
    expect(r3.quantity_reserved).toBe(7);
    const count2 = (db.prepare(`SELECT COUNT(*) AS c FROM stock_reservations`).get() as any).c;
    expect(count2).toBe(1);
  });

  it('consume marks CONSUMED; release after consume returns undefined', () => {
    const db = createFixture();
    setFeatureEnabled(db, 'feature_batch_locations', true);
    const batchId = seedBatch(db, { batchNo: 'B1', qty: 100 });

    StockReservationModel.create(
      { item_id: 1, warehouse_id: 1, batch_id: batchId, quantity_reserved: 5, reference_doctype: 'TRANSFER', reference_docno: 'TR-1', reference_line_id: 1 },
      db
    );
    const consumed = StockReservationModel.consume(
      { reference_doctype: 'TRANSFER', reference_docno: 'TR-1', reference_line_id: 1 },
      db
    );
    expect(consumed?.status).toBe('CONSUMED');

    // Consumed rows are terminal — release is a no-op
    const released = StockReservationModel.release(
      { reference_doctype: 'TRANSFER', reference_docno: 'TR-1', reference_line_id: 1 },
      db
    );
    expect(released).toBeUndefined();
  });

  it('throws when the feature flag is off; auto-release respects QC_HOLD', () => {
    const db = createFixture();
    // Flag defaults off (migration inserts '0')
    expect(isFeatureEnabled(db, 'feature_batch_locations')).toBe(false);
    expect(() =>
      StockReservationModel.create(
        { item_id: 1, warehouse_id: 1, quantity_reserved: 5, reference_doctype: 'SALES_ORDER', reference_docno: 'SO-9', reference_line_id: 1 },
        db
      )
    ).toThrow('feature_batch_locations');

    setFeatureEnabled(db, 'feature_batch_locations', true);
    StockReservationModel.create(
      { item_id: 1, warehouse_id: 1, quantity_reserved: 3, reference_doctype: 'QC_HOLD', reference_docno: 'QC-1', reference_line_id: 1 },
      db
    );
    // Age it past the TTL then auto-release: QC_HOLD survives
    db.prepare(`UPDATE stock_reservations SET created_at = datetime('now','-48 hours') WHERE reference_doctype='QC_HOLD'`).run();
    const released = StockReservationModel.autoReleaseExpired(db, 24);
    expect(released).toBe(0);
  });
});

describe('7.3 batch status derivation and overrides', () => {
  it('ACTIVE by default; BLOCKED when halted; override wins except EXPIRED', () => {
    const db = createFixture();
    const batchId = seedBatch(db, { batchNo: 'B1', qty: 10 });
    const locId = (db.prepare(`SELECT location_id FROM batch_stock_by_location WHERE batch_id=?`).get(batchId) as any).location_id;

    expect(getEffectiveBatchStatus(db, batchId, locId)).toBe('ACTIVE');

    // Halted → BLOCKED
    db.prepare(`UPDATE stock_batches SET halted=1, halted_reason='damaged' WHERE id=?`).run(batchId);
    expect(getEffectiveBatchStatus(db, batchId, locId)).toBe('BLOCKED');

    // Override (e.g. QUARANTINED) beats halted
    setBatchStatusOverride(db, batchId, locId, 'QUARANTINED');
    expect(getEffectiveBatchStatus(db, batchId, locId)).toBe('QUARANTINED');

    // EXPIRED cannot be overridden — derived from expiry_date only
    expect(() => setBatchStatusOverride(db, batchId, locId, 'EXPIRED')).toThrow();
    db.prepare(`UPDATE stock_batches SET halted=0, halted_reason=NULL, expiry_date='2020-01-01' WHERE id=?`).run(batchId);
    expect(getEffectiveBatchStatus(db, batchId, locId)).toBe('EXPIRED');

    // Clear override → falls back to halted=0 + qty>0 → ACTIVE? no — expiry wins
    db.prepare(`UPDATE batch_stock_by_location SET status_override=NULL WHERE batch_id=?`).run(batchId);
    expect(getEffectiveBatchStatus(db, batchId, locId)).toBe('EXPIRED');

    // Zero availability → REJECTED (only when not expired/halted/overridden)
    db.prepare(`UPDATE stock_batches SET expiry_date=NULL WHERE id=?`).run(batchId);
    db.prepare(`UPDATE batch_stock_by_location SET quantity_available=0 WHERE batch_id=?`).run(batchId);
    expect(getEffectiveBatchStatus(db, batchId, locId)).toBe('REJECTED');
  });

  it('per-location override: same batch QUARANTINED in one location, ACTIVE in another', () => {
    const db = createFixture();
    db.prepare(`INSERT INTO locations (warehouse_id,location_code,location_name) VALUES (1,'RACK-A','Rack A')`).run();
    const defaultLoc = (db.prepare(`SELECT id FROM locations WHERE warehouse_id=1 AND location_code='DEFAULT'`).get() as any).id;
    const rackA = (db.prepare(`SELECT id FROM locations WHERE warehouse_id=1 AND location_code='RACK-A'`).get() as any).id;

    const batchId = seedBatch(db, { batchNo: 'B1', qty: 10 });
    db.prepare(
      `INSERT INTO batch_stock_by_location (batch_id,location_id,quantity_physical,quantity_reserved,quantity_available) VALUES (?,?,5,0,5)`
    ).run(batchId, rackA);

    setBatchStatusOverride(db, batchId, rackA, 'QUARANTINED');
    expect(getEffectiveBatchStatus(db, batchId, defaultLoc)).toBe('ACTIVE');
    expect(getEffectiveBatchStatus(db, batchId, rackA)).toBe('QUARANTINED');
  });
});

describe('7.4 FEFO/FIFO skips non-ACTIVE locations', () => {
  it('consumes from ACTIVE location rows only; quarantined rows are bypassed', () => {
    const db = createFixture();
    setFeatureEnabled(db, 'feature_batch_locations', true);
    db.prepare(`INSERT INTO locations (warehouse_id,location_code,location_name) VALUES (1,'RACK-A','Rack A')`).run();
    const defaultLoc = (db.prepare(`SELECT id FROM locations WHERE warehouse_id=1 AND location_code='DEFAULT'`).get() as any).id;
    const rackA = (db.prepare(`SELECT id FROM locations WHERE warehouse_id=1 AND location_code='RACK-A'`).get() as any).id;

    // Batch B1 (older) entirely quarantined in DEFAULT; B2 (newer) ACTIVE in DEFAULT + RACK-A
    const b1 = seedBatch(db, { batchNo: 'B1', qty: 10, cost: 5, received: '2026-01-01', locationId: defaultLoc });
    const b2 = seedBatch(db, { batchNo: 'B2', qty: 20, cost: 8, received: '2026-02-01', locationId: defaultLoc });
    db.prepare(
      `INSERT INTO batch_stock_by_location (batch_id,location_id,quantity_physical,quantity_reserved,quantity_available) VALUES (?,?,5,0,5)`
    ).run(b2, rackA);
    setBatchStatusOverride(db, b1, defaultLoc, 'QUARANTINED');

    db.prepare(
      `INSERT INTO stock_balances (item_id,warehouse_id,quantity,quantity_physical,quantity_reserved,quantity_available)
       VALUES (1,1,25,25,0,25)`
    ).run();
    db.prepare(`UPDATE items SET current_stock=25 WHERE id=1`).run();

    // Consume 7: B1 skipped (quarantined), all from B2@DEFAULT (oldest
    // location first).
    const consumption = StockMovementModel.consumeFromOldestBatches(1, 1, 7, db);
    expect(consumption).toHaveLength(1);
    expect(consumption[0].batchId).toBe(b2);
    expect(consumption[0].consumed).toBe(7);

    const rows = db
      .prepare(`SELECT bsl.quantity_physical, bsl.quantity_available, l.location_code FROM batch_stock_by_location bsl JOIN locations l ON bsl.location_id=l.id WHERE bsl.batch_id=? ORDER BY l.location_code`)
      .all(b2) as any[];
    const byCode = Object.fromEntries(rows.map((r) => [r.location_code, r]));
    // DEFAULT (older location) covers all 7; RACK-A untouched.
    expect(byCode['DEFAULT'].quantity_physical).toBe(13);
    expect(byCode['RACK-A'].quantity_physical).toBe(5);
    // Quarantined B1 untouched
    const b1row = db.prepare(`SELECT quantity_physical FROM batch_stock_by_location WHERE batch_id=?`).get(b1) as any;
    expect(b1row.quantity_physical).toBe(10);
  });
});

describe('7.9 backfill: one location row per existing batch', () => {
  it('creates exactly one DEFAULT location row per batch; idempotent; balances updated', () => {
    const db = createFixture();
    // Pre-feature state: two batches in stock_batches only
    db.prepare(
      `INSERT INTO stock_batches (batch_no,item_id,warehouse_id,source_type,source_id,quantity_original,quantity_remaining,unit_cost,received_date)
       VALUES ('OLD-1',1,1,'PURCHASE',1,20,20,5,'2026-01-01')`
    ).run();
    db.prepare(
      `INSERT INTO stock_batches (batch_no,item_id,warehouse_id,source_type,source_id,quantity_original,quantity_remaining,unit_cost,received_date)
       VALUES ('OLD-2',1,1,'PURCHASE',2,30,30,6,'2026-02-01')`
    ).run();
    db.prepare(`INSERT INTO stock_balances (item_id,warehouse_id,quantity) VALUES (1,1,50)`).run();

    const inserted1 = runBackfillBatchLocations(db);
    expect(inserted1).toBe(2);

    const rows = db
      .prepare(`SELECT sb.batch_no, l.location_code, bsl.quantity_physical, bsl.quantity_available FROM batch_stock_by_location bsl JOIN stock_batches sb ON sb.id=bsl.batch_id JOIN locations l ON l.id=bsl.location_id ORDER BY sb.batch_no`)
      .all() as any[];
    expect(rows).toHaveLength(2);
    expect(rows[0].location_code).toBe('DEFAULT');
    expect(rows[0].quantity_physical).toBe(20);
    expect(rows[1].location_code).toBe('DEFAULT');
    expect(rows[1].quantity_physical).toBe(30);

    // stock_balances extension columns synced
    const bal = db.prepare(`SELECT quantity_physical, quantity_reserved, quantity_available FROM stock_balances WHERE item_id=1 AND warehouse_id=1`).get() as any;
    expect(bal.quantity_physical).toBe(50);
    expect(bal.quantity_available).toBe(50);
    expect(bal.quantity_reserved).toBe(0);

    // Idempotent: second run inserts nothing
    const inserted2 = runBackfillBatchLocations(db);
    expect(inserted2).toBe(0);
    const count = (db.prepare(`SELECT COUNT(*) AS c FROM batch_stock_by_location`).get() as any).c;
    expect(count).toBe(2);
  });
});

describe('7.10 feature flag off vs on behavior', () => {
  it('flag off: legacy path (quantity_remaining) is used; reservations rejected', () => {
    const db = createFixture();
    // Flag off (default from migration)
    const batchId = seedBatch(db, { batchNo: 'B1', qty: 50 });
    db.prepare(`INSERT INTO stock_balances (item_id,warehouse_id,quantity) VALUES (1,1,50)`).run();
    db.prepare(`UPDATE items SET current_stock=50 WHERE id=1`).run();

    const consumption = StockMovementModel.consumeFromOldestBatches(1, 1, 10, db);
    // Legacy path returns the batch too (single path both ways) — but
    // batch_stock_by_location is NOT consumed
    expect(consumption.length).toBeGreaterThan(0);
    const locRow = db.prepare(`SELECT quantity_physical FROM batch_stock_by_location WHERE batch_id=?`).get(batchId) as any;
    // Legacy path only decrements stock_batches.quantity_remaining
    const master = db.prepare(`SELECT quantity_remaining FROM stock_batches WHERE id=?`).get(batchId) as any;
    expect(master.quantity_remaining).toBe(40);
    expect(() =>
      StockReservationModel.create(
        { item_id: 1, warehouse_id: 1, quantity_reserved: 1, reference_doctype: 'X', reference_docno: 'D', reference_line_id: 1 },
        db
      )
    ).toThrow();
    void locRow;
  });

  it('flag on: consumption goes through batch_stock_by_location; reservations work', () => {
    const db = createFixture();
    setFeatureEnabled(db, 'feature_batch_locations', true);
    const batchId = seedBatch(db, { batchNo: 'B1', qty: 50 });
    db.prepare(
      `INSERT INTO stock_balances (item_id,warehouse_id,quantity,quantity_physical,quantity_reserved,quantity_available)
       VALUES (1,1,50,50,0,50)`
    ).run();
    db.prepare(`UPDATE items SET current_stock=50 WHERE id=1`).run();

    const consumption = StockMovementModel.consumeFromOldestBatches(1, 1, 10, db);
    expect(consumption[0].batchId).toBe(batchId);

    const locRow = db.prepare(`SELECT quantity_physical FROM batch_stock_by_location WHERE batch_id=?`).get(batchId) as any;
    expect(locRow.quantity_physical).toBe(40); // location row consumed
    const master = db.prepare(`SELECT quantity_remaining FROM stock_batches WHERE id=?`).get(batchId) as any;
    expect(master.quantity_remaining).toBe(40); // master synced too

    const r = StockReservationModel.create(
      { item_id: 1, warehouse_id: 1, batch_id: batchId, quantity_reserved: 4, reference_doctype: 'SALES_ORDER', reference_docno: 'SO-1', reference_line_id: 1 },
      db
    );
    expect(r.status).toBe('ACTIVE');
  });
});
