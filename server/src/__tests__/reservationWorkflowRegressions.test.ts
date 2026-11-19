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
          { item_id: item, quantity: 3, unit_price: 50, tax_rate: 0 },
          { item_id: item, quantity: 3, unit_price: 50, tax_rate: 0 },
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
describe('Finding 19: item change on a reserved line (current behaviour)', () => {
  it('leaves the old reservation ACTIVE when the line changes item', async () => {
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

    // Edit the line to a DIFFERENT item.
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

    // CURRENT behaviour, measured: the reopen returned item A's 3 units to its
    // bin (physical back to 5) AND made the reservation ACTIVE again holding
    // those same 3 units, while 3 units of item B were sold separately. So the
    // hold is only a leak - available 2 while nothing is owed on it - and the
    // batch itself is whole (quantity_remaining 5). Header and child rows agree
    // (3/3), so this is NOT header-vs-child corruption; it is a stranded hold.
    expect(reservationRow(reservation.id)).toEqual({ status: 'ACTIVE', quantity_reserved: 3 });
    expect(binRow(bA, loc)).toEqual({ physical: 5, reserved: 3, available: 2 });
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
          { item_id: item, quantity: 3, unit_price: 50, tax_rate: 0, reservation_id: large.id },
          { item_id: item, quantity: 2, unit_price: 50, tax_rate: 0, reservation_id: small.id },
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
          { item_id: item, quantity: 2, unit_price: 50, tax_rate: 0, reservation_id: r2.id },
          { item_id: item, quantity: 2, unit_price: 50, tax_rate: 0, reservation_id: r1.id },
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

    // Collapse both lines into ONE line of 4.
    const res = await request(app).put(`/api/invoices/${invoice}`).set('Cookie', cookie)
      .send({ customer_id: customerId, invoice_date: AS_OF, warehouse_id: warehouseA, items: [
        { item_id: item, quantity: 4, unit_price: 50, tax_rate: 0 },
      ] });
    // MEASURED, not changed: collapsing two reserved lines into one fails with
    // 400 "sellable stock 0, requested 4". Both reservations were reopened (the
    // bins hold 6 physical with 0 reserved), but the survival of exactly ONE
    // reservation forces the whole 4-unit line onto a reservation that holds 2,
    // and a reservation-backed line never falls back to FIFO - so it asks for 4
    // from a 2-unit reserve. Two reservations cannot serve one line.
    expect(res.status).toBe(400);
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

    // Split into two lines of 2, neither naming a reservation.
    const res = await request(app).put(`/api/invoices/${invoice}`).set('Cookie', cookie)
      .send({ customer_id: customerId, invoice_date: AS_OF, warehouse_id: warehouseA, items: [
        { item_id: item, quantity: 2, unit_price: 50, tax_rate: 0 },
        { item_id: item, quantity: 2, unit_price: 50, tax_rate: 0 },
      ] });
    // MEASURED, not changed: splitting one 4-unit reserved line into two 2-unit
    // lines SUCCEEDS, but only the first new line takes the reservation. The
    // second is left unlinked, and the reservation keeps 2 units reserved that
    // nothing owes - the same stranded hold as NEW-2, reached by splitting.
    expect(res.status).toBe(200);
    expect(reservationRow(r1.id)).toEqual({ status: 'ACTIVE', quantity_reserved: 2 });
    expect(binRow(b1, loc)).toEqual({ physical: 6, reserved: 2, available: 4 });
    const splitLinked = db.prepare('SELECT reservation_id FROM invoice_items WHERE invoice_id = ? ORDER BY id')
      .all(invoice) as Array<{ reservation_id: number | null }>;
    expect(splitLinked.map((l) => l.reservation_id)).toEqual([r1.id, null]);
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
