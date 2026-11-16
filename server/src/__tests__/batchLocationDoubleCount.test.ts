/**
 * BUG-013 item 4: the flag-on sellable query must not double count.
 *
 * The query UNION ALLs two lists. The first is batch-derived: for a batch that
 * HAS location rows it sums the bins; for a batch with NO location rows it uses
 * the master quantity. The second list is the "residual" — unbatched stock —
 * computed as `stock_balances.quantity - SUM(all batches)`.
 *
 * The double-count risk is a PARTIALLY covered batch: some of its quantity sits
 * in a bin, the rest does not. If the residual branch deducted only the covered
 * part, the uncovered remainder would be counted twice — once by the bin branch
 * and again by the residual. The residual branch therefore deducts EVERY batch
 * regardless of coverage. This spec pins that.
 *
 * The second risk is warehouse scope: a batch whose own `warehouse_id` differs
 * from the warehouse a bin points at. The batch must count once, in exactly the
 * warehouse the bin names, and the query must not emit two rows for one pair —
 * a duplicate pair would make callers that read one row per pair mis-report.
 *
 * These are the two cases Gull asked for. Results are asserted as exact
 * numbers, not as "greater than zero".
 */
import { beforeAll, beforeEach, describe, expect, it } from '@jest/globals';
import db from '../config/database';
import { setFeatureEnabled } from '../utils/featureFlags';
/* eslint-disable-next-line @typescript-eslint/no-require-imports */
const StockMovementModel = (require('../models/StockMovement') as { default: typeof import('../models/StockMovement').default }).default;

const FLAG = 'feature_batch_locations';

function makeItem(tag: string): number {
  const code = `DCOUNT-${tag}-${Date.now()}-${Math.floor(process.hrtime()[1])}`;
  return Number(
    db.prepare(
      `INSERT INTO items (item_code, item_name, unit_of_measure, standard_cost, is_active)
       VALUES (?, ?, 'PCS', 10, 1)`,
    ).run(code, `Double Count ${tag}`).lastInsertRowid,
  );
}

function makeWarehouse(code: string): number {
  const id = Number(
    db.prepare(`INSERT INTO warehouses (warehouse_code, warehouse_name, is_active) VALUES (?, ?, 1)`)
      .run(`${code}-${Date.now()}-${Math.floor(process.hrtime()[1])}`, `DC ${code}`).lastInsertRowid,
  );
  db.prepare(`INSERT INTO locations (warehouse_id, location_code, location_name) VALUES (?, 'DEFAULT', 'Default')`)
    .run(id);
  return id;
}

/** A batch row in `warehouseId`, with `remaining` units. */
function makeBatch(itemId: number, warehouseId: number, remaining: number): number {
  return Number(
    db.prepare(
      `INSERT INTO stock_batches (batch_no, item_id, warehouse_id, source_type, source_id,
                                  quantity_original, quantity_remaining, unit_cost, received_date)
       VALUES (?, ?, ?, 'OPENING', 0, ?, ?, 10, '2026-01-01')`,
    ).run(`DC-B-${Date.now()}-${Math.floor(process.hrtime()[1])}`, itemId, warehouseId, remaining, remaining).lastInsertRowid,
  );
}

/** The warehouse DEFAULT location id (created by makeWarehouse). */
function defaultLocation(warehouseId: number): number {
  const row = db.prepare(
    `SELECT id FROM locations WHERE warehouse_id = ? AND location_code = 'DEFAULT' LIMIT 1`,
  ).get(warehouseId) as { id: number } | undefined;
  if (!row) throw new Error(`no DEFAULT location for warehouse ${warehouseId}`);
  return row.id;
}

/** Put `qty` of `batchId` into the bin at `locationId`. */
function coverBatch(batchId: number, locationId: number, qty: number): void {
  db.prepare(
    `INSERT INTO batch_stock_by_location (batch_id, location_id, quantity_physical, quantity_reserved, quantity_available)
     VALUES (?, ?, ?, 0, ?)`,
  ).run(batchId, locationId, qty, qty);
}

/** Set the warehouse-level balance the residual branch subtracts from. */
function setBalance(itemId: number, warehouseId: number, quantity: number): void {
  db.prepare(
    `INSERT INTO stock_balances (item_id, warehouse_id, quantity) VALUES (?, ?, ?)
     ON CONFLICT(item_id, warehouse_id) DO UPDATE SET quantity = excluded.quantity`,
  ).run(itemId, warehouseId, quantity);
}

/** Read through the same public path the item list uses. */
function sellable(itemId: number, warehouseId: number): number {
  const rows = StockMovementModel.getSellableAvailability(itemId, warehouseId, db) as Array<{ sellable_qty: number }>;
  return rows.length === 0 ? 0 : Number(rows[0].sellable_qty);
}

describe('BUG-013 item 4: the flag-on sellable query never double counts', () => {
  beforeAll(() => {
    setFeatureEnabled(db, FLAG, true);
  });

  beforeEach(() => {
    setFeatureEnabled(db, FLAG, true);
  });

  it('counts a partly covered batch exactly once', () => {
    const itemId = makeItem('partial');
    const wh = makeWarehouse('DC-PART');
    // One batch of 10: 6 mirrored in the bin, 4 never covered.
    const batchId = makeBatch(itemId, wh, 10);
    coverBatch(batchId, defaultLocation(wh), 6);
    // The warehouse balance matches the batch total, so the residual is zero.
    setBalance(itemId, wh, 10);

    // If the residual deducted only the covered 6, the uncovered 4 would be
    // counted twice: 6 from the bin branch plus 4 residual = 10, versus 14.
    expect(sellable(itemId, wh)).toBeCloseTo(10, 3);
  });

  it('counts a batch whose bin warehouse differs from its own warehouse once', () => {
    const itemId = makeItem('xwh');
    const ownWh = makeWarehouse('DC-OWN');
    const otherWh = makeWarehouse('DC-OTHER');
    // The batch belongs to ownWh but its one bin row points at otherWh.
    const batchId = makeBatch(itemId, ownWh, 7);
    coverBatch(batchId, defaultLocation(otherWh), 7);
    setBalance(itemId, otherWh, 7);
    setBalance(itemId, ownWh, 0);

    // The bin branch reports 7 under otherWh. The uncovered branch must NOT
    // also report the batch under ownWh (it has a bin row), and the residual
    // branch must be zero in both warehouses.
    expect(sellable(itemId, otherWh)).toBeCloseTo(7, 3);
    expect(sellable(itemId, ownWh)).toBeCloseTo(0, 3);
  });

  it('never emits two rows for the same item and warehouse pair', () => {
    const itemId = makeItem('pairs');
    const wh = makeWarehouse('DC-PAIRS');
    // Two batches, same pair: one fully covered, one uncovered.
    const covered = makeBatch(itemId, wh, 5);
    coverBatch(covered, defaultLocation(wh), 5);
    makeBatch(itemId, wh, 3);
    setBalance(itemId, wh, 8);

    const rows = StockMovementModel.getSellableAvailability(null, null, db) as Array<{
      item_id: number; warehouse_id: number; sellable_qty: number;
    }>;
    const forThis = rows.filter((r) => r.item_id === itemId && r.warehouse_id === wh);
    // One row for the pair, not two: the residual branch and the batch branch
    // must never both emit the same (item, warehouse). getSellableAvailability
    // groups by the pair, so a duplicate would already be summed; this asserts
    // the real shape a caller iterates over.
    expect(forThis).toHaveLength(1);
    expect(forThis[0].sellable_qty).toBeCloseTo(8, 3);
    // And the public read agrees.
    expect(sellable(itemId, wh)).toBeCloseTo(8, 3);
  });
});
