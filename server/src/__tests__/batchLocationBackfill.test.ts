/**
 * BUG-013: a legacy database must survive a `feature_batch_locations` flip.
 *
 * The defect: `sellableAvailabilityByWarehouseSql` reads
 * `batch_stock_by_location` when the flag is on, but nothing ever filled that
 * table for batches created while the flag was off. Flipping the flag on made
 * every sale see sellable stock 0 — a stock-amnesia switch.
 *
 * This spec walks the real sequence an existing install goes through:
 *
 *   1. buy stock with the flag OFF (the legacy shape — no location rows),
 *   2. confirm the location table is empty for that batch,
 *   3. run the backfill migration,
 *   4. flip the flag ON,
 *   5. sell — the sale must succeed and deduct the real quantity.
 *
 * The backfill is exercised through its own file, so the test proves the
 * migration body, not a hand-written INSERT.
 */
import { beforeAll, describe, expect, it } from '@jest/globals';
import fs from 'fs';
import path from 'path';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { createCustomer, createItem, getAuthCookie, nextIdemKey, purchaseStock } from './helpers/invoiceReturnSpec';
import { batchLocationDriftImbalances, expectAllInvariantsHold } from './helpers/accountingInvariants';
import { setFeatureEnabled } from '../utils/featureFlags';

/** Run a migration file by name, exactly as the boot path does. */
function runMigrationFile(name: string): void {
  const sql = fs.readFileSync(path.join(__dirname, '..', 'migrations', name), 'utf8');
  db.exec(sql);
}

function locationRowsFor(batchId: number): number {
  return (db.prepare(
    'SELECT COUNT(*) AS n FROM batch_stock_by_location WHERE batch_id = ?',
  ).get(batchId) as { n: number }).n;
}

function batchFor(itemId: number): { id: number; quantity_remaining: number } {
  return db.prepare(
    'SELECT id, quantity_remaining FROM stock_batches WHERE item_id = ? ORDER BY id DESC LIMIT 1',
  ).get(itemId) as { id: number; quantity_remaining: number };
}

function warehouseId(): number {
  return (db.prepare('SELECT id FROM warehouses WHERE is_active = 1 LIMIT 1').get() as { id: number }).id;
}

function sellableFromLocationTable(itemId: number): number {
  return (db.prepare(`
    SELECT COALESCE(SUM(bsl.quantity_available), 0) AS q
    FROM batch_stock_by_location bsl
    JOIN stock_batches sb ON sb.id = bsl.batch_id
    WHERE sb.item_id = ?
  `).get(itemId) as { q: number }).q;
}

describe('BUG-013: legacy batches survive a feature_batch_locations flip', () => {
  let cookie: string;
  let customerId: number;

  beforeAll(async () => {
    cookie = await getAuthCookie();
    customerId = await createCustomer('Flip Flag Co', cookie);
  });

  it('a batch bought with the flag off gets a location row and stays sellable after the flip', async () => {
    // Guarantee the legacy shape regardless of what earlier tests left behind.
    setFeatureEnabled(db, 'feature_batch_locations', false);

    const itemId = await createItem('Legacy Flip Item', cookie);
    const wh = warehouseId();
    await purchaseStock(itemId, wh, 7, 40, cookie);

    const batch = batchFor(itemId);
    expect(Number(batch.quantity_remaining)).toBeCloseTo(7, 3);

    // The write path is no longer gated on the flag, so a new batch gets its
    // location row even while the flag is off. That is the second half of the
    // fix: the flag must only choose which source is READ.
    expect(locationRowsFor(batch.id)).toBe(1);

    // Model the legacy shape explicitly: remove the row, as a batch created by
    // an older build would have had none.
    db.prepare('DELETE FROM batch_stock_by_location WHERE batch_id = ?').run(batch.id);
    expect(locationRowsFor(batch.id)).toBe(0);

    // 3. The backfill migration is what repairs an existing database.
    runMigrationFile('127_backfill_batch_stock_by_location.sql');
    expect(locationRowsFor(batch.id)).toBe(1);

    // 4. Flip the flag on. Before the fix this is where sales broke.
    setFeatureEnabled(db, 'feature_batch_locations', true);

    // The backfilled row carries the real quantity, so the two sources agree.
    expect(sellableFromLocationTable(itemId)).toBeCloseTo(Number(batch.quantity_remaining), 3);
    expect(batchLocationDriftImbalances(db)).toEqual([]);
  });

  it('still sells after the flip, for the right quantity', async () => {
    setFeatureEnabled(db, 'feature_batch_locations', true);

    const itemId = await createItem('Legacy Flip Sale Item', cookie);
    const wh = warehouseId();
    await purchaseStock(itemId, wh, 10, 25, cookie);
    const batch = batchFor(itemId);

    // Legacy shape: drop the location row and zero the flag-only mirror, as a
    // database that never ran the maintenance while the flag was off would have.
    db.prepare('DELETE FROM batch_stock_by_location WHERE batch_id = ?').run(batch.id);
    db.prepare(
      'UPDATE stock_balances SET quantity_available = 0 WHERE item_id = ? AND warehouse_id = ?',
    ).run(itemId, wh);
    runMigrationFile('127_backfill_batch_stock_by_location.sql');

    const before = sellableFromLocationTable(itemId);
    expect(before).toBeGreaterThanOrEqual(10);

    const res = await request(app)
      .post('/api/invoices')
      .set('Cookie', cookie)
      .set('Idempotency-Key', nextIdemKey('bug013-sale'))
      .send({
        customer_id: customerId,
        invoice_date: '2026-11-05',
        warehouse_id: wh,
        items: [{ item_id: itemId, quantity: 4, unit_price: 100 }],
      });
    // The sale itself must succeed. Before the fix this returned 400 with
    // "sellable stock 0, requested 4".
    expect(res.status).toBe(201);

    // Deduct the real quantity from BOTH sources, and keep them in step.
    const after = batchFor(itemId);
    expect(sellableFromLocationTable(itemId)).toBeCloseTo(Number(after.quantity_remaining), 3);
    expect(batchLocationDriftImbalances(db)).toEqual([]);
    expectAllInvariantsHold('sold after a legacy flag flip');

    // Restore the shipped default so this spec cannot leak the flag on.
    setFeatureEnabled(db, 'feature_batch_locations', false);
  });

  it('the backfill is idempotent: a second run changes nothing', async () => {
    const itemId = await createItem('Legacy Flip Idempotent', cookie);
    const wh = warehouseId();
    await purchaseStock(itemId, wh, 5, 10, cookie);
    const batch = batchFor(itemId);

    db.prepare('DELETE FROM batch_stock_by_location WHERE batch_id = ?').run(batch.id);
    db.prepare(
      'UPDATE stock_balances SET quantity_available = 0 WHERE item_id = ? AND warehouse_id = ?',
    ).run(itemId, wh);
    runMigrationFile('127_backfill_batch_stock_by_location.sql');
    const firstRun = db.prepare(
      'SELECT quantity_available FROM batch_stock_by_location WHERE batch_id = ?',
    ).get(batch.id) as { quantity_available: number };

    runMigrationFile('127_backfill_batch_stock_by_location.sql');
    const rows = db.prepare(
      'SELECT COUNT(*) AS n, COALESCE(SUM(quantity_available), 0) AS q FROM batch_stock_by_location WHERE batch_id = ?',
    ).get(batch.id) as { n: number; q: number };

    expect(rows.n).toBe(1);
    expect(Number(rows.q)).toBeCloseTo(Number(firstRun.quantity_available), 3);
  });

  it('repairs a MIXED state: batches with and without location rows', async () => {
    // The dangerous half-migrated shape: an install that ran the batch-location
    // model but only sometimes wrote location rows. The flag-on read path walks
    // batch_stock_by_location, so a batch WITHOUT a row is invisible (sellable
    // 0) while a batch WITH one is fine. Splitting the difference breaks sales
    // unpredictably. After one migration run there must be no such split.
    setFeatureEnabled(db, 'feature_batch_locations', false);

    const itemId = await createItem('Mixed State Item', cookie);
    const wh = warehouseId();
    await purchaseStock(itemId, wh, 6, 30, cookie, '2026-11-01');
    await purchaseStock(itemId, wh, 4, 35, cookie, '2026-11-02');
    await purchaseStock(itemId, wh, 9, 40, cookie, '2026-11-03');

    const batches = db.prepare(
      'SELECT id, quantity_remaining FROM stock_batches WHERE item_id = ? ORDER BY id',
    ).all(itemId) as Array<{ id: number; quantity_remaining: number }>;
    expect(batches.length).toBe(3);

    // Make it mixed on purpose: strip the row from the first and third only,
    // and give the middle one a STALE quantity so the migration must not trust
    // an existing row blindly.
    db.prepare('DELETE FROM batch_stock_by_location WHERE batch_id = ?').run(batches[0].id);
    db.prepare('DELETE FROM batch_stock_by_location WHERE batch_id = ?').run(batches[2].id);
    db.prepare(
      'UPDATE batch_stock_by_location SET quantity_physical = 0, quantity_available = 0 WHERE batch_id = ?',
    ).run(batches[1].id);
    const preCount = db.prepare('SELECT COUNT(*) AS n FROM batch_stock_by_location WHERE batch_id IN (?,?,?)')
      .get(batches[0].id, batches[1].id, batches[2].id) as { n: number };
    expect(preCount.n).toBe(1);

    runMigrationFile('127_backfill_batch_stock_by_location.sql');

    // After the migration every batch has a location row carrying its real
    // remaining quantity. The stale row is left alone (the migration skips
    // batches that already have a row) — that is why the write-time path must
    // keep rows in step; the drift check is what catches a stale one.
    for (const b of batches) {
      const row = db.prepare(
        'SELECT COUNT(*) AS n, COALESCE(SUM(quantity_available), 0) AS q FROM batch_stock_by_location WHERE batch_id = ?',
      ).get(b.id) as { n: number; q: number };
      expect(row.n).toBe(1);
    }

    // The two batches that had NO row are now visible with the right quantity.
    for (const idx of [0, 2]) {
      const row = db.prepare(
        'SELECT COALESCE(SUM(quantity_available), 0) AS q FROM batch_stock_by_location WHERE batch_id = ?',
      ).get(batches[idx].id) as { q: number };
      expect(Number(row.q)).toBeCloseTo(Number(batches[idx].quantity_remaining), 3);
    }

    // Repaired state: the item-level sum now AGREES with the master batches.
    // Equality, not >=: the migration also corrects a stale existing row, so
    // after one run there is exactly one truth and no phantom or hidden stock.
    const staleRowQ = db.prepare(
      'SELECT COALESCE(SUM(quantity_available), 0) AS q FROM batch_stock_by_location WHERE batch_id = ?',
    ).get(batches[1].id) as { q: number };
    expect(Number(staleRowQ.q)).toBeCloseTo(Number(batches[1].quantity_remaining), 3);

    const locationTotal = sellableFromLocationTable(itemId);
    const masterTotal = batches.reduce((s, b) => s + Number(b.quantity_remaining), 0);
    expect(locationTotal).toBeCloseTo(masterTotal, 3);

    setFeatureEnabled(db, 'feature_batch_locations', false);
  });
});
