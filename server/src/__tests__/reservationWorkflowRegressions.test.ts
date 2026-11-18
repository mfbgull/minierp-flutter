/**
 * S-1 review follow-up — regressions found by GLM review + CI on 435064fe.
 *
 * 1. Legacy single-bin release: `release`/`markConsumed` must still decrement
 *    the PARENT bin reserve when the reservation has no child allocation rows.
 *    (CI: inventoryQueryControllers.test.ts:279)
 * 2. Partial multi-bin sales: child rows must never be created by a negative
 *    release, and only the intended allocation may be drained.
 * 3. Multi-bin void: an active-order void must re-reserve the exact per-bin
 *    allocations, not just the parent total; closed/cancelled orders stay consumed.
 * 4. Batch-only reservation through the invoice path: a reservation with a
 *    batch_id but no location_id must not 409, and both stock stores must stay
 *    in step.
 */
import { beforeAll, describe, expect, it } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { StockReservationModel } from '../models/StockReservation';
import { setFeatureEnabled } from '../utils/featureFlags';
import { createCustomer, createItem, getAuthCookie, nextIdemKey, purchaseStock } from './helpers/invoiceReturnSpec';

const FLAG = 'feature_batch_locations';
const AS_OF = '2026-10-15';

let cookie = '';
let customerId = 0;
let warehouseA = 0;

beforeAll(async () => {
  cookie = await getAuthCookie();
  customerId = await createCustomer('S1 Regression Customer', cookie);
  warehouseA = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
});

function defaultLocation(wh: number): number {
  return (db.prepare(
    "SELECT id FROM locations WHERE warehouse_id = ? AND location_code = 'DEFAULT'",
  ).get(wh) as { id: number }).id;
}

function batchIdsOf(itemId: number, wh: number): number[] {
  return (db.prepare(
    'SELECT id FROM stock_batches WHERE item_id = ? AND warehouse_id = ? ORDER BY received_date ASC, id ASC',
  ).all(itemId, wh) as Array<{ id: number }>).map((r) => r.id);
}

function binRow(batchId: number, locationId: number): { physical: number; reserved: number; available: number } {
  const r = db.prepare(
    `SELECT quantity_physical as physical, quantity_reserved as reserved, quantity_available as available
     FROM batch_stock_by_location WHERE batch_id = ? AND location_id = ?`,
  ).get(batchId, locationId) as { physical: number; reserved: number; available: number } | undefined;
  return r ?? { physical: 0, reserved: 0, available: 0 };
}

function reservationRow(id: number): { status: string; quantity_reserved: number } {
  return db.prepare('SELECT status, quantity_reserved FROM stock_reservations WHERE id = ?')
    .get(id) as { status: string; quantity_reserved: number };
}

function reservationBinRows(reservationId: number): Array<{ batch_id: number; location_id: number; quantity_reserved: number }> {
  return db.prepare(
    'SELECT batch_id, location_id, quantity_reserved FROM stock_reservation_bins WHERE reservation_id = ? ORDER BY id',
  ).all(reservationId) as Array<{ batch_id: number; location_id: number; quantity_reserved: number }>;
}

function binCount(reservationId: number): number {
  return (db.prepare('SELECT COUNT(*) AS c FROM stock_reservation_bins WHERE reservation_id = ?')
    .get(reservationId) as { c: number }).c;
}

function seedSalesOrder(status: string): string {
  const soNo = `SO-S1R-${status}-${Date.now()}-${Math.floor(Math.random() * 1e6)}`;
  db.prepare(`
    INSERT INTO sales_orders (so_no, customer_id, so_date, status, total_amount, warehouse_id)
    VALUES (?, ?, ?, ?, 0, ?)
  `).run(soNo, customerId, AS_OF, status, warehouseA);
  return soNo;
}

async function sell(itemId: number, qty: number, tag: string, reservationId?: number): Promise<number> {
  const res = await request(app)
    .post('/api/invoices')
    .set('Cookie', cookie)
    .set('Idempotency-Key', nextIdemKey(`s1r-${tag}`))
    .send({
      customer_id: customerId,
      invoice_date: AS_OF,
      items: [{
        item_id: itemId, quantity: qty, unit_price: 50, tax_rate: 0,
        ...(reservationId !== undefined ? { reservation_id: reservationId } : {}),
      }],
      warehouse_id: warehouseA,
    });
  return res.status;
}

async function cancelInvoice(invoiceId: number): Promise<number> {
  const res = await request(app)
    .put(`/api/invoices/${invoiceId}/cancel`)
    .set('Cookie', cookie)
    .send({ reason: 'S1 regression test' });
  return res.status;
}

function lastInvoiceId(): number {
  return (db.prepare('SELECT id FROM invoices ORDER BY id DESC LIMIT 1').get() as { id: number }).id;
}

// ── 1. Legacy single-bin release must still decrement the parent bin reserve ──

describe('Finding 1: legacy single-bin release', () => {
  it('release() restores the batch/location reserved and available quantities', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R legacy-release ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 10, 40, cookie, AS_OF);
    const [batchId] = batchIdsOf(item, warehouseA);
    const loc = defaultLocation(warehouseA);

    // A legacy row: parent location_id/batch_id set and NO child allocation row
    // (the shape written before migration 129 existed).
    const soNo = seedSalesOrder('Confirmed');
    db.prepare(`INSERT INTO stock_reservations
      (item_id,warehouse_id,batch_id,location_id,quantity_reserved,
       reference_doctype,reference_docno,reference_line_id,status)
      VALUES (?,?,?,?,2,'SALES_ORDER',?,1,'ACTIVE')`)
      .run(item, warehouseA, batchId, loc, soNo);
    db.prepare(`UPDATE batch_stock_by_location SET quantity_reserved = 2, quantity_available = 8
      WHERE batch_id = ? AND location_id = ?`).run(batchId, loc);
    expect(binRow(batchId, loc)).toEqual({ physical: 10, reserved: 2, available: 8 });

    const released = StockReservationModel.release(
      { reference_doctype: 'SALES_ORDER', reference_docno: soNo, reference_line_id: 1 }, db,
    );
    expect(released?.status).toBe('RELEASED');
    // Both units freed: reserved 0, available 10.
    expect(binRow(batchId, loc)).toEqual({ physical: 10, reserved: 0, available: 10 });
    expect(binCount(Number(released?.id))).toBe(0);
  });

  it('markConsumed via consumeById frees the parent bin reserve and keeps no child rows', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R legacy-consume ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 10, 40, cookie, AS_OF);
    const [batchId] = batchIdsOf(item, warehouseA);
    const loc = defaultLocation(warehouseA);

    const soNo = seedSalesOrder('Confirmed');
    const inserted = db.prepare(`INSERT INTO stock_reservations
      (item_id,warehouse_id,batch_id,location_id,quantity_reserved,
       reference_doctype,reference_docno,reference_line_id,status)
      VALUES (?,?,?,?,3,'SALES_ORDER',?,1,'ACTIVE')`)
      .run(item, warehouseA, batchId, loc, soNo);
    const reservationId = Number(inserted.lastInsertRowid);
    db.prepare(`UPDATE batch_stock_by_location SET quantity_reserved = 3, quantity_available = 7
      WHERE batch_id = ? AND location_id = ?`).run(batchId, loc);
    expect(binRow(batchId, loc)).toEqual({ physical: 10, reserved: 3, available: 7 });

    const consumed = StockReservationModel.consumeById(reservationId, db);
    expect(consumed?.status).toBe('CONSUMED');
    // Reserved cleared, so available returns to physical (minus other reserves).
    expect(binRow(batchId, loc)).toEqual({ physical: 10, reserved: 0, available: 10 });
    expect(binCount(reservationId)).toBe(0);
  });
});

// ── 2. Repeated partial multi-bin sales must not corrupt child rows ──

describe('Finding 2: child allocations after repeated partial sales', () => {
  it('never creates child rows on release, and only drains the intended allocation', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R partial-rows ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 5, 40, cookie, '2026-10-01');
    await purchaseStock(item, warehouseA, 5, 42, cookie, '2026-10-05');
    const [b1, b2] = batchIdsOf(item, warehouseA);
    const loc = defaultLocation(warehouseA);

    const reservation = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 6,
      reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Confirmed'), reference_line_id: 1,
      bins: [
        { batch_id: b1, location_id: loc, quantity: 4 },
        { batch_id: b2, location_id: loc, quantity: 2 },
      ],
    }, db);
    expect(reservationBinRows(reservation.id)).toEqual([
      { batch_id: b1, location_id: loc, quantity_reserved: 4 },
      { batch_id: b2, location_id: loc, quantity_reserved: 2 },
    ]);

    // Three 1-unit partial sales. Each must only shrink the rows it drains.
    expect(await sell(item, 1, 'p1', reservation.id)).toBe(201);
    expect(reservationBinRows(reservation.id)).toEqual([
      { batch_id: b1, location_id: loc, quantity_reserved: 3 },
      { batch_id: b2, location_id: loc, quantity_reserved: 2 },
    ]);
    expect(await sell(item, 1, 'p2', reservation.id)).toBe(201);
    expect(reservationBinRows(reservation.id)).toEqual([
      { batch_id: b1, location_id: loc, quantity_reserved: 2 },
      { batch_id: b2, location_id: loc, quantity_reserved: 2 },
    ]);
    expect(await sell(item, 1, 'p3', reservation.id)).toBe(201);
    expect(reservationBinRows(reservation.id)).toEqual([
      { batch_id: b1, location_id: loc, quantity_reserved: 1 },
      { batch_id: b2, location_id: loc, quantity_reserved: 2 },
    ]);

    // Row count must never grow; only two allocations exist.
    expect(binCount(reservation.id)).toBe(2);
    // Sum of child rows must equal the reservation remainder.
    const sum = reservationBinRows(reservation.id).reduce((s, r) => s + Number(r.quantity_reserved), 0);
    expect(sum).toBe(Number(reservationRow(reservation.id).quantity_reserved));
    expect(reservationRow(reservation.id)).toEqual({ status: 'ACTIVE', quantity_reserved: 3 });
    // Bins agree: b1 reserved 1, b2 reserved 2.
    expect(binRow(b1, loc)).toEqual({ physical: 2, reserved: 1, available: 1 });
    expect(binRow(b2, loc)).toEqual({ physical: 5, reserved: 2, available: 3 });
  });

  it('drains the remainder of a partial sale across bins in stored order', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R partial-span ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 5, 40, cookie, '2026-10-01');
    await purchaseStock(item, warehouseA, 5, 42, cookie, '2026-10-05');
    const [b1, b2] = batchIdsOf(item, warehouseA);
    const loc = defaultLocation(warehouseA);

    const reservation = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 6,
      reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Confirmed'), reference_line_id: 1,
      bins: [
        { batch_id: b1, location_id: loc, quantity: 4 },
        { batch_id: b2, location_id: loc, quantity: 2 },
      ],
    }, db);

    // Sell 5: drains b1 fully (4) and takes 1 from b2.
    expect(await sell(item, 5, 'span', reservation.id)).toBe(201);
    expect(reservationBinRows(reservation.id)).toEqual([
      { batch_id: b2, location_id: loc, quantity_reserved: 1 },
    ]);
    expect(binRow(b1, loc)).toEqual({ physical: 1, reserved: 0, available: 1 });
    expect(binRow(b2, loc)).toEqual({ physical: 4, reserved: 1, available: 3 });
    const sum = reservationBinRows(reservation.id).reduce((s, r) => s + Number(r.quantity_reserved), 0);
    expect(sum).toBe(Number(reservationRow(reservation.id).quantity_reserved));
  });
});

// ── 3. Multi-bin void must re-reserve the exact allocations ──

describe('Finding 3: multi-bin void reopens exact allocations', () => {
  it('re-reserves each bin when the source order is active', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R void-multibin ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 5, 40, cookie, '2026-10-01');
    await purchaseStock(item, warehouseA, 5, 42, cookie, '2026-10-05');
    const [b1, b2] = batchIdsOf(item, warehouseA);
    const loc = defaultLocation(warehouseA);

    const reservation = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 6,
      reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Confirmed'), reference_line_id: 1,
      bins: [
        { batch_id: b1, location_id: loc, quantity: 4 },
        { batch_id: b2, location_id: loc, quantity: 2 },
      ],
    }, db);

    expect(await sell(item, 6, 'void-multibin', reservation.id)).toBe(201);
    expect(reservationRow(reservation.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
    const invoiceId = lastInvoiceId();

    expect(await cancelInvoice(invoiceId)).toBe(200);

    // Stock restored per bin AND the reservation is ACTIVE with allocations back.
    expect(binRow(b1, loc)).toEqual({ physical: 5, reserved: 4, available: 1 });
    expect(binRow(b2, loc)).toEqual({ physical: 5, reserved: 2, available: 3 });
    expect(reservationRow(reservation.id)).toEqual({ status: 'ACTIVE', quantity_reserved: 6 });
    expect(reservationBinRows(reservation.id)).toEqual([
      { batch_id: b1, location_id: loc, quantity_reserved: 4 },
      { batch_id: b2, location_id: loc, quantity_reserved: 2 },
    ]);
  });

  it('leaves a multi-bin reservation CONSUMED when the source order is completed', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R void-multibin-closed ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 5, 40, cookie, '2026-10-01');
    await purchaseStock(item, warehouseA, 5, 42, cookie, '2026-10-05');
    const [b1, b2] = batchIdsOf(item, warehouseA);
    const loc = defaultLocation(warehouseA);

    const reservation = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 6,
      reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Completed'), reference_line_id: 1,
      bins: [
        { batch_id: b1, location_id: loc, quantity: 4 },
        { batch_id: b2, location_id: loc, quantity: 2 },
      ],
    }, db);

    expect(await sell(item, 6, 'void-multibin-closed', reservation.id)).toBe(201);
    const invoiceId = lastInvoiceId();
    expect(await cancelInvoice(invoiceId)).toBe(200);

    // Stock restored, but the reservation stays CONSUMED with no reserves.
    expect(binRow(b1, loc)).toEqual({ physical: 5, reserved: 0, available: 5 });
    expect(binRow(b2, loc)).toEqual({ physical: 5, reserved: 0, available: 5 });
    expect(reservationRow(reservation.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
  });
});

// ── 4. Batch-only reservation through the invoice path ──

describe('Finding 4: batch-only reservation through the invoice path', () => {
  it('does not 409 and keeps both stock stores in step', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R batch-only ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 10, 40, cookie, AS_OF);
    const [batchId] = batchIdsOf(item, warehouseA);

    const soNo = seedSalesOrder('Confirmed');
    const reservation = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, batch_id: batchId,
      quantity_reserved: 4, reference_doctype: 'SALES_ORDER', reference_docno: soNo, reference_line_id: 1,
    }, db);
    expect(reservation.location_id ?? null).toBeNull();

    const before = Number((db.prepare('SELECT quantity_remaining FROM stock_batches WHERE id = ?')
      .get(batchId) as { quantity_remaining: number }).quantity_remaining);

    expect(await sell(item, 4, 'batch-only-inv', reservation.id)).toBe(201);

    const after = Number((db.prepare('SELECT quantity_remaining FROM stock_batches WHERE id = ?')
      .get(batchId) as { quantity_remaining: number }).quantity_remaining);
    expect(after).toBe(before - 4);
    expect(reservationRow(reservation.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
  });

  it('keeps the known fractional-quantity case green (0.3 reserve, 3x0.1 sales)', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R fractional ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 5, 40, cookie, AS_OF);
    const [batchId] = batchIdsOf(item, warehouseA);
    const loc = defaultLocation(warehouseA);

    const reservation = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, location_id: loc, batch_id: batchId,
      quantity_reserved: 0.3, reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Confirmed'), reference_line_id: 1,
    }, db);

    expect(await sell(item, 0.1, 'frac1', reservation.id)).toBe(201);
    expect(await sell(item, 0.1, 'frac2', reservation.id)).toBe(201);
    expect(await sell(item, 0.1, 'frac3', reservation.id)).toBe(201);
    expect(reservationRow(reservation.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
    const b = binRow(batchId, loc);
    expect(Math.round(b.physical * 1000) / 1000).toBe(4.7);
    expect(Math.round(b.reserved * 1000) / 1000).toBe(0);
    expect(Math.round(b.available * 1000) / 1000).toBe(4.7);
  });
});
