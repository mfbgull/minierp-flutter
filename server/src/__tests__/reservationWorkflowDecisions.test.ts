/**
 * S-1 follow-up — Gull's two resolved reservation-workflow decisions.
 *
 * Decision A: voiding a linked invoice REOPENS its consumed reservation —
 *   but only when the reservation's source order is still ACTIVE. If the
 *   source order is closed (Invoiced/Completed) or Cancelled, the void
 *   restores stock but leaves the reservation CONSUMED.
 *
 * Decision B: ONE reservation may span MULTIPLE bins. Its quantity is
 *   allocated across bins, and consume/release act on every bin it covers.
 *   The invoice line still carries ONE durable `reservation_id`.
 *
 * Decision C: an EDIT that removes the link between a line and its
 *   reservation reopens the hold only while the source order is still ACTIVE
 *   (the same rule as Decision A). When the reopen is impossible - a terminal
 *   order, or a reference that is not a sales order - the edit RELEASES that
 *   reservation by id: terminal RELEASED, quantity_reserved 0. It must never
 *   be left CONSUMED as if the sale still stood.
 *
 * Sales-order terminal rule is read from SalesOrderModel's own transition
 * matrix (Draft|Confirmed|Delivered active; Invoiced|Completed|Cancelled
 * terminal), so "active order" is not guessed.
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
  customerId = await createCustomer('S1 Decision Customer', cookie);
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

/** Insert a sales order in a given status and return its `so_no`. */
function seedSalesOrder(status: string): string {
  const soNo = `SO-S1D-${status}-${Date.now()}-${Math.floor(Math.random() * 1e6)}`;
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
    .set('Idempotency-Key', nextIdemKey(`s1d-${tag}`))
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
    .send({ reason: 'S1 decision test' });
  return res.status;
}

function lastInvoiceId(): number {
  return (db.prepare('SELECT id FROM invoices ORDER BY id DESC LIMIT 1').get() as { id: number }).id;
}

// ───────────────────────── Decision B: multi-bin ─────────────────────────

describe('Decision B: one reservation may span multiple bins', () => {
  it('create with bins[] reserves each named bin and stores the child rows', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1D multibin ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 5, 40, cookie, '2026-10-01');
    await purchaseStock(item, warehouseA, 5, 42, cookie, '2026-10-05');
    const [b1, b2] = batchIdsOf(item, warehouseA);
    const loc = defaultLocation(warehouseA);

    const reservation = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA,
      quantity_reserved: 6,
      reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Confirmed'), reference_line_id: 1,
      bins: [
        { batch_id: b1, location_id: loc, quantity: 4 },
        { batch_id: b2, location_id: loc, quantity: 2 },
      ],
    }, db);

    expect(reservation.quantity_reserved).toBe(6);
    expect(binRow(b1, loc)).toEqual({ physical: 5, reserved: 4, available: 1 });
    expect(binRow(b2, loc)).toEqual({ physical: 5, reserved: 2, available: 3 });
    expect(reservationBinRows(reservation.id)).toEqual([
      { batch_id: b1, location_id: loc, quantity_reserved: 4 },
      { batch_id: b2, location_id: loc, quantity_reserved: 2 },
    ]);
  });

  it('a sale against a multi-bin reservation drains each bin and releases each reserve', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1D multibin2 ${Date.now()}`, cookie);
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

    expect(await sell(item, 6, 'multibin-sell', reservation.id)).toBe(201);

    // Each bin drained by its reserved share; reservation fully consumed.
    expect(binRow(b1, loc)).toEqual({ physical: 1, reserved: 0, available: 1 });
    expect(binRow(b2, loc)).toEqual({ physical: 3, reserved: 0, available: 3 });
    expect(reservationRow(reservation.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
  });

  it('rejects bins[] that name a batch of a different item', async () => {
    setFeatureEnabled(db, FLAG, true);
    const itemA = await createItem(`S1D multi-itemA ${Date.now()}`, cookie);
    const itemB = await createItem(`S1D multi-itemB ${Date.now()}`, cookie);
    await purchaseStock(itemA, warehouseA, 5, 40, cookie, '2026-10-01');
    await purchaseStock(itemB, warehouseA, 5, 40, cookie, '2026-10-01');
    const [batchOfA] = batchIdsOf(itemA, warehouseA);
    const [batchOfB] = batchIdsOf(itemB, warehouseA);
    const loc = defaultLocation(warehouseA);

    // Reservation is for itemA but one bin names itemB's batch: the guarded
    // reserve write must refuse, and the whole txn must roll back.
    expect(() => StockReservationModel.create({
      item_id: itemA, warehouse_id: warehouseA, quantity_reserved: 4,
      reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Confirmed'), reference_line_id: 1,
      bins: [
        { batch_id: batchOfA, location_id: loc, quantity: 2 },
        { batch_id: batchOfB, location_id: loc, quantity: 2 },
      ],
    }, db)).toThrow(/Reservation exceeds location availability or stock identity is invalid/);

    expect(binRow(batchOfA, loc)).toEqual({ physical: 5, reserved: 0, available: 5 });
    expect(binRow(batchOfB, loc)).toEqual({ physical: 5, reserved: 0, available: 5 });
    const count = (db.prepare('SELECT COUNT(*) AS c FROM stock_reservations WHERE item_id = ?').get(itemA) as { c: number }).c;
    expect(count).toBe(0);
  });

  it('rejects bins[] whose total does not match quantity_reserved', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1D multi-total ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 5, 40, cookie, '2026-10-01');
    await purchaseStock(item, warehouseA, 5, 42, cookie, '2026-10-05');
    const [b1, b2] = batchIdsOf(item, warehouseA);
    const loc = defaultLocation(warehouseA);

    expect(() => StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 6,
      reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Confirmed'), reference_line_id: 1,
      bins: [
        { batch_id: b1, location_id: loc, quantity: 2 },
        { batch_id: b2, location_id: loc, quantity: 2 },
      ],
    }, db)).toThrow(/Reservation bins total 4 does not match quantity_reserved 6/);

    expect(binRow(b1, loc)).toEqual({ physical: 5, reserved: 0, available: 5 });
  });

  it('the public REST endpoint accepts bins[] and reserves each bin', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1D multi-rest ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 5, 40, cookie, '2026-10-01');
    await purchaseStock(item, warehouseA, 5, 42, cookie, '2026-10-05');
    const [b1, b2] = batchIdsOf(item, warehouseA);
    const loc = defaultLocation(warehouseA);

    const created = await request(app)
      .post('/api/inventory/reservations')
      .set('Cookie', cookie)
      .send({
        item_id: item, warehouse_id: warehouseA, quantity_reserved: 6,
        reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Confirmed'), reference_line_id: 1,
        bins: [
          { batch_id: b1, location_id: loc, quantity: 4 },
          { batch_id: b2, location_id: loc, quantity: 2 },
        ],
      });
    expect(created.status).toBe(201);
    expect(created.body.quantity_reserved).toBe(6);
    expect(reservationBinRows(created.body.id)).toEqual([
      { batch_id: b1, location_id: loc, quantity_reserved: 4 },
      { batch_id: b2, location_id: loc, quantity_reserved: 2 },
    ]);
    expect(binRow(b1, loc)).toEqual({ physical: 5, reserved: 4, available: 1 });
    expect(binRow(b2, loc)).toEqual({ physical: 5, reserved: 2, available: 3 });
  });

  it('a partial sale against a multi-bin reservation leaves the remainder reserved and ACTIVE', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1D multibin3 ${Date.now()}`, cookie);
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

    // Sell 3: drain oldest bin first (b1), leaving b2 fully reserved and b1 with 1.
    expect(await sell(item, 3, 'multibin-part', reservation.id)).toBe(201);
    expect(reservationRow(reservation.id)).toEqual({ status: 'ACTIVE', quantity_reserved: 3 });
    expect(binRow(b1, loc)).toEqual({ physical: 2, reserved: 1, available: 1 });
    expect(binRow(b2, loc)).toEqual({ physical: 5, reserved: 2, available: 3 });
  });
});

// ─────────────── Decision A: void reopens a consumed reservation ───────────────

describe('Decision A: voiding a linked invoice reopens its reservation only when the source order is active', () => {
  it('reopens (ACTIVE, qty restored) when the source sales order is still active', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1D void-active ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 10, 40, cookie, AS_OF);
    const [batchId] = batchIdsOf(item, warehouseA);
    const loc = defaultLocation(warehouseA);

    const soNo = seedSalesOrder('Confirmed');
    const reservation = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, location_id: loc, batch_id: batchId,
      quantity_reserved: 4, reference_doctype: 'SALES_ORDER', reference_docno: soNo, reference_line_id: 1,
    }, db);

    expect(await sell(item, 4, 'void-active', reservation.id)).toBe(201);
    expect(reservationRow(reservation.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
    const invoiceId = lastInvoiceId();

    expect(await cancelInvoice(invoiceId)).toBe(200);

    // Stock restored AND the reservation is active again with its quantity back.
    expect(binRow(batchId, loc)).toEqual({ physical: 10, reserved: 4, available: 6 });
    expect(reservationRow(reservation.id)).toEqual({ status: 'ACTIVE', quantity_reserved: 4 });
  });

  it('does NOT reopen when the source sales order is Completed (closed)', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1D void-closed ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 10, 40, cookie, AS_OF);
    const [batchId] = batchIdsOf(item, warehouseA);
    const loc = defaultLocation(warehouseA);

    const reservation = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, location_id: loc, batch_id: batchId,
      quantity_reserved: 4, reference_doctype: 'SALES_ORDER',
      reference_docno: seedSalesOrder('Completed'), reference_line_id: 1,
    }, db);

    expect(await sell(item, 4, 'void-closed', reservation.id)).toBe(201);
    const invoiceId = lastInvoiceId();
    expect(await cancelInvoice(invoiceId)).toBe(200);

    // Stock comes back, but the reservation stays CONSUMED.
    expect(binRow(batchId, loc)).toEqual({ physical: 10, reserved: 0, available: 10 });
    expect(reservationRow(reservation.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
  });

  it('does NOT reopen when the source sales order is Cancelled', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1D void-cancelled ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 10, 40, cookie, AS_OF);
    const [batchId] = batchIdsOf(item, warehouseA);
    const loc = defaultLocation(warehouseA);

    const reservation = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, location_id: loc, batch_id: batchId,
      quantity_reserved: 4, reference_doctype: 'SALES_ORDER',
      reference_docno: seedSalesOrder('Cancelled'), reference_line_id: 1,
    }, db);

    expect(await sell(item, 4, 'void-cancelled', reservation.id)).toBe(201);
    const invoiceId = lastInvoiceId();
    expect(await cancelInvoice(invoiceId)).toBe(200);

    expect(binRow(batchId, loc)).toEqual({ physical: 10, reserved: 0, available: 10 });
    expect(reservationRow(reservation.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
  });

  it('does NOT reopen a reservation whose reference is not a sales order', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1D void-nonorder ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 10, 40, cookie, AS_OF);
    const [batchId] = batchIdsOf(item, warehouseA);
    const loc = defaultLocation(warehouseA);

    const reservation = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, location_id: loc, batch_id: batchId,
      quantity_reserved: 4, reference_doctype: 'TRANSFER', reference_docno: `TR-${Date.now()}`, reference_line_id: 1,
    }, db);

    expect(await sell(item, 4, 'void-nonorder', reservation.id)).toBe(201);
    const invoiceId = lastInvoiceId();
    expect(await cancelInvoice(invoiceId)).toBe(200);

    expect(binRow(batchId, loc)).toEqual({ physical: 10, reserved: 0, available: 10 });
    expect(reservationRow(reservation.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
  });

  it('reopens only the sold remainder when the reservation was partially consumed', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1D void-partial ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 10, 40, cookie, AS_OF);
    const [batchId] = batchIdsOf(item, warehouseA);
    const loc = defaultLocation(warehouseA);

    const reservation = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, location_id: loc, batch_id: batchId,
      quantity_reserved: 4, reference_doctype: 'SALES_ORDER',
      reference_docno: seedSalesOrder('Delivered'), reference_line_id: 1,
    }, db);

    expect(await sell(item, 1, 'void-partial', reservation.id)).toBe(201);
    expect(reservationRow(reservation.id)).toEqual({ status: 'ACTIVE', quantity_reserved: 3 });
    const invoiceId = lastInvoiceId();
    expect(await cancelInvoice(invoiceId)).toBe(200);

    // The 1 sold unit's reserve comes back on top of the 3 still reserved.
    expect(binRow(batchId, loc)).toEqual({ physical: 10, reserved: 4, available: 6 });
    expect(reservationRow(reservation.id)).toEqual({ status: 'ACTIVE', quantity_reserved: 4 });
  });
});

// ─────────── GLM finding 1: decimal-safe partial consumption ───────────

function round3(n: number): number {
  return Math.round(n * 1000) / 1000;
}

describe('Decimal partial consumption: reserve 0.3 then sell 0.1 three times', () => {
  it('consumes the reservation exactly to zero with no drift and no spurious 409', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1D decimal ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 1, 10, cookie, AS_OF);
    const [batchId] = batchIdsOf(item, warehouseA);
    const loc = defaultLocation(warehouseA);

    // Stock the bin with a clean 1.000 physical.
    db.prepare(`
      INSERT INTO batch_stock_by_location (batch_id, location_id, quantity_physical, quantity_reserved, quantity_available)
      VALUES (?, ?, 1, 0, 1)
      ON CONFLICT(batch_id, location_id) DO UPDATE SET
        quantity_physical = 1, quantity_reserved = 0, quantity_available = 1
    `).run(batchId, loc);

    const reservation = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, location_id: loc, batch_id: batchId,
      quantity_reserved: 0.3, reference_doctype: 'SALES_ORDER',
      reference_docno: seedSalesOrder('Confirmed'), reference_line_id: 1,
    }, db);

    for (const tag of ['d1', 'd2', 'd3']) {
      // GLM finding: the third sale used to 409 because float drift left
      // ~0.1 reserved and the reservation looked short.
      expect(await sell(item, 0.1, `decimal-${tag}`, reservation.id)).toBe(201);
    }

    expect(reservationRow(reservation.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
    // No residual reserve: available must equal physical.
    const row = binRow(batchId, loc);
    expect(round3(row.reserved)).toBe(0);
    expect(round3(row.available)).toBe(round3(row.physical));
  });
});

// ─────────── GLM finding 2: batch-only reservation must not regress ───────

describe('Batch-only reservation (no location_id) still works end to end', () => {
  it('creates and consumes a batch-only reservation without touching location rows', () => {
    setFeatureEnabled(db, FLAG, true);

    const warehouse = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
    const itemNo = `S1D-BO-${Date.now()}`;
    const itemId = db.prepare(
      "INSERT INTO items (item_code, item_name, unit_of_measure, is_active) VALUES (?, ?, 'pcs', 1)",
    ).run(itemNo, itemNo).lastInsertRowid as number;
    const batchId = db.prepare(
      "INSERT INTO stock_batches (batch_no, item_id, warehouse_id, source_type, source_id, quantity_original, quantity_remaining, unit_cost, received_date) VALUES (?, ?, ?, 'PURCHASE', 1, 40, 40, 5, ?)",
    ).run(itemNo, itemId, warehouse, AS_OF).lastInsertRowid as number;

    const reference = `SO-BO-${Date.now()}`;
    const reservation = StockReservationModel.create({
      item_id: itemId, warehouse_id: warehouse, batch_id: batchId,
      quantity_reserved: 5, reference_doctype: 'SALES_ORDER', reference_docno: reference, reference_line_id: 1,
    }, db);

    expect(reservation.status).toBe('ACTIVE');
    expect(reservation.quantity_reserved).toBe(5);
    // Batch-only: no child bin rows, and no location write happens.
    expect(reservationBinRows(reservation.id)).toEqual([]);

    const consumed = StockReservationModel.consume(
      { reference_doctype: 'SALES_ORDER', reference_docno: reference, reference_line_id: 1 }, db,
    );
    expect(consumed?.status).toBe('CONSUMED');

    // The master batch row is untouched by reserve/consume (batch-only shape).
    const batch = db.prepare('SELECT quantity_remaining FROM stock_batches WHERE id = ?')
      .get(batchId) as { quantity_remaining: number };
    expect(batch.quantity_remaining).toBe(40);
  });

  it('the public REST endpoint still accepts and releases a batch-only reservation', async () => {
    setFeatureEnabled(db, FLAG, true);
    const warehouse = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
    const itemNo = `S1D-BO-REST-${Date.now()}`;
    const itemId = db.prepare(
      "INSERT INTO items (item_code, item_name, unit_of_measure, is_active) VALUES (?, ?, 'pcs', 1)",
    ).run(itemNo, itemNo).lastInsertRowid as number;
    const batchId = db.prepare(
      "INSERT INTO stock_batches (batch_no, item_id, warehouse_id, source_type, source_id, quantity_original, quantity_remaining, unit_cost, received_date) VALUES (?, ?, ?, 'PURCHASE', 1, 40, 40, 5, ?)",
    ).run(itemNo, itemId, warehouse, AS_OF).lastInsertRowid as number;
    const reference = `SO-BO-REST-${Date.now()}`;

    const created = await request(app)
      .post('/api/inventory/reservations')
      .set('Cookie', cookie)
      .send({
        item_id: itemId, warehouse_id: warehouse, batch_id: batchId,
        quantity_reserved: 5, reference_doctype: 'SALES_ORDER', reference_docno: reference, reference_line_id: 1,
      });
    expect(created.status).toBe(201);
    expect(created.body.status).toBe('ACTIVE');
    expect(reservationBinRows(created.body.id)).toEqual([]);

    const released = await request(app)
      .delete(`/api/inventory/reservations/${created.body.id}/release`)
      .set('Cookie', cookie);
    expect(released.status).toBe(200);
    expect(released.body.status).toBe('RELEASED');
  });
});

// ────── Decision C: an edit releases a hold it cannot reopen ──────

/**
 * Approved rule (audit/DECISIONS.md, this round's follow-up): an edit that
 * removes the link between a line and its reservation can only hand the hold
 * back while the source sales order is still active. A terminal order, or a
 * reference that is not a sales order, makes the reopen impossible, and the
 * hold must be RELEASED by id (terminal, quantity_reserved 0) instead of
 * being left CONSUMED as if the sale still stood. Void and cancel keep the
 * CONSUMED rule that Decision A pins.
 */
describe('Decision C: an edit that drops a reservation link releases a hold it cannot reopen', () => {
  /** Line ids of an invoice, in stored order - the identity an edit resends. */
  function lineIdsOf(invoiceId: number): number[] {
    return (db.prepare('SELECT id FROM invoice_items WHERE invoice_id = ? ORDER BY id')
      .all(invoiceId) as Array<{ id: number }>).map((r) => r.id);
  }

  /** `orderStatus` null seeds a reference that is NOT a sales order. */
  async function setup(tag: string, orderStatus: string | null) {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1D edit-release ${tag} ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 5, 40, cookie, AS_OF);
    const [batchId] = batchIdsOf(item, warehouseA);
    const loc = defaultLocation(warehouseA);

    const reservation = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 3,
      reference_doctype: orderStatus === null ? 'TRANSFER' : 'SALES_ORDER',
      reference_docno: orderStatus === null ? `TR-${Date.now()}` : seedSalesOrder(orderStatus),
      reference_line_id: 1,
      bins: [{ batch_id: batchId, location_id: loc, quantity: 3 }],
    }, db);

    expect(await sell(item, 3, `edit-release-${tag}`, reservation.id)).toBe(201);
    expect(reservationRow(reservation.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
    const invoice = lastInvoiceId();
    return { item, batchId, loc, reservation, invoice, lineId: lineIdsOf(invoice)[0] };
  }

  /** The edit keeps the line and its item, but DROPS the reservation link. */
  function editWithoutLink(invoice: number, lineId: number, itemId: number, qty = 3) {
    return request(app)
      .put(`/api/invoices/${invoice}`)
      .set('Cookie', cookie)
      .send({
        customer_id: customerId,
        invoice_date: AS_OF,
        warehouse_id: warehouseA,
        items: [{ id: lineId, item_id: itemId, quantity: qty, unit_price: 50, tax_rate: 0 }],
      });
  }

  function linkedReservations(invoice: number): Array<number | null> {
    return (db.prepare('SELECT reservation_id FROM invoice_items WHERE invoice_id = ? ORDER BY id')
      .all(invoice) as Array<{ reservation_id: number | null }>).map((r) => r.reservation_id);
  }

  it('releases the hold when the source order is Completed (the reopen is impossible)', async () => {
    const { item, batchId, loc, reservation, invoice, lineId } = await setup('completed', 'Completed');

    expect((await editWithoutLink(invoice, lineId, item)).status).toBe(200);

    // Released by id: terminal, no quantity held, no child allocation left.
    expect(reservationRow(reservation.id)).toEqual({ status: 'RELEASED', quantity_reserved: 0 });
    expect(db.prepare('SELECT * FROM stock_reservation_bins WHERE reservation_id = ?')
      .all(reservation.id)).toEqual([]);
    // The bin is free: 5 bought, the re-sale of 3 came from unreserved stock.
    expect(binRow(batchId, loc)).toEqual({ physical: 2, reserved: 0, available: 2 });
    expect(linkedReservations(invoice)).toEqual([null]);
  });

  it('releases the hold when the source order is Cancelled', async () => {
    const { item, batchId, loc, reservation, invoice, lineId } = await setup('cancelled', 'Cancelled');

    expect((await editWithoutLink(invoice, lineId, item)).status).toBe(200);

    expect(reservationRow(reservation.id)).toEqual({ status: 'RELEASED', quantity_reserved: 0 });
    expect(binRow(batchId, loc)).toEqual({ physical: 2, reserved: 0, available: 2 });
  });

  it('releases the hold when the reference is not a sales order', async () => {
    const { item, batchId, loc, reservation, invoice, lineId } = await setup('nonorder', null);

    expect((await editWithoutLink(invoice, lineId, item)).status).toBe(200);

    expect(reservationRow(reservation.id)).toEqual({ status: 'RELEASED', quantity_reserved: 0 });
    expect(binRow(batchId, loc)).toEqual({ physical: 2, reserved: 0, available: 2 });
  });

  it('negative control: an active-order hold is still reopened and re-linked', async () => {
    const { item, batchId, loc, reservation, invoice, lineId } = await setup('active', 'Confirmed');

    expect((await editWithoutLink(invoice, lineId, item)).status).toBe(200);

    // Unchanged behaviour: the reopen puts the hold back, and the line picks it
    // up again, so the sale is still linked and consumed.
    expect(reservationRow(reservation.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
    expect(binRow(batchId, loc)).toEqual({ physical: 2, reserved: 0, available: 2 });
    expect(linkedReservations(invoice)).toEqual([reservation.id]);
  });

  it('negative control: a terminal-order edit that still claims the hold fails closed and rolls back', async () => {
    const { item, batchId, loc, reservation, invoice, lineId } = await setup('claimed', 'Completed');

    // The line keeps its link while the order is terminal: the hold cannot be
    // reopened, so the edit has nothing to satisfy the claim with and must
    // refuse. The release that this edit performs first must roll back with it.
    const res = await request(app)
      .put(`/api/invoices/${invoice}`)
      .set('Cookie', cookie)
      .send({
        customer_id: customerId,
        invoice_date: AS_OF,
        warehouse_id: warehouseA,
        items: [{ id: lineId, item_id: item, quantity: 3, unit_price: 50, tax_rate: 0, reservation_id: reservation.id }],
      });
    expect(res.status).toBe(409);

    // Nothing was half-applied: the hold is exactly where the sale left it.
    expect(reservationRow(reservation.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
    expect(binRow(batchId, loc)).toEqual({ physical: 2, reserved: 0, available: 2 });
    expect(linkedReservations(invoice)).toEqual([reservation.id]);
  });
});
