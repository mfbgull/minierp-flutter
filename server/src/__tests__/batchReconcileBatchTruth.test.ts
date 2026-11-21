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

  it('a multi-batch item still rejects when the TOTAL batch quantity would exceed the original', async () => {
    setFeatureEnabled(db, 'feature_batch_locations', false);
    // One batch, one bin. The batch original is 5; a reconciliation to 6 is
    // inside the bin capacity but above the batch original, so it must be a
    // 4xx — never a 500 and never a silent trim.
    const seedRow = seed({ original: 5, bin: 5, balance: 5 });

    const res = await correct({
      batch_id: seedRow.batchId,
      location_id: seedRow.locationId,
      new_quantity_physical: 6,
    });

    expect(res.status).toBe(400);
    expect(state(seedRow)).toEqual({ binTotal: 5, batchTotal: 5, balanceQty: 5 });
  });
});
