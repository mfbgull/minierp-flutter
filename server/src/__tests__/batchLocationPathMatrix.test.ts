/**
 * BUG-013 path matrix: every flag-branching stock write path must hold
 * invariants A-J under BOTH states of `feature_batch_locations`.
 *
 * WHY THIS EXISTS. The flag chooses which stock source the sellable query
 * READS. It must never change which source a write MAINTAINS. Three defects of
 * exactly that shape shipped: the return void, the sellable read, and the
 * transfer void. Each survived because no single test drove every path under
 * both flag states and then LOOKED AT THE NUMBERS.
 *
 * So this spec does two things the earlier one did not:
 *   1. It names the real route for every path. A 404 or a 403 FAILS the test
 *      instead of being waved through — a path that silently never ran must
 *      not count as covered.
 *   2. It asserts the stock numbers actually moved, at the batch level, the
 *      location level and the warehouse balance level. Invariants A-J alone
 *      cannot tell "the write went to both sources" from "the write never
 *      happened".
 *
 * Routes, from `server/src/routes/inventory.ts` and `routes/production.ts`:
 *   transfer            POST /api/inventory/stock-transfers
 *   transfer void       POST /api/inventory/stock-transfers/:movementNo/void
 *   adjustment          POST /api/inventory/stock-movements   (movement_type ADJUSTMENT)
 *   production          POST /api/production
 *   physical count      POST /api/inventory/physical-counts/:id/items + /complete
 *   expiry write-off    POST /api/inventory/expired/write-off
 *   damage write-off    POST /api/inventory/damaged/write-off
 *
 * The flag is forced through `setFeatureEnabled` on the isolated per-worker
 * test database. Production default stays OFF.
 */
import { beforeAll, describe, expect, it } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { expectAllInvariantsHold } from './helpers/accountingInvariants';
import { setFeatureEnabled } from '../utils/featureFlags';
import { createItem, getAuthCookie, nextIdemKey, purchaseStock } from './helpers/invoiceReturnSpec';

const FLAG = 'feature_batch_locations';
const AS_OF = '2026-10-15';

let cookie = '';
let warehouseA = 0;
let warehouseB = 0;

function warehouses(): { a: number; b: number } {
  const rows = db.prepare('SELECT id FROM warehouses ORDER BY id').all() as Array<{ id: number }>;
  return { a: rows[0].id, b: rows[1].id };
}

async function buy(itemId: number, wh: number, qty: number, cost: number): Promise<void> {
  await purchaseStock(itemId, wh, qty, cost, cookie, AS_OF);
}

/** Warehouse balance, the number a stock report shows. */
function balance(itemId: number, wh: number): number {
  const row = db.prepare('SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?')
    .get(itemId, wh) as { quantity: number } | undefined;
  return row ? Number(row.quantity) : 0;
}

/** Master batch total, the flag-OFF source of truth. */
function batchTotal(itemId: number, wh: number): number {
  const row = db.prepare(
    'SELECT COALESCE(SUM(quantity_remaining), 0) AS q FROM stock_batches WHERE item_id = ? AND warehouse_id = ?',
  ).get(itemId, wh) as { q: number };
  return Number(row.q);
}

/** Location-row total, the flag-ON source of truth. */
function locationTotal(itemId: number, wh: number): number {
  const row = db.prepare(
    `SELECT COALESCE(SUM(bsl.quantity_available), 0) AS q
     FROM batch_stock_by_location bsl
     JOIN stock_batches sb ON sb.id = bsl.batch_id
     WHERE sb.item_id = ? AND sb.warehouse_id = ?`,
  ).get(itemId, wh) as { q: number };
  return Number(row.q);
}

/**
 * The three numbers must agree, and the warehouse delta must equal `delta`.
 * `delta` is signed: negative for a consume, positive for a receive.
 */
function expectStockMoved(
  where: string,
  itemId: number,
  wh: number,
  before: { balance: number; batch: number; location: number },
  delta: number,
): void {
  const now = { balance: balance(itemId, wh), batch: batchTotal(itemId, wh), location: locationTotal(itemId, wh) };
  expect({ where, ...now }).toEqual({
    where,
    balance: Number((before.balance + delta).toFixed(3)),
    batch: Number((before.batch + delta).toFixed(3)),
    location: Number((before.location + delta).toFixed(3)),
  });
}

function snapshot(itemId: number, wh: number): { balance: number; batch: number; location: number } {
  return { balance: balance(itemId, wh), batch: batchTotal(itemId, wh), location: locationTotal(itemId, wh) };
}

/** The id of the single batch holding this item in this warehouse. */
function batchIdOf(itemId: number, wh: number): number {
  const row = db.prepare(
    'SELECT id FROM stock_batches WHERE item_id = ? AND warehouse_id = ? ORDER BY id ASC LIMIT 1',
  ).get(itemId, wh) as { id: number } | undefined;
  expect(row?.id).toBeTruthy();
  return row!.id;
}

/**
 * The expired write-off refuses a batch that is not actually expired, so the
 * fixture has to date the batch into the past. The item must also be marked
 * as expiry-tracked for the expiry path to consider it.
 */
function makeExpired(itemId: number, wh: number, expiryDate: string): number {
  db.prepare('UPDATE items SET has_expiry = 1 WHERE id = ?').run(itemId);
  const batchId = batchIdOf(itemId, wh);
  db.prepare('UPDATE stock_batches SET expiry_date = ? WHERE id = ?').run(expiryDate, batchId);
  return batchId;
}

describe('BUG-013: every flag-branching stock write path holds A-J in both flag states', () => {
  beforeAll(async () => {
    cookie = await getAuthCookie();
    const wh = warehouses();
    warehouseA = wh.a;
    warehouseB = wh.b;
  });

  for (const featureOn of [false, true]) {
    const label = featureOn ? 'flag ON' : 'flag OFF';

    describe(label, () => {
      beforeAll(() => {
        setFeatureEnabled(db, FLAG, featureOn);
      });

      it('transfer moves stock out of the source and into the destination', async () => {
        const itemId = await createItem(`Transfer ${label}`, cookie);
        await buy(itemId, warehouseA, 10, 50);
        expectAllInvariantsHold(`transfer:before:${label}`, db);
        const fromBefore = snapshot(itemId, warehouseA);
        const toBefore = snapshot(itemId, warehouseB);

        const res = await request(app)
          .post('/api/inventory/stock-transfers')
          .set('Cookie', cookie)
          .set('Idempotency-Key', nextIdemKey('pathmatrix-transfer'))
          .send({
            item_id: itemId,
            from_warehouse_id: warehouseA,
            to_warehouse_id: warehouseB,
            quantity: 4,
            transfer_date: AS_OF,
            notes: `path matrix transfer (${label})`,
          });
        expect(res.status).toBe(201);

        expectStockMoved(`transfer:from:${label}`, itemId, warehouseA, fromBefore, -4);
        expectStockMoved(`transfer:to:${label}`, itemId, warehouseB, toBefore, +4);
        expectAllInvariantsHold(`transfer:after:${label}`, db);
      });

      it('transfer void restores BOTH warehouses', async () => {
        const itemId = await createItem(`Transfer Void ${label}`, cookie);
        await buy(itemId, warehouseA, 8, 30);

        const created = await request(app)
          .post('/api/inventory/stock-transfers')
          .set('Cookie', cookie)
          .set('Idempotency-Key', nextIdemKey('pathmatrix-transfer-void'))
          .send({
            item_id: itemId,
            from_warehouse_id: warehouseA,
            to_warehouse_id: warehouseB,
            quantity: 3,
            transfer_date: AS_OF,
            notes: `path matrix transfer void (${label})`,
          });
        expect(created.status).toBe(201);

        const movementNo = (
          db.prepare(
            `SELECT movement_no FROM stock_movements
             WHERE item_id = ? AND warehouse_id = ? AND movement_type = 'TRANSFER'
             ORDER BY id ASC LIMIT 1`,
          ).get(itemId, warehouseA) as { movement_no: string } | undefined
        )?.movement_no;
        expect(movementNo).toBeTruthy();

        const fromBefore = snapshot(itemId, warehouseA);
        const toBefore = snapshot(itemId, warehouseB);

        const voided = await request(app)
          .post(`/api/inventory/stock-transfers/${movementNo}/void`)
          .set('Cookie', cookie)
          .set('Idempotency-Key', nextIdemKey('pathmatrix-transfer-void-call'))
          .send({ reason: `path matrix void (${label})` });
        expect(voided.status).toBe(200);

        expectStockMoved(`transfer-void:from:${label}`, itemId, warehouseA, fromBefore, +3);
        expectStockMoved(`transfer-void:to:${label}`, itemId, warehouseB, toBefore, -3);
        expectAllInvariantsHold(`transfer-void:after:${label}`, db);
      });

      it('a negative stock adjustment consumes batch and location alike', async () => {
        const itemId = await createItem(`Adjust ${label}`, cookie);
        await buy(itemId, warehouseA, 6, 25);
        const before = snapshot(itemId, warehouseA);

        const res = await request(app)
          .post('/api/inventory/stock-movements')
          .set('Cookie', cookie)
          .set('Idempotency-Key', nextIdemKey('pathmatrix-adjust'))
          .send({
            item_id: itemId,
            warehouse_id: warehouseA,
            quantity: -2,
            movement_type: 'ADJUSTMENT',
            movement_date: AS_OF,
            remarks: `path matrix adjustment (${label})`,
          });
        expect(res.status).toBe(201);

        expectStockMoved(`adjust:${label}`, itemId, warehouseA, before, -2);
        expectAllInvariantsHold(`adjust:after:${label}`, db);
      });

      it('production consumes inputs and receives output', async () => {
        const inputId = await createItem(`Prod In ${label}`, cookie);
        const outputId = await createItem(`Prod Out ${label}`, cookie);
        await buy(inputId, warehouseA, 10, 12);
        const inBefore = snapshot(inputId, warehouseA);
        const outBefore = snapshot(outputId, warehouseA);

        const res = await request(app)
          .post('/api/productions')
          .set('Cookie', cookie)
          .set('Idempotency-Key', nextIdemKey('pathmatrix-prod'))
          .send({
            warehouse_id: warehouseA,
            production_date: AS_OF,
            input_items: [{ item_id: inputId, quantity: 4 }],
            outputs: [{ item_id: outputId, quantity: 2 }],
          });
        expect([200, 201]).toContain(res.status);

        expectStockMoved(`production:input:${label}`, inputId, warehouseA, inBefore, -4);
        expectStockMoved(`production:output:${label}`, outputId, warehouseA, outBefore, +2);
        expectAllInvariantsHold(`production:after:${label}`, db);
      });

      it('a completed physical count applies the counted quantity to both sources', async () => {
        const itemId = await createItem(`Count ${label}`, cookie);
        await buy(itemId, warehouseA, 5, 20);
        const before = snapshot(itemId, warehouseA);

        const created = await request(app)
          .post('/api/inventory/physical-counts')
          .set('Cookie', cookie)
          .set('Idempotency-Key', nextIdemKey('pathmatrix-count'))
          .send({ warehouse_id: warehouseA, count_date: AS_OF, notes: `path matrix count (${label})` });
        expect(created.status).toBe(201);
        const countId = (created.body as { id: number }).id;
        expect(countId).toBeTruthy();

        const recorded = await request(app)
          .post(`/api/inventory/physical-counts/${countId}/items`)
          .set('Cookie', cookie)
          .set('Idempotency-Key', nextIdemKey('pathmatrix-count-item'))
          .send({ item_id: itemId, counted_quantity: 3, notes: `counted 3 (${label})` });
        expect([200, 201]).toContain(recorded.status);

        const completed = await request(app)
          .post(`/api/inventory/physical-counts/${countId}/complete`)
          .set('Cookie', cookie)
          .set('Idempotency-Key', nextIdemKey('pathmatrix-count-complete'))
          .send({});
        expect([200, 201]).toContain(completed.status);

        expectStockMoved(`count:${label}`, itemId, warehouseA, before, -2);
        expectAllInvariantsHold(`count:after:${label}`, db);
      });

      it('expired write-off removes the batch from both sources', async () => {
        const itemId = await createItem(`Expiry ${label}`, cookie);
        await buy(itemId, warehouseA, 4, 15);
        const batchId = makeExpired(itemId, warehouseA, '2020-01-01');
        const before = snapshot(itemId, warehouseA);

        const res = await request(app)
          .post('/api/inventory/expired/write-off')
          .set('Cookie', cookie)
          .set('Idempotency-Key', nextIdemKey('pathmatrix-expiry'))
          .send({ batchIds: [batchId], reason: `path matrix expiry (${label})`, glAccount: '7202' });
        expect([200, 201]).toContain(res.status);

        // The write-off moves the batch to the EXPIRED warehouse and zeroes
        // the source, so the SOURCE warehouse is what must read zero.
        expect({ where: `expiry:${label}`, ...snapshot(itemId, warehouseA) })
          .toEqual({ where: `expiry:${label}`, balance: 0, batch: 0, location: 0 });
        expect(before.balance).toBe(4);
        expectAllInvariantsHold(`expiry:after:${label}`, db);
      });

      it('damage write-off removes the batch from both sources', async () => {
        const itemId = await createItem(`Damage ${label}`, cookie);
        await buy(itemId, warehouseA, 5, 15);
        const batchId = batchIdOf(itemId, warehouseA);
        const before = snapshot(itemId, warehouseA);

        const res = await request(app)
          .post('/api/inventory/damaged/write-off')
          .set('Cookie', cookie)
          .set('Idempotency-Key', nextIdemKey('pathmatrix-damage'))
          .send({ batchIds: [batchId], reason: `path matrix damage (${label})`, glAccount: '7204' });
        expect([200, 201]).toContain(res.status);

        // The surplus moved to the DAMAGED warehouse; the source reads zero.
        expect({ where: `damage:${label}`, ...snapshot(itemId, warehouseA) })
          .toEqual({ where: `damage:${label}`, balance: 0, batch: 0, location: 0 });
        expect(before.balance).toBe(5);
        expectAllInvariantsHold(`damage:after:${label}`, db);
      });
    });
  }
});
