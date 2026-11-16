/**
 * BUG-013 regression: voiding a sales return must leave the books balanced
 * under BOTH states of the `feature_batch_locations` flag.
 *
 * WHY THIS EXISTS. The void path (`reverseBatchRestore` in
 * `services/invoiceReturnService.ts`) used to branch on the flag and write
 * ONE of the two stock sources:
 *
 *   flag ON  → decrement `batch_stock_by_location`
 *   flag OFF → decrement `stock_batches`
 *
 * Writing only one source breaks invariant E (stock_balances.quantity ==
 * SUM(stock_batches.quantity_remaining)) as soon as the flag is ON: the void
 * removes units from `stock_balances` but the master batch rows keep them.
 * The rehearsal found it as `stockImbalances → { diff: -4 }`.
 *
 * The fix writes BOTH sources unconditionally. This spec pins that: it runs
 * the same return-then-void sequence once per flag state, in the same file,
 * and asserts invariants A–J after each.
 *
 * The flag must choose which source the sellable query READS. It must never
 * decide which source is MAINTAINED.
 */
import { afterAll, beforeAll, describe, expect, it } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import {
  createCustomer,
  createItem,
  getAuthCookie,
  nextIdemKey,
  processReturn,
  purchaseStock,
  settleReturn,
} from './helpers/invoiceReturnSpec';
import { expectAllInvariantsHold } from './helpers/accountingInvariants';
import { setFeatureEnabled } from '../utils/featureFlags';

let cookie = '';
let customerId = 0;
const FLAG = 'feature_batch_locations';

function firstWarehouseId(): number {
  const row = db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number } | undefined;
  if (!row) throw new Error('void-invariants: no warehouse seeded');
  return row.id;
}

/**
 * Buy 10 @ cost, sell 6, return 4, settle it, then void the return. Returns
 * the void response so the caller can assert it succeeded.
 */
async function buySellReturnVoid(warehouseId: number, itemId: number, label: string) {
  await purchaseStock(itemId, warehouseId, 10, 100, cookie, '2026-10-01');

  const sale = await request(app)
    .post('/api/invoices')
    .set('Cookie', cookie)
    .set('Idempotency-Key', nextIdemKey(`${label}-sale`))
    .send({
      customer_id: customerId,
      invoice_date: '2026-10-02',
      warehouse_id: warehouseId,
      items: [{ item_id: itemId, quantity: 6, unit_price: 200 }],
      paid_amount: 0,
    });
  expect([200, 201]).toContain(sale.status);
  const invoiceId: number = sale.body.id;
  const saleItemIds: number[] = db
    .prepare('SELECT id FROM invoice_items WHERE invoice_id = ? ORDER BY id')
    .all(invoiceId)
    .map((r) => (r as { id: number }).id);

  const ret = await processReturn(
    invoiceId,
    {
      invoiceItemIds: saleItemIds,
      quantities: [4],
      returnDate: '2026-10-03',
      warehouseId,
      reason: `${label} return`,
    },
    cookie,
  );
  expect([200, 201]).toContain(ret.status);
  expect(ret.returnId).toBeTruthy();
  await settleReturn(ret.returnId!, [{ type: 'credit', amount: 4 * 200 }], cookie);

  const voidRes = await request(app)
    .post(`/api/invoice-returns/${ret.returnId}/void`)
    .set('Cookie', cookie);
  expect([200, 204]).toContain(voidRes.status);

  return { invoiceId, returnId: ret.returnId!, voidStatus: voidRes.status };
}

describe('BUG-013: a voided return keeps invariants A-J under either flag', () => {
  let warehouseId = 0;
  let originalFlag = false;

  beforeAll(async () => {
    cookie = await getAuthCookie();
    warehouseId = firstWarehouseId();
    originalFlag = (db.prepare('SELECT value FROM settings WHERE key = ?').get(FLAG) as { value: string } | undefined)?.value === '1';
  });

  afterAll(() => {
    setFeatureEnabled(db, FLAG, originalFlag);
  });

  // Both cases run the identical sequence. Only the flag differs, so any
  // divergence between them is the flag branch itself.
  for (const flagOn of [false, true]) {
    it(`holds invariants A-J after buying, selling, returning and voiding with the flag ${flagOn ? 'ON' : 'OFF'}`, async () => {
      setFeatureEnabled(db, FLAG, flagOn);
      const itemId = await createItem(`VOID-INV-${flagOn ? 'ON' : 'OFF'}`, cookie);
      customerId = customerId || (await createCustomer(`VOID-INV Customer ${flagOn}`, cookie));

      const { invoiceId, returnId } = await buySellReturnVoid(warehouseId, itemId, flagOn ? 'on' : 'off');

      // Invariant E: the two stock sources must agree after the void.
      const bal = db
        .prepare('SELECT COALESCE(SUM(quantity), 0) AS q FROM stock_balances WHERE item_id = ?')
        .get(itemId) as { q: number };
      const batches = db
        .prepare('SELECT COALESCE(SUM(quantity_remaining), 0) AS q FROM stock_batches WHERE item_id = ?')
        .get(itemId) as { q: number };
      expect(Number(bal.q)).toBeCloseTo(Number(batches.q), 4);

      // Invariant: voiding restores exactly what the return consumed. Net
      // stock is 10 bought − 6 sold = 4.
      expect(Number(bal.q)).toBeCloseTo(4, 4);

      // A-J, the shared gate.
      expectAllInvariantsHold(`void-return-flag-${flagOn ? 'on' : 'off'}`, db);

      // Sanity: the objects we touched really are voided / unchanged.
      const retRow = db.prepare('SELECT status FROM invoice_returns WHERE id = ?').get(returnId) as { status: string };
      expect(String(retRow.status).toUpperCase()).toBe('VOIDED');
      const inv = db.prepare('SELECT id FROM invoices WHERE id = ?').get(invoiceId) as { id: number };
      expect(inv.id).toBe(invoiceId);
    });
  }
});
