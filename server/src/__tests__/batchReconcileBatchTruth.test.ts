import { afterEach, beforeAll, describe, expect, it } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { setFeatureEnabled } from '../utils/featureFlags';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

/**
 * PR #40 follow-up: three confirmed defects in
 * POST /api/inventory/batch-reconciliation/correct.
 *
 * Gull's decision (audit/DECISIONS.md, D-RECON-BATCH-TRUTH): every item is
 * tracked in a batch, so `stock_batches` is the FULL stock count for an
 * item+warehouse and `stock_balances.quantity` must equal the sum of the batch
 * quantities. An unbatched residual is never preserved.
 *
 * Finding 1 — the balance mirror drifts because the route moves it by the
 *   correction delta. A stale mirror keeps its residual and never converges
 *   (balance 50, batch total 10, correct the bin to 6 -> balance stays 46).
 * Finding 2 — a drifted mirror lower than the batch total makes the delta
 *   negative, so `quantity + delta` goes below zero and the DB CHECK
 *   `quantity >= 0` throws HTTP 500 (balance 3, bin to 0).
 * Finding 3 — a physical quantity above `quantity_original` hits the DB CHECK
 *   `quantity_remaining <= quantity_original` and throws HTTP 500 instead of a
 *   clear 4xx rejection.
 * Finding 4 (PR #52 review) — the guard compared ONE bin's requested count
 *   with `quantity_original`, but the batch master is set from the SUM of all
 *   bins. Original 10 with bins 5+5 lets a request of 10 for one bin through,
 *   then the total 15 trips the DB CHECK as an HTTP 500.
 *
 * Mounted route: the request goes through permissions, the Zod body
 * validation, the controller and the SQLite CHECK constraints.
 */

let cookie = '';
let seq = 0;

beforeAll(async () => {
  cookie = await getAuthCookie();
});

afterEach(() => {
  setFeatureEnabled(db, 'feature_batch_locations', false);
});

type Seed = { batchId: number; locationId: number; itemId: number; warehouseId: number };

function seed(
  options: { original?: number; bin?: number; balance?: number | null }
): Seed {
  const original = options.original ?? 10;
  const bin = options.bin ?? original;
  seq += 1;
  const suffix = `${Date.now()}-${seq}`;
  const item = db
    .prepare(`INSERT INTO items (item_code, item_name) VALUES (?, ?)`)
    .run(`BTR-IT-${suffix}`, 'Batch Truth Item');
  const warehouse = db
    .prepare(`INSERT INTO warehouses (warehouse_code, warehouse_name) VALUES (?, ?)`)
    .run(`BTR-WH-${suffix}`, 'Batch Truth WH');
  const batch = db
    .prepare(
      `INSERT INTO stock_batches
         (batch_no, item_id, warehouse_id, source_type, source_id,
          quantity_original, quantity_remaining, unit_cost, received_date)
       VALUES (?, ?, ?, 'PURCHASE', 1, ?, ?, 2, '2026-01-01')`
    )
    .run(`BTR-BATCH-${suffix}`, item.lastInsertRowid, warehouse.lastInsertRowid, original, bin);
  const location = db
    .prepare(
      `INSERT INTO locations (warehouse_id, location_code, location_name)
       VALUES (?, ?, 'Batch Truth Location')`
    )
    .run(warehouse.lastInsertRowid, `BTR-LOC-${suffix}`);
  db.prepare(
    `INSERT INTO batch_stock_by_location
       (batch_id, location_id, quantity_physical, quantity_reserved, quantity_available)
     VALUES (?, ?, ?, 0, ?)`
  ).run(batch.lastInsertRowid, location.lastInsertRowid, bin, bin);
  if (options.balance !== null && options.balance !== undefined) {
    db.prepare(
      `INSERT INTO stock_balances (item_id, warehouse_id, quantity) VALUES (?, ?, ?)`
    ).run(item.lastInsertRowid, warehouse.lastInsertRowid, options.balance);
  }
  return {
    batchId: Number(batch.lastInsertRowid),
    locationId: Number(location.lastInsertRowid),
    itemId: Number(item.lastInsertRowid),
    warehouseId: Number(warehouse.lastInsertRowid),
  };
}

const correct = (body: Record<string, unknown>) =>
  request(app)
    .post('/api/inventory/batch-reconciliation/correct')
    .set('Cookie', cookie)
    .send(body);

function state(seedRow: Seed) {
  const bin = db
    .prepare(
      `SELECT COALESCE(SUM(quantity_physical), 0) AS total
       FROM batch_stock_by_location WHERE batch_id = ?`
    )
    .get(seedRow.batchId) as { total: number };
  const batch = db
    .prepare('SELECT quantity_remaining FROM stock_batches WHERE id = ?')
    .get(seedRow.batchId) as { quantity_remaining: number };
  const balance = db
    .prepare('SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?')
    .get(seedRow.itemId, seedRow.warehouseId) as { quantity: number } | undefined;
  return {
    binTotal: bin.total,
    batchTotal: batch.quantity_remaining,
    balanceQty: balance?.quantity,
  };
}

function countMovements(seedRow: Seed): number {
  return (
    db
      .prepare(
        `SELECT COUNT(*) AS n FROM stock_movements
         WHERE item_id = ? AND warehouse_id = ? AND reference_doctype = 'BATCH_RECONCILIATION'`
      )
      .get(seedRow.itemId, seedRow.warehouseId) as { n: number }
  ).n;
}

/** GL rows are global, so a before/after count is the only safe assertion. */
function glCounts(): { entries: number; lines: number } {
  const entries = (db.prepare('SELECT COUNT(*) AS n FROM journal_entries').get() as { n: number }).n;
  const lines = (db.prepare('SELECT COUNT(*) AS n FROM journal_lines').get() as { n: number }).n;
  return { entries, lines };
}

/**
 * One batch with SEVERAL bin rows, holding the same batch is the point: the
 * per-bin guard sees one bin's value, the batch master sees the sum.
 */
function seedMultiBin(options: {
  original: number;
  binQuantities: number[];
  balance?: number | null;
}): Seed & { locationIds: number[] } {
  const seedRow = seed({
    original: options.original,
    bin: options.binQuantities[0],
    balance: options.balance === undefined ? options.original : options.balance,
  });
  // seed() sets the batch master from the FIRST bin only. Under the batch-truth
  // policy the master is the sum of every bin, so re-stamp it to keep the
  // fixture consistent before the request.
  const total = options.binQuantities.reduce((a, b) => a + b, 0);
  db.prepare('UPDATE stock_batches SET quantity_remaining = ? WHERE id = ?').run(total, seedRow.batchId);
  const locationIds = [seedRow.locationId];
  for (const qty of options.binQuantities.slice(1)) {
    seq += 1;
    const suffix = `${Date.now()}-${seq}`;
    const loc = db
      .prepare(
        `INSERT INTO locations (warehouse_id, location_code, location_name)
         VALUES (?, ?, 'Batch Truth Bin')`
      )
      .run(seedRow.warehouseId, `BTR-LOCM-${suffix}`);
    db.prepare(
      `INSERT INTO batch_stock_by_location
         (batch_id, location_id, quantity_physical, quantity_reserved, quantity_available)
       VALUES (?, ?, ?, 0, ?)`
    ).run(seedRow.batchId, loc.lastInsertRowid, qty, qty);
    locationIds.push(Number(loc.lastInsertRowid));
  }
  return { ...seedRow, locationIds };
}

function binQuantities(batchId: number): number[] {
  return (
    db
      .prepare(
        `SELECT quantity_physical FROM batch_stock_by_location
         WHERE batch_id = ? ORDER BY location_id ASC`
      )
      .all(batchId) as Array<{ quantity_physical: number }>
  ).map(r => r.quantity_physical);
}

describe('Finding 1: a stale balance mirror converges to the batch truth', () => {
  it('balance 50 / batch total 10, reconcile bin to 6 -> both 6 (not 46)', async () => {
    setFeatureEnabled(db, 'feature_batch_locations', false);
    const seedRow = seed({ original: 10, bin: 10, balance: 50 });

    const res = await correct({
      batch_id: seedRow.batchId,
      location_id: seedRow.locationId,
      new_quantity_physical: 6,
    });

    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({
      success: true,
      old_quantity: 10,
      new_quantity: 6,
      diff: -4,
    });
    // THE BITE: on main the balance row still reads 46.
    expect(state(seedRow)).toEqual({ binTotal: 6, batchTotal: 6, balanceQty: 6 });
  });

  it('the movement and its GL entry record the real -4 batch correction, never the -40 stale-mirror repair', async () => {
    setFeatureEnabled(db, 'feature_batch_locations', false);
    // Gull's ruling (audit/DECISIONS.md, 2026-11-22): stock_balances is a
    // DERIVED mirror. The batch sum is the full physical truth, so resetting a
    // stale mirror from 50 to 6 is counter repair, not a stock movement. Only
    // the real batch correction (10 -> 6 = -4) may reach stock_movements and
    // the GL. The -40 mirror-only delta must never be posted.
    const seedRow = seed({ original: 10, bin: 10, balance: 50 });
    const glBefore = glCounts();

    const res = await correct({
      batch_id: seedRow.batchId,
      location_id: seedRow.locationId,
      new_quantity_physical: 6,
    });

    expect(res.status).toBe(200);
    expect(state(seedRow).balanceQty).toBe(6);

    // Exactly one reconciliation movement, and it is -4 (the batch delta).
    const movements = db
      .prepare(
        `SELECT quantity, financial_value, journal_entry_id FROM stock_movements
         WHERE item_id = ? AND warehouse_id = ? AND reference_doctype = 'BATCH_RECONCILIATION'`
      )
      .all(seedRow.itemId, seedRow.warehouseId) as Array<{
      quantity: number;
      financial_value: number | null;
      journal_entry_id: number | null;
    }>;
    expect(movements).toHaveLength(1);
    expect(movements[0].quantity).toBe(-4);

    // The movement carries ONLY the batch delta. If the stale-mirror repair
    // ever leaked into the movement it would read -44 (or -40), not -4.
    //
    // shortcut: this route inserts its stock_movements row directly and never
    // calls the GL posting path, so financial_value stays 0 and
    // journal_entry_id stays NULL. That is pre-existing on origin/main (not
    // introduced here) and posting GL for it is Gull's decision, so the test
    // pins the current fact instead of an assumed value. Upgrade when the
    // route starts posting through StockMovementModel.
    expect(movements[0].financial_value).toBe(0);
    expect(movements[0].journal_entry_id).toBeNull();

    // No journal entry was created for a mirror-only delta.
    expect(glCounts()).toEqual(glBefore);
  });

  it('balance mirror follows the batch truth with the flag ON too', async () => {
    setFeatureEnabled(db, 'feature_batch_locations', true);
    const seedRow = seed({ original: 10, bin: 10, balance: 50 });

    const res = await correct({
      batch_id: seedRow.batchId,
      location_id: seedRow.locationId,
      new_quantity_physical: 6,
    });

    expect(res.status).toBe(200);
    expect(state(seedRow)).toEqual({ binTotal: 6, batchTotal: 6, balanceQty: 6 });
  });
});

describe('Finding 2: a balance mirror lower than the batch total does not 500', () => {
  it('drifted balance 3 / batch total 10, reconcile bin to 0 -> both 0', async () => {
    setFeatureEnabled(db, 'feature_batch_locations', false);
    const seedRow = seed({ original: 10, bin: 10, balance: 3 });

    const res = await correct({
      batch_id: seedRow.batchId,
      location_id: seedRow.locationId,
      new_quantity_physical: 0,
    });

    // THE BITE: on main this is HTTP 500 from CHECK(quantity >= 0).
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ success: true, new_quantity: 0, diff: -10 });
    expect(state(seedRow)).toEqual({ binTotal: 0, batchTotal: 0, balanceQty: 0 });
  });
});

describe('Finding 3: a physical quantity above the batch original is a 4xx', () => {
  it('quantity_original 5, request 50 -> 4xx and no writes at all', async () => {
    setFeatureEnabled(db, 'feature_batch_locations', false);
    const seedRow = seed({ original: 5, bin: 5, balance: 5 });
    const before = state(seedRow);
    const movementsBefore = countMovements(seedRow);

    const res = await correct({
      batch_id: seedRow.batchId,
      location_id: seedRow.locationId,
      new_quantity_physical: 50,
    });

    // THE BITE: on main this is HTTP 500 from CHECK(quantity_remaining <= quantity_original).
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/quantity_original|exceed/i);

    // Rollback assertions: no bin write, no batch write, no balance write,
    // no movement row.
    expect(state(seedRow)).toEqual(before);
    expect(countMovements(seedRow)).toBe(movementsBefore);
  });

  it('a request above the batch original still rejects when the item has several bins', async () => {
    setFeatureEnabled(db, 'feature_batch_locations', false);
    // Two bins of one batch. Original 5, bins 2+3. A request of 6 for one bin
    // is above the batch original and must be a 4xx even though it is an
    // ordinary-looking per-bin value.
    const seedRow = seedMultiBin({ original: 5, binQuantities: [2, 3] });

    const res = await correct({
      batch_id: seedRow.batchId,
      location_id: seedRow.locationIds[0],
      new_quantity_physical: 6,
    });

    expect(res.status).toBe(400);
    expect(state(seedRow)).toEqual({ binTotal: 5, batchTotal: 5, balanceQty: 5 });
  });
});

describe('Finding 4: the guard uses the SUM across all bins, not one bin', () => {
  it('original 10, bins 5+5, request one bin to 10 -> 4xx and zero writes anywhere', async () => {
    setFeatureEnabled(db, 'feature_batch_locations', false);
    const seedRow = seedMultiBin({ original: 10, binQuantities: [5, 5] });
    const before = state(seedRow);
    const binsBefore = binQuantities(seedRow.batchId);
    const movementsBefore = countMovements(seedRow);
    const glBefore = glCounts();

    const res = await correct({
      batch_id: seedRow.batchId,
      location_id: seedRow.locationIds[0],
      new_quantity_physical: 10,
    });

    // THE BITE: the per-bin guard (10 <= 10) passes, the transaction sets the
    // batch master to 5 + 10 = 15, and CHECK(quantity_remaining <=
    // quantity_original) throws HTTP 500. The summed guard rejects with 400.
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/quantity_original|exceed/i);

    // No write to any bin row (not even the requested one).
    expect(binQuantities(seedRow.batchId)).toEqual(binsBefore);
    // No write to the batch master or the balance mirror.
    expect(state(seedRow)).toEqual(before);
    // No stock movement, and no journal entry or line.
    expect(countMovements(seedRow)).toBe(movementsBefore);
    expect(glCounts()).toEqual(glBefore);
  });

  it('original 10, bins 5+5, request one bin to 5 is still allowed (the sum is 10)', async () => {
    setFeatureEnabled(db, 'feature_batch_locations', false);
    // A no-op-shaped request must not be blocked by the summed guard: the
    // resulting sum (5 + 5 = 10) equals the original, so the correction is
    // valid and must keep working.
    const seedRow = seedMultiBin({ original: 10, binQuantities: [5, 5] });

    const res = await correct({
      batch_id: seedRow.batchId,
      location_id: seedRow.locationIds[1],
      new_quantity_physical: 5,
    });

    expect(res.status).toBe(200);
    expect(state(seedRow)).toEqual({ binTotal: 10, batchTotal: 10, balanceQty: 10 });
  });

  it('original 10, bins 5+5, request one bin to 3 -> 200, sum 8 everywhere', async () => {
    setFeatureEnabled(db, 'feature_batch_locations', false);
    // The normal reduction across bins: the guard must not reject a sum that
    // stays inside the original, and the batch truth must follow the sum.
    const seedRow = seedMultiBin({ original: 10, binQuantities: [5, 5] });

    const res = await correct({
      batch_id: seedRow.batchId,
      location_id: seedRow.locationIds[0],
      new_quantity_physical: 3,
    });

    expect(res.status).toBe(200);
    expect(binQuantities(seedRow.batchId)).toEqual([3, 5]);
    expect(state(seedRow)).toEqual({ binTotal: 8, batchTotal: 8, balanceQty: 8 });
  });
});
