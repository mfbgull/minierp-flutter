/**
 * NEW-G regression (GLM Round 4 review) — fractional stock after cancelling a
 * resize-EDITED reserved invoice.
 *
 * Scenario (current client shape: every line sends BOTH its `id` and its
 * `reservation_id`):
 *   1. Buy 20 units of one item into one batch/bin.
 *   2. Create two same-item reservations (qty 2 and 3) on a Confirmed SO.
 *   3. Sell them on one invoice: line A (reservation 1, qty 2) and
 *      line B (reservation 2, qty 3). Stock after sale = 15.
 *   4. Edit the invoice to [qty 2, qty 2] — same line ids and reservation
 *      ids. The edit reverse-reconsumes, so stock after edit = 16.
 *   5. Cancel the invoice.
 *
 * Expected: quantity_physical (batch_stock_by_location) and
 * stock_batches.quantity_remaining both return to exactly 20.
 *
 * Reported (OLD payload, commit 674863e4): 19.998 instead of 20.
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
let warehouseId = 0;

beforeAll(async () => {
  cookie = await getAuthCookie();
  customerId = await createCustomer('NEW-G Precision Customer', cookie);
  warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
});

function defaultLocation(wh: number): number {
  return (db.prepare(
    "SELECT id FROM locations WHERE warehouse_id = ? AND location_code = 'DEFAULT'",
  ).get(wh) as { id: number }).id;
}

function batchIdOf(itemId: number, wh: number): number {
  return (db.prepare(
    'SELECT id FROM stock_batches WHERE item_id = ? AND warehouse_id = ? ORDER BY id LIMIT 1',
  ).get(itemId, wh) as { id: number }).id;
}

/** Sum of physical units for the item, across every batch/bin. */
function physicalTotal(itemId: number): number {
  const r = db.prepare(`
    SELECT COALESCE(SUM(bsl.quantity_physical), 0) AS total
    FROM batch_stock_by_location bsl
    JOIN stock_batches sb ON sb.id = bsl.batch_id
    WHERE sb.item_id = ?
  `).get(itemId) as { total: number };
  return Number(r.total);
}

/** Sum of stock_batches.quantity_remaining for the item. */
function remainingTotal(itemId: number): number {
  const r = db.prepare(
    'SELECT COALESCE(SUM(quantity_remaining), 0) AS total FROM stock_batches WHERE item_id = ?',
  ).get(itemId) as { total: number };
  return Number(r.total);
}

function seedSalesOrder(status: string): string {
  const soNo = `SO-NEWG-${status}-${Date.now()}-${Math.floor(Math.random() * 1e6)}`;
  db.prepare(`
    INSERT INTO sales_orders (so_no, customer_id, so_date, status, total_amount, warehouse_id)
    VALUES (?, ?, ?, ?, 0, ?)
  `).run(soNo, customerId, AS_OF, status, warehouseId);
  return soNo;
}

describe('NEW-G: cancel of a resize-edited reserved invoice restores exact stock', () => {
  it('two same-item reserved lines edited 2+3 -> 2+2 then cancelled return stock to 20', async () => {
    setFeatureEnabled(db, FLAG, true);
    const item = await createItem(`NEWG item ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseId, 20, 10, cookie, '2026-10-01');
    const batchId = batchIdOf(item, warehouseId);
    const loc = defaultLocation(warehouseId);

    expect(physicalTotal(item)).toBe(20);
    expect(remainingTotal(item)).toBe(20);

    // Two distinct reservations on the SAME item, each on its own Confirmed SO.
    const res1 = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseId, quantity_reserved: 2,
      reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Confirmed'), reference_line_id: 1,
      bins: [{ batch_id: batchId, location_id: loc, quantity: 2 }],
    }, db);
    const res2 = StockReservationModel.create({
      item_id: item, warehouse_id: warehouseId, quantity_reserved: 3,
      reference_doctype: 'SALES_ORDER', reference_docno: seedSalesOrder('Confirmed'), reference_line_id: 1,
      bins: [{ batch_id: batchId, location_id: loc, quantity: 3 }],
    }, db);

    // Create the invoice with the two reserved lines.
    const createRes = await request(app)
      .post('/api/invoices')
      .set('Cookie', cookie)
      .set('Idempotency-Key', nextIdemKey('newg-create'))
      .send({
        customer_id: customerId,
        invoice_date: AS_OF,
        items: [
          { item_id: item, quantity: 2, unit_price: 50, tax_rate: 0, reservation_id: res1.id },
          { item_id: item, quantity: 3, unit_price: 50, tax_rate: 0, reservation_id: res2.id },
        ],
        warehouse_id: warehouseId,
      });
    expect(createRes.status).toBe(201);
    const invoiceId = createRes.body.id as number;

    expect(physicalTotal(item)).toBe(15);

    // Read the created line ids (the edit must resend id + reservation_id).
    const lines = db.prepare(
      'SELECT id, reservation_id, quantity FROM invoice_items WHERE invoice_id = ? ORDER BY id',
    ).all(invoiceId) as Array<{ id: number; reservation_id: number | null; quantity: number }>;
    expect(lines).toHaveLength(2);

    // Edit: 2+3 -> 2+2, keeping both line ids and reservation ids (client shape).
    const editRes = await request(app)
      .put(`/api/invoices/${invoiceId}`)
      .set('Cookie', cookie)
      .send({
        invoice_no: createRes.body.invoice_no,
        customer_id: customerId,
        invoice_date: AS_OF,
        due_date: AS_OF,
        status: 'Unpaid',
        total_amount: 200,
        items: [
          { id: lines[0].id, item_id: item, quantity: 2, unit_price: 50, tax_rate: 0, reservation_id: lines[0].reservation_id },
          { id: lines[1].id, item_id: item, quantity: 2, unit_price: 50, tax_rate: 0, reservation_id: lines[1].reservation_id },
        ],
        warehouse_id: warehouseId,
      });
    expect(editRes.status).toBe(200);

    // After the edit the sale of 4 stands, so 16 remain.
    expect(physicalTotal(item)).toBe(16);

    // Cancel the invoice.
    const cancelRes = await request(app)
      .put(`/api/invoices/${invoiceId}/cancel`)
      .set('Cookie', cookie)
      .send({ reason: 'NEW-G regression' });
    expect(cancelRes.status).toBe(200);

    // The cancel must restore exactly 4 units, back to the original 20.
    expect(physicalTotal(item)).toBe(20);
    expect(remainingTotal(item)).toBe(20);

    // And the bin that sold the units holds them again.
    const bin = db.prepare(
      'SELECT quantity_physical, quantity_reserved FROM batch_stock_by_location WHERE batch_id = ? AND location_id = ?',
    ).get(batchId, loc) as { quantity_physical: number; quantity_reserved: number };
    expect(bin.quantity_physical).toBe(20);
    // The cancel reopens both reservations (their SOs are still Confirmed), so
    // the edited line quantities (2+2) are held again. This is Decision A's
    // reopen rule, unchanged by the fix — asserted so a future change to the
    // restore cannot silently drop the holds.
    expect(bin.quantity_reserved).toBe(4);
  });
});
