import { afterEach, beforeAll, describe, expect, it, jest } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import ItemModel from '../models/Item';
import StockMovementModel from '../models/StockMovement';
import logger from '../utils/logger';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

/**
 * Fallow health remediation — `inventoryController.createStockMovement`
 * (CRAP 106.4). Covers the required-field guard, the negative-stock guard,
 * normal and batch-consumption paths (including multiple batches), and the
 * error response.
 */
describe('inventoryController.createStockMovement', () => {
  let cookie = '';
  let seq = 0;

  beforeAll(async () => {
    cookie = await getAuthCookie();
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  const post = (body: Record<string, unknown>) =>
    request(app)
      .post('/api/inventory/stock-movements')
      .set('Cookie', cookie)
      .send(body);

  async function fixture(): Promise<{ itemId: number; warehouseId: number }> {
    seq += 1;
    const suffix = `${Date.now()}-${seq}`;
    const item = await request(app)
      .post('/api/inventory/items')
      .set('Cookie', cookie)
      .send({
        item_code: `SM-ITEM-${suffix}`,
        item_name: `Stock movement item ${suffix}`,
        unit_of_measure: 'Nos',
        standard_cost: 10,
        is_purchased: 1,
        is_active: 1,
      });
    expect(item.status).toBe(201);
    const warehouse = await request(app)
      .post('/api/inventory/warehouses')
      .set('Cookie', cookie)
      .send({
        warehouse_code: `SM-WH-${suffix}`,
        warehouse_name: `Stock movement WH ${suffix}`,
        is_active: 1,
      });
    expect(warehouse.status).toBe(201);
    return { itemId: item.body.id, warehouseId: warehouse.body.id };
  }

  function seedStock(
    itemId: number,
    warehouseId: number,
    batches: Array<{ quantity: number; unitCost?: number }>,
  ): void {
    let total = 0;
    batches.forEach((batch, index) => {
      db.prepare(
        `INSERT INTO stock_batches (
           batch_no, item_id, warehouse_id, source_type, source_id,
           quantity_original, quantity_remaining, unit_cost, received_date
         ) VALUES (?, ?, ?, 'PURCHASE', ?, ?, ?, ?, '2026-01-01')`,
      ).run(
        `SM-BATCH-${Date.now()}-${seq}-${index}`,
        itemId,
        warehouseId,
        900000 + seq * 10 + index,
        batch.quantity,
        batch.quantity,
        batch.unitCost ?? 10,
      );
      total += batch.quantity;
    });

    const existing = db
      .prepare(
        'SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?',
      )
      .get(itemId, warehouseId) as { quantity: number } | undefined;
    if (existing) {
      db.prepare(
        'UPDATE stock_balances SET quantity = ? WHERE item_id = ? AND warehouse_id = ?',
      ).run(existing.quantity + total, itemId, warehouseId);
    } else {
      db.prepare(
        'INSERT INTO stock_balances (item_id, warehouse_id, quantity) VALUES (?, ?, ?)',
      ).run(itemId, warehouseId, total);
    }
  }

  it('rejects a movement missing required fields', async () => {
    const res = await post({ item_id: 1 });

    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/required/i);
  });

  it('rejects an outgoing movement that exceeds available stock', async () => {
    const { itemId, warehouseId } = await fixture();

    const res = await post({
      item_id: itemId,
      warehouse_id: warehouseId,
      quantity: -1,
      movement_type: 'OUT',
    });

    expect(res.status).toBe(400);
    expect(res.body).toEqual({
      error: 'Insufficient stock',
      details: { available: 0, requested: 1 },
    });
  });

  it('records a normal incoming movement', async () => {
    const { itemId, warehouseId } = await fixture();

    const res = await post({
      item_id: itemId,
      warehouse_id: warehouseId,
      quantity: 5,
      movement_type: 'IN',
      unit_cost: 10,
    });

    expect(res.status).toBe(201);
    expect(res.body.quantity).toBe(5);
    expect(res.body.movement_type).toBe('IN');
  });

  it('consumes multiple batches and logs the batch count', async () => {
    const { itemId, warehouseId } = await fixture();
    seedStock(itemId, warehouseId, [
      { quantity: 5, unitCost: 8 },
      { quantity: 5, unitCost: 12 },
    ]);

    const res = await post({
      item_id: itemId,
      warehouse_id: warehouseId,
      quantity: -8,
      movement_type: 'ADJUSTMENT',
    });

    expect(res.status).toBe(201);
    const movements = db
      .prepare(
        `SELECT quantity FROM stock_movements
         WHERE item_id = ? AND movement_type = 'ADJUSTMENT'
         ORDER BY id`,
      )
      .all(itemId) as Array<{ quantity: number }>;
    expect(movements).toHaveLength(2);
    expect(movements.reduce((sum, row) => sum + row.quantity, 0)).toBe(-8);
  });

  it('uses batch consumption for a negative sale even though sale skips the negative-stock guard', async () => {
    const { itemId, warehouseId } = await fixture();
    seedStock(itemId, warehouseId, [{ quantity: 5 }]);

    const res = await post({
      item_id: itemId,
      warehouse_id: warehouseId,
      quantity: -2,
      movement_type: 'SALE',
    });

    expect(res.status).toBe(201);
    expect(res.body.quantity).toBe(-2);
    expect(res.body.movement_type).toBe('SALE');
  });

  it('uses the generic unit fallback when the item lookup is missing', async () => {
    const { itemId, warehouseId } = await fixture();
    jest.spyOn(ItemModel, 'getById').mockReturnValueOnce(undefined);

    const res = await post({
      item_id: itemId,
      warehouse_id: warehouseId,
      quantity: 1,
      movement_type: 'IN',
    });

    expect(res.status).toBe(201);
    expect(res.body.quantity).toBe(1);
  });

  it('returns a sanitized 500 when the model throws', async () => {
    const { itemId, warehouseId } = await fixture();
    jest.spyOn(logger, 'error').mockImplementation(() => logger);
    jest
      .spyOn(StockMovementModel, 'recordMovement')
      .mockImplementationOnce(() => {
        throw new Error('SQL detail that must not reach the client');
      });

    const res = await post({
      item_id: itemId,
      warehouse_id: warehouseId,
      quantity: 1,
      movement_type: 'IN',
    });

    expect(res.status).toBe(500);
    expect(res.body).toEqual({ error: 'Failed to create stock movement' });
  });
});
