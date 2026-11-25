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
  options: { original?: number; bin?: number; balance?: number | null; unitCost?: number }
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
       VALUES (?, ?, ?, 'PURCHASE', 1, ?, ?, ?, '2026-01-01')`
    )
    .run(
      `BTR-BATCH-${suffix}`,
      item.lastInsertRowid,
      warehouse.lastInsertRowid,
      original,
      bin,
      options.unitCost ?? 2
    );
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

// A reason is now REQUIRED (Gull's product rule), so the helper supplies a
// default one; callers override or omit it to test the validation itself.
const REASON = 'Damaged in the warehouse';
const correct = (body: Record<string, unknown>) =>
  request(app)
    .post('/api/inventory/batch-reconciliation/correct')
    .set('Cookie', cookie)
    .send({ reason: REASON, ...body });

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
    // PR #52 follow-up (Gull approved): the real -4 is now accounted through
    // the existing write-off flow - Dr inventory_shrinkage / Cr
    // inventory_asset at batch cost (4 x 2 = 8). The -40 mirror repair is data
    // synchronization and is NOT part of this quantity or amount.
    expect(movements[0].financial_value).toBe(8);
    expect(movements[0].journal_entry_id).not.toBeNull();

    // The only journal entry is for the -4, and there is exactly one.
    const glAfter = glCounts();
    expect(glAfter.entries - glBefore.entries).toBe(1);
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

/**
 * Reason and accounting for the REAL -4 batch change.
 *
 * Gull's clarification: the user states WHY the physical count changed (loss,
 * damage, or another reason). The real -4 adjustment must retain that reason
 * and follow the existing accounting flow. The -40 stale-mirror repair is data
 * synchronization only: no loss, no journal entry.
 *
 * These cases EVIDENCE the route as it actually behaves. They do not invent an
 * account mapping, and they do not add GL to the reconciliation route.
 */
describe('Reason and accounting on the REAL batch delta', () => {
  it('10 -> 6 with a reason: ONE movement of -4 carrying the reason, and one balanced GL entry', async () => {
    setFeatureEnabled(db, 'feature_batch_locations', false);
    const seedRow = seed({ original: 10, bin: 10, balance: 10 });
    const glBefore = glCounts();

    const res = await correct({
      batch_id: seedRow.batchId,
      location_id: seedRow.locationId,
      new_quantity_physical: 6,
      reason: 'Damaged in the warehouse',
    });

    expect(res.status).toBe(200);
    // The route reports what it accounted.
    expect(res.body).toMatchObject({ diff: -4, reason: 'Damaged in the warehouse', gl_amount: 8 });

    const movement = db
      .prepare(
        `SELECT id, quantity, remarks, journal_entry_id, financial_value, financial_posted
         FROM stock_movements
         WHERE item_id = ? AND reference_doctype = 'BATCH_RECONCILIATION'`
      )
      .get(seedRow.itemId) as {
      id: number; quantity: number; remarks: string; journal_entry_id: number | null;
      financial_value: number | null; financial_posted: number;
    };

    // Exactly ONE movement, for the real -4.
    expect(countMovements(seedRow)).toBe(1);
    expect(movement.quantity).toBe(-4);
    // The reason is retained on the movement.
    expect(movement.remarks).toContain('reason=Damaged in the warehouse');
    // The real removal is accounted at batch cost (4 x unit_cost 2).
    expect(movement.financial_value).toBe(8);
    expect(movement.financial_posted).toBe(1);
    expect(movement.journal_entry_id).not.toBeNull();

    // One journal entry, Dr inventory_shrinkage / Cr inventory_asset, 8.00.
    const glAfter = glCounts();
    expect(glAfter.entries - glBefore.entries).toBe(1);
    const entry = db
      .prepare(
        `SELECT amount, debit_account, credit_account, reference_type, description
         FROM journal_entries WHERE id = ?`
      )
      .get(movement.journal_entry_id) as {
      amount: number; debit_account: string; credit_account: string;
      reference_type: string; description: string;
    };
    // 7200's text code. Reuses the write-off mapping; nothing new invented.
    expect(entry.debit_account).toBe('inventory_shrinkage');
    expect(entry.credit_account).toBe('inventory_asset');
    expect(entry.amount).toBe(8);
    expect(entry.reference_type).toBe('BATCH_RECONCILIATION');
    expect(entry.description).toContain('Damaged in the warehouse');

    // The batch truth and mirror still converge.
    expect(state(seedRow)).toEqual({ binTotal: 6, batchTotal: 6, balanceQty: 6 });
  });

  it('mirror 50 / batch 10 -> 6 reseats the mirror to 6 and accounts ONLY the -4', async () => {
    setFeatureEnabled(db, 'feature_batch_locations', false);
    // The -40 mirror repair is data synchronization. It must not appear in the
    // movement quantity, the GL amount, or any second journal entry.
    const seedRow = seed({ original: 10, bin: 10, balance: 50 });
    const glBefore = glCounts();

    const res = await correct({
      batch_id: seedRow.batchId,
      location_id: seedRow.locationId,
      new_quantity_physical: 6,
      reason: 'Damaged in the warehouse',
    });

    expect(res.status).toBe(200);

    // Mirror reseated to the batch truth, not repaired by 40.
    expect(state(seedRow)).toEqual({ binTotal: 6, batchTotal: 6, balanceQty: 6 });

    // ONE movement, quantity -4 (never -44 or -40).
    expect(countMovements(seedRow)).toBe(1);
    const movement = db
      .prepare(
        `SELECT quantity, journal_entry_id, financial_value FROM stock_movements
         WHERE item_id = ? AND reference_doctype = 'BATCH_RECONCILIATION'`
      )
      .get(seedRow.itemId) as { quantity: number; journal_entry_id: number | null; financial_value: number };
    expect(movement.quantity).toBe(-4);
    expect(movement.financial_value).toBe(8);

    // Exactly ONE journal entry, and its amount covers the -4 only.
    const glAfter = glCounts();
    expect(glAfter.entries - glBefore.entries).toBe(1);
    // The single entry covers the -4 only: 4 x unit_cost 2 = 8. The 40-unit
    // stale repair is absent, so the amount is not 88 or 80.
    const entry = db
      .prepare('SELECT amount FROM journal_entries WHERE id = ?')
      .get(movement.journal_entry_id) as { amount: number };
    expect(entry.amount).toBe(8);
  });

  it.each([
    ['missing', undefined],
    ['empty', ''],
    ['blank', '   '],
    ['too long', 'x'.repeat(501)],
  ])('a %s reason returns 4xx with no writes at all', async (_label, reason) => {
    setFeatureEnabled(db, 'feature_batch_locations', false);
    const seedRow = seed({ original: 10, bin: 10, balance: 10 });
    const before = state(seedRow);
    const movementsBefore = countMovements(seedRow);
    const glBefore = glCounts();

    const res = await correct({
      batch_id: seedRow.batchId,
      location_id: seedRow.locationId,
      new_quantity_physical: 6,
      reason: reason as unknown as string,
    });

    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/reason/i);

    // Nothing written: bins, batch, mirror, movements, GL.
    expect(binQuantities(seedRow.batchId)).toEqual([10]);
    expect(state(seedRow)).toEqual(before);
    expect(countMovements(seedRow)).toBe(movementsBefore);
    expect(glCounts()).toEqual(glBefore);
  });

  it('an invalid gl_account returns 4xx with no writes', async () => {
    setFeatureEnabled(db, 'feature_batch_locations', false);
    const seedRow = seed({ original: 10, bin: 10, balance: 10 });
    const before = state(seedRow);
    const glBefore = glCounts();

    const res = await correct({
      batch_id: seedRow.batchId,
      location_id: seedRow.locationId,
      new_quantity_physical: 6,
      gl_account: '9999',
    });

    expect(res.status).toBe(400);
    expect(state(seedRow)).toEqual(before);
    expect(glCounts()).toEqual(glBefore);
  });

  it('the caller can pick a 7200-family loss account, e.g. 7202 damaged goods', async () => {
    setFeatureEnabled(db, 'feature_batch_locations', false);
    const seedRow = seed({ original: 10, bin: 10, balance: 10 });

    const res = await correct({
      batch_id: seedRow.batchId,
      location_id: seedRow.locationId,
      new_quantity_physical: 6,
      reason: 'Damaged in the warehouse',
      gl_account: '7202',
    });

    expect(res.status).toBe(200);
    const movement = db
      .prepare(`SELECT journal_entry_id FROM stock_movements
                WHERE item_id = ? AND reference_doctype = 'BATCH_RECONCILIATION'`)
      .get(seedRow.itemId) as { journal_entry_id: number };
    const entry = db
      .prepare('SELECT debit_account, amount FROM journal_entries WHERE id = ?')
      .get(movement.journal_entry_id) as { debit_account: string; amount: number };
    // 7202 carries the text code 'damaged_goods_loss' (existing chart).
    expect(entry.debit_account).toBe('damaged_goods_loss');
    expect(entry.amount).toBe(8);
  });

  it('an INCREASE posts Dr inventory_asset / Cr inventory_correction for the found value', async () => {
    setFeatureEnabled(db, 'feature_batch_locations', false);
    // Bin 4, original 10: the count goes UP to 10. That is an overage, so the
    // higher inventory asset needs a balancing entry (as the ADJUSTMENT posting
    // in StockMovementModel does).
    const seedRow = seed({ original: 10, bin: 4, balance: 4, unitCost: 2 });
    const glBefore = glCounts();

    const res = await correct({
      batch_id: seedRow.batchId,
      location_id: seedRow.locationId,
      new_quantity_physical: 10,
      reason: 'Found during recount',
    });

    expect(res.status).toBe(200);
    const movement = db
      .prepare(`SELECT quantity, financial_value, journal_entry_id FROM stock_movements
                WHERE item_id = ? AND reference_doctype = 'BATCH_RECONCILIATION'`)
      .get(seedRow.itemId) as { quantity: number; financial_value: number; journal_entry_id: number | null };
    expect(movement.quantity).toBe(6);
    // 6 units @ 2 = 12 of found value.
    expect(movement.financial_value).toBe(12);
    expect(movement.journal_entry_id).not.toBeNull();

    const entry = db
      .prepare('SELECT debit_account, credit_account, amount FROM journal_entries WHERE id = ?')
      .get(movement.journal_entry_id) as { debit_account: string; credit_account: string; amount: number };
    expect(entry.debit_account).toBe('inventory_asset');
    expect(entry.credit_account).toBe('inventory_correction');
    expect(entry.amount).toBe(12);

    // Exactly one balanced entry: two lines, one debit and one credit.
    const glAfter = glCounts();
    expect(glAfter.entries).toBe(glBefore.entries + 1);
    expect(glAfter.lines).toBe(glBefore.lines + 2);
  });

  it('a zero-unit-cost batch removes stock with no journal entry (nothing to value)', async () => {
    setFeatureEnabled(db, 'feature_batch_locations', false);
    const seedRow = seed({ original: 10, bin: 10, balance: 10, unitCost: 0 });
    const glBefore = glCounts();

    const res = await correct({
      batch_id: seedRow.batchId,
      location_id: seedRow.locationId,
      new_quantity_physical: 6,
    });

    expect(res.status).toBe(200);
    const movement = db
      .prepare(`SELECT quantity, financial_value, journal_entry_id FROM stock_movements
                WHERE item_id = ? AND reference_doctype = 'BATCH_RECONCILIATION'`)
      .get(seedRow.itemId) as { quantity: number; financial_value: number; journal_entry_id: number | null };
    expect(movement.quantity).toBe(-4);
    expect(movement.financial_value).toBe(0);
    // postLegacyStockEntry rejects a zero amount, so nothing is posted.
    expect(movement.journal_entry_id).toBeNull();
    expect(glCounts()).toEqual(glBefore);
  });
});

describe('Decimal boundary: guard agrees with the persisted CHECK', () => {
  // Values ABOVE 5 that the old +0.0005 slack let through to the CHECK.
  const justOver = [5.0001, 5.0002, 5.0003, 5.0004, 5.0005];

  it.each(justOver)(
    'original 5, request %s -> clear 4xx, never a database 500, and zero writes',
    async (requested) => {
      setFeatureEnabled(db, 'feature_batch_locations', false);
      const seedRow = seed({ original: 5, bin: 5, balance: 5 });
      const before = state(seedRow);
      const movementsBefore = countMovements(seedRow);
      const glBefore = glCounts();

      const res = await correct({
        batch_id: seedRow.batchId,
        location_id: seedRow.locationId,
        new_quantity_physical: requested,
      });

      // 4xx, not the CHECK's 500.
      expect(res.status).toBe(400);
      expect(res.body.error).toMatch(/quantity_original|exceed/i);
      // The message must not be a raw SQLite error.
      expect(res.body.error).not.toMatch(/CHECK constraint/i);

      // Nothing written anywhere.
      expect(binQuantities(seedRow.batchId)).toEqual([5]);
      expect(state(seedRow)).toEqual(before);
      expect(state(seedRow)).toEqual({ binTotal: 5, batchTotal: 5, balanceQty: 5 });
      expect(countMovements(seedRow)).toBe(movementsBefore);
      expect(glCounts()).toEqual(glBefore);
    }
  );

  it('a request that equals the original exactly still succeeds (5 of 5)', async () => {
    setFeatureEnabled(db, 'feature_batch_locations', false);
    const seedRow = seed({ original: 5, bin: 5, balance: 5 });

    const res = await correct({
      batch_id: seedRow.batchId,
      location_id: seedRow.locationId,
      new_quantity_physical: 5,
    });

    expect(res.status).toBe(200);
    expect(state(seedRow)).toEqual({ binTotal: 5, batchTotal: 5, balanceQty: 5 });
  });

  it('3-decimal rounding residue below the original is still accepted (5.000 -> 5)', async () => {
    setFeatureEnabled(db, 'feature_batch_locations', false);
    // 5.0000 arrives as 5. A value within the persisted precision must not be
    // rejected, or the fix would break legitimate 3-decimal counts.
    const seedRow = seed({ original: 5, bin: 5, balance: 5 });

    const res = await correct({
      batch_id: seedRow.batchId,
      location_id: seedRow.locationId,
      new_quantity_physical: 5.0,
    });

    expect(res.status).toBe(200);
    expect(state(seedRow)).toEqual({ binTotal: 5, batchTotal: 5, balanceQty: 5 });
  });
});
