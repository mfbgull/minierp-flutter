import { afterEach, beforeAll, describe, expect, it } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { setFeatureEnabled } from '../utils/featureFlags';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

/**
 * S-4 (GitHub issue #15): `correctBatchReconciliation` reconciles the bin
 * (`batch_stock_by_location`) and the batch master (`stock_batches`) but never
 * writes `stock_balances`, so `stock_balances.quantity` keeps the pre-correction
 * on-hand and Invariant E fails. The fix must keep all three in step in ONE
 * transaction, in BOTH flag states.
 *
 * Mounted-route integration test: POST /api/inventory/batch-reconciliation/correct
 */

let cookie = '';
let seq = 0;

beforeAll(async () => {
  cookie = await getAuthCookie();
});

afterEach(() => {
  setFeatureEnabled(db, 'feature_batch_locations', false);
});

function seedBatch(quantity = 10): { batchId: number; locationId: number; itemId: number; warehouseId: number } {
  return seedBatchWithBin(quantity, quantity);
}

function seedBatchWithBin(
  originalQuantity: number,
  binQuantity: number,
  seedBalance = true
): { batchId: number; locationId: number; itemId: number; warehouseId: number } {
  seq += 1;
  const suffix = `${Date.now()}-${seq}`;
  const item = db
    .prepare(`INSERT INTO items (item_code, item_name) VALUES (?, ?)`)
    .run(`PAR-IT-${suffix}`, 'Parity Item');
  const warehouse = db
    .prepare(`INSERT INTO warehouses (warehouse_code, warehouse_name) VALUES (?, ?)`)
    .run(`PAR-WH-${suffix}`, 'Parity WH');
  const batch = db
    .prepare(
      `INSERT INTO stock_batches
         (batch_no, item_id, warehouse_id, source_type, source_id,
          quantity_original, quantity_remaining, unit_cost, received_date)
       VALUES (?, ?, ?, 'PURCHASE', 1, ?, ?, 2, '2026-01-01')`
    )
    .run(`PAR-BATCH-${suffix}`, item.lastInsertRowid, warehouse.lastInsertRowid, originalQuantity, binQuantity);
  const location = db
    .prepare(
      `INSERT INTO locations (warehouse_id, location_code, location_name)
       VALUES (?, ?, 'Parity Location')`
    )
    .run(warehouse.lastInsertRowid, `PAR-LOC-${suffix}`);
  db.prepare(
    `INSERT INTO batch_stock_by_location
       (batch_id, location_id, quantity_physical, quantity_reserved, quantity_available)
     VALUES (?, ?, ?, 0, ?)`
  ).run(batch.lastInsertRowid, location.lastInsertRowid, binQuantity, binQuantity);
  // The on-hand mirror that the defect forgets to update.
  if (seedBalance) {
    db.prepare(
      `INSERT INTO stock_balances (item_id, warehouse_id, quantity) VALUES (?, ?, ?)`
    ).run(item.lastInsertRowid, warehouse.lastInsertRowid, binQuantity);
  }
  return {
    batchId: Number(batch.lastInsertRowid),
    locationId: Number(location.lastInsertRowid),
    itemId: Number(item.lastInsertRowid),
    warehouseId: Number(warehouse.lastInsertRowid),
  };
}

// A second batch on an EXISTING item+warehouse (its own location), with no
// stock_balances row of its own.
function seedBatchForItem(
  seed: { itemId: number; warehouseId: number },
  binQuantity: number
): { batchId: number; locationId: number } {
  seq += 1;
  const suffix = `${Date.now()}-${seq}`;
  const batch = db
    .prepare(
      `INSERT INTO stock_batches
         (batch_no, item_id, warehouse_id, source_type, source_id,
          quantity_original, quantity_remaining, unit_cost, received_date)
       VALUES (?, ?, ?, 'PURCHASE', 1, ?, ?, 2, '2026-01-01')`
    )
    .run(`PAR-BATCH2-${suffix}`, seed.itemId, seed.warehouseId, binQuantity, binQuantity);
  const location = db
    .prepare(
      `INSERT INTO locations (warehouse_id, location_code, location_name)
       VALUES (?, ?, 'Parity Location 2')`
    )
    .run(seed.warehouseId, `PAR-LOC2-${suffix}`);
  db.prepare(
    `INSERT INTO batch_stock_by_location
       (batch_id, location_id, quantity_physical, quantity_reserved, quantity_available)
     VALUES (?, ?, ?, 0, ?)`
  ).run(batch.lastInsertRowid, location.lastInsertRowid, binQuantity, binQuantity);
  return {
    batchId: Number(batch.lastInsertRowid),
    locationId: Number(location.lastInsertRowid),
  };
}

const correct = (body: Record<string, unknown>) =>  request(app)
    .post('/api/inventory/batch-reconciliation/correct')
    .set('Cookie', cookie)
    .send(body);

// A location in a given warehouse (no bin row), for cross-location and
// cross-warehouse probes.
function seedLocation(warehouseId: number, kind = 'Parity Location X'): number {
  seq += 1;
  const suffix = `${Date.now()}-${seq}`;
  const loc = db
    .prepare(
      `INSERT INTO locations (warehouse_id, location_code, location_name)
       VALUES (?, ?, ?)`
    )
    .run(warehouseId, `PAR-LOCX-${suffix}`, kind);
  return Number(loc.lastInsertRowid);
}

function seedWarehouse(): number {
  seq += 1;
  const suffix = `${Date.now()}-${seq}`;
  const wh = db
    .prepare(`INSERT INTO warehouses (warehouse_code, warehouse_name) VALUES (?, ?)`)
    .run(`PAR-WHX-${suffix}`, 'Parity WH X');
  return Number(wh.lastInsertRowid);
}

describe('S-4 correctBatchReconciliation keeps stock_balances in step', () => {
  it('flag OFF: reconcile 10 -> 6 updates bin, batch master AND stock_balances.quantity', async () => {
    setFeatureEnabled(db, 'feature_batch_locations', false);
    const seed = seedBatch(10);

    const res = await correct({
      batch_id: seed.batchId,
      location_id: seed.locationId,
      new_quantity_physical: 6,
    });

    expect(res.status).toBe(200);
    expect(res.body.diff).toBe(-4);

    const bin = db
      .prepare(
        `SELECT quantity_physical, quantity_available FROM batch_stock_by_location
         WHERE batch_id = ? AND location_id = ?`
      )
      .get(seed.batchId, seed.locationId) as { quantity_physical: number; quantity_available: number };
    expect(bin).toEqual({ quantity_physical: 6, quantity_available: 6 });

    const batch = db
      .prepare('SELECT quantity_remaining FROM stock_batches WHERE id = ?')
      .get(seed.batchId) as { quantity_remaining: number };
    expect(batch.quantity_remaining).toBe(6);

    // THE BITE: on main this is still 10 (defect).
    const balance = db
      .prepare('SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?')
      .get(seed.itemId, seed.warehouseId) as { quantity: number };
    expect(balance.quantity).toBe(6);
  });

  it('flag ON: reconcile updates bin, batch master, stock_balances.quantity AND extension columns', async () => {
    setFeatureEnabled(db, 'feature_batch_locations', true);
    const seed = seedBatch(10);

    const res = await correct({
      batch_id: seed.batchId,
      location_id: seed.locationId,
      new_quantity_physical: 6,
    });

    expect(res.status).toBe(200);

    const balance = db
      .prepare(
        `SELECT quantity, quantity_physical, quantity_reserved, quantity_available
         FROM stock_balances WHERE item_id = ? AND warehouse_id = ?`
      )
      .get(seed.itemId, seed.warehouseId) as {
      quantity: number;
      quantity_physical: number;
      quantity_reserved: number;
      quantity_available: number;
    };
    expect(balance.quantity).toBe(6);
    expect(balance.quantity_physical).toBe(6);
    expect(balance.quantity_reserved).toBe(0);
    expect(balance.quantity_available).toBe(6);
  });

  it('Invariant E: stock_balances.quantity equals on-hand after a correction that increases the bin', async () => {
    setFeatureEnabled(db, 'feature_batch_locations', false);
    // original capacity 10 so a bin increase to 9 stays inside the
    // stock_batches CHECK (quantity_remaining <= quantity_original); the bin
    // currently holds 4, so the correction raises it by 5.
    const seed = seedBatchWithBin(10, 4);

    const res = await correct({
      batch_id: seed.batchId,
      location_id: seed.locationId,
      new_quantity_physical: 9,
    });
    expect(res.status).toBe(200);

    const balance = db
      .prepare('SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?')
      .get(seed.itemId, seed.warehouseId) as { quantity: number };
    const binTotal = db
      .prepare('SELECT COALESCE(SUM(quantity_physical), 0) AS total FROM batch_stock_by_location WHERE batch_id = ?')
      .get(seed.batchId) as { total: number };

    expect(balance.quantity).toBe(9);
    expect(balance.quantity).toBe(binTotal.total);
  });

  it('seeds a missing stock_balances row from the batch truth, never a negative quantity', async () => {
    setFeatureEnabled(db, 'feature_batch_locations', false);
    // No stock_balances row at all: a reduction must not insert a negative
    // quantity (CHECK quantity >= 0 would reject it).
    const seed = seedBatchWithBin(10, 10, false);

    const res = await correct({
      batch_id: seed.batchId,
      location_id: seed.locationId,
      new_quantity_physical: 7,
    });
    expect(res.status).toBe(200);

    const balance = db
      .prepare('SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?')
      .get(seed.itemId, seed.warehouseId) as { quantity: number };
    expect(balance.quantity).toBe(7);
  });

  it('seeds a missing stock_balances row from ALL batches of the item+warehouse, not just the corrected one', async () => {
    setFeatureEnabled(db, 'feature_batch_locations', false);
    // Two batches on the SAME item+warehouse, no stock_balances row yet.
    const first = seedBatchWithBin(10, 10, false);
    const second = seedBatchForItem(first, 5);

    // Correct only the FIRST batch 10 -> 7.
    const res = await correct({
      batch_id: first.batchId,
      location_id: first.locationId,
      new_quantity_physical: 7,
    });
    expect(res.status).toBe(200);

    const balance = db
      .prepare('SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?')
      .get(first.itemId, first.warehouseId) as { quantity: number };
    // 7 (corrected first batch) + 5 (untouched second batch) = 12.
    expect(balance.quantity).toBe(12);
    expect(second.batchId).toBeGreaterThan(0);
  });

  it('BLOCKER A: rejects a target bin row that does not exist (no phantom stock_balances)', async () => {
    setFeatureEnabled(db, 'feature_batch_locations', false);
    // Batch holds 10 in its own location; request targets another location in
    // the SAME warehouse that has NO batch_stock_by_location row.
    const seed = seedBatch(10);
    const otherLocation = seedLocation(seed.warehouseId);

    const before = db
      .prepare('SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?')
      .get(seed.itemId, seed.warehouseId) as { quantity: number };

    const res = await correct({
      batch_id: seed.batchId,
      location_id: otherLocation,
      new_quantity_physical: 6,
    });

    // Must NOT invent stock: either reject or leave everything unchanged.
    expect([400, 404]).toContain(res.status);

    const after = db
      .prepare('SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?')
      .get(seed.itemId, seed.warehouseId) as { quantity: number };
    expect(after.quantity).toBe(before.quantity);

    const bin = db
      .prepare('SELECT quantity_physical FROM batch_stock_by_location WHERE batch_id = ? AND location_id = ?')
      .get(seed.batchId, seed.locationId) as { quantity_physical: number };
    expect(bin.quantity_physical).toBe(10);
  });

  it('BLOCKER B: rejects a location that belongs to a different warehouse', async () => {
    setFeatureEnabled(db, 'feature_batch_locations', false);
    const seed = seedBatch(10);
    const otherWarehouse = seedWarehouse();
    const foreignLocation = seedLocation(otherWarehouse, 'Foreign Location');

    const res = await correct({
      batch_id: seed.batchId,
      location_id: foreignLocation,
      new_quantity_physical: 6,
    });

    expect([400, 404]).toContain(res.status);

    // No phantom balance in the foreign warehouse either.
    const foreignBalance = db
      .prepare('SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?')
      .get(seed.itemId, otherWarehouse) as { quantity: number } | undefined;
    expect(foreignBalance?.quantity ?? 0).toBe(0);
  });
});
