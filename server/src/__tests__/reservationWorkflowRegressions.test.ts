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

/** Header↔child invariant: the parent total must equal the sum of its child rows. */
function expectHeaderMatchesChildren(reservationId: number): void {
  const sum = reservationBinRows(reservationId)
    .reduce((s, r) => s + Number(r.quantity_reserved), 0);
  expect(Math.round(sum * 1000) / 1000).toBe(Number(reservationRow(reservationId).quantity_reserved));
}

function reservationBinRows(reservationId: number): Array<{ batch_id: number; location_id: number; quantity_reserved: number }> {
  return db.prepare(
    'SELECT batch_id, location_id, quantity_reserved FROM stock_reservation_bins WHERE reservation_id = ? ORDER BY id',
  ).all(reservationId) as Array<{ batch_id: number; location_id: number; quantity_reserved: number }>;
}

/** Live allocations only: a row drained to 0 is void history, not an allocation. */
function liveBinRows(reservationId: number): Array<{ batch_id: number; location_id: number; quantity_reserved: number }> {
  return reservationBinRows(reservationId).filter((r) => Number(r.quantity_reserved) > 0);
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

function rackLocation(wh: number, code: string): number {
  db.prepare('INSERT INTO locations (warehouse_id, location_code, location_name) VALUES (?, ?, ?)')
    .run(wh, code, code);
  return (db.prepare('SELECT id FROM locations WHERE warehouse_id = ? AND location_code = ?')
    .get(wh, code) as { id: number }).id;
}

function moveToRack(batchId: number, wh: number, locId: number, qty: number): void {
  const def = defaultLocation(wh);
  db.prepare('UPDATE batch_stock_by_location SET quantity_physical = quantity_physical - ?, quantity_available = quantity_available - ? WHERE batch_id = ? AND location_id = ?')
    .run(qty, qty, batchId, def);
  db.prepare(`INSERT INTO batch_stock_by_location (batch_id, location_id, quantity_physical, quantity_reserved, quantity_available)
              VALUES (?, ?, ?, 0, ?)`).run(batchId, locId, qty, qty);
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

/** Line ids of an invoice, in stored order - the identity an edit resends. */
function lineIdsOf(invoiceId: number): number[] {
  return (db.prepare('SELECT id FROM invoice_items WHERE invoice_id = ? ORDER BY id')
    .all(invoiceId) as Array<{ id: number }>).map((r) => r.id);
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
    expect(liveBinRows(reservation.id)).toEqual([
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

  // GLM HIGH: a PARTIAL sale deleted the fully-drained b1 row (keepRows was
  // false whenever a remainder was left), so the void restored only b2 and
  // then added the whole sold qty to the parent — parent 6 vs child sum 2.
  it('Finding 3b: a PARTIAL multi-bin sale then void restores every original bin', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R void-partial-multibin ${Date.now()}`, cookie);
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
    expectHeaderMatchesChildren(reservation.id);

    // Sell 5 of 6: drains b1 fully (4) and takes 1 from b2, leaving 1 ACTIVE.
    expect(await sell(item, 5, 'void-partial-multibin', reservation.id)).toBe(201);
    expect(reservationRow(reservation.id)).toEqual({ status: 'ACTIVE', quantity_reserved: 1 });
    expectHeaderMatchesChildren(reservation.id);
    const invoiceId = lastInvoiceId();

    expect(await cancelInvoice(invoiceId)).toBe(200);

    // The void must restore the ORIGINAL allocation, not just the last row.
    expect(reservationRow(reservation.id)).toEqual({ status: 'ACTIVE', quantity_reserved: 6 });
    expect(reservationBinRows(reservation.id)).toEqual([
      { batch_id: b1, location_id: loc, quantity_reserved: 4 },
      { batch_id: b2, location_id: loc, quantity_reserved: 2 },
    ]);
    expectHeaderMatchesChildren(reservation.id);
    expect(binRow(b1, loc)).toEqual({ physical: 5, reserved: 4, available: 1 });
    expect(binRow(b2, loc)).toEqual({ physical: 5, reserved: 2, available: 3 });
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

// ── 5. GLM LOW findings: duplicate bins[] and RELEASED re-create without bins ──

describe('Finding 5: LOW cross-review findings', () => {
  // LOW-1: duplicate bins naming the same batch+location in one request.
  it('rejects duplicate bins instead of writing two ambiguous rows', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R dup-bins ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 10, 40, cookie, AS_OF);
    const [b1] = batchIdsOf(item, warehouseA);
    const loc = defaultLocation(warehouseA);

    // The same bin twice: without de-duplication the two child rows are
    // indistinguishable, so apply/restore cannot tell which one to touch.
    expect(() => StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 5,
      reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Confirmed'), reference_line_id: 1,
      bins: [
        { batch_id: b1, location_id: loc, quantity: 2 },
        { batch_id: b1, location_id: loc, quantity: 3 },
      ],
    }, db)).toThrow(/duplicate/i);

    // Nothing was written for that reference.
    expect(db.prepare('SELECT COUNT(*) AS c FROM stock_reservations WHERE item_id = ?')
      .get(item) as { c: number }).toEqual({ c: 0 });
    expect(binRow(b1, loc)).toEqual({ physical: 10, reserved: 0, available: 10 });
  });

  // LOW-2: a RELEASED row re-created with the legacy single-bin shape (no bins[])
  // had no child rows and no parent bin, so nothing was re-reserved yet the
  // row flipped ACTIVE carrying the requested quantity.
  it('does not reactivate a RELEASED multi-bin reservation when no allocation is given', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R released-recreate ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 5, 40, cookie, '2026-10-01');
    await purchaseStock(item, warehouseA, 5, 42, cookie, '2026-10-05');
    const [b1, b2] = batchIdsOf(item, warehouseA);
    const loc = defaultLocation(warehouseA);
    const soNo = seedSalesOrder('Confirmed');

    const reservation = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 3,
      reference_doctype: 'SALES_ORDER', reference_docno: soNo, reference_line_id: 1,
      bins: [
        { batch_id: b1, location_id: loc, quantity: 2 },
        { batch_id: b2, location_id: loc, quantity: 1 },
      ],
    }, db);

    const released = StockReservationModel.release(
      { reference_doctype: 'SALES_ORDER', reference_docno: soNo, reference_line_id: 1 }, db);
    expect(released?.status).toBe('RELEASED');
    expect(reservationBinRows(reservation.id)).toEqual([]);
    expect(binRow(b1, loc)).toEqual({ physical: 5, reserved: 0, available: 5 });

    // Re-create the same reference line WITHOUT bins[]: there is nothing to
    // re-reserve, so the row must not become an empty ACTIVE reservation.
    expect(() => StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 3,
      reference_doctype: 'SALES_ORDER', reference_docno: soNo, reference_line_id: 1,
    }, db)).toThrow(/allocation|bins/i);

    expect(reservationRow(reservation.id)).toEqual({ status: 'RELEASED', quantity_reserved: 3 });
    expect(binRow(b1, loc)).toEqual({ physical: 5, reserved: 0, available: 5 });
  });
});

// ── 6. Duplicate-reference guard: a different allocation or quantity reuses nothing ──

describe('Finding 6: duplicate reference-line guards', () => {
  it('refuses a re-create with a different bin allocation or quantity', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R dup-ref ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 5, 40, cookie, '2026-10-01');
    await purchaseStock(item, warehouseA, 5, 42, cookie, '2026-10-05');
    const [b1, b2] = batchIdsOf(item, warehouseA);
    const loc = defaultLocation(warehouseA);
    const soNo = seedSalesOrder('Confirmed');

    StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 4,
      reference_doctype: 'SALES_ORDER', reference_docno: soNo, reference_line_id: 1,
      bins: [
        { batch_id: b1, location_id: loc, quantity: 3 },
        { batch_id: b2, location_id: loc, quantity: 1 },
      ],
    }, db);

    // Same reference line, different bin split.
    expect(() => StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 4,
      reference_doctype: 'SALES_ORDER', reference_docno: soNo, reference_line_id: 1,
      bins: [
        { batch_id: b1, location_id: loc, quantity: 1 },
        { batch_id: b2, location_id: loc, quantity: 3 },
      ],
    }, db)).toThrow(/different stock or quantity/i);

    // Same reference line, different quantity.
    expect(() => StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 5,
      reference_doctype: 'SALES_ORDER', reference_docno: soNo, reference_line_id: 1,
      bins: [
        { batch_id: b1, location_id: loc, quantity: 3 },
        { batch_id: b2, location_id: loc, quantity: 2 },
      ],
    }, db)).toThrow(/different stock or quantity/i);

    // Same reference line, different warehouse.
    expect(() => StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA + 999, quantity_reserved: 4,
      reference_doctype: 'SALES_ORDER', reference_docno: soNo, reference_line_id: 1,
      bins: [
        { batch_id: b1, location_id: loc, quantity: 3 },
        { batch_id: b2, location_id: loc, quantity: 1 },
      ],
    }, db)).toThrow(/different stock or quantity/i);

    // The original allocation is untouched.
    expect(binRow(b1, loc)).toEqual({ physical: 5, reserved: 3, available: 2 });
    expect(binRow(b2, loc)).toEqual({ physical: 5, reserved: 1, available: 4 });
  });

  it('rejects a bins[] total that does not match quantity_reserved', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R bad-total ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 5, 40, cookie, '2026-10-01');
    await purchaseStock(item, warehouseA, 5, 42, cookie, '2026-10-05');
    const [b1, b2] = batchIdsOf(item, warehouseA);
    const loc = defaultLocation(warehouseA);

    expect(() => StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 6,
      reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Confirmed'), reference_line_id: 1,
      bins: [
        { batch_id: b1, location_id: loc, quantity: 1 },
        { batch_id: b2, location_id: loc, quantity: 2 },
      ],
    }, db)).toThrow(/does not match quantity_reserved/i);

    expect(binRow(b1, loc)).toEqual({ physical: 5, reserved: 0, available: 5 });
    expect(binRow(b2, loc)).toEqual({ physical: 5, reserved: 0, available: 5 });
  });
});

// ── 7. Voiding ONE of several invoices must restore only THAT invoice's bins ──

/**
 * GLM re-review of 4842faf5: the void restored the reservation's whole original
 * allocation (`quantity_allocated`) rather than the bins this invoice drained.
 * With two sales against one reservation, voiding the second over-reserved.
 * The durable fix is a per-invoice-item bin-consumption ledger, so the void can
 * restore exactly what that line took instead of guessing from quantities.
 */
describe('Finding 7: a void restores only the voided invoice line\'s bins', () => {
  function consumptionRows(invoiceId: number): Array<{ batch_id: number; location_id: number; quantity: number }> {
    return db.prepare(
      `SELECT batch_id, location_id, quantity FROM invoice_item_bin_consumption
       WHERE invoice_item_id IN (SELECT id FROM invoice_items WHERE invoice_id = ?) ORDER BY id`,
    ).all(invoiceId) as Array<{ batch_id: number; location_id: number; quantity: number }>;
  }

  it('restores only b2 when the second of two invoices is voided', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R void-two-invoices ${Date.now()}`, cookie);
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

    // Invoice 1 takes all 4 from b1; invoice 2 takes the 2 from b2.
    expect(await sell(item, 4, 'vi-1', reservation.id)).toBe(201);
    const invoice1 = lastInvoiceId();
    expect(await sell(item, 2, 'vi-2', reservation.id)).toBe(201);
    const invoice2 = lastInvoiceId();
    expect(reservationRow(reservation.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });

    // The ledger must record exactly what each line drained.
    expect(consumptionRows(invoice1)).toEqual([{ batch_id: b1, location_id: loc, quantity: 4 }]);
    expect(consumptionRows(invoice2)).toEqual([{ batch_id: b2, location_id: loc, quantity: 2 }]);

    // Void ONLY invoice 2: b2 comes back, b1 stays sold.
    expect(await cancelInvoice(invoice2)).toBe(200);

    expect(reservationRow(reservation.id)).toEqual({ status: 'ACTIVE', quantity_reserved: 2 });
    expect(liveBinRows(reservation.id)).toEqual([{ batch_id: b2, location_id: loc, quantity_reserved: 2 }]);
    expectHeaderMatchesChildren(reservation.id);
    expect(binRow(b1, loc)).toEqual({ physical: 1, reserved: 0, available: 1 });
    expect(binRow(b2, loc)).toEqual({ physical: 5, reserved: 2, available: 3 });
  });

  it('does not 409 on void when the voided line\'s bin still has physical stock', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R void-physical ${Date.now()}`, cookie);
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

    expect(await sell(item, 4, 'vp-1', reservation.id)).toBe(201);
    expect(await sell(item, 2, 'vp-2', reservation.id)).toBe(201);
    const invoice2 = lastInvoiceId();

    // b1 now holds physical 1 (5 - 4). Restoring the whole original b1
    // allocation of 4 would try to reserve 4 on a bin with physical 1.
    expect(await cancelInvoice(invoice2)).toBe(200);

    expect(reservationRow(reservation.id)).toEqual({ status: 'ACTIVE', quantity_reserved: 2 });
    expectHeaderMatchesChildren(reservation.id);
    expect(binRow(b1, loc)).toEqual({ physical: 1, reserved: 0, available: 1 });
    expect(binRow(b2, loc)).toEqual({ physical: 5, reserved: 2, available: 3 });
  });
});

// ── 8. Re-creating a RELEASED multi-bin reservation with the same bins[] ──

describe('Finding 8: released multi-bin reservation reactivation contract', () => {
  it('reactivates idempotently when the same bins[] is resent', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R released-samebins ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 5, 40, cookie, '2026-10-01');
    await purchaseStock(item, warehouseA, 5, 42, cookie, '2026-10-05');
    const [b1, b2] = batchIdsOf(item, warehouseA);
    const loc = defaultLocation(warehouseA);
    const soNo = seedSalesOrder('Confirmed');
    const bins = [
      { batch_id: b1, location_id: loc, quantity: 2 },
      { batch_id: b2, location_id: loc, quantity: 1 },
    ];

    const created = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 3,
      reference_doctype: 'SALES_ORDER', reference_docno: soNo, reference_line_id: 1,
      bins,
    }, db);
    StockReservationModel.release(
      { reference_doctype: 'SALES_ORDER', reference_docno: soNo, reference_line_id: 1 }, db);
    expect(reservationBinRows(created.id)).toEqual([]);

    // The same request again: same reference, same bins[], same quantity.
    const again = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 3,
      reference_doctype: 'SALES_ORDER', reference_docno: soNo, reference_line_id: 1,
      bins,
    }, db);

    expect(again.id).toBe(created.id);
    expect(again.status).toBe('ACTIVE');
    expect(reservationRow(created.id)).toEqual({ status: 'ACTIVE', quantity_reserved: 3 });
    expect(liveBinRows(created.id)).toEqual([
      { batch_id: b1, location_id: loc, quantity_reserved: 2 },
      { batch_id: b2, location_id: loc, quantity_reserved: 1 },
    ]);
    expectHeaderMatchesChildren(created.id);
    expect(binRow(b1, loc)).toEqual({ physical: 5, reserved: 2, available: 3 });
    expect(binRow(b2, loc)).toEqual({ physical: 5, reserved: 1, available: 4 });
    // Exactly one row for the reference line.
    expect((db.prepare('SELECT COUNT(*) AS c FROM stock_reservations WHERE reference_docno = ?')
      .get(soNo) as { c: number }).c).toBe(1);
  });
});

// ── 9. Legacy fallback: a line with no ledger row still restores exactly ──

describe('Finding 9: reopenForInvoiceLine restores stored allocations (legacy path)', () => {
  it('restores each bin to its recorded allocation, not to an increment', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R legacy-reopen ${Date.now()}`, cookie);
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

    // Drain the whole reservation, then call the legacy entry point directly -
    // this is the branch a pre-131 invoice line takes on void.
    expect(await sell(item, 6, 'lg-1', reservation.id)).toBe(201);
    expect(reservationRow(reservation.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });

    // The real void reverses the stock FIRST, then reopens the reserve.
    db.prepare('UPDATE batch_stock_by_location SET quantity_physical = quantity_physical + ? WHERE batch_id = ? AND location_id = ?').run(4, b1, loc);
    db.prepare('UPDATE batch_stock_by_location SET quantity_physical = quantity_physical + ? WHERE batch_id = ? AND location_id = ?').run(2, b2, loc);
    StockReservationModel.reopenForInvoiceLine(db, reservation.id, 6);

    expect(reservationRow(reservation.id)).toEqual({ status: 'ACTIVE', quantity_reserved: 6 });
    expect(liveBinRows(reservation.id)).toEqual([
      { batch_id: b1, location_id: loc, quantity_reserved: 4 },
      { batch_id: b2, location_id: loc, quantity_reserved: 2 },
    ]);
    expectHeaderMatchesChildren(reservation.id);
    expect(binRow(b1, loc)).toEqual({ physical: 5, reserved: 4, available: 1 });
    expect(binRow(b2, loc)).toEqual({ physical: 5, reserved: 2, available: 3 });
  });

  it('does nothing for a non-positive quantity or an unknown reservation', () => {
    StockReservationModel.reopenForInvoiceLine(db, 999999, 5);
    const item = (db.prepare('SELECT id FROM items ORDER BY id DESC LIMIT 1').get() as { id: number }).id;
    const r = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 1,
      reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Confirmed'), reference_line_id: 1,
      batch_id: batchIdsOf(item, warehouseA)[0], location_id: defaultLocation(warehouseA),
    }, db);
    StockReservationModel.reopenForInvoiceLine(db, r.id, 0);
    expect(reservationRow(r.id)).toEqual({ status: 'ACTIVE', quantity_reserved: 1 });
  });
});

// ── 10. A void from a NON-DEFAULT bin must restore that same bin ──

/**
 * GLM review of 90d57a3a (HIGH-1): reverseStockForItems restored the physical
 * quantity into the warehouse's DEFAULT bin, while the reservation restore put
 * the reserve back on the ORIGINAL bin. The stock either vanished from the bin
 * that held it or the void 409'd because the original bin had no physical left
 * to reserve. Both directions are covered here.
 */
describe('Finding 10: non-DEFAULT bin void keeps physical and reserved together', () => {
  /** A second, non-DEFAULT location in the warehouse. */
  function rackLocation(wh: number, code: string): number {
    db.prepare('INSERT INTO locations (warehouse_id, location_code, location_name) VALUES (?, ?, ?)')
      .run(wh, code, code);
    return (db.prepare('SELECT id FROM locations WHERE warehouse_id = ? AND location_code = ?')
      .get(wh, code) as { id: number }).id;
  }

  /** Move `qty` of a batch's physical stock out of DEFAULT into another bin. */
  function moveToRack(batchId: number, wh: number, locId: number, qty: number): void {
    const def = defaultLocation(wh);
    db.prepare('UPDATE batch_stock_by_location SET quantity_physical = quantity_physical - ?, quantity_available = quantity_available - ? WHERE batch_id = ? AND location_id = ?')
      .run(qty, qty, batchId, def);
    db.prepare(`INSERT INTO batch_stock_by_location (batch_id, location_id, quantity_physical, quantity_reserved, quantity_available)
                VALUES (?, ?, ?, 0, ?)`).run(batchId, locId, qty, qty);
  }

  it('restores physical stock to the original non-DEFAULT bin, not DEFAULT', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R rack-void ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 5, 40, cookie, '2026-10-01');
    const [b1] = batchIdsOf(item, warehouseA);
    const rack = rackLocation(warehouseA, `R-A-${Date.now()}`);
    moveToRack(b1, warehouseA, rack, 5);

    const reservation = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 4,
      reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Confirmed'), reference_line_id: 1,
      bins: [{ batch_id: b1, location_id: rack, quantity: 4 }],
    }, db);

    // Exact physical: the rack holds exactly the reserved 4.
    expect(await sell(item, 4, 'rv-1', reservation.id)).toBe(201);
    const invoice = lastInvoiceId();
    expect(binRow(b1, rack)).toEqual({ physical: 1, reserved: 0, available: 1 });

    expect(await cancelInvoice(invoice)).toBe(200);

    // Physical returns to the rack, never to DEFAULT.
    expect(binRow(b1, rack)).toEqual({ physical: 5, reserved: 4, available: 1 });
    expect(binRow(b1, defaultLocation(warehouseA)).physical).toBe(0);
    expect(reservationRow(reservation.id)).toEqual({ status: 'ACTIVE', quantity_reserved: 4 });
    expectHeaderMatchesChildren(reservation.id);
  });

  it('restores to the original non-DEFAULT bin when it holds surplus', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R rack-surplus ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 10, 40, cookie, '2026-10-01');
    const [b1] = batchIdsOf(item, warehouseA);
    const rack = rackLocation(warehouseA, `R-B-${Date.now()}`);
    moveToRack(b1, warehouseA, rack, 10);

    const reservation = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 4,
      reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Confirmed'), reference_line_id: 1,
      bins: [{ batch_id: b1, location_id: rack, quantity: 4 }],
    }, db);

    expect(await sell(item, 4, 'rs-1', reservation.id)).toBe(201);
    const invoice = lastInvoiceId();
    expect(binRow(b1, rack)).toEqual({ physical: 6, reserved: 0, available: 6 });

    expect(await cancelInvoice(invoice)).toBe(200);

    expect(binRow(b1, rack)).toEqual({ physical: 10, reserved: 4, available: 6 });
    expect(binRow(b1, defaultLocation(warehouseA)).physical).toBe(0);
    expectHeaderMatchesChildren(reservation.id);
  });
});

// ── 11. stock_balances mirror must track reservation writes ──

/**
 * GLM review of 90d57a3a (MEDIUM-1): stock_balances.quantity_reserved and
 * quantity_available were never written by the reservation path, so a reader
 * of that mirror saw 0 reserved no matter what the bins held. The mirror is
 * now synchronized inside the same transaction as the bin writes.
 */
describe('Finding 11: stock_balances mirror tracks reservations', () => {
  function balanceRow(itemId: number, wh: number): { reserved: number; available: number } {
    const r = db.prepare(
      'SELECT quantity_reserved AS reserved, quantity_available AS available FROM stock_balances WHERE item_id = ? AND warehouse_id = ?',
    ).get(itemId, wh) as { reserved: number | null; available: number | null } | undefined;
    return { reserved: Number(r?.reserved ?? 0), available: Number(r?.available ?? 0) };
  }

  it('tracks create, partial consume, release and void restore', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R mirror ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 5, 40, cookie, '2026-10-01');
    await purchaseStock(item, warehouseA, 5, 42, cookie, '2026-10-05');
    const [b1, b2] = batchIdsOf(item, warehouseA);
    const loc = defaultLocation(warehouseA);
    const soNo = seedSalesOrder('Confirmed');

    const reservation = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 6,
      reference_doctype: 'SALES_ORDER', reference_docno: soNo, reference_line_id: 1,
      bins: [
        { batch_id: b1, location_id: loc, quantity: 4 },
        { batch_id: b2, location_id: loc, quantity: 2 },
      ],
    }, db);
    expect(balanceRow(item, warehouseA)).toEqual({ reserved: 6, available: 4 });

    // Partial sale of 2 leaves 4 reserved.
    // 10 bought, 2 sold -> physical 8; 4 still reserved -> available 4.
    expect(await sell(item, 2, 'mb-1', reservation.id)).toBe(201);
    expect(balanceRow(item, warehouseA)).toEqual({ reserved: 4, available: 4 });

    // Void restores the 2.
    expect(await cancelInvoice(lastInvoiceId())).toBe(200);
    expect(balanceRow(item, warehouseA)).toEqual({ reserved: 6, available: 4 });

    // Release clears the reserve.
    StockReservationModel.release(
      { reference_doctype: 'SALES_ORDER', reference_docno: soNo, reference_line_id: 1 }, db);
    expect(balanceRow(item, warehouseA)).toEqual({ reserved: 0, available: 10 });
  });

  it('stays correct across a full consume and its void', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R mirror2 ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 6, 40, cookie, '2026-10-01');
    const [b1] = batchIdsOf(item, warehouseA);
    const loc = defaultLocation(warehouseA);

    const reservation = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 6,
      reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Confirmed'), reference_line_id: 1,
      bins: [{ batch_id: b1, location_id: loc, quantity: 6 }],
    }, db);
    expect(balanceRow(item, warehouseA)).toEqual({ reserved: 6, available: 0 });

    expect(await sell(item, 6, 'mf-1', reservation.id)).toBe(201);
    expect(balanceRow(item, warehouseA)).toEqual({ reserved: 0, available: 0 });

    expect(await cancelInvoice(lastInvoiceId())).toBe(200);
    expect(balanceRow(item, warehouseA)).toEqual({ reserved: 6, available: 0 });
  });
});

// ── 12. Invoice edit and delete→restore follow the same reservation rule ──

/**
 * Gull approved extending the cancel rule to the other two stock-reversing
 * invoice operations: when an operation reverses the sale, reopen the linked
 * reservation only if its source order is still active, and reserve it again
 * when a deleted invoice is restored. Closed and cancelled source orders stay
 * unreserved in every direction. The per-invoice bin ledger must be preserved
 * across the round trip so the exact bins come back, exactly once.
 */
describe('Finding 12: edit and delete/restore follow the reservation rule', () => {
  function ledgerRows(invoiceId: number): Array<{ batch_id: number; location_id: number; quantity: number }> {
    return db.prepare(
      `SELECT batch_id, location_id, quantity FROM invoice_item_bin_consumption
       WHERE invoice_item_id IN (SELECT id FROM invoice_items WHERE invoice_id = ?) ORDER BY id`,
    ).all(invoiceId) as Array<{ batch_id: number; location_id: number; quantity: number }>;
  }

  async function deleteInvoice(invoiceId: number): Promise<number> {
    const res = await request(app).delete(`/api/invoices/${invoiceId}`).set('Cookie', cookie);
    return res.status;
  }

  async function restoreInvoice(invoiceId: number): Promise<number> {
    const res = await request(app).post(`/api/invoices/${invoiceId}/restore`).set('Cookie', cookie).send({});
    if (res.status >= 400) console.log('RESTORE_FAIL', res.status, JSON.stringify(res.body));
    return res.status;
  }

  it('reopens the reservation when an active-order invoice is deleted, and re-reserves on restore', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R del-restore ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 6, 40, cookie, '2026-10-01');
    const [b1] = batchIdsOf(item, warehouseA);
    const loc = defaultLocation(warehouseA);

    const reservation = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 4,
      reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Confirmed'), reference_line_id: 1,
      bins: [{ batch_id: b1, location_id: loc, quantity: 4 }],
    }, db);

    expect(await sell(item, 4, 'dr-1', reservation.id)).toBe(201);
    const invoice = lastInvoiceId();
    expect(reservationRow(reservation.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
    expect(binRow(b1, loc)).toEqual({ physical: 2, reserved: 0, available: 2 });

    // Delete reverses the sale: the reserve comes back from the ledger bins.
    expect(await deleteInvoice(invoice)).toBe(200);
    expect(reservationRow(reservation.id)).toEqual({ status: 'ACTIVE', quantity_reserved: 4 });
    expect(binRow(b1, loc)).toEqual({ physical: 6, reserved: 4, available: 2 });
    expectHeaderMatchesChildren(reservation.id);

    // Restore reserves it again, exactly once.
    expect(await restoreInvoice(invoice)).toBe(200);
    expect(reservationRow(reservation.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
    expect(binRow(b1, loc)).toEqual({ physical: 2, reserved: 0, available: 2 });
    // Children stay as zeroed rows (the ledger that lets a later void restore
    // the exact allocation), never as live reservations.
    expect(liveBinRows(reservation.id)).toEqual([]);
    expectHeaderMatchesChildren(reservation.id);
  });

  // GLM LOW-1: the fixture used the status 'Closed', which is not one of the
  // schema's values (Draft, Confirmed, Delivered, Invoiced, Completed,
  // Cancelled). It passed only by accident - any unknown string is absent from
  // the active list. 'Cancelled' is the real terminal status, so this test now
  // proves the rule for a genuinely closed order.
  it('leaves a cancelled-order reservation unreserved across delete and restore', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R del-closed ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 6, 40, cookie, '2026-10-01');
    const [b1] = batchIdsOf(item, warehouseA);
    const loc = defaultLocation(warehouseA);

    const reservation = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 4,
      reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Cancelled'), reference_line_id: 1,
      bins: [{ batch_id: b1, location_id: loc, quantity: 4 }],
    }, db);

    expect(await sell(item, 4, 'dc-1', reservation.id)).toBe(201);
    const invoice = lastInvoiceId();

    expect(await deleteInvoice(invoice)).toBe(200);
    expect(reservationRow(reservation.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
    expect(binRow(b1, loc)).toEqual({ physical: 6, reserved: 0, available: 6 });

    expect(await restoreInvoice(invoice)).toBe(200);
    expect(reservationRow(reservation.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
    expect(binRow(b1, loc)).toEqual({ physical: 2, reserved: 0, available: 2 });
  });

  it('reopens the reservation when an active-order invoice is edited to a smaller quantity', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R edit ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 6, 40, cookie, '2026-10-01');
    const [b1] = batchIdsOf(item, warehouseA);
    const loc = defaultLocation(warehouseA);

    const reservation = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 4,
      reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Confirmed'), reference_line_id: 1,
      bins: [{ batch_id: b1, location_id: loc, quantity: 4 }],
    }, db);

    expect(await sell(item, 4, 'ed-1', reservation.id)).toBe(201);
    const invoice = lastInvoiceId();

    // Edit to 2: the stock reverses and the reserve must come back, not stay
    // stuck at CONSUMED with nothing reserved.
    const res = await request(app)
      .put(`/api/invoices/${invoice}`)
      .set('Cookie', cookie)
      .send({
        customer_id: customerId,
        invoice_date: AS_OF,
        items: [{ item_id: item, quantity: 2, unit_price: 50, tax_rate: 0 }],
        warehouse_id: warehouseA,
      });
    expect(res.status).toBe(200);

    // The 4-unit sale reversed (physical back to 6, reserve restored to 4),
    // then the edited line re-sold 2 from that same reservation -> physical 4,
    // and the link keeps the 2-unit remainder reserved rather than orphaned.
    expect(binRow(b1, loc)).toEqual({ physical: 4, reserved: 2, available: 2 });
    expectHeaderMatchesChildren(reservation.id);
  });
});

// ── 13. one batch split across two bins ──

/**
 * GLM review of fa84cf61 (HIGH-1): reverseStockForItems picked the restore
 * bin with `find(d => d.batch_id === movement.batch_id)`, which is the FIRST
 * matching bin only. A reservation may hold one batch across several bins, so
 * a void that reassembled the whole quantity on the first bin left the other
 * bins short and the first bin over-stocked. Each bin must get back exactly
 * what it gave.
 */
describe('Finding 13: a batch split across two bins reverses per bin', () => {
  it('voids back to each bin the batch came from', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R split-bin ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 10, 40, cookie, '2026-10-01');
    const [b1] = batchIdsOf(item, warehouseA);
    const rackA = rackLocation(warehouseA, `R-SPLIT-A-${Date.now()}`);
    const rackB = rackLocation(warehouseA, `R-SPLIT-B-${Date.now()}`);
    // 10 of batch b1: 4 in rack A, 6 in rack B.
    moveToRack(b1, warehouseA, rackA, 4);
    moveToRack(b1, warehouseA, rackB, 6);

    // Reserve 3 from each rack out of the same batch.
    const reservation = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 6,
      reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Confirmed'), reference_line_id: 1,
      bins: [
        { batch_id: b1, location_id: rackA, quantity: 3 },
        { batch_id: b1, location_id: rackB, quantity: 3 },
      ],
    }, db);

    expect(await sell(item, 6, 'sb-1', reservation.id)).toBe(201);
    expect(binRow(b1, rackA)).toEqual({ physical: 1, reserved: 0, available: 1 });
    expect(binRow(b1, rackB)).toEqual({ physical: 3, reserved: 0, available: 3 });

    expect(await cancelInvoice(lastInvoiceId())).toBe(200);

    // Each bin gets back exactly its own 3, never 6 on the first match.
    expect(binRow(b1, rackA)).toEqual({ physical: 4, reserved: 3, available: 1 });
    expect(binRow(b1, rackB)).toEqual({ physical: 6, reserved: 3, available: 3 });
    expect(binRow(b1, defaultLocation(warehouseA))).toEqual({ physical: 0, reserved: 0, available: 0 });
    expect(reservationRow(reservation.id)).toEqual({ status: 'ACTIVE', quantity_reserved: 6 });
    expectHeaderMatchesChildren(reservation.id);
  });
});

// ── 14. restore of a non-DEFAULT sale ──

/**
 * GLM review of fa84cf61 (HIGH-2): reversing a delete re-consumed stock with
 * reconsumeRestoredInvoiceItems, which looked the location up by warehouse and
 * took DEFAULT. A sale from a rack bin therefore either failed (the rack's
 * units were already credited back on delete, so DEFAULT had nothing to give)
 * or moved stock into DEFAULT. Restore must replay the recorded bin per line.
 */
describe('Finding 14: restoring a deleted non-DEFAULT sale', () => {
  function rackLocation(wh: number, code: string): number {
    db.prepare('INSERT INTO locations (warehouse_id, location_code, location_name) VALUES (?, ?, ?)')
      .run(wh, code, code);
    return (db.prepare('SELECT id FROM locations WHERE warehouse_id = ? AND location_code = ?')
      .get(wh, code) as { id: number }).id;
  }

  function moveToRack(batchId: number, wh: number, locId: number, qty: number): void {
    const def = defaultLocation(wh);
    db.prepare('UPDATE batch_stock_by_location SET quantity_physical = quantity_physical - ?, quantity_available = quantity_available - ? WHERE batch_id = ? AND location_id = ?')
      .run(qty, qty, batchId, def);
    db.prepare(`INSERT INTO batch_stock_by_location (batch_id, location_id, quantity_physical, quantity_reserved, quantity_available)
                VALUES (?, ?, ?, 0, ?)`).run(batchId, locId, qty, qty);
  }

  it('restores the rack bin exactly after a delete and restore round trip', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R restore-rack ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 10, 40, cookie, '2026-10-01');
    const [b1] = batchIdsOf(item, warehouseA);
    const rackA = rackLocation(warehouseA, `R-RST-A-${Date.now()}`);
    const rackB = rackLocation(warehouseA, `R-RST-B-${Date.now()}`);
    moveToRack(b1, warehouseA, rackA, 4);
    moveToRack(b1, warehouseA, rackB, 6);

    const reservation = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 6,
      reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Confirmed'), reference_line_id: 1,
      bins: [
        { batch_id: b1, location_id: rackA, quantity: 3 },
        { batch_id: b1, location_id: rackB, quantity: 3 },
      ],
    }, db);

    expect(await sell(item, 6, 'rr-1', reservation.id)).toBe(201);
    const invoice = lastInvoiceId();
    expect(binRow(b1, rackA)).toEqual({ physical: 1, reserved: 0, available: 1 });
    expect(binRow(b1, rackB)).toEqual({ physical: 3, reserved: 0, available: 3 });

    const del = await request(app).delete(`/api/invoices/${invoice}`).set('Cookie', cookie);
    expect(del.status).toBe(200);
    expect(binRow(b1, rackA)).toEqual({ physical: 4, reserved: 3, available: 1 });
    expect(binRow(b1, rackB)).toEqual({ physical: 6, reserved: 3, available: 3 });

    const res = await request(app).post(`/api/invoices/${invoice}/restore`).set('Cookie', cookie).send({});
    expect(res.status).toBe(200);

    // Back to the sold state, per bin, with nothing in DEFAULT.
    expect(binRow(b1, rackA)).toEqual({ physical: 1, reserved: 0, available: 1 });
    expect(binRow(b1, rackB)).toEqual({ physical: 3, reserved: 0, available: 3 });
    expect(binRow(b1, defaultLocation(warehouseA))).toEqual({ physical: 0, reserved: 0, available: 0 });
    expect(reservationRow(reservation.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
    expectHeaderMatchesChildren(reservation.id);
  });
});

// ── 15. invoice edit keeps the reservation link ──

/**
 * GLM review of fa84cf61 (MEDIUM-1): the edit path reversed stock and re-created
 * the lines with no reservation_id, then consumed FIFO. The reservation stayed
 * ACTIVE after the reopen and was never taken again, so the bin ended up
 * over-reserved, and the re-created line was orphaned from its reservation.
 * Edit must relink the line and re-consume the reservation exactly once.
 */
describe('Finding 15: an edit relinks the reservation', () => {
  it('keeps the link and re-consumes the reservation exactly once', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R edit-link ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 10, 40, cookie, '2026-10-01');
    const [b1] = batchIdsOf(item, warehouseA);
    const loc = defaultLocation(warehouseA);

    const reservation = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 6,
      reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Confirmed'), reference_line_id: 1,
      bins: [{ batch_id: b1, location_id: loc, quantity: 6 }],
    }, db);

    expect(await sell(item, 6, 'el-1', reservation.id)).toBe(201);
    const invoice = lastInvoiceId();

    const res = await request(app)
      .put(`/api/invoices/${invoice}`)
      .set('Cookie', cookie)
      .send({
        customer_id: customerId,
        invoice_date: AS_OF,
        items: [{ item_id: item, quantity: 6, unit_price: 50, tax_rate: 0 }],
        warehouse_id: warehouseA,
      });
    expect(res.status).toBe(200);

    // The re-created line still points at the reservation - no orphan.
    const linked = db.prepare('SELECT reservation_id FROM invoice_items WHERE invoice_id = ?')
      .all(invoice) as Array<{ reservation_id: number | null }>;
    expect(linked.length).toBe(1);
    expect(linked[0].reservation_id).toBe(reservation.id);

    // Sold 6 again: the reserve is fully consumed, not left ACTIVE on top.
    expect(reservationRow(reservation.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
    expect(binRow(b1, loc)).toEqual({ physical: 4, reserved: 0, available: 4 });
    expectHeaderMatchesChildren(reservation.id);
  });
});

// ── 16. LOW-2: duplicate create after a partial sale ──

/**
 * GLM LOW-2 asked whether the duplicate-create signature stays correct once a
 * partial sale has drained part of a reservation. After a partial sale the row
 * is still ACTIVE with a smaller quantity and fewer live child rows, so a
 * duplicate create that repeats the ORIGINAL bins[] must not silently "match"
 * and hand back a reservation that no longer holds those bins.
 */
describe('Finding 16: duplicate create after a partial sale', () => {
  it('rejects a duplicate create that repeats the pre-sale bins', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R dup-partial ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 6, 40, cookie, '2026-10-01');
    const [b1] = batchIdsOf(item, warehouseA);
    const loc = defaultLocation(warehouseA);
    const soNo = seedSalesOrder('Confirmed');
    const bins = [{ batch_id: b1, location_id: loc, quantity: 4 }];

    const reservation = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 4,
      reference_doctype: 'SALES_ORDER', reference_docno: soNo, reference_line_id: 1,
      bins,
    }, db);

    expect(await sell(item, 2, 'dp-1', reservation.id)).toBe(201);
    expect(reservationRow(reservation.id)).toEqual({ status: 'ACTIVE', quantity_reserved: 2 });

    // Repeating the ORIGINAL 4 is a conflict, not a match: the live row holds 2.
    expect(() => StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 4,
      reference_doctype: 'SALES_ORDER', reference_docno: soNo, reference_line_id: 1,
      bins,
    }, db)).toThrow(expect.objectContaining({ status: 409 }));

    // Repeating the LIVE 2 is the idempotent duplicate and returns the row.
    const again = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 2,
      reference_doctype: 'SALES_ORDER', reference_docno: soNo, reference_line_id: 1,
      bins: [{ batch_id: b1, location_id: loc, quantity: 2 }],
    }, db);
    expect(again.id).toBe(reservation.id);
    expect(reservationRow(reservation.id)).toEqual({ status: 'ACTIVE', quantity_reserved: 2 });
  });
});

// ── 17. NEW-1: two lines of one item, distinct reservations ──

/**
 * GLM round 2 (NEW-1): the edit relink map was keyed by item_id, so two invoice
 * lines for the SAME item backed by DIFFERENT reservations collapsed onto the
 * last one written. Both re-created lines then drained that single reservation,
 * which asked it for more than it held and returned 400 - and on a shape where
 * the quantities happened to fit, it would silently consume the wrong
 * reservation twice and leave the other ACTIVE. The mapping must be per line.
 */
describe('Finding 17: an edit keeps each line on its own reservation', () => {
  it('relinks two same-item lines to their own reservations', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R two-lines ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 10, 40, cookie, '2026-10-01');
    const [b1] = batchIdsOf(item, warehouseA);
    const loc = defaultLocation(warehouseA);

    const r1 = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 3,
      reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Confirmed'), reference_line_id: 1,
      bins: [{ batch_id: b1, location_id: loc, quantity: 3 }],
    }, db);
    const r2 = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 3,
      reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Confirmed'), reference_line_id: 1,
      bins: [{ batch_id: b1, location_id: loc, quantity: 3 }],
    }, db);

    // One invoice, two lines of the same item, one reservation each.
    const create = await request(app)
      .post('/api/invoices')
      .set('Cookie', cookie)
      .set('Idempotency-Key', nextIdemKey('s1r-two-lines'))
      .send({
        customer_id: customerId,
        invoice_date: AS_OF,
        warehouse_id: warehouseA,
        items: [
          { item_id: item, quantity: 3, unit_price: 50, tax_rate: 0, reservation_id: r1.id },
          { item_id: item, quantity: 3, unit_price: 50, tax_rate: 0, reservation_id: r2.id },
        ],
      });
    expect(create.status).toBe(201);
    const invoice = lastInvoiceId();
    expect(reservationRow(r1.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
    expect(reservationRow(r2.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });

    // Edit the same two lines. Both reopens fire, so both are ACTIVE again and
    // each must be taken by its OWN line, once.
    const res = await request(app)
      .put(`/api/invoices/${invoice}`)
      .set('Cookie', cookie)
      .send({
        customer_id: customerId,
        invoice_date: AS_OF,
        warehouse_id: warehouseA,
        items: [
          // Each line resends its own id; the approved identity for an edit.
          { id: lineIdsOf(invoice)[0], item_id: item, quantity: 3, unit_price: 50, tax_rate: 0 },
          { id: lineIdsOf(invoice)[1], item_id: item, quantity: 3, unit_price: 50, tax_rate: 0 },
        ],
      });
    expect(res.status).toBe(200);

    const linked = db.prepare('SELECT reservation_id FROM invoice_items WHERE invoice_id = ? ORDER BY id')
      .all(invoice) as Array<{ reservation_id: number | null }>;
    expect(linked.length).toBe(2);
    expect(linked.map((l) => l.reservation_id).sort()).toEqual([r1.id, r2.id].sort());

    // Each reservation consumed exactly once, neither left ACTIVE on top.
    expect(reservationRow(r1.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
    expect(reservationRow(r2.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
    expect(binRow(b1, loc)).toEqual({ physical: 4, reserved: 0, available: 4 });
    expectHeaderMatchesChildren(r1.id);
    expectHeaderMatchesChildren(r2.id);
  });
});

// ── 18. NEW-3: a return restocks the bin the stock was sold from ──

/**
 * GLM round 2 (NEW-3): the return path built its reversal items without line
 * ids or ledger draws, so reverseStockForItems fell back to the warehouse
 * DEFAULT. Stock sold from a rack came back to DEFAULT: the rack stayed empty
 * and a bin that never held the goods gained them.
 */
describe('Finding 18: a return restocks the sold bin', () => {
  it('returns rack stock to the rack, leaving DEFAULT untouched', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R return-rack ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 10, 40, cookie, '2026-10-01');
    const [b1] = batchIdsOf(item, warehouseA);
    const rack = rackLocation(warehouseA, `R-RET-${Date.now()}`);
    moveToRack(b1, warehouseA, rack, 10);
    const def = defaultLocation(warehouseA);

    const reservation = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 4,
      reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Confirmed'), reference_line_id: 1,
      bins: [{ batch_id: b1, location_id: rack, quantity: 4 }],
    }, db);

    expect(await sell(item, 4, 'rt-1', reservation.id)).toBe(201);
    const invoice = lastInvoiceId();
    expect(binRow(b1, rack)).toEqual({ physical: 6, reserved: 0, available: 6 });

    const lineId = (db.prepare('SELECT id FROM invoice_items WHERE invoice_id = ? ORDER BY id')
      .get(invoice) as { id: number }).id;
    const res = await request(app)
      .post(`/api/invoices/${invoice}/return`)
      .set('Cookie', cookie)
      .set('Idempotency-Key', nextIdemKey('s1r-return'))
      .send({ items: [{ invoice_item_id: lineId, return_quantity: 2 }], reason: 'S1R return to rack' });
    expect(res.status).toBe(200);

    // The 2 returned units go back to the rack they were sold from.
    expect(binRow(b1, rack)).toEqual({ physical: 8, reserved: 0, available: 8 });
    expect(binRow(b1, def)).toEqual({ physical: 0, reserved: 0, available: 0 });
  });
});

// ── 19. NEW-2 (characterization only, behaviour NOT changed) ──

/**
 * GLM round 2 (NEW-2): changing a reserved invoice line to a DIFFERENT item
 * leaves the old reservation ACTIVE and unlinked. This test documents the
 * CURRENT behaviour so the decision Gull makes is recorded against a fact, not
 * against an assumption. It asserts today's outcome deliberately - when Gull
 * picks an option in audit/DECISIONS.md, flip these assertions.
 */
describe('Finding 19: item change on a reserved line (superseded by Finding 25)', () => {
  it('now RELEASES the old reservation instead of leaving it ACTIVE', async () => {
    setFeatureEnabled(db, FLAG, true);
    const itemA = await createItem(`S1R switch-a ${Date.now()}`, cookie);
    const itemB = await createItem(`S1R switch-b ${Date.now()}`, cookie);
    await purchaseStock(itemA, warehouseA, 5, 40, cookie, '2026-10-01');
    await purchaseStock(itemB, warehouseA, 5, 45, cookie, '2026-10-01');
    const [bA] = batchIdsOf(itemA, warehouseA);
    const loc = defaultLocation(warehouseA);

    const reservation = StockReservationModel.create({
      item_id: itemA, warehouse_id: warehouseA, quantity_reserved: 3,
      reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Confirmed'), reference_line_id: 1,
      bins: [{ batch_id: bA, location_id: loc, quantity: 3 }],
    }, db);

    expect(await sell(itemA, 3, 'sw-1', reservation.id)).toBe(201);
    const invoice = lastInvoiceId();
    expect(reservationRow(reservation.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });

    const res = await request(app)
      .put(`/api/invoices/${invoice}`)
      .set('Cookie', cookie)
      .send({
        customer_id: customerId,
        invoice_date: AS_OF,
        warehouse_id: warehouseA,
        items: [{ item_id: itemB, quantity: 3, unit_price: 50, tax_rate: 0 }],
      });
    expect(res.status).toBe(200);

    // This test pinned the OLD stranded hold (ACTIVE holding 3, bin 5/3/2,
    // available 2 with nothing owed). Gull approved Option 1 in
    // audit/DECISIONS.md, so the hold is now RELEASED and the bin is whole.
    // Kept rather than deleted: it is the same scenario, read the other way.
    expect(reservationRow(reservation.id)).toEqual({ status: 'RELEASED', quantity_reserved: 0 });
    expect(binRow(bA, loc)).toEqual({ physical: 5, reserved: 0, available: 5 });
    const linked = db.prepare('SELECT reservation_id FROM invoice_items WHERE invoice_id = ? ORDER BY id')
      .all(invoice) as Array<{ reservation_id: number | null }>;
    expect(linked.map((l) => l.reservation_id)).toEqual([null]);

    // Item B's own sale is unaffected - the two items never mix.
    const [bB] = batchIdsOf(itemB, warehouseA);
    expect(binRow(bB, loc)).toEqual({ physical: 2, reserved: 0, available: 2 });
  });
});

// ── 20. NEW-4: reordered same-item lines with unequal reservations ──

/**
 * GLM round 3 of 5c08286b: the per-item queue still paired reservations by
 * ARRAY POSITION. Swapping two same-item lines whose reservations hold
 * different quantities hands the larger line the smaller reservation, which
 * overdraws it and returns 400. With equal quantities it does not fail at all -
 * it silently links each line to the other's reservation. Neither is
 * acceptable, so the match must use the reservation_id the client sends, or
 * another durable line identity, never the position.
 */
describe('Finding 20: reordered same-item lines pair by reservation, not position', () => {
  it('keeps each line on its own reservation when the order is swapped', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R reorder ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 10, 40, cookie, '2026-10-01');
    const [b1] = batchIdsOf(item, warehouseA);
    const loc = defaultLocation(warehouseA);

    const small = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 2,
      reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Confirmed'), reference_line_id: 1,
      bins: [{ batch_id: b1, location_id: loc, quantity: 2 }],
    }, db);
    const large = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 3,
      reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Confirmed'), reference_line_id: 1,
      bins: [{ batch_id: b1, location_id: loc, quantity: 3 }],
    }, db);

    // Sold in ONE order: the 2-unit line first, then the 3-unit line.
    const create = await request(app)
      .post('/api/invoices')
      .set('Cookie', cookie)
      .set('Idempotency-Key', nextIdemKey('s1r-reorder'))
      .send({
        customer_id: customerId,
        invoice_date: AS_OF,
        warehouse_id: warehouseA,
        items: [
          { item_id: item, quantity: 2, unit_price: 50, tax_rate: 0, reservation_id: small.id },
          { item_id: item, quantity: 3, unit_price: 50, tax_rate: 0, reservation_id: large.id },
        ],
      });
    expect(create.status).toBe(201);
    const invoice = lastInvoiceId();

    // Edit with the SAME two lines in the OPPOSITE order, each still naming its
    // own reservation. The client is explicit, so there is nothing to infer.
    const res = await request(app)
      .put(`/api/invoices/${invoice}`)
      .set('Cookie', cookie)
      .send({
        customer_id: customerId,
        invoice_date: AS_OF,
        warehouse_id: warehouseA,
        items: [
          // Ids travel with their lines, so the swap is unambiguous.
          { id: lineIdsOf(invoice)[1], item_id: item, quantity: 3, unit_price: 50, tax_rate: 0, reservation_id: large.id },
          { id: lineIdsOf(invoice)[0], item_id: item, quantity: 2, unit_price: 50, tax_rate: 0, reservation_id: small.id },
        ],
      });
    expect(res.status).toBe(200);

    // Each line still points at the reservation it names, in the new order.
    const linked = db.prepare('SELECT quantity, reservation_id FROM invoice_items WHERE invoice_id = ? ORDER BY id')
      .all(invoice) as Array<{ quantity: number; reservation_id: number | null }>;
    expect(linked).toEqual([
      { quantity: 3, reservation_id: large.id },
      { quantity: 2, reservation_id: small.id },
    ]);

    expect(reservationRow(small.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
    expect(reservationRow(large.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
    expect(binRow(b1, loc)).toEqual({ physical: 5, reserved: 0, available: 5 });
    expectHeaderMatchesChildren(small.id);
    expectHeaderMatchesChildren(large.id);
  });
});

describe('Finding 21: equal-quantity reorder must not swap the links', () => {
  it('links each line to the reservation it names, not its neighbours\'', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R equal ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 10, 40, cookie, '2026-10-01');
    const [b1] = batchIdsOf(item, warehouseA);
    const loc = defaultLocation(warehouseA);

    // Same quantity on both lines, so a positional swap CANNOT fail - it just
    // silently links each line to the other's reservation. This is the case
    // GLM warned about and the reason equality is not a safety net.
    const r1 = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 2,
      reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Confirmed'), reference_line_id: 1,
      bins: [{ batch_id: b1, location_id: loc, quantity: 2 }],
    }, db);
    const r2 = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 2,
      reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Confirmed'), reference_line_id: 1,
      bins: [{ batch_id: b1, location_id: loc, quantity: 2 }],
    }, db);

    const create = await request(app)
      .post('/api/invoices')
      .set('Cookie', cookie)
      .set('Idempotency-Key', nextIdemKey('s1r-equal'))
      .send({
        customer_id: customerId, invoice_date: AS_OF, warehouse_id: warehouseA,
        items: [
          { item_id: item, quantity: 2, unit_price: 50, tax_rate: 0, reservation_id: r1.id },
          { item_id: item, quantity: 2, unit_price: 50, tax_rate: 0, reservation_id: r2.id },
        ],
      });
    expect(create.status).toBe(201);
    const invoice = lastInvoiceId();

    // Swap the two lines. Both stay 2 units, so nothing can fail on quantity.
    const res = await request(app)
      .put(`/api/invoices/${invoice}`)
      .set('Cookie', cookie)
      .send({
        customer_id: customerId, invoice_date: AS_OF, warehouse_id: warehouseA,
        items: [
          { id: lineIdsOf(invoice)[1], item_id: item, quantity: 2, unit_price: 50, tax_rate: 0, reservation_id: r2.id },
          { id: lineIdsOf(invoice)[0], item_id: item, quantity: 2, unit_price: 50, tax_rate: 0, reservation_id: r1.id },
        ],
      });
    expect(res.status).toBe(200);

    const linked = db.prepare('SELECT reservation_id FROM invoice_items WHERE invoice_id = ? ORDER BY id')
      .all(invoice) as Array<{ reservation_id: number | null }>;
    expect(linked.map((l) => l.reservation_id)).toEqual([r2.id, r1.id]);
    expect(reservationRow(r1.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
    expect(reservationRow(r2.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
    expect(binRow(b1, loc)).toEqual({ physical: 6, reserved: 0, available: 6 });
  });
});

// ── 22. line-count change (investigation only, behaviour NOT changed) ──

/**
 * GLM round 3 asked for the line-count scenario reproduced concretely before
 * any behaviour change. This test DRIVES the scenarios and prints the state; it
 * asserts only what is currently true, so it documents the defects instead of
 * fixing them. Fill in the expectations once Gull decides the semantics.
 */
describe('Finding 22: an edit changes the NUMBER of lines', () => {
  async function setup(tag: string) {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R count ${tag} ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 10, 40, cookie, '2026-10-01');
    const [b1] = batchIdsOf(item, warehouseA);
    const loc = defaultLocation(warehouseA);
    return { item, b1, loc };
  }

  it('a) two reserved lines collapsed into one line', async () => {
    const { item, b1, loc } = await setup('a');
    const r1 = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 2,
      reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Confirmed'), reference_line_id: 1,
      bins: [{ batch_id: b1, location_id: loc, quantity: 2 }],
    }, db);
    const r2 = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 2,
      reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Confirmed'), reference_line_id: 1,
      bins: [{ batch_id: b1, location_id: loc, quantity: 2 }],
    }, db);
    const create = await request(app).post('/api/invoices').set('Cookie', cookie)
      .set('Idempotency-Key', nextIdemKey('s1r-count-a'))
      .send({ customer_id: customerId, invoice_date: AS_OF, warehouse_id: warehouseA, items: [
        { item_id: item, quantity: 2, unit_price: 50, tax_rate: 0, reservation_id: r1.id },
        { item_id: item, quantity: 2, unit_price: 50, tax_rate: 0, reservation_id: r2.id },
      ] });
    expect(create.status).toBe(201);
    const invoice = lastInvoiceId();

    // Collapse both lines into ONE line of 4, keeping only the first id. The
    // approved rule says one line can never consume two reservations, so this
    // is refused with 409 rather than the old 400 about "sellable stock".
    const [firstLine] = lineIdsOf(invoice);
    const res = await request(app).put(`/api/invoices/${invoice}`).set('Cookie', cookie)
      .send({ customer_id: customerId, invoice_date: AS_OF, warehouse_id: warehouseA, items: [
        { id: firstLine, item_id: item, quantity: 4, unit_price: 50, tax_rate: 0 },
      ] });
    expect(res.status).toBe(409);
    // The whole edit is one transaction, so the failed edit rolls back
    // completely: the invoice and both reservations stay exactly as sold.
    const linkedA = db.prepare('SELECT reservation_id FROM invoice_items WHERE invoice_id = ? ORDER BY id')
      .all(invoice) as Array<{ reservation_id: number | null }>;
    expect(linkedA.map((l) => l.reservation_id)).toEqual([r1.id, r2.id]);
    expect(reservationRow(r1.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
    expect(reservationRow(r2.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
    expect(binRow(b1, loc)).toEqual({ physical: 6, reserved: 0, available: 6 });
  });

  it('b) one reserved line split into two lines', async () => {
    const { item, b1, loc } = await setup('b');
    const r1 = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 4,
      reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Confirmed'), reference_line_id: 1,
      bins: [{ batch_id: b1, location_id: loc, quantity: 4 }],
    }, db);
    const create = await request(app).post('/api/invoices').set('Cookie', cookie)
      .set('Idempotency-Key', nextIdemKey('s1r-count-b'))
      .send({ customer_id: customerId, invoice_date: AS_OF, warehouse_id: warehouseA, items: [
        { item_id: item, quantity: 4, unit_price: 50, tax_rate: 0, reservation_id: r1.id },
      ] });
    expect(create.status).toBe(201);
    const invoice = lastInvoiceId();

    // Split into two lines of 2. Both name the same reservation, which is what
    // the approved rule allows: one reservation divides across the resulting
    // lines. (Finding 26a drives the same thing end to end.)
    const [lineOne] = lineIdsOf(invoice);
    const res = await request(app).put(`/api/invoices/${invoice}`).set('Cookie', cookie)
      .send({ customer_id: customerId, invoice_date: AS_OF, warehouse_id: warehouseA, items: [
        { id: lineOne, item_id: item, quantity: 2, unit_price: 50, tax_rate: 0, reservation_id: r1.id },
        { item_id: item, quantity: 2, unit_price: 50, tax_rate: 0, reservation_id: r1.id },
      ] });
    // Was: MEASURED stranded hold - only the first line took the reservation and
    // r1 kept 2 held that nothing owed. Now the split divides r1 and consumes it
    // once, so nothing is left reserved.
    expect(res.status).toBe(200);
    expect(reservationRow(r1.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
    expect(binRow(b1, loc)).toEqual({ physical: 6, reserved: 0, available: 6 });
    const splitLinked = db.prepare('SELECT reservation_id FROM invoice_items WHERE invoice_id = ? ORDER BY id')
      .all(invoice) as Array<{ reservation_id: number | null }>;
    expect(splitLinked.map((l) => l.reservation_id)).toEqual([r1.id, r1.id]);
  });

  it('c) an unreserved line has no reservation to relink', async () => {
    const { item, b1, loc } = await setup('c');
    const create = await request(app).post('/api/invoices').set('Cookie', cookie)
      .set('Idempotency-Key', nextIdemKey('s1r-count-c'))
      .send({ customer_id: customerId, invoice_date: AS_OF, warehouse_id: warehouseA, items: [
        { item_id: item, quantity: 3, unit_price: 50, tax_rate: 0 },
      ] });
    expect(create.status).toBe(201);
    const invoice = lastInvoiceId();

    const res = await request(app).put(`/api/invoices/${invoice}`).set('Cookie', cookie)
      .send({ customer_id: customerId, invoice_date: AS_OF, warehouse_id: warehouseA, items: [
        { item_id: item, quantity: 3, unit_price: 50, tax_rate: 0 },
      ] });
    // An unreserved line is the control: nothing to relink, and the reverse
    // plus re-consume round-trips exactly.
    expect(res.status).toBe(200);
    expect(binRow(b1, loc)).toEqual({ physical: 7, reserved: 0, available: 7 });
  });
});

// ── 23. partial return of a line sold from two bins (analysis only) ──

/**
 * GLM round 3 finding, unreproduced until now: a line sold from TWO bins returns
 * a PARTIAL quantity, and the return is proportional, so it cannot say which bin
 * the customer physically brought back. This test DRIVES that case and records
 * the current split. The allocation rule is a product decision and is NOT
 * changed here - the assertions document today's behaviour, and the options are
 * written up for Gull.
 */
describe('Finding 23: partial return of one line sold from two bins', () => {
  it('cannot be exact today: an unreserved sale records no per-bin draw', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R two-bin ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 10, 40, cookie, AS_OF);
    const [b1] = batchIdsOf(item, warehouseA);
    const rack = rackLocation(warehouseA, `S1R-TWOBIN-${Date.now()}`);
    const dl = defaultLocation(warehouseA);

    // ONE batch, 4 on the rack and 6 in DEFAULT.
    moveToRack(b1, warehouseA, rack, 4);
    const create = await request(app).post('/api/invoices').set('Cookie', cookie)
      .set('Idempotency-Key', nextIdemKey('s1r-twobin'))
      .send({ customer_id: customerId, invoice_date: AS_OF, warehouse_id: warehouseA, items: [
        { item_id: item, quantity: 8, unit_price: 50, tax_rate: 0 },
      ] });
    expect(create.status).toBe(201);
    const invoice = lastInvoiceId();
    // The sale really did span both bins.
    const rackLeft = binRow(b1, rack).physical;
    const dlLeft = binRow(b1, dl).physical;
    expect({ rackLeft, dlLeft }).toEqual({ rackLeft: 2, dlLeft: 0 });

    // ROOT CAUSE, measured: the per-bin ledger is written ONLY for a
    // reservation-backed line, so a plain FIFO sale has no record of which bin
    // each unit came from. A partial return can therefore only be split by
    // re-walking the batch's bins, never by replaying what actually happened.
    const lineId = (db.prepare('SELECT id FROM invoice_items WHERE invoice_id = ?').get(invoice) as { id: number }).id;
    const draws = db.prepare('SELECT * FROM invoice_item_bin_consumption WHERE invoice_item_id = ?').all(lineId);
    expect(draws).toEqual([]);

    // A partial return of 2 goes to ONE bin - whichever the walk reaches first -
    // and DEFAULT gained the 2 even though the sale drew mostly from it. This is
    // the behaviour under discussion; it is recorded, NOT endorsed and NOT
    // changed, pending Gull's decision on allocation.
    const ret = await request(app).post(`/api/invoices/${invoice}/return`).set('Cookie', cookie)
      .set('Idempotency-Key', nextIdemKey('s1r-twobin-ret'))
      .send({ items: [{ invoice_item_id: lineId, return_quantity: 2 }], reason: 'two-bin partial' });
    expect(ret.status).toBe(200);
    const returned = { dl: binRow(b1, dl).physical, rack: binRow(b1, rack).physical };
    expect(returned).toEqual({ dl: 2, rack: 2 });
  });
});

// ── 24. the detail read must carry reservation_id (GLM: Flutter is blocked) ──

/**
 * GLM is blocked on the Flutter fix because GET /api/invoices/:id never
 * returned reservation_id, so an edit form cannot resend the link that NEW-4
 * now matches on. Without it the client falls back to the positional queue -
 * the very defect Finding 20 exists to catch - so the field is not cosmetic:
 * it is what makes the round trip of line identity possible at all.
 */
describe('Finding 24: GET /api/invoices/:id exposes each line reservation', () => {
  it('returns the right reservation_id for two same-item lines, and null when unreserved', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R detail ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 10, 40, cookie, AS_OF);
    const [b1] = batchIdsOf(item, warehouseA);
    const loc = defaultLocation(warehouseA);

    const r1 = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 2,
      reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Confirmed'), reference_line_id: 1,
      bins: [{ batch_id: b1, location_id: loc, quantity: 2 }],
    }, db);
    // Same item, different reservation, different quantity: if the read ever
    // returned a positional or item-based guess, these two could not be told
    // apart - which is exactly why the assertions name each one.
    const r2 = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: 3,
      reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Confirmed'), reference_line_id: 1,
      bins: [{ batch_id: b1, location_id: loc, quantity: 3 }],
    }, db);

    const create = await request(app)
      .post('/api/invoices')
      .set('Cookie', cookie)
      .set('Idempotency-Key', nextIdemKey('s1r-detail'))
      .send({
        customer_id: customerId,
        invoice_date: AS_OF,
        warehouse_id: warehouseA,
        items: [
          { item_id: item, quantity: 2, unit_price: 50, tax_rate: 0, reservation_id: r1.id },
          { item_id: item, quantity: 3, unit_price: 50, tax_rate: 0, reservation_id: r2.id },
          { item_id: item, quantity: 1, unit_price: 50, tax_rate: 0 },
        ],
      });
    expect(create.status).toBe(201);
    const invoice = lastInvoiceId();

    const res = await request(app).get(`/api/invoices/${invoice}`).set('Cookie', cookie);
    expect(res.status).toBe(200);
    const items = res.body.items as Array<{ quantity: number; reservation_id: number | null }>;
    expect(items).toHaveLength(3);

    // Each line carries its own link, matched by quantity so the assertion
    // proves identity rather than position. The third line was never reserved
    // and must stay null - a legacy/unreserved line is not an error.
    const byQty = items.map((i) => ({ quantity: i.quantity, reservation_id: i.reservation_id }))
      .sort((a, b) => a.quantity - b.quantity);
    expect(byQty).toEqual([
      { quantity: 1, reservation_id: null },
      { quantity: 2, reservation_id: r1.id },
      { quantity: 3, reservation_id: r2.id },
    ]);
    // The field must be PRESENT, not merely undefined on every row: an absent
    // key and a null value are the same thing to some serializers but not to a
    // client that checks `hasOwnProperty`.
    for (const line of items) {
      expect(Object.prototype.hasOwnProperty.call(line, 'reservation_id')).toBe(true);
    }

    // Line order must be stable between two reads, or the client cannot pair
    // its rows with its own state.
    const again = await request(app).get(`/api/invoices/${invoice}`).set('Cookie', cookie);
    expect((again.body.items as Array<{ id: number }>).map((i) => i.id))
      .toEqual((items as unknown as Array<{ id: number }>).map((i) => i.id));
  });
});

// ── 25. NEW-2, Option 1: an item change RELEASES the old reservation ──

/**
 * Approved product rule (NEW-2, Option 1 in audit/DECISIONS.md): when an edit
 * changes a reserved line to a DIFFERENT item, the old reservation is RELEASED,
 * not reopened. Reopening it (the behaviour Finding 19 pins) left the units held
 * on an invoice that no longer contains the item - a stranded hold. Changing the
 * line back does NOT reuse the released reservation; the user must reserve again,
 * because release is terminal.
 */
describe('Finding 25: changing a reserved line to another item releases it', () => {
  async function setup(tag: string, orderStatus = 'Confirmed') {
    setFeatureEnabled(db, FLAG, true);
    const itemA = await createItem(`S1R rl-a ${tag} ${Date.now()}`, cookie);
    const itemB = await createItem(`S1R rl-b ${tag} ${Date.now()}`, cookie);
    await purchaseStock(itemA, warehouseA, 5, 40, cookie, AS_OF);
    await purchaseStock(itemB, warehouseA, 5, 45, cookie, AS_OF);
    const [bA] = batchIdsOf(itemA, warehouseA);
    const [bB] = batchIdsOf(itemB, warehouseA);
    const loc = defaultLocation(warehouseA);
    const reservation = StockReservationModel.create({
      item_id: itemA, warehouse_id: warehouseA, quantity_reserved: 3,
      reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder(orderStatus), reference_line_id: 1,
      bins: [{ batch_id: bA, location_id: loc, quantity: 3 }],
    }, db);
    expect(await sell(itemA, 3, `rl-${tag}`, reservation.id)).toBe(201);
    expect(reservationRow(reservation.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
    return { itemA, itemB, bA, bB, loc, reservation };
  }

  function editTo(invoice: number, itemId: number) {
    return request(app).put(`/api/invoices/${invoice}`).set('Cookie', cookie)
      .send({ customer_id: customerId, invoice_date: AS_OF, warehouse_id: warehouseA, items: [
        { item_id: itemId, quantity: 3, unit_price: 50, tax_rate: 0 },
      ] });
  }

  it('a) releases the old reservation and frees its bin', async () => {
    const { itemB, bA, bB, loc, reservation } = await setup('a');
    const invoice = lastInvoiceId();

    expect((await editTo(invoice, itemB)).status).toBe(200);

    // The old reservation is RELEASED and holds nothing.
    expect(reservationRow(reservation.id)).toEqual({ status: 'RELEASED', quantity_reserved: 0 });
    // Its bin is free again: the 3 units are back and not held.
    expect(binRow(bA, loc)).toEqual({ physical: 5, reserved: 0, available: 5 });
    expect(db.prepare('SELECT * FROM stock_reservation_bins WHERE reservation_id = ?').all(reservation.id)).toEqual([]);
    // No invoice line points at it.
    const linked = db.prepare('SELECT reservation_id FROM invoice_items WHERE invoice_id = ?').all(invoice) as Array<{ reservation_id: number | null }>;
    expect(linked).toEqual([{ reservation_id: null }]);
    // The NEW item is correctly accounted: 3 sold, 2 left, nothing held.
    expect(binRow(bB, loc)).toEqual({ physical: 2, reserved: 0, available: 2 });
  });

  it('b) changing the line BACK does not reuse the released reservation', async () => {
    const { itemA, itemB, loc, reservation } = await setup('b');
    const invoice = lastInvoiceId();

    expect((await editTo(invoice, itemB)).status).toBe(200);
    expect(reservationRow(reservation.id)).toEqual({ status: 'RELEASED', quantity_reserved: 0 });

    // Change back to item A. Release is terminal, so this must NOT resurrect it -
    // the sale is unreserved and draws from free stock instead.
    expect((await editTo(invoice, itemA)).status).toBe(200);
    expect(reservationRow(reservation.id)).toEqual({ status: 'RELEASED', quantity_reserved: 0 });
    const [bA] = batchIdsOf(itemA, warehouseA);
    expect(binRow(bA, loc)).toEqual({ physical: 2, reserved: 0, available: 2 });
    const linked = db.prepare('SELECT reservation_id FROM invoice_items WHERE invoice_id = ?').all(invoice) as Array<{ reservation_id: number | null }>;
    expect(linked).toEqual([{ reservation_id: null }]);
  });

  it('c) a cancelled source order releases the hold instead of reopening it', async () => {
    const { itemB, bA, loc, reservation } = await setup('c', 'Cancelled');
    const invoice = lastInvoiceId();

    expect((await editTo(invoice, itemB)).status).toBe(200);

    // The cancelled-order rule already said "do not reopen". Releasing is the
    // stronger form of the same answer: the hold must not survive at all.
    expect(reservationRow(reservation.id)).toEqual({ status: 'RELEASED', quantity_reserved: 0 });
    expect(binRow(bA, loc)).toEqual({ physical: 5, reserved: 0, available: 5 });
  });

  it('d) an unreleased line keeps its reservation (no accidental release)', async () => {
    const { itemA, bA, loc, reservation } = await setup('d');
    const invoice = lastInvoiceId();

    // SAME item, same quantity: the reservation is unchanged, so it must stay
    // CONSUMED and linked - a release here would silently unlink a good sale.
    const res = await request(app).put(`/api/invoices/${invoice}`).set('Cookie', cookie)
      .send({ customer_id: customerId, invoice_date: AS_OF, warehouse_id: warehouseA, items: [
        { item_id: itemA, quantity: 3, unit_price: 55, tax_rate: 0, reservation_id: reservation.id },
      ] });
    expect(reservationRow(reservation.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
    expect(binRow(bA, loc)).toEqual({ physical: 2, reserved: 0, available: 2 });
    const linked = db.prepare('SELECT reservation_id FROM invoice_items WHERE invoice_id = ?').all(invoice) as Array<{ reservation_id: number | null }>;
    expect(linked).toEqual([{ reservation_id: reservation.id }]);
  });
});

// ── 26. line-count edits: split one reservation, reject a collapse ──

/**
 * Approved rule (audit/DECISIONS.md): one reservation may SPLIT across several
 * resulting lines - divide its reserved quantity and consume each part exactly
 * once - but an edit that would force ONE line to consume several distinct
 * reservations is rejected with 409, and the whole edit rolls back.
 *
 * Both halves need the association to be keyed by durable IDs. Position is not
 * an identity here: a line may be reordered, and one reservation now legitimately
 * appears on several lines, so a per-item queue and a "next reservation" walk
 * are both wrong. Finding 26e covers the combined case.
 */
describe('Finding 26: line-count edits', () => {
  async function setup(tag: string, reservedQty: number[], orderStatus = 'Confirmed') {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R lc ${tag} ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 20, 40, cookie, AS_OF);
    const [b] = batchIdsOf(item, warehouseA);
    const loc = defaultLocation(warehouseA);
    const reservations = reservedQty.map((q) => StockReservationModel.create({
      item_id: item, warehouse_id: warehouseA, quantity_reserved: q,
      reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder(orderStatus), reference_line_id: 1,
      bins: [{ batch_id: b, location_id: loc, quantity: q }],
    }, db));
    return { item, b, loc, reservations };
  }

  it('a) splits one 4-unit reservation across two 2-unit lines', async () => {
    const { item, b, loc, reservations } = await setup('split', [4]);
    const r = reservations[0];
    const create = await request(app).post('/api/invoices').set('Cookie', cookie)
      .set('Idempotency-Key', nextIdemKey('s1r-lc-split'))
      .send({ customer_id: customerId, invoice_date: AS_OF, warehouse_id: warehouseA, items: [
        { item_id: item, quantity: 4, unit_price: 50, tax_rate: 0, reservation_id: r.id },
      ] });
    expect(create.status).toBe(201);
    const invoice = lastInvoiceId();

    // Split into two 2-unit lines, BOTH still naming the same reservation.
    const res = await request(app).put(`/api/invoices/${invoice}`).set('Cookie', cookie)
      .send({ customer_id: customerId, invoice_date: AS_OF, warehouse_id: warehouseA, items: [
        // One line keeps the old id; the added line omits it, which is how a
        // split is expressed.
        { id: lineIdsOf(invoice)[0], item_id: item, quantity: 2, unit_price: 50, tax_rate: 0, reservation_id: r.id },
        { item_id: item, quantity: 2, unit_price: 50, tax_rate: 0, reservation_id: r.id },
      ] });
    expect(res.status).toBe(200);

    const linked = db.prepare('SELECT reservation_id FROM invoice_items WHERE invoice_id = ? ORDER BY id')
      .all(invoice) as Array<{ reservation_id: number | null }>;
    expect(linked.map((l) => l.reservation_id)).toEqual([r.id, r.id]);
    // Fully consumed, and NO stranded reserved quantity.
    expect(reservationRow(r.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
    expect(binRow(b, loc)).toEqual({ physical: 16, reserved: 0, available: 16 });
    expectHeaderMatchesChildren(r.id);
  });

  it('b) rejects collapsing two reservations into one line with 409 and no state change', async () => {
    const { item, b, loc, reservations } = await setup('collapse', [2, 2]);
    const [r1, r2] = reservations;
    const create = await request(app).post('/api/invoices').set('Cookie', cookie)
      .set('Idempotency-Key', nextIdemKey('s1r-lc-collapse'))
      .send({ customer_id: customerId, invoice_date: AS_OF, warehouse_id: warehouseA, items: [
        { item_id: item, quantity: 2, unit_price: 50, tax_rate: 0, reservation_id: r1.id },
        { item_id: item, quantity: 2, unit_price: 50, tax_rate: 0, reservation_id: r2.id },
      ] });
    expect(create.status).toBe(201);
    const invoice = lastInvoiceId();
    const before = {
      r1: reservationRow(r1.id), r2: reservationRow(r2.id), bin: binRow(b, loc),
      items: db.prepare('SELECT item_id, quantity, reservation_id FROM invoice_items WHERE invoice_id = ? ORDER BY id').all(invoice),
    };
    expect(before.bin).toEqual({ physical: 16, reserved: 0, available: 16 });

    // Collapse both into ONE 4-unit line that keeps the first line's id and
    // names r1 only - it would have to consume r1 AND r2.
    const res = await request(app).put(`/api/invoices/${invoice}`).set('Cookie', cookie)
      .send({ customer_id: customerId, invoice_date: AS_OF, warehouse_id: warehouseA, items: [
        { id: lineIdsOf(invoice)[0], item_id: item, quantity: 4, unit_price: 50, tax_rate: 0, reservation_id: r1.id },
      ] });
    expect(res.status).toBe(409);
    expect(String(res.body.error)).toMatch(/two reservations|multiple reservations|collapse/i);

    // NOTHING moved: invoice lines, both reservations and the bin are untouched.
    const after = {
      r1: reservationRow(r1.id), r2: reservationRow(r2.id), bin: binRow(b, loc),
      items: db.prepare('SELECT item_id, quantity, reservation_id FROM invoice_items WHERE invoice_id = ? ORDER BY id').all(invoice),
    };
    expect(after).toEqual(before);
  });

  it('c) control: an unreserved line resizes freely', async () => {
    const { item, b, loc } = await setup('plain', []);
    const create = await request(app).post('/api/invoices').set('Cookie', cookie)
      .set('Idempotency-Key', nextIdemKey('s1r-lc-plain'))
      .send({ customer_id: customerId, invoice_date: AS_OF, warehouse_id: warehouseA, items: [
        { item_id: item, quantity: 3, unit_price: 50, tax_rate: 0 },
      ] });
    expect(create.status).toBe(201);
    const invoice = lastInvoiceId();

    const res = await request(app).put(`/api/invoices/${invoice}`).set('Cookie', cookie)
      .send({ customer_id: customerId, invoice_date: AS_OF, warehouse_id: warehouseA, items: [
        { item_id: item, quantity: 1, unit_price: 50, tax_rate: 0 },
        { item_id: item, quantity: 2, unit_price: 50, tax_rate: 0 },
      ] });
    expect(res.status).toBe(200);
    expect(binRow(b, loc)).toEqual({ physical: 17, reserved: 0, available: 17 });
    const linked = db.prepare('SELECT reservation_id FROM invoice_items WHERE invoice_id = ? ORDER BY id')
      .all(invoice) as Array<{ reservation_id: number | null }>;
    expect(linked.map((l) => l.reservation_id)).toEqual([null, null]);
  });

  it('d) splits a reservation while reordering the lines', async () => {
    const { item, b, loc, reservations } = await setup('reorder', [4]);
    const r = reservations[0];
    const create = await request(app).post('/api/invoices').set('Cookie', cookie)
      .set('Idempotency-Key', nextIdemKey('s1r-lc-reorder'))
      .send({ customer_id: customerId, invoice_date: AS_OF, warehouse_id: warehouseA, items: [
        { item_id: item, quantity: 4, unit_price: 50, tax_rate: 0, reservation_id: r.id },
      ] });
    expect(create.status).toBe(201);
    const invoice = lastInvoiceId();

    // THREE lines of unequal size, two of them on the reservation, in a
    // different order than anything the old positional queue could follow.
    const res = await request(app).put(`/api/invoices/${invoice}`).set('Cookie', cookie)
      .send({ customer_id: customerId, invoice_date: AS_OF, warehouse_id: warehouseA, items: [
        { id: lineIdsOf(invoice)[0], item_id: item, quantity: 1, unit_price: 50, tax_rate: 0, reservation_id: r.id },
        { item_id: item, quantity: 3, unit_price: 50, tax_rate: 0, reservation_id: r.id },
        { item_id: item, quantity: 2, unit_price: 50, tax_rate: 0 },
      ] });
    expect(res.status).toBe(200);
    const linked = db.prepare('SELECT quantity, reservation_id FROM invoice_items WHERE invoice_id = ? ORDER BY id')
      .all(invoice) as Array<{ quantity: number; reservation_id: number | null }>;
    expect(linked).toEqual([
      { quantity: 1, reservation_id: r.id },
      { quantity: 3, reservation_id: r.id },
      { quantity: 2, reservation_id: null },
    ]);
    expect(reservationRow(r.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
    // 20 bought - 4 reserved sale - 2 unreserved sale = 14.
    expect(binRow(b, loc)).toEqual({ physical: 14, reserved: 0, available: 14 });
  });

  it('e) combines a split with an item change, leaving no stranded remainder', async () => {
    setFeatureEnabled(db, FLAG, true);
    const other = await createItem(`S1R lc-e-other ${Date.now()}`, cookie);
    await purchaseStock(other, warehouseA, 10, 45, cookie, AS_OF);
    const { item, b, loc, reservations } = await setup('combined', [4]);
    const r = reservations[0];
    const create = await request(app).post('/api/invoices').set('Cookie', cookie)
      .set('Idempotency-Key', nextIdemKey('s1r-lc-combined'))
      .send({ customer_id: customerId, invoice_date: AS_OF, warehouse_id: warehouseA, items: [
        { item_id: item, quantity: 4, unit_price: 50, tax_rate: 0, reservation_id: r.id },
      ] });
    expect(create.status).toBe(201);
    const invoice = lastInvoiceId();

    // Line 1 keeps the item with 2 units on the reservation; line 2 becomes a
    // DIFFERENT item. The approved rule governs this without a new decision: a
    // reservation is divided across the lines that still name it, and any part
    // no line takes must NOT stay held - a 4-unit reservation cut to 2 is the
    // stranded hold again, reached by resizing. So the 2 unused units are a
    // release of the remainder, and line 2 is an ordinary unreserved sale.
    const res = await request(app).put(`/api/invoices/${invoice}`).set('Cookie', cookie)
      .send({ customer_id: customerId, invoice_date: AS_OF, warehouse_id: warehouseA, items: [
        { id: lineIdsOf(invoice)[0], item_id: item, quantity: 2, unit_price: 50, tax_rate: 0, reservation_id: r.id },
        { item_id: other, quantity: 2, unit_price: 60, tax_rate: 0 },
      ] });
    expect(res.status).toBe(200);

    const linked = db.prepare('SELECT quantity, item_id, reservation_id FROM invoice_items WHERE invoice_id = ? ORDER BY id')
      .all(invoice) as Array<{ quantity: number; item_id: number; reservation_id: number | null }>;
    // Line 1 keeps its link; the changed line does not inherit it.
    expect(linked.map((l) => ({ quantity: l.quantity, reservation_id: l.reservation_id })))
      .toEqual([{ quantity: 2, reservation_id: r.id }, { quantity: 2, reservation_id: null }]);
    // r is CONSUMED for the 2 it provided, with NOTHING left reserved.
    expect(reservationRow(r.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
    // Bought 20 for item A: 2 sold from the reservation, 2 not. Nothing held.
    expect(binRow(b, loc)).toEqual({ physical: 18, reserved: 0, available: 18 });
    expectHeaderMatchesChildren(r.id);
    const [bo] = batchIdsOf(other, warehouseA);
    expect(binRow(bo, loc)).toEqual({ physical: 8, reserved: 0, available: 8 });
  });
});

// ── 27. release/reopen must pair by durable ID, not by array position ──

/**
 * GLM HIGH on e390321a. The release-vs-reopen loop paired `oldItems[index]` to
 * `items[index]`. Any edit that reorders lines or deletes a middle line shifts
 * every later index, so a KEPT line was released and a CHANGED line kept a live
 * hold. Both repros below failed for exactly that reason.
 */
describe('Finding 27: release/reopen pairs by reservation id, not position', () => {
  async function twoSameItemLines(tag: string) {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`S1R pair-a ${tag} ${Date.now()}`, cookie);
    const other = await createItem(`S1R pair-b ${tag} ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseA, 20, 40, cookie, AS_OF);
    await purchaseStock(other, warehouseA, 10, 45, cookie, AS_OF);
    const [b] = batchIdsOf(item, warehouseA);
    const [bo] = batchIdsOf(other, warehouseA);
    const loc = defaultLocation(warehouseA);
    // Two reservations for the SAME item: r1 for 2 units, r2 for 3.
    const r1 = StockReservationModel.create({ item_id: item, warehouse_id: warehouseA,
      quantity_reserved: 2, reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Confirmed'),
      reference_line_id: 1, bins: [{ batch_id: b, location_id: loc, quantity: 2 }] }, db);
    const r2 = StockReservationModel.create({ item_id: item, warehouse_id: warehouseA,
      quantity_reserved: 3, reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Confirmed'),
      reference_line_id: 2, bins: [{ batch_id: b, location_id: loc, quantity: 3 }] }, db);
    const create = await request(app).post('/api/invoices').set('Cookie', cookie)
      .set('Idempotency-Key', nextIdemKey(`s1r-pair-${tag}`))
      .send({ customer_id: customerId, invoice_date: AS_OF, warehouse_id: warehouseA, items: [
        { item_id: item, quantity: 2, unit_price: 50, tax_rate: 0, reservation_id: r1.id },
        { item_id: item, quantity: 3, unit_price: 50, tax_rate: 0, reservation_id: r2.id },
      ] });
    expect(create.status).toBe(201);
    return { item, other, b, bo, loc, r1, r2, invoice: lastInvoiceId() };
  }

  it('a) reorder plus item change releases only the changed line\'s reservation', async () => {
    const { item, other, b, bo, loc, r1, r2, invoice } = await twoSameItemLines('reorder');
    // Payload reversed: the CHANGED line (r2 -> item B) comes FIRST, the kept
    // A/r1 line second. Position and identity disagree on purpose.
    const [lineA, lineB] = lineIdsOf(invoice);
    const res = await request(app).put(`/api/invoices/${invoice}`).set('Cookie', cookie)
      .send({ customer_id: customerId, invoice_date: AS_OF, warehouse_id: warehouseA, items: [
        // lineB keeps its id but becomes item B; lineA keeps its id, its item
        // and its own reservation r1. Identity comes from the ids only.
        { id: lineB, item_id: other, quantity: 3, unit_price: 50, tax_rate: 0 },
        { id: lineA, item_id: item, quantity: 2, unit_price: 50, tax_rate: 0, reservation_id: r1.id },
      ] });
    expect(res.status).toBe(200);

    // r1 backs the line that KEPT item A: it must be consumed, not released.
    expect(reservationRow(r1.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
    expectHeaderMatchesChildren(r1.id);
    // r2's line became item B, so r2 is released - nothing held.
    expect(reservationRow(r2.id)).toEqual({ status: 'RELEASED', quantity_reserved: 0 });
    // Bins: A sold 2 of 20 -> 18 free; B sold 3 of 10 -> 7 free. Nothing held.
    expect(binRow(b, loc)).toEqual({ physical: 18, reserved: 0, available: 18 });
    expect(binRow(bo, loc)).toEqual({ physical: 7, reserved: 0, available: 7 });
    const linked = db.prepare('SELECT item_id, quantity, reservation_id FROM invoice_items WHERE invoice_id = ? ORDER BY id')
      .all(invoice) as Array<{ item_id: number; quantity: number; reservation_id: number | null }>;
    expect(linked.map((l) => l.reservation_id)).toEqual([null, r1.id]);
  });

  it('b) deleting a middle line keeps the surviving line\'s own reservation', async () => {
    const { item, other, b, bo, loc, r1, r2 } = await twoSameItemLines('delete');
    // A three-line invoice so a middle line can disappear: A/r1(2), A/r2(3), B(1).
    const create = await request(app).post('/api/invoices').set('Cookie', cookie)
      .set('Idempotency-Key', nextIdemKey('s1r-pair-delete-3'))
      .send({ customer_id: customerId, invoice_date: AS_OF, warehouse_id: warehouseA, items: [
        { item_id: other, quantity: 1, unit_price: 60, tax_rate: 0 },
      ] });
    expect(create.status).toBe(201);
    const second = lastInvoiceId();
    // Edit the 2-line invoice instead so indexes are: old [r1(2), r2(3)].
    const invoice = db.prepare('SELECT invoice_id FROM invoice_items WHERE reservation_id = ? LIMIT 1')
      .get(r1.id) as { invoice_id: number };
    const [firstId, secondId] = lineIdsOf(invoice.invoice_id);
    expect(firstId).toBeLessThan(secondId);
    const res = await request(app).put(`/api/invoices/${invoice.invoice_id}`).set('Cookie', cookie)
      .send({ customer_id: customerId, invoice_date: AS_OF, warehouse_id: warehouseA, items: [
        // r1's line is DELETED; r2's line survives unchanged and keeps its id.
        // Index 0 now belongs to r2, so a positional pairing would read r2 as
        // "changed" and r1 as "kept" - exactly backwards.
        { id: secondId, item_id: item, quantity: 3, unit_price: 50, tax_rate: 0, reservation_id: r2.id },
      ] });
    expect(res.status).toBe(200);

    expect(reservationRow(r2.id)).toEqual({ status: 'CONSUMED', quantity_reserved: 0 });
    expectHeaderMatchesChildren(r2.id);
    // r1's line was DELETED, not changed. Per the approved ruling its
    // reservation REOPENS because the source order is still active - the units
    // go back to the order, they do not vanish. Releasing here would destroy a
    // hold the user never released.
    expect(reservationRow(r1.id)).toEqual({ status: 'ACTIVE', quantity_reserved: 2 });
    // 20 bought, 3 sold, so 17 physical; r1's 2 are held again for the order.
    expect(binRow(b, loc)).toEqual({ physical: 17, reserved: 2, available: 15 });
    const linked = db.prepare('SELECT reservation_id FROM invoice_items WHERE invoice_id = ? ORDER BY id')
      .all(invoice.invoice_id) as Array<{ reservation_id: number | null }>;
    expect(linked.map((l) => l.reservation_id)).toEqual([r2.id]);
    expect(second).toBeGreaterThan(0);
  });

  it('c) a failed edit later in the same transaction rolls the release back', async () => {
    const { item, b, loc, r1, r2, invoice } = await twoSameItemLines('rollback');
    const before = {
      r1: reservationRow(r1.id), r2: reservationRow(r2.id), bin: binRow(b, loc),
      items: db.prepare('SELECT item_id, quantity, reservation_id FROM invoice_items WHERE invoice_id = ? ORDER BY id').all(invoice),
    };
    // Second line asks for more than the whole batch can sell -> validation
    // fails AFTER the release of r1 has already run inside the transaction.
    const res = await request(app).put(`/api/invoices/${invoice}`).set('Cookie', cookie)
      .send({ customer_id: customerId, invoice_date: AS_OF, warehouse_id: warehouseA, items: [
        { id: lineIdsOf(invoice)[0], item_id: item, quantity: 2, unit_price: 50, tax_rate: 0, reservation_id: r1.id },
        { item_id: 999999, quantity: 1, unit_price: 50, tax_rate: 0 },
      ] });
    expect(res.status).toBeGreaterThanOrEqual(400);
    // The release must not survive a rolled-back edit.
    expect({
      r1: reservationRow(r1.id), r2: reservationRow(r2.id), bin: binRow(b, loc),
      items: db.prepare('SELECT item_id, quantity, reservation_id FROM invoice_items WHERE invoice_id = ? ORDER BY id').all(invoice),
    }).toEqual(before);
  });
});
