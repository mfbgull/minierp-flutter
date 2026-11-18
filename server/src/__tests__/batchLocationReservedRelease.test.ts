/**
 * S-1 (audit/GLM-STOCK-REVIEW.md): sale consumption decrements a bin's
 * quantity_physical but may leave quantity_reserved behind, so a
 * reserved-then-sold bin undercounts available stock permanently.
 *
 * This spec drives the REAL invoice route on the real test database, so a
 * pass or fail reflects the product, not a model helper called in isolation.
 *
 * Scenario (flag ON):
 *   1. A bin reads physical = 10. Reserve 4 -> quantity_reserved = 4,
 *      quantity_available = 6 (trigger: MAX(0, physical - reserved)).
 *   2. Sell the reserved 4 of that batch through POST /api/invoices.
 *   3. Nothing is reserved any more: the bin must read reserved = 0 and
 *      available = 6.
 *
 * Red today: consumeBatchesByLocation drains quantity_physical only, and the
 * invoice path never releases the reservation, so reserved stays 4 and
 * available reads 2.
 */
import { beforeAll, describe, expect, it } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { StockReservationModel } from '../models/StockReservation';
import { setFeatureEnabled } from '../utils/featureFlags';
import {
  createCustomer,
  createItem,
  getAuthCookie,
  nextIdemKey,
  purchaseStock,
} from './helpers/invoiceReturnSpec';

const FLAG = 'feature_batch_locations';
const AS_OF = '2026-10-15';

let cookie = '';
let customerId = 0;
let warehouseA = 0;

beforeAll(async () => {
  cookie = await getAuthCookie();
  customerId = await createCustomer('S1 Reserved Release Customer', cookie);
  const wh = db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number };
  warehouseA = wh.id;
});

function defaultLocation(wh: number): number {
  return (db.prepare(
    "SELECT id FROM locations WHERE warehouse_id = ? AND location_code = 'DEFAULT'",
  ).get(wh) as { id: number }).id;
}

function batchIdOf(itemId: number, wh: number): number {
  return (db.prepare(
    'SELECT id FROM stock_batches WHERE item_id = ? AND warehouse_id = ? ORDER BY id DESC LIMIT 1',
  ).get(itemId, wh) as { id: number }).id;
}

function binRow(batchId: number, locationId: number): {
  physical: number; reserved: number; available: number;
} {
  const r = db.prepare(
    `SELECT quantity_physical as physical, quantity_reserved as reserved, quantity_available as available
     FROM batch_stock_by_location WHERE batch_id = ? AND location_id = ?`,
  ).get(batchId, locationId) as { physical: number; reserved: number; available: number } | undefined;
  return r ?? { physical: 0, reserved: 0, available: 0 };
}

async function sell(itemId: number, qty: number, tag: string, reservationId?: number): Promise<number> {
  const res = await request(app)
    .post('/api/invoices')
    .set('Cookie', cookie)
    .set('Idempotency-Key', nextIdemKey(`s1-${tag}`))
    .send({
      customer_id: customerId,
      invoice_date: AS_OF,
      items: [{
        item_id: itemId,
        quantity: qty,
        unit_price: 50,
        tax_rate: 0,
        ...(reservationId !== undefined ? { reservation_id: reservationId } : {}),
      }],
      warehouse_id: warehouseA,
    });
  return res.status;
}

describe('S-1: a reserved-then-sold bin releases its reservation', () => {
  it('reserve 4 of 10, sell the reserved 4: reserved returns to 0 and available to 6 (flag ON)', async () => {
    setFeatureEnabled(db, FLAG, true);
    const itemId = await createItem(`S1 reserved-sold ${Date.now()}`, cookie);
    await purchaseStock(itemId, warehouseA, 10, 40, cookie, AS_OF);
    const batchId = batchIdOf(itemId, warehouseA);
    const locId = defaultLocation(warehouseA);

    // Step 1: reserve 4 against the real bin.
    const reservation = StockReservationModel.create(
      {
        item_id: itemId,
        warehouse_id: warehouseA,
        location_id: locId,
        batch_id: batchId,
        quantity_reserved: 4,
        reference_doctype: 'SALES_ORDER',
        reference_docno: `SO-S1-${Date.now()}`,
        reference_line_id: 1,
      },
      db,
    );

    expect(binRow(batchId, locId)).toEqual({ physical: 10, reserved: 4, available: 6 });

    // Step 2: sell the reserved 4 and name the reservation it fulfils.
    const status = await sell(itemId, 4, 'reserved', reservation.id);
    expect(status).toBe(201);

    // Step 3: nothing is reserved any more. physical drained by 4, so the bin
    // must read reserved = 0 and available = 6. Red today: 4 and 2.
    expect(binRow(batchId, locId)).toEqual({ physical: 6, reserved: 0, available: 6 });
  });

  it('releases ONLY the named reservation; a second reservation on the same bin stays ACTIVE (flag ON)', async () => {
    setFeatureEnabled(db, FLAG, true);
    const itemId = await createItem(`S1 two-reservations ${Date.now()}`, cookie);
    await purchaseStock(itemId, warehouseA, 10, 40, cookie, AS_OF);
    const batchId = batchIdOf(itemId, warehouseA);
    const locId = defaultLocation(warehouseA);

    const first = StockReservationModel.create(
      {
        item_id: itemId, warehouse_id: warehouseA, location_id: locId, batch_id: batchId,
        quantity_reserved: 4, reference_doctype: 'SALES_ORDER',
        reference_docno: `SO-A-${Date.now()}`, reference_line_id: 1,
      },
      db,
    );
    const second = StockReservationModel.create(
      {
        item_id: itemId, warehouse_id: warehouseA, location_id: locId, batch_id: batchId,
        quantity_reserved: 2, reference_doctype: 'SALES_ORDER',
        reference_docno: `SO-B-${Date.now()}`, reference_line_id: 1,
      },
      db,
    );
    // 4 + 2 reserved of 10 physical -> 4 available.
    expect(binRow(batchId, locId)).toEqual({ physical: 10, reserved: 6, available: 4 });

    // Sell only the first reservation's 4 units, naming it explicitly.
    expect(await sell(itemId, 4, 'two-reservations', first.id)).toBe(201);

    const firstRow = db.prepare('SELECT status FROM stock_reservations WHERE id = ?').get(first.id) as { status: string };
    const secondRow = db.prepare('SELECT status FROM stock_reservations WHERE id = ?').get(second.id) as { status: string };
    expect(firstRow.status).toBe('CONSUMED');
    expect(secondRow.status).toBe('ACTIVE');
    // Only the first 4 released: physical 10-4=6, reserved still 2, available 4.
    expect(binRow(batchId, locId)).toEqual({ physical: 6, reserved: 2, available: 4 });
  });
});
