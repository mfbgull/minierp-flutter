/**
 * Issue #21 - purchase-order cancellation reservation parity.
 *
 * Kilo flagged PO cancellation as a possible place where the batch/bin mirror
 * and the stock tables could drift while a reservation is live. A purchase
 * order never creates a stock reservation: only invoices, POS sales and
 * returns do. So cancelling a submitted PO must not release, zero or
 * duplicate anything, and the reservation must release exactly once at its
 * own release call.
 */
import { beforeAll, describe, expect, it } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { expectAllInvariantsHold, batchLocationDriftImbalances } from './helpers/accountingInvariants';
import { setFeatureEnabled } from '../utils/featureFlags';
import { createItem, getAuthCookie, nextIdemKey } from './helpers/invoiceReturnSpec';

const FLAG = 'feature_batch_locations';

interface BinRow {
  batch_id: number;
  location_id: number;
  quantity_physical: number;
  quantity_reserved: number;
  quantity_available: number;
}

let cookie = '';
let warehouseId = 0;
let supplierId = 0;
let itemId = 0;
let batchId = 0;
let locationId = 0;
let reservationId = 0;
let poId = 0;
let docno = '';

function binRow(): BinRow {
  const row = db.prepare(
    `SELECT bsl.batch_id, bsl.location_id, bsl.quantity_physical,
            bsl.quantity_reserved, bsl.quantity_available
       FROM batch_stock_by_location bsl
       JOIN stock_batches sb ON sb.id = bsl.batch_id
      WHERE sb.item_id = ? AND sb.warehouse_id = ?`,
  ).get(itemId, warehouseId) as BinRow | undefined;
  if (!row) throw new Error('bin row missing');
  return row;
}

function balanceQty(): number {
  const row = db.prepare(
    'SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?',
  ).get(itemId, warehouseId) as { quantity: number } | undefined;
  return Number(row?.quantity ?? -1);
}

function reservationRow(): { status: string; quantity_reserved: number } {
  return db.prepare('SELECT status, quantity_reserved FROM stock_reservations WHERE id = ?')
    .get(reservationId) as { status: string; quantity_reserved: number };
}

describe('Issue #21: PO cancellation leaves reservations and stock parity intact', () => {
  beforeAll(async () => {
    setFeatureEnabled(db, FLAG, true);
    cookie = await getAuthCookie();
    warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id').all() as Array<{ id: number }>)[0].id;

    const s = await request(app)
      .post('/api/suppliers')
      .set('Cookie', cookie)
      .send({ supplier_code: `POCANCEL-${Date.now()}`, supplier_name: 'PO Cancel Parity Supplier' });
    expect([200, 201]).toContain(s.status);
    supplierId = ((s.body as { data?: { id: number } }).data?.id ?? 0) as number;
    expect(supplierId).toBeTruthy();

    itemId = await createItem('PO-CANCEL-PARITY', cookie);

    const buy = await request(app)
      .post('/api/purchases')
      .set('Cookie', cookie)
      .set('Idempotency-Key', nextIdemKey('po-cancel-parity-buy'))
      .send({
        item_id: itemId,
        warehouse_id: warehouseId,
        quantity: 10,
        unit_cost: 20,
        purchase_date: '2026-11-10',
        supplier_id: supplierId,
        supplier_name: 'PO Cancel Parity Supplier',
      });
    expect([200, 201]).toContain(buy.status);

    const bin = binRow();
    batchId = bin.batch_id;
    locationId = bin.location_id;
    expect(Number(bin.quantity_physical)).toBe(10);

    docno = `PO-CANCEL-PARITY-${Date.now()}`;
    const res = await request(app)
      .post('/api/inventory/reservations')
      .set('Cookie', cookie)
      .send({
        item_id: itemId,
        warehouse_id: warehouseId,
        quantity_reserved: 4,
        reference_doctype: 'INVOICE',
        reference_docno: docno,
        reference_line_id: 1,
        bins: [{ batch_id: batchId, location_id: locationId, quantity: 4 }],
      });
    expect(res.status).toBe(201);
    reservationId = (res.body as { id: number }).id;
    expect(reservationId).toBeTruthy();

    const po = await request(app)
      .post('/api/purchase-orders')
      .set('Cookie', cookie)
      .send({
        supplier_id: supplierId,
        po_date: '2026-11-11',
        items: [{ item_id: itemId, quantity: 5, unit_price: 20 }],
      });
    expect([200, 201]).toContain(po.status);
    poId = ((po.body as { data?: { id: number } }).data?.id ?? (po.body as { id?: number }).id ?? 0) as number;
    expect(poId).toBeTruthy();

    const submitted = await request(app)
      .post(`/api/purchase-orders/${poId}/status`)
      .set('Cookie', cookie)
      .send({ status: 'Submitted' });
    expect(submitted.status).toBe(200);
  });

  it('cancels a submitted PO without touching the live reservation', async () => {
    const cancelled = await request(app)
      .post(`/api/purchase-orders/${poId}/status`)
      .set('Cookie', cookie)
      .send({ status: 'Cancelled' });
    expect(cancelled.status).toBe(200);
    expect((cancelled.body as { status: string }).status).toBe('Cancelled');

    const bin = binRow();
    expect(Number(bin.quantity_physical)).toBe(10);
    expect(Number(bin.quantity_reserved)).toBe(4);
    expect(Number(bin.quantity_available)).toBe(6);
    expect(balanceQty()).toBe(10);

    const res = reservationRow();
    expect(res.status).toBe('ACTIVE');
    expect(Number(res.quantity_reserved)).toBe(4);

    const count = db.prepare(
      "SELECT COUNT(*) AS n FROM stock_reservations WHERE reference_doctype = 'INVOICE' AND reference_docno = ?",
    ).get(docno) as { n: number };
    expect(Number(count.n)).toBe(1);

    const movements = db.prepare('SELECT COUNT(*) AS n FROM stock_movements WHERE reference_docno = ?')
      .get(docno) as { n: number };
    expect(Number(movements.n)).toBe(0);

    expect(batchLocationDriftImbalances(db)).toEqual([]);
    expectAllInvariantsHold('po-cancel-reservation-parity', db);
  });

  it('releases the reservation exactly once, at its own release call', async () => {
    const first = await request(app)
      .delete(`/api/inventory/reservations/${reservationId}/release`)
      .set('Cookie', cookie);
    expect(first.status).toBe(200);

    const bin = binRow();
    expect(Number(bin.quantity_physical)).toBe(10);
    expect(Number(bin.quantity_reserved)).toBe(0);
    expect(Number(bin.quantity_available)).toBe(10);
    expect(balanceQty()).toBe(10);
    expect(reservationRow().status).toBe('RELEASED');

    const second = await request(app)
      .delete(`/api/inventory/reservations/${reservationId}/release`)
      .set('Cookie', cookie);
    expect(second.status).toBeGreaterThanOrEqual(400);
    expect(second.status).toBeLessThan(500);

    const after = binRow();
    expect(Number(after.quantity_reserved)).toBe(0);
    expect(Number(after.quantity_available)).toBe(10);
    expect(batchLocationDriftImbalances(db)).toEqual([]);
    expectAllInvariantsHold('po-cancel-reservation-parity-release', db);
  });
});
