/**
 * BUG-013 guard: the "uncovered batch" merge must be scoped to the warehouse
 * being sold from, and must be exact.
 *
 * WHY THIS EXISTS. The flag-on sellable query reads `batch_stock_by_location`
 * with an INNER JOIN, so a batch with no location row is invisible. The fix
 * merges such batches back in at their master quantity. A merge that ignored
 * the warehouse would let a sale in warehouse A consume stock that physically
 * sits in warehouse B — a phantom cross-warehouse transfer. This spec splits one
 * item across two warehouses, covers only one of them with a location row, and
 * asserts each warehouse still reports exactly its own stock.
 *
 * It also pins the "log every time it fires" behaviour: the merge is a signal
 * that the location table is behind, so silence would hide the drift.
 */
import { beforeAll, describe, expect, it, jest } from '@jest/globals';
import db from '../config/database';
import { setFeatureEnabled } from '../utils/featureFlags';

const FLAG = 'feature_batch_locations';
const AS_OF = '2099-01-01';

// The merge warns through ../utils/logger. Capture those calls at the registry
// the model resolves, exactly as the database-boundary spec does.
const warnings: string[] = [];
jest.mock('../utils/logger', () => {
  const real = jest.requireActual('../utils/logger') as { default: Record<string, unknown> };
  const logger = Object.create(real.default) as Record<string, unknown>;
  const base = logger.warn as (...a: unknown[]) => void;
  logger.warn = (...args: unknown[]) => {
    warnings.push(args.map(String).join(' '));
    base?.(...args);
  };
  return { default: logger, __esModule: true };
});

/* eslint-disable-next-line @typescript-eslint/no-require-imports */
const StockMovementModel = (require('../models/StockMovement') as { default: typeof import('../models/StockMovement').default }).default;

function makeItem(): number {
  const code = `SCOPE-${Date.now()}-${Math.floor(process.hrtime()[1])}`;
  return Number(
    db.prepare(
      `INSERT INTO items (item_code, item_name, unit_of_measure, standard_cost, is_active)
       VALUES (?, ?, 'PCS', 10, 1)`,
    ).run(code, `Scope Item ${code}`).lastInsertRowid,
  );
}
function makeWarehouse(code: string): number {
  const id = Number(
    db.prepare(`INSERT INTO warehouses (warehouse_code, warehouse_name, is_active) VALUES (?, ?, 1)`)
      .run(code, `Scope ${code}`).lastInsertRowid,
  );
  // Every warehouse needs a DEFAULT location row, as Warehouse.create guarantees.
  db.prepare(`INSERT INTO locations (warehouse_id, location_code, location_name) VALUES (?, 'DEFAULT', 'Default')`)
    .run(id);
  return id;
}

/** Stock a warehouse the way the API does; optionally mirror it to the location table. */
function addBatch(itemId: number, warehouseId: number, qty: number, withLocation: boolean): number {
  const batchNo = `SCOPE-B-${Date.now()}-${Math.floor(process.hrtime()[1])}`;
  const batchId = Number(
    db.prepare(
      `INSERT INTO stock_batches (batch_no, item_id, warehouse_id, source_type, source_id,
                                  quantity_original, quantity_remaining, unit_cost, received_date)
       VALUES (?, ?, ?, 'OPENING', 0, ?, ?, 10, '2026-01-01')`,
    ).run(batchNo, itemId, warehouseId, qty, qty).lastInsertRowid,
  );
  db.prepare(
    `INSERT INTO stock_balances (item_id, warehouse_id, quantity) VALUES (?, ?, ?)
     ON CONFLICT(item_id, warehouse_id) DO UPDATE SET quantity = quantity + excluded.quantity`,
  ).run(itemId, warehouseId, qty);
  if (withLocation) {
    const loc = db.prepare(`SELECT id FROM locations WHERE warehouse_id = ? ORDER BY id LIMIT 1`)
      .get(warehouseId) as { id: number };
    db.prepare(
      `INSERT INTO batch_stock_by_location (batch_id, location_id, quantity_physical, quantity_reserved, quantity_available)
       VALUES (?, ?, ?, 0, ?)`,
    ).run(batchId, loc.id, qty, qty);
  }
  return batchId;
}

function sellable(itemId: number, warehouseId: number): number {
  const rows = StockMovementModel.getSellableAvailability(itemId, warehouseId, db);
  return rows.length === 0 ? 0 : Number(rows[0].sellable_qty);
}

describe('BUG-013: the uncovered-batch merge is warehouse-scoped and exact', () => {
  let itemId: number;
  let whCovered: number;
  let whUncovered: number;

  beforeAll(() => {
    setFeatureEnabled(db, FLAG, true);
    itemId = makeItem();
    whCovered = makeWarehouse(`SCOPE-A-${Date.now() % 100000}`);
    whUncovered = makeWarehouse(`SCOPE-B-${Date.now() % 100000}`);
    // One batch per warehouse. Only the first gets a location row, so the
    // "partial coverage" state that broke the sale is reproduced exactly.
    addBatch(itemId, whCovered, 5, true);
    addBatch(itemId, whUncovered, 7, false);
  });

  it('reports the covered warehouse stock exactly', () => {
    expect(sellable(itemId, whCovered)).toBeCloseTo(5, 3);
  });

  it('reports the uncovered warehouse stock exactly', () => {
    expect(sellable(itemId, whUncovered)).toBeCloseTo(7, 3);
  });

  it('never lets one warehouse see the other warehouse stock', () => {
    expect(sellable(itemId, whCovered)).toBeCloseTo(5, 3);
    expect(sellable(itemId, whUncovered)).toBeCloseTo(7, 3);
  });

  it('consumes exactly from the selling warehouse and leaves the other untouched', () => {
    warnings.length = 0;
    const consumed = StockMovementModel.consumeFromOldestBatches(itemId, whUncovered, 3, db, AS_OF);
    expect(consumed.reduce((s: number, c: { consumed: number }) => s + c.consumed, 0)).toBeCloseTo(3, 3);
    // consumeFromOldestBatches moves the batch layer only; the sale path moves
    // stock_balances alongside it. Mirror that here so the derived read is the
    // real post-sale shape.
    db.prepare('UPDATE stock_balances SET quantity = quantity - 3 WHERE item_id = ? AND warehouse_id = ?')
      .run(itemId, whUncovered);
    expect(sellable(itemId, whUncovered)).toBeCloseTo(4, 3);
    expect(sellable(itemId, whCovered)).toBeCloseTo(5, 3);
  });

  it('logs a warning when it merges uncovered batches', () => {
    warnings.length = 0;
    StockMovementModel.consumeFromOldestBatches(itemId, whUncovered, 1, db, AS_OF);
    expect(warnings.join('\n')).toContain('BUG-013 guard');
  });
});
