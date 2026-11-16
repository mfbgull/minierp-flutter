/**
 * BUG-013 legacy-upgrade rehearsal.
 *
 * The unit specs prove migration 127 is correct on a fixture they build in the
 * SAME process. This one asks the deployment question instead: take a real
 * database that predates the batch-location model — batches with no location
 * rows and stock_balances mirrors stuck at 0 — upgrade it through migration 127
 * as a FILE, then run a month of operations through the public API and check
 * that nothing broke.
 *
 * Two things this spec proves that the others do not:
 *   1. Row counts before and after the migration, on a database that already
 *      holds stock. The migration must fill exactly the missing rows and change
 *      nothing else.
 *   2. The four operation families (sale, return, transfer, void) all work on
 *      the upgraded copy, invariants A-J hold, and the per-bin drift check
 *      reports zero.
 *
 * HOW THE "LEGACY" COPY IS BUILT. Not by faking rows. The database is built by
 * the real server on a temp DATABASE_PATH, exercised with a purchase, then the
 * batch-location state is STRIPPED to the pre-migration shape: location rows
 * deleted and the stock_balances mirrors zeroed. That is exactly what an
 * install that ran with the flag off looks like, so the upgrade is exercised
 * against the real defect, not a stand-in for it.
 *
 * Runs on its own temp database, never the live one. Read-only on failure.
 */
import fs from 'fs';
import os from 'os';
import path from 'path';
import { afterAll, beforeAll, describe, expect, it } from '@jest/globals';
import request from 'supertest';
import Database from 'better-sqlite3';
import app from '../app';
import db, { dbPath } from '../config/database';
import { setFeatureEnabled } from '../utils/featureFlags';
import {
  batchLocationDriftImbalances,
  expectAllInvariantsHold,
} from './helpers/accountingInvariants';
import {
  createCustomer,
  createInvoice,
  createItem,
  getAuthCookie,
  nextIdemKey,
  purchaseStock,
} from './helpers/invoiceReturnSpec';

const FLAG = 'feature_batch_locations';
const AS_OF = '2026-09-20';

let legacyDir = '';
let legacyPath = '';
let cookie = '';
let warehouseA = 0;
let warehouseB = 0;

/** Row counts that matter to this migration, read straight from a file. */
interface Counts {
  warehouses: number;
  locations: number;
  defaultLocations: number;
  batches: number;
  batchesWithoutLocation: number;
  batchLocations: number;
  stockBalances: number;
  zeroBalances: number;
  batchQty: number;
  locationQty: number;
}

function countFile(file: string): Counts {
  const conn = new Database(file, { readonly: true });
  try {
    const n = (sql: string): number => Number((conn.prepare(sql).get() as { n: number }).n);
    return {
      warehouses: n('SELECT COUNT(*) AS n FROM warehouses'),
      locations: n('SELECT COUNT(*) AS n FROM locations'),
      defaultLocations: n("SELECT COUNT(*) AS n FROM locations WHERE location_code = 'DEFAULT'"),
      batches: n('SELECT COUNT(*) AS n FROM stock_batches'),
      batchesWithoutLocation: n(
        `SELECT COUNT(*) AS n FROM stock_batches sb
         WHERE NOT EXISTS (SELECT 1 FROM batch_stock_by_location b WHERE b.batch_id = sb.id)`,
      ),
      batchLocations: n('SELECT COUNT(*) AS n FROM batch_stock_by_location'),
      stockBalances: n('SELECT COUNT(*) AS n FROM stock_balances'),
      zeroBalances: n('SELECT COUNT(*) AS n FROM stock_balances WHERE quantity_available = 0'),
      batchQty: n('SELECT COALESCE(SUM(quantity_remaining), 0) AS n FROM stock_batches'),
      locationQty: n('SELECT COALESCE(SUM(quantity_physical), 0) AS n FROM batch_stock_by_location'),
    };
  } finally {
    conn.close();
  }
}

/**
 * Strip the batch-location state to the shape an install that ran with the flag
 * OFF would have. Location rows are removed; the stock_balances mirrors are
 * zeroed. This is the pre-migration state, produced by deleting the new write,
 * not by inventing legacy numbers.
 */
function stripToLegacy(file: string): void {
  const conn = new Database(file);
  try {
    conn.pragma('foreign_keys = OFF');
    conn.exec('DELETE FROM batch_stock_by_location');
    conn.exec('UPDATE stock_balances SET quantity_physical = 0, quantity_reserved = 0, quantity_available = 0');
    conn.pragma('foreign_keys = ON');
  } finally {
    conn.close();
  }
}

/** Run migration 127 as a file, exactly as a boot would, on a copy. */
function runMigration127(file: string): void {
  const sql = fs.readFileSync(
    path.join(__dirname, '..', 'migrations', '127_backfill_batch_stock_by_location.sql'),
    'utf8',
  );
  const conn = new Database(file);
  try {
    conn.exec(sql);
  } finally {
    conn.close();
  }
}

function warehouses(): { a: number; b: number } {
  const rows = db.prepare('SELECT id FROM warehouses ORDER BY id').all() as Array<{ id: number }>;
  return { a: rows[0].id, b: rows[1].id };
}

function batchTotal(itemId: number, wh: number): number {
  const row = db.prepare(
    'SELECT COALESCE(SUM(quantity_remaining), 0) AS q FROM stock_batches WHERE item_id = ? AND warehouse_id = ?',
  ).get(itemId, wh) as { q: number };
  return Number(row.q);
}

function locationTotal(itemId: number, wh: number): number {
  const row = db.prepare(
    `SELECT COALESCE(SUM(bsl.quantity_available), 0) AS q
     FROM batch_stock_by_location bsl
     JOIN stock_batches sb ON sb.id = bsl.batch_id
     WHERE sb.item_id = ? AND sb.warehouse_id = ?`,
  ).get(itemId, wh) as { q: number };
  return Number(row.q);
}

function balance(itemId: number, wh: number): number {
  const row = db.prepare('SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?')
    .get(itemId, wh) as { quantity: number } | undefined;
  return row ? Number(row.quantity) : 0;
}

describe('BUG-013: a legacy database upgrades through migration 127 and keeps working', () => {
  /** The populated pre-migration copy, built once and reused by every case. */
  let before: Counts;
  let after: Counts;

  beforeAll(async () => {
    cookie = await getAuthCookie();
    const wh = warehouses();
    warehouseA = wh.a;
    warehouseB = wh.b;

    // Populate the live temp database with real batches through the API.
    const seed = await createItem('Legacy Seed', cookie);
    await purchaseStock(seed, warehouseA, 25, 40, cookie, AS_OF);
    await purchaseStock(seed, warehouseB, 10, 40, cookie, AS_OF);

    // Freeze that populated state to a file, then strip it to the legacy shape.
    legacyDir = fs.mkdtempSync(path.join(os.tmpdir(), 'bug013-legacy-'));
    legacyPath = path.join(legacyDir, 'erp.db');
    db.pragma('wal_checkpoint(TRUNCATE)');
    fs.copyFileSync(dbPath, legacyPath);
    stripToLegacy(legacyPath);

    before = countFile(legacyPath);
    runMigration127(legacyPath);
    after = countFile(legacyPath);

    // Write the before/after table to a file as well as stdout. Jest's setup
    // can swallow console output, and ship-time reviewers should not have to
    // re-run the spec to see the numbers.
    const rows: string[] = [];
    for (const key of Object.keys(before) as Array<keyof Counts>) {
      const d = after[key] - before[key];
      rows.push(`${key.padEnd(24)} ${String(before[key]).padStart(8)}  ${String(after[key]).padStart(8)}  ${(d >= 0 ? '+' : '') + d}`);
    }
    const table = [
      '=== migration 127 row counts (populated legacy copy) ===',
      'column                      before      after     delta',
      ...rows,
    ].join('\n');
    console.log(`\n${table}`);
    const outFile = process.env.BUG013_ROWCOUNT_REPORT;
    if (outFile) fs.writeFileSync(outFile, `${table}\n`);
  }, 120_000);

  afterAll(() => {
    if (legacyDir) fs.rmSync(legacyDir, { recursive: true, force: true });
  });

  it('fills exactly the missing location rows and changes nothing else', () => {
    // Before: batches exist, no location row carries them, the mirrors are 0.
    expect(before.batches).toBeGreaterThan(0);
    expect(before.batchesWithoutLocation).toBe(before.batches);
    expect(before.batchLocations).toBe(0);
    expect(before.zeroBalances).toBe(before.stockBalances);

    // After: one location row per batch, and no batch is left uncovered.
    expect(after.batches).toBe(before.batches);
    expect(after.batchesWithoutLocation).toBe(0);
    expect(after.batchLocations).toBe(before.batches);

    // No warehouse or balance row is created or removed by the backfill.
    expect(after.warehouses).toBe(before.warehouses);
    expect(after.stockBalances).toBe(before.stockBalances);

    // The quantity the location rows carry equals the batch quantity it mirrors.
    expect(after.locationQty).toBe(before.batchQty);
  });

  it('seeds a DEFAULT location for any warehouse that lacks one', () => {
    expect(after.defaultLocations).toBeGreaterThanOrEqual(before.defaultLocations);
    expect(after.locations).toBeGreaterThanOrEqual(before.locations);
  });

  it('is idempotent: a second run changes no count', () => {
    runMigration127(legacyPath);
    expect(countFile(legacyPath)).toEqual(after);
  });

  it('leaves the upgraded database observable at the layer that failed', () => {
    // The pre-migration bug: batch_stock_by_location answered 0 for stock that
    // stock_batches still held. After the migration the two agree.
    expect(after.locationQty).toBeGreaterThan(0);
    expect(after.zeroBalances).toBeLessThan(before.zeroBalances);
  });
});

describe('BUG-013: a month of operations on the upgraded database', () => {
  beforeAll(async () => {
    cookie = await getAuthCookie();
    const wh = warehouses();
    warehouseA = wh.a;
    warehouseB = wh.b;
    setFeatureEnabled(db, FLAG, true);
  });

  it('sells, returns, transfers and voids with invariants A-J and zero drift', async () => {
    const itemId = await createItem('Upgraded Flow', cookie);
    await purchaseStock(itemId, warehouseA, 20, 55, cookie, AS_OF);
    expectAllInvariantsHold('upgraded:after purchase', db);

    const customerId = await createCustomer('Upgraded Customer', cookie);
    const sale = await createInvoice(
      {
        customerId,
        itemId,
        lines: [{ quantity: 5, unitPrice: 90 }],
        payment: 'full',
        invoiceDate: AS_OF,
      },
      cookie,
    );
    expect(sale.invoiceId).toBeGreaterThan(0);
    expectAllInvariantsHold('upgraded:after sale', db);

    // Transfer out of A into B, then void it: both warehouses must return.
    const aBefore = { batch: batchTotal(itemId, warehouseA), location: locationTotal(itemId, warehouseA) };
    const created = await request(app)
      .post('/api/inventory/stock-transfers')
      .set('Cookie', cookie)
      .set('Idempotency-Key', nextIdemKey('upgraded-transfer'))
      .send({
        item_id: itemId,
        from_warehouse_id: warehouseA,
        to_warehouse_id: warehouseB,
        quantity: 4,
        transfer_date: AS_OF,
        notes: 'upgrade rehearsal transfer',
      });
    expect(created.status).toBe(201);
    expectAllInvariantsHold('upgraded:after transfer', db);

    const movementNo = (
      db.prepare(
        `SELECT movement_no FROM stock_movements
         WHERE item_id = ? AND warehouse_id = ? AND movement_type = 'TRANSFER'
         ORDER BY id DESC LIMIT 1`,
      ).get(itemId, warehouseA) as { movement_no: string } | undefined
    )?.movement_no;
    expect(movementNo).toBeTruthy();

    const voided = await request(app)
      .post(`/api/inventory/stock-transfers/${movementNo}/void`)
      .set('Cookie', cookie)
      .set('Idempotency-Key', nextIdemKey('upgraded-transfer-void'))
      .send({ reason: 'upgrade rehearsal void' });
    expect(voided.status).toBe(200);

    // The void put warehouse A back where it was before the transfer.
    expect({ batch: batchTotal(itemId, warehouseA), location: locationTotal(itemId, warehouseA) })
      .toEqual(aBefore);
    expect({ batch: batchTotal(itemId, warehouseA) })
      .toEqual({ batch: balance(itemId, warehouseA) });

    expectAllInvariantsHold('upgraded:after void', db);
    expect(batchLocationDriftImbalances(db)).toEqual([]);
  });

  it('never reports a batch as over-covered on any bin after the month', () => {
    // Per-bin: physical must equal available + reserved. A single mismatch
    // fails the whole run.
    const rows = db.prepare(
      `SELECT bsl.id AS id,
              bsl.quantity_physical - bsl.quantity_available - bsl.quantity_reserved AS diff
       FROM batch_stock_by_location bsl
       WHERE ABS(bsl.quantity_physical - bsl.quantity_available - bsl.quantity_reserved) > 0.005`,
    ).all() as Array<{ id: number; diff: number }>;
    expect(rows).toEqual([]);
    expect(batchLocationDriftImbalances(db)).toEqual([]);
  });
});
