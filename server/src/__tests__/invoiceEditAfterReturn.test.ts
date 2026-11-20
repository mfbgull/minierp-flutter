/**
 * Reject an invoice edit once a return has been recorded.
 *
 * Referential-integrity defect (GLM PR #45 review): `invoice_return_items
 * .invoice_item_id` references `invoice_items(id)` with no ON DELETE
 * cascade. An invoice edit deletes and recreates the invoice line rows, so
 * a recorded return leaves a dangling reference. SQLite (foreign_keys = ON)
 * then aborts the edit with "FOREIGN KEY constraint failed" — a raw 500
 * thrown from deep inside the transaction, after some writes may already
 * have run.
 *
 * Approved behaviour (Gull): reject the edit up front with HTTP 409 and a
 * clear message, before any invoice-line, stock, reservation or accounting
 * write. Scope: ANY recorded return row for the invoice, partial or full.
 *
 * This is a real-route test: invoice create, return, and edit all go through
 * the Express routes, using the current client payload shape (each edited
 * line resends its `id` and `reservation_id`).
 */
import { beforeAll, describe, expect, it } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import {
  createCustomer, createItem, getAuthCookie, nextIdemKey, purchaseStock,
} from './helpers/invoiceReturnSpec';

const AS_OF = '2026-10-15';
const EXPECTED_MESSAGE = 'This invoice cannot be edited after a return has been recorded.';

let cookie = '';
let customerId = 0;
let warehouseId = 0;

beforeAll(async () => {
  cookie = await getAuthCookie();
  customerId = await createCustomer('Edit-After-Return Customer', cookie);
  warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
});

function physicalTotal(itemId: number): number {
  const r = db.prepare(`
    SELECT COALESCE(SUM(bsl.quantity_physical), 0) AS total
    FROM batch_stock_by_location bsl
    JOIN stock_batches sb ON sb.id = bsl.batch_id
    WHERE sb.item_id = ?
  `).get(itemId) as { total: number };
  return Number(r.total);
}

function remainingTotal(itemId: number): number {
  const r = db.prepare(
    'SELECT COALESCE(SUM(quantity_remaining), 0) AS total FROM stock_batches WHERE item_id = ?',
  ).get(itemId) as { total: number };
  return Number(r.total);
}

/** Snapshot of every table the rejected edit must leave untouched. */
function stateSnapshot(invoiceId: number) {
  return {
    invoiceItems: db.prepare(
      'SELECT id, item_id, quantity, unit_price, reservation_id FROM invoice_items WHERE invoice_id = ? ORDER BY id',
    ).all(invoiceId),
    returnItems: db.prepare(
      `SELECT iri.id, iri.invoice_item_id, iri.item_id, iri.quantity
       FROM invoice_return_items iri
       JOIN invoice_returns ir ON ir.id = iri.return_id
       WHERE ir.invoice_id = ? ORDER BY iri.id`,
    ).all(invoiceId),
    stockBatches: db.prepare(
      'SELECT id, quantity_remaining FROM stock_batches ORDER BY id',
    ).all(),
    batchStockByLocation: db.prepare(
      'SELECT batch_id, location_id, quantity_physical, quantity_reserved FROM batch_stock_by_location ORDER BY batch_id, location_id',
    ).all(),
    reservations: db.prepare(
      'SELECT id, status, quantity_reserved FROM stock_reservations ORDER BY id',
    ).all(),
    stockMovements: db.prepare(
      'SELECT id, item_id, movement_type, quantity, reference_doctype, reference_docno FROM stock_movements ORDER BY id',
    ).all(),
    journalLines: db.prepare(
      'SELECT id, account_id, debit, credit, reference_type, reference_id, voided FROM journal_lines ORDER BY id',
    ).all(),
  };
}

describe('invoice edit after a recorded return is rejected before any write', () => {
  it('a partial return then a normal PUT returns 409 with no side effects', async () => {
    const item = await createItem(`Edit-After-Return ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseId, 10, 20, cookie, '2026-10-01');
    expect(physicalTotal(item)).toBe(10);
    expect(remainingTotal(item)).toBe(10);

    // Create the invoice through the real route (current client shape).
    const createRes = await request(app)
      .post('/api/invoices')
      .set('Cookie', cookie)
      .set('Idempotency-Key', nextIdemKey('edit-after-return-create'))
      .send({
        customer_id: customerId,
        invoice_date: AS_OF,
        items: [{ item_id: item, quantity: 5, unit_price: 20, tax_rate: 0 }],
        warehouse_id: warehouseId,
      });
    expect(createRes.status).toBe(201);
    const invoiceId = createRes.body.id as number;

    const linesBefore = db.prepare(
      'SELECT id, reservation_id, quantity FROM invoice_items WHERE invoice_id = ? ORDER BY id',
    ).all(invoiceId) as Array<{ id: number; reservation_id: number | null; quantity: number }>;
    expect(linesBefore).toHaveLength(1);

    // Record a PARTIAL return (2 of 5) through the real route. No disposition:
    // the return stands Unsettled, which is enough to leave the row recorded.
    const returnRes = await request(app)
      .post(`/api/invoices/${invoiceId}/return`)
      .set('Cookie', cookie)
      .set('Idempotency-Key', nextIdemKey('edit-after-return-ret'))
      .send({ items: [{ invoice_item_id: linesBefore[0].id, return_quantity: 2 }] });
    expect([200, 201]).toContain(returnRes.status);
    const recorded = db.prepare(
      `SELECT COUNT(*) AS n FROM invoice_return_items iri
       JOIN invoice_returns ir ON ir.id = iri.return_id
       WHERE ir.invoice_id = ? AND iri.invoice_item_id = ?`,
    ).get(invoiceId, linesBefore[0].id) as { n: number };
    expect(recorded.n).toBe(1);

    const before = stateSnapshot(invoiceId);

    // Attempt a normal edit: reduce the line from 5 to 4, resending the line
    // id and reservation_id exactly as the desktop client does.
    const editRes = await request(app)
      .put(`/api/invoices/${invoiceId}`)
      .set('Cookie', cookie)
      .send({
        invoice_no: createRes.body.invoice_no,
        customer_id: customerId,
        invoice_date: AS_OF,
        due_date: AS_OF,
        status: 'Unpaid',
        total_amount: 80,
        items: [{
          id: linesBefore[0].id,
          item_id: item,
          quantity: 4,
          unit_price: 20,
          tax_rate: 0,
          reservation_id: linesBefore[0].reservation_id,
        }],
        warehouse_id: warehouseId,
      });

    expect(editRes.status).toBe(409);
    expect(editRes.body.error).toBe(EXPECTED_MESSAGE);

    // Nothing the edit touches may have moved.
    expect(stateSnapshot(invoiceId)).toEqual(before);
    // 10 bought, 5 sold on the invoice, 2 returned: 7 physically left.
    expect(physicalTotal(item)).toBe(7);
    expect(remainingTotal(item)).toBe(7);
  });

  it('a full return also blocks the edit (any recorded return row)', async () => {
    const item = await createItem(`Edit-After-Full-Return ${Date.now()}`, cookie);
    await purchaseStock(item, warehouseId, 4, 25, cookie, '2026-10-01');

    const createRes = await request(app)
      .post('/api/invoices')
      .set('Cookie', cookie)
      .set('Idempotency-Key', nextIdemKey('edit-after-full-create'))
      .send({
        customer_id: customerId,
        invoice_date: AS_OF,
        items: [{ item_id: item, quantity: 4, unit_price: 25, tax_rate: 0 }],
        warehouse_id: warehouseId,
      });
    expect(createRes.status).toBe(201);
    const invoiceId = createRes.body.id as number;
    const line = db.prepare(
      'SELECT id, reservation_id FROM invoice_items WHERE invoice_id = ? ORDER BY id',
    ).get(invoiceId) as { id: number; reservation_id: number | null };

    const returnRes = await request(app)
      .post(`/api/invoices/${invoiceId}/return`)
      .set('Cookie', cookie)
      .set('Idempotency-Key', nextIdemKey('edit-after-full-ret'))
      .send({ items: [{ invoice_item_id: line.id, return_quantity: 4 }] });
    expect([200, 201]).toContain(returnRes.status);

    const before = stateSnapshot(invoiceId);
    const editRes = await request(app)
      .put(`/api/invoices/${invoiceId}`)
      .set('Cookie', cookie)
      .send({
        invoice_no: createRes.body.invoice_no,
        customer_id: customerId,
        invoice_date: AS_OF,
        due_date: AS_OF,
        status: 'Unpaid',
        total_amount: 75,
        items: [{
          id: line.id, item_id: item, quantity: 3, unit_price: 25, tax_rate: 0,
          reservation_id: line.reservation_id,
        }],
        warehouse_id: warehouseId,
      });

    expect(editRes.status).toBe(409);
    expect(editRes.body.error).toBe(EXPECTED_MESSAGE);
    expect(stateSnapshot(invoiceId)).toEqual(before);
  });
});
