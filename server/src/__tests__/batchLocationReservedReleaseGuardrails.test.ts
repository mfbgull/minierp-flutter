/**
 * S-1 follow-up (GLM cross-review of 1417b0d7): the first fix linked a sale
 * to a reservation by id, but four gaps remained:
 *
 *   1. A reservation_id naming ANOTHER item/warehouse/batch/location was
 *      accepted, and the drain came from the invoice line's own bin.
 *   2. A partial sale released the WHOLE reservation instead of the sold
 *      quantity (reserve 4, sell 1 -> 0 reserved, not 3).
 *   3. Consuming a valid reservation required feature_batch_locations ON,
 *      but only READS may depend on the flag — writes maintain both
 *      stock_batches and batch_stock_by_location regardless.
 *   4. The invoice-line -> reservation link was not persisted, so audit and
 *      reversal could not reconstruct it.
 *
 * Every case drives the REAL POST /api/invoices route on the real test DB.
 */
import { beforeAll, describe, expect, it } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { StockReservationModel } from '../models/StockReservation';
import WarehouseModel from '../models/Warehouse';
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
  customerId = await createCustomer('S1 Guardrail Customer', cookie);
  warehouseA = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
});

function defaultLocation(wh: number): number {
  return (db.prepare(
    "SELECT id FROM locations WHERE warehouse_id = ? AND location_code = 'DEFAULT'",
  ).get(wh) as { id: number }).id;
}

function warehouseB(): number {
  const existing = db.prepare('SELECT id FROM warehouses WHERE id <> ? ORDER BY id LIMIT 1')
    .get(warehouseA) as { id: number } | undefined;
  if (existing) return existing.id;
  return WarehouseModel.create(db, { warehouse_code: 'S1G-B', warehouse_name: 'S1G Warehouse B' });
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

function reservationStatus(id: number): { status: string; quantity_reserved: number } {
  return db.prepare('SELECT status, quantity_reserved FROM stock_reservations WHERE id = ?')
    .get(id) as { status: string; quantity_reserved: number };
}

async function sell(
  itemId: number, qty: number, tag: string, reservationId?: number, warehouseId = warehouseA,
): Promise<number> {
  const res = await request(app)
    .post('/api/invoices')
    .set('Cookie', cookie)
    .set('Idempotency-Key', nextIdemKey(`s1g-${tag}`))
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
      warehouse_id: warehouseId,
    });
  return res.status;
}

function makeReservation(itemId: number, wh: number, batchId: number, locId: number, qty: number, doc: string) {
  return StockReservationModel.create(
    {
      item_id: itemId, warehouse_id: wh, location_id: locId, batch_id: batchId,
      quantity_reserved: qty, reference_doctype: 'SALES_ORDER',
      reference_docno: doc, reference_line_id: 1,
    },
    db,
  );
}

describe('S-1 guardrails: reservation link must be validated, partial, flag-free and persisted', () => {
  it('(1) rejects a reservation_id that belongs to another item, with 4xx and no stock writes', async () => {
    setFeatureEnabled(db, FLAG, true);
    const itemA = await createItem(`S1G owner ${Date.now()}`, cookie);
    const itemB = await createItem(`S1G other ${Date.now()}`, cookie);
    await purchaseStock(itemA, warehouseA, 10, 40, cookie, AS_OF);
    await purchaseStock(itemB, warehouseA, 10, 40, cookie, AS_OF);
    const batchA = batchIdOf(itemA, warehouseA);
    const batchB = batchIdOf(itemB, warehouseA);
    const loc = defaultLocation(warehouseA);

    const foreign = makeReservation(itemB, warehouseA, batchB, loc, 4, `SO-ITEM-${Date.now()}`);

    // Invoice itemA, but name itemB's reservation: must be refused.
    const before = binRow(batchA, loc);
    const status = await sell(itemA, 4, 'foreign-item', foreign.id);
    expect(status).toBeGreaterThanOrEqual(400);
    expect(status).toBeLessThan(500);

    // No inventory or reservation writes happened.
    expect(binRow(batchA, loc)).toEqual(before);
    expect(reservationStatus(foreign.id)).toEqual({ status: 'ACTIVE', quantity_reserved: 4 });
  });

  it('(1) rejects a reservation_id that belongs to another warehouse, with 4xx and no stock writes', async () => {
    setFeatureEnabled(db, FLAG, true);
    const itemId = await createItem(`S1G otherwh ${Date.now()}`, cookie);
    const wh = warehouseB();
    await purchaseStock(itemId, warehouseA, 10, 40, cookie, AS_OF);
    await purchaseStock(itemId, wh, 10, 40, cookie, AS_OF);
    const batchA = batchIdOf(itemId, warehouseA);
    const batchWh = batchIdOf(itemId, wh);
    const locA = defaultLocation(warehouseA);
    const locWh = defaultLocation(wh);

    // Reservation lives in the OTHER warehouse; the invoice line is in A.
    const foreign = makeReservation(itemId, wh, batchWh, locWh, 4, `SO-WH-${Date.now()}`);

    const status = await sell(itemId, 4, 'other-warehouse', foreign.id);
    expect(status).toBeGreaterThanOrEqual(400);
    expect(status).toBeLessThan(500);
    expect(binRow(batchA, locA)).toEqual({ physical: 10, reserved: 0, available: 10 });
    expect(binRow(batchWh, locWh)).toEqual({ physical: 10, reserved: 4, available: 6 });
    expect(reservationStatus(foreign.id)).toEqual({ status: 'ACTIVE', quantity_reserved: 4 });
  });

  it('(2) a partial sale leaves the remainder reserved and ACTIVE: reserve 4, invoice 1 -> 3 reserved', async () => {
    setFeatureEnabled(db, FLAG, true);
    const itemId = await createItem(`S1G partial ${Date.now()}`, cookie);
    await purchaseStock(itemId, warehouseA, 10, 40, cookie, AS_OF);
    const batchId = batchIdOf(itemId, warehouseA);
    const loc = defaultLocation(warehouseA);

    const reservation = makeReservation(itemId, warehouseA, batchId, loc, 4, `SO-PART-${Date.now()}`);
    expect(binRow(batchId, loc)).toEqual({ physical: 10, reserved: 4, available: 6 });

    // Sell 1 of the reserved 4.
    expect(await sell(itemId, 1, 'partial', reservation.id)).toBe(201);

    // Physical drained by exactly 1; the remaining 3 stay reserved and ACTIVE.
    expect(binRow(batchId, loc)).toEqual({ physical: 9, reserved: 3, available: 6 });
    expect(reservationStatus(reservation.id)).toEqual({ status: 'ACTIVE', quantity_reserved: 3 });
  });

  it('(2) two partial sales drain the reservation to zero and then mark it CONSUMED', async () => {
    setFeatureEnabled(db, FLAG, true);
    const itemId = await createItem(`S1G partial2 ${Date.now()}`, cookie);
    await purchaseStock(itemId, warehouseA, 10, 40, cookie, AS_OF);
    const batchId = batchIdOf(itemId, warehouseA);
    const loc = defaultLocation(warehouseA);
    const reservation = makeReservation(itemId, warehouseA, batchId, loc, 4, `SO-PART2-${Date.now()}`);

    expect(await sell(itemId, 3, 'part2a', reservation.id)).toBe(201);
    expect(reservationStatus(reservation.id)).toEqual({ status: 'ACTIVE', quantity_reserved: 1 });
    expect(binRow(batchId, loc)).toEqual({ physical: 7, reserved: 1, available: 6 });

    expect(await sell(itemId, 1, 'part2b', reservation.id)).toBe(201);
    expect(reservationStatus(reservation.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
    expect(binRow(batchId, loc)).toEqual({ physical: 6, reserved: 0, available: 6 });
  });

  it('(2) multi-bin: the drain comes from the RESERVATION bin, never another bin of the same item', async () => {
    setFeatureEnabled(db, FLAG, true);
    const itemId = await createItem(`S1G multibin ${Date.now()}`, cookie);
    // Two receipts -> two batches, each with its own bin.
    await purchaseStock(itemId, warehouseA, 5, 40, cookie, '2026-10-01');
    await purchaseStock(itemId, warehouseA, 5, 42, cookie, '2026-10-05');
    const batches = db.prepare(
      'SELECT id FROM stock_batches WHERE item_id = ? AND warehouse_id = ? ORDER BY received_date ASC, id ASC',
    ).all(itemId, warehouseA) as Array<{ id: number }>;
    const oldBatch = batches[0].id;
    const newBatch = batches[1].id;
    const loc = defaultLocation(warehouseA);

    // Reserve 4 from the NEWER batch explicitly.
    const reservation = makeReservation(itemId, warehouseA, newBatch, loc, 4, `SO-MB-${Date.now()}`);
    const newBefore = binRow(newBatch, loc);
    const oldBefore = binRow(oldBatch, loc);

    // Sell against the reservation: the take must hit the NEWER bin, not FIFO's older bin.
    expect(await sell(itemId, 4, 'multibin', reservation.id)).toBe(201);

    expect(binRow(newBatch, loc).physical).toBe(newBefore.physical - 4);
    expect(binRow(newBatch, loc).reserved).toBe(0);
    expect(binRow(oldBatch, loc)).toEqual(oldBefore);
  });

  it('(3) a valid reservation_id consumes with feature_batch_locations OFF, and writes reach both tables', async () => {
    setFeatureEnabled(db, FLAG, true);
    const itemId = await createItem(`S1G flagon ${Date.now()}`, cookie);
    await purchaseStock(itemId, warehouseA, 10, 40, cookie, AS_OF);
    const batchId = batchIdOf(itemId, warehouseA);
    const loc = defaultLocation(warehouseA);
    const reservation = makeReservation(itemId, warehouseA, batchId, loc, 4, `SO-FLAGOFF-${Date.now()}`);

    // Flip the flag OFF: only READS may depend on it. A valid consume must
    // still work, and both stock_batches and batch_stock_by_location update.
    setFeatureEnabled(db, FLAG, false);

    const status = await sell(itemId, 4, 'flag-off', reservation.id);
    expect(status).toBe(201);

    const batchRow = db.prepare('SELECT quantity_remaining FROM stock_batches WHERE id = ?')
      .get(batchId) as { quantity_remaining: number };
    expect(Number(batchRow.quantity_remaining)).toBe(6);
    expect(binRow(batchId, loc)).toEqual({ physical: 6, reserved: 0, available: 6 });
    expect(reservationStatus(reservation.id).status).toBe('CONSUMED');
    setFeatureEnabled(db, FLAG, true);
  });

  it('(3) an UNKNOWN reservation_id is a 4xx even with the flag OFF (never a 500)', async () => {
    setFeatureEnabled(db, FLAG, true);
    const itemId = await createItem(`S1G unknown ${Date.now()}`, cookie);
    await purchaseStock(itemId, warehouseA, 10, 40, cookie, AS_OF);
    setFeatureEnabled(db, FLAG, false);

    const status = await sell(itemId, 1, 'unknown-flagoff', 987654321);
    expect(status).toBeGreaterThanOrEqual(400);
    expect(status).toBeLessThan(500);
    setFeatureEnabled(db, FLAG, true);
  });

  it('(4) persists the invoice-line -> reservation_id link for audit and reversal', async () => {
    setFeatureEnabled(db, FLAG, true);
    const itemId = await createItem(`S1G persist ${Date.now()}`, cookie);
    await purchaseStock(itemId, warehouseA, 10, 40, cookie, AS_OF);
    const batchId = batchIdOf(itemId, warehouseA);
    const loc = defaultLocation(warehouseA);
    const reservation = makeReservation(itemId, warehouseA, batchId, loc, 4, `SO-PERSIST-${Date.now()}`);

    expect(await sell(itemId, 4, 'persist', reservation.id)).toBe(201);

    const linked = db.prepare(`
      SELECT ii.reservation_id AS rid
      FROM invoice_items ii
      JOIN invoices i ON i.id = ii.invoice_id
      WHERE ii.item_id = ?
      ORDER BY ii.id DESC LIMIT 1
    `).get(itemId) as { rid: number | null } | undefined;
    expect(linked?.rid).toBe(reservation.id);
  });
});
