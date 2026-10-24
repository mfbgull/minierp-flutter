import { afterEach, beforeAll, describe, expect, it, jest } from '@jest/globals';
import type { Request, Response } from 'express';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { correctBatchReconciliation } from '../controllers/inventoryController';
import logger from '../utils/logger';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

/**
 * Fallow health remediation — `resolveOpeningWarehouse` (CRAP 67.9) and
 * `correctBatchReconciliation` (CRAP 132).
 */

let cookie = '';
let seq = 0;

beforeAll(async () => {
  cookie = await getAuthCookie();
});

afterEach(() => {
  jest.restoreAllMocks();
});

const createItem = (body: Record<string, unknown>) => {
  seq += 1;
  return request(app)
    .post('/api/inventory/items')
    .set('Cookie', cookie)
    .send({ item_code: `OPEN-${Date.now()}-${seq}`, item_name: `Opening ${seq}`, ...body });
};

describe('item opening stock warehouse resolution', () => {
  it('uses the default warehouse when none is supplied', async () => {
    const res = await createItem({ current_stock: 5, standard_cost: 3 });

    expect(res.status).toBe(201);
    const movement = db
      .prepare(
        `SELECT warehouse_id, quantity FROM stock_movements
         WHERE item_id = ? AND movement_type = 'OPENING'`
      )
      .get(res.body.id) as { warehouse_id: number; quantity: number };
    expect(movement).toMatchObject({ quantity: 5 });
  });

  it('accepts a valid active warehouse', async () => {
    const warehouse = db
      .prepare(
        `INSERT INTO warehouses (warehouse_code, warehouse_name, is_active)
         VALUES ('OPEN-WH', 'Opening WH', 1)`
      )
      .run();

    const res = await createItem({
      current_stock: 2,
      standard_cost: 4,
      warehouse_id: Number(warehouse.lastInsertRowid),
    });

    expect(res.status).toBe(201);
    const movement = db
      .prepare(`SELECT warehouse_id FROM stock_movements WHERE item_id = ?`)
      .get(res.body.id) as { warehouse_id: number };
    expect(movement.warehouse_id).toBe(Number(warehouse.lastInsertRowid));
  });

  it('rejects a warehouse field of the wrong type', async () => {
    const res = await createItem({
      current_stock: 1,
      standard_cost: 2,
      warehouse_id: { nested: true },
    });
    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: 'warehouse_id must be a positive integer' });
  });

  it('rejects unknown and inactive warehouses', async () => {
    const unknown = await createItem({ current_stock: 1, standard_cost: 2, warehouse_id: 999999 });
    expect(unknown.status).toBe(400);
    expect(unknown.body).toEqual({
      error: 'warehouse_id must reference an active warehouse',
    });

    const inactive = db
      .prepare(
        `INSERT INTO warehouses (warehouse_code, warehouse_name, is_active)
         VALUES ('OPEN-WH-OFF', 'Closed WH', 0)`
      )
      .run();
    const inactiveRes = await createItem({
      current_stock: 1,
      standard_cost: 2,
      warehouse_id: Number(inactive.lastInsertRowid),
    });
    expect(inactiveRes.status).toBe(400);
    expect(inactiveRes.body).toEqual({
      error: 'warehouse_id must reference an active warehouse',
    });
  });

  it('requires cost for opening stock and no warehouse for zero stock', async () => {
    const noCost = await createItem({ current_stock: 3 });
    expect(noCost.status).toBe(400);
    expect(noCost.body).toEqual({
      error: 'standard_cost must be greater than 0 when current_stock is greater than 0',
    });

    const zero = await createItem({ current_stock: 0 });
    expect(zero.status).toBe(201);
  });
});

describe('correctBatchReconciliation', () => {
  let seedSeq = 0;

  function seedBatch(): { batchId: number; locationId: number } {
    seedSeq += 1;
    const suffix = `${Date.now()}-${seedSeq}`;
    const item = db
      .prepare(`INSERT INTO items (item_code, item_name) VALUES (?, ?)`)
      .run(`REC-IT-${suffix}`, 'Reconcile Item');
    const warehouse = db
      .prepare(`INSERT INTO warehouses (warehouse_code, warehouse_name) VALUES (?, ?)`)
      .run(`REC-WH-${suffix}`, 'Reconcile WH');
    const batch = db
      .prepare(
        `INSERT INTO stock_batches
           (batch_no, item_id, warehouse_id, source_type, source_id,
            quantity_original, quantity_remaining, unit_cost, received_date)
         VALUES (?, ?, ?, 'PURCHASE', 1, 10, 10, 2, '2026-01-01')`
      )
      .run(`REC-BATCH-${suffix}`, item.lastInsertRowid, warehouse.lastInsertRowid);
    const location = db
      .prepare(
        `INSERT INTO locations (warehouse_id, location_code, location_name)
         VALUES (?, ?, 'Reconcile Location')`
      )
      .run(warehouse.lastInsertRowid, `REC-LOC-${suffix}`);
    db.prepare(
      `INSERT INTO batch_stock_by_location
         (batch_id, location_id, quantity_physical, quantity_reserved, quantity_available)
       VALUES (?, ?, 10, 0, 10)`
    ).run(batch.lastInsertRowid, location.lastInsertRowid);
    return {
      batchId: Number(batch.lastInsertRowid),
      locationId: Number(location.lastInsertRowid),
    };
  }

  const correct = (body: Record<string, unknown>) =>
    request(app)
      .post('/api/inventory/batch-reconciliation/correct')
      .set('Cookie', cookie)
      .send(body);

  it('validates required fields, location, batch and quantity', async () => {
    const seed = seedBatch();

    expect((await correct({})).status).toBe(400);

    const noLocation = await correct({
      batch_id: seed.batchId,
      location_id: 999999,
      new_quantity_physical: 5,
    });
    expect(noLocation.status).toBe(404);
    expect(noLocation.body).toEqual({ error: 'Location not found' });

    const noBatch = await correct({
      batch_id: 999999,
      location_id: seed.locationId,
      new_quantity_physical: 5,
    });
    expect(noBatch.status).toBe(404);
    expect(noBatch.body).toEqual({ error: 'Batch not found' });

    const negative = await correct({
      batch_id: seed.batchId,
      location_id: seed.locationId,
      new_quantity_physical: -1,
    });
    expect(negative.status).toBe(400);
    expect(negative.body).toEqual({
      error: 'new_quantity_physical must be a non-negative number',
    });
  });

  it('corrects the location row, master quantity and writes a movement', async () => {
    const seed = seedBatch();

    const res = await correct({
      batch_id: seed.batchId,
      location_id: seed.locationId,
      new_quantity_physical: 7,
    });

    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      success: true,
      batch_id: seed.batchId,
      location_id: seed.locationId,
      old_quantity: 10,
      new_quantity: 7,
      diff: -3,
    });

    const locationRow = db
      .prepare(
        `SELECT quantity_physical, quantity_available FROM batch_stock_by_location
         WHERE batch_id = ? AND location_id = ?`
      )
      .get(seed.batchId, seed.locationId) as {
      quantity_physical: number;
      quantity_available: number;
    };
    expect(locationRow).toEqual({ quantity_physical: 7, quantity_available: 7 });

    const batch = db
      .prepare('SELECT quantity_remaining FROM stock_batches WHERE id = ?')
      .get(seed.batchId) as { quantity_remaining: number };
    expect(batch.quantity_remaining).toBe(7);

    const movement = db
      .prepare(
        `SELECT quantity, reference_docno FROM stock_movements
         WHERE reference_doctype = 'BATCH_RECONCILIATION' AND batch_id = ?`
      )
      .get(seed.batchId) as { quantity: number; reference_docno: string };
    expect(movement).toEqual({ quantity: -3, reference_docno: `RECON-${seed.batchId}` });
  });

  it('returns a sanitized 500 when the correction fails', () => {
    jest.spyOn(logger, 'error').mockImplementation(() => logger);
    jest.spyOn(db, 'prepare').mockImplementation(() => {
      throw new Error('forced reconciliation failure');
    });
    const status = jest.fn();
    const json = jest.fn();
    const res = { status, json } as unknown as Response;
    status.mockReturnValue(res);

    correctBatchReconciliation(
      { user: { id: 1 }, body: { batch_id: 1, location_id: 1, new_quantity_physical: 5 } } as unknown as Request,
      res
    );
    expect(status).toHaveBeenCalledWith(500);
  });
});
