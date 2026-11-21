/**
 * S-6: migration 127 must not wipe a live reservation on upgrade.
 *
 * The report: 127 sets `stock_balances.quantity_physical` to
 * SUM(stock_batches.quantity_remaining), `quantity_reserved` to 0, and
 * `quantity_available` to the same SUM. The runtime mirror
 * (`syncStockBalancesExtension`) instead sums the BIN rows
 * (`batch_stock_by_location`). A reservation reduces the bin's
 * `quantity_reserved`, never `stock_batches.quantity_remaining`, so after 127
 * the mirror claims the reserved units are sellable, and `resolveAvailableQuantity`
 * (flag-ON) reads that mirror as the sale gate.
 *
 * The upgrade sequence under test is supported and real:
 *   - `add-batch-location-model.sql` and `StockReservation` both landed in
 *     8103a1e2 (2026-09-13);
 *   - migration 127 landed later, in 9064800c (2026-11-16).
 * So a database built by the 2026-09-13 line, with the flag ON and a live
 * reservation, is exactly the "immediately before 127" state this spec builds.
 *
 * The pre-127 state is built by the PRODUCTION reservation path, not by hand,
 * then 127 runs as its own file — the same way the boot sequence runs it.
 */
import fs from 'fs';
import path from 'path';
import { beforeAll, describe, expect, it } from '@jest/globals';
import db from '../config/database';
import { StockReservationModel } from '../models/StockReservation';
import StockMovementModel from '../models/StockMovement';
import { setFeatureEnabled } from '../utils/featureFlags';
import { createCustomer, createItem, getAuthCookie, purchaseStock } from './helpers/invoiceReturnSpec';

const FLAG = 'feature_batch_locations';

/** Run a migration file by name, exactly as the boot path does. */
function runMigrationFile(name: string): void {
  db.exec(fs.readFileSync(path.join(__dirname, '..', 'migrations', name), 'utf8'));
}

/** The upgrade sequence a build with S-6's fix runs, in boot order. */
function runUpgrade(): void {
  runMigrationFile('127_backfill_batch_stock_by_location.sql');
  runMigrationFile('132_stock_balance_mirror_from_bins.sql');
}

function mirror(itemId: number, warehouseId: number): {
  quantity_physical: number; quantity_reserved: number; quantity_available: number;
} {
  return db.prepare(
    `SELECT quantity_physical, quantity_reserved, quantity_available
     FROM stock_balances WHERE item_id = ? AND warehouse_id = ?`,
  ).get(itemId, warehouseId) as {
    quantity_physical: number; quantity_reserved: number; quantity_available: number;
  };
}

function bin(batchId: number, locationId: number): {
  quantity_physical: number; quantity_reserved: number; quantity_available: number;
} {
  return db.prepare(
    `SELECT quantity_physical, quantity_reserved, quantity_available
     FROM batch_stock_by_location WHERE batch_id = ? AND location_id = ?`,
  ).get(batchId, locationId) as {
    quantity_physical: number; quantity_reserved: number; quantity_available: number;
  };
}

describe('S-6: migration 127 preserves a live reservation', () => {
  let itemId = 0;
  let warehouseId = 0;
  let batchId = 0;
  let locationId = 0;

  beforeAll(async () => {
    const cookie = await getAuthCookie();
    await createCustomer('Reserved Upgrade Co', cookie);
    setFeatureEnabled(db, FLAG, true);
    itemId = await createItem('S6-RESERVED-ITEM', cookie);
    warehouseId = (db.prepare('SELECT id FROM warehouses WHERE is_active = 1 LIMIT 1').get() as { id: number }).id;

    // 10 units on hand, flag ON, so the bin row exists before the upgrade.
    await purchaseStock(itemId, warehouseId, 10, 5, cookie, '2026-09-05');

    const batch = db.prepare(
      'SELECT id FROM stock_batches WHERE item_id = ? ORDER BY id DESC LIMIT 1',
    ).get(itemId) as { id: number };
    batchId = batch.id;
    locationId = (db.prepare(
      `SELECT id FROM locations WHERE warehouse_id = ? AND location_code = 'DEFAULT'`,
    ).get(warehouseId) as { id: number }).id;

    // A live ACTIVE reservation of 4 units, created by the production path.
    StockReservationModel.create({
      item_id: itemId,
      warehouse_id: warehouseId,
      batch_id: batchId,
      location_id: locationId,
      quantity_reserved: 4,
      reference_doctype: 'SALES_ORDER',
      reference_docno: 'SO-S6-1',
      reference_line_id: 1,
    }, db);
  });

  it('the pre-127 state really holds a live reservation (fixture sanity)', () => {
    expect(bin(batchId, locationId).quantity_reserved).toBe(4);
    expect(bin(batchId, locationId).quantity_available).toBe(6);
    const m = mirror(itemId, warehouseId);
    expect(m.quantity_physical).toBe(10);
    expect(m.quantity_reserved).toBe(4);
    expect(m.quantity_available).toBe(6);
    const live = db.prepare(
      `SELECT COUNT(*) AS n FROM stock_reservations
       WHERE reference_docno = 'SO-S6-1' AND status = 'ACTIVE'`,
    ).get() as { n: number };
    expect(live.n).toBe(1);
  });

  it('the repair migration is registered in the boot sequence', () => {
    // The upgrade test above runs the file directly, so on its own it would
    // stay green with the migration unregistered. Pin the registration.
    const applied = db.prepare(
      `SELECT filename FROM schema_migrations
       WHERE filename = '132_stock_balance_mirror_from_bins.sql'`,
    ).get() as { filename: string } | undefined;
    expect(applied?.filename).toBe('132_stock_balance_mirror_from_bins.sql');
  });

  it('the upgrade keeps the reserved units out of the sellable gate', () => {
    runUpgrade();

    // The bin row is the authoritative record of what is held.
    expect(bin(batchId, locationId).quantity_reserved).toBe(4);
    expect(bin(batchId, locationId).quantity_available).toBe(6);

    // The mirror is what the flag-ON sale gate reads.
    const m = mirror(itemId, warehouseId);
    expect(m.quantity_reserved).toBe(4);
    expect(m.quantity_available).toBe(6);
  });

  it('the reserved units are not offered to a sale after the upgrade', () => {
    runUpgrade();

    // 10 on hand, 4 held: only 6 may be sold. A sale of 10 must be refused.
    expect(() => StockMovementModel.consumeForSale(itemId, warehouseId, 10, db, '2026-09-10'))
      .toThrow();
  });
});
