/**
 * Goods owner-withdrawal: repeated edit, and void after an edit.
 *
 * Independent review found both paths broken on current main. The FIRST edit
 * succeeds (HTTP 200); the SECOND edit returns HTTP 500. After one edit the
 * document's movement rows still carry the superseded outbound row (withdraw
 * -4) next to the live one (-5), because the edit path restores stock through
 * compensating inbound rows and never marks the old outbound rows as
 * superseded. A later void replays BOTH outbound rows, so it tries to restore
 * 4 + 5 = 9 units into a batch whose quantity_original is 10 and whose
 * quantity_remaining is 5. The INV-21 CHECK
 * `quantity_remaining <= quantity_original` rejects the UPDATE and the void
 * fails with a 500, leaving the withdrawal posted.
 *
 * Each case drives the real API on the isolated per-suite database, and asserts
 * that BOTH stock mirrors (`stock_batches` and `batch_stock_by_location`) plus
 * the accounting state (GL lines for the document) match the ACTIVE withdrawal.
 */
import { beforeAll, describe, expect, it } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { createItem, getAuthCookie, nextIdemKey, purchaseStock } from './helpers/invoiceReturnSpec';

// The bin write is ungated (BUG-013), so the default bin row exists with the
// flag OFF — its default in this repo stays OFF.
const AS_OF = '2026-10-15';

let cookie = '';
let warehouseId = 0;

beforeAll(async () => {
  cookie = await getAuthCookie();
  expect(cookie).not.toBe('');
  warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
});

function defaultLocation(wh: number): number {
  return (db.prepare(
    "SELECT id FROM locations WHERE warehouse_id = ? AND location_code = 'DEFAULT'",
  ).get(wh) as { id: number }).id;
}

const batchOf = (itemId: number): number => (db.prepare(
  'SELECT id FROM stock_batches WHERE item_id = ? AND warehouse_id = ? ORDER BY id ASC LIMIT 1',
).get(itemId, warehouseId) as { id: number }).id;

const batchRemaining = (batchId: number): number => Number(
  (db.prepare('SELECT quantity_remaining FROM stock_batches WHERE id = ?')
    .get(batchId) as { quantity_remaining: number }).quantity_remaining,
);

const binRow = (batchId: number, locationId: number) => db.prepare(
  `SELECT quantity_physical AS physical, quantity_reserved AS reserved, quantity_available AS available
   FROM batch_stock_by_location WHERE batch_id = ? AND location_id = ?`,
).get(batchId, locationId) as { physical: number; reserved: number; available: number } | undefined;

const post = (url: string, body: Record<string, unknown>) =>
  request(app).post(url)
    .set('Cookie', cookie)
    .set('Idempotency-Key', nextIdemKey('owe-repeat'))
    .send(body);

const put = (url: string, body: Record<string, unknown>) =>
  request(app).put(url)
    .set('Cookie', cookie)
    .set('Idempotency-Key', nextIdemKey('owe-repeat'))
    .send(body);

const del = (url: string) => request(app).delete(url).set('Cookie', cookie);

const withdrawalBody = (itemId: number, quantity: number) => ({
  withdrawal_date: AS_OF,
  kind: 'goods',
  items: [{ item_id: itemId, warehouse_id: warehouseId, quantity }],
});

const idOf = (res: request.Response): number => (res.body?.data?.id ?? res.body?.id) as number;

/**
 * Outbound rows alone hold history; inbound rows are restores. A re-posted
 * document keeps its superseded outbound rows, so the ledger nets to zero only
 * when every consumed unit has been restored exactly once.
 */
function movementTotals(withdrawalNo: string): { outbound: number; inbound: number } {
  const r = db.prepare(`
    SELECT
      COALESCE(SUM(CASE WHEN quantity < 0 THEN -quantity ELSE 0 END), 0) AS outbound,
      COALESCE(SUM(CASE WHEN quantity > 0 THEN  quantity ELSE 0 END), 0) AS inbound
    FROM stock_movements
    WHERE reference_docno = ?
      AND reference_doctype IN ('OWNER_WITHDRAWAL','OWNER_WITHDRAWAL_REVERSAL')
  `).get(withdrawalNo) as { outbound: number; inbound: number };
  return { outbound: Number(r.outbound), inbound: Number(r.inbound) };
}

/**
 * GL state of the document. A goods posting is one balanced entry: a debit row
 * for the drawings account and a matching credit row for inventory.
 */
function glOf(withdrawalId: number): {
  liveDebit: number;
  liveCredit: number;
  liveEntries: number;
  voidedDebit: number;
} {
  const r = db.prepare(`
    SELECT
      COALESCE(SUM(CASE WHEN COALESCE(jl.voided, 0) = 0 THEN jl.debit ELSE 0 END), 0) AS liveDebit,
      COALESCE(SUM(CASE WHEN COALESCE(jl.voided, 0) = 0 THEN jl.credit ELSE 0 END), 0) AS liveCredit,
      COUNT(DISTINCT CASE WHEN COALESCE(jl.voided, 0) = 0 THEN jl.journal_entry_id END) AS liveEntries,
      COALESCE(SUM(CASE WHEN COALESCE(jl.voided, 0) = 1 THEN jl.debit ELSE 0 END), 0) AS voidedDebit
    FROM journal_lines jl
    WHERE jl.reference_type = 'OWNER_WITHDRAWAL' AND jl.reference_id = ?
  `).get(withdrawalId) as {
    liveDebit: number; liveCredit: number; liveEntries: number; voidedDebit: number;
  };
  return {
    liveDebit: Number(r.liveDebit),
    liveCredit: Number(r.liveCredit),
    liveEntries: Number(r.liveEntries),
    voidedDebit: Number(r.voidedDebit),
  };
}

describe('goods owner-withdrawal: repeated edit keeps the mirrors on the active lines', () => {
  it('a second PUT succeeds and both stock mirrors match the live 6-unit line', async () => {
    const itemId = await createItem('OWE-REPEAT-EDIT', cookie);
    await purchaseStock(itemId, warehouseId, 10, 5, cookie);

    const batchId = batchOf(itemId);
    const locId = defaultLocation(warehouseId);
    expect(batchRemaining(batchId)).toBe(10);
    expect(binRow(batchId, locId)).toEqual({ physical: 10, reserved: 0, available: 10 });

    // ── create: withdraw 4 ────────────────────────────────────────────
    const created = await post('/api/owner-equity/withdrawals', withdrawalBody(itemId, 4));
    expect([200, 201]).toContain(created.status);
    const withdrawalId = idOf(created);
    const withdrawalNo = String(
      (db.prepare('SELECT withdrawal_no FROM owner_withdrawals WHERE id = ?')
        .get(withdrawalId) as { withdrawal_no: string }).withdrawal_no,
    );
    expect(withdrawalId).toBeGreaterThan(0);

    expect(batchRemaining(batchId)).toBe(6);
    expect(binRow(batchId, locId)).toEqual({ physical: 6, reserved: 0, available: 6 });

    // ── first edit: 4 → 5 (succeeds on main) ──────────────────────────
    const firstEdit = await put(`/api/owner-equity/withdrawals/${withdrawalId}`, withdrawalBody(itemId, 5));
    expect(firstEdit.status).toBe(200);
    expect(batchRemaining(batchId)).toBe(5);
    expect(binRow(batchId, locId)).toEqual({ physical: 5, reserved: 0, available: 5 });

    // ── second edit: 5 → 6 (HTTP 500 on main) ─────────────────────────
    const secondEdit = await put(`/api/owner-equity/withdrawals/${withdrawalId}`, withdrawalBody(itemId, 6));
    expect(secondEdit.status).toBe(200);

    // Both mirrors follow the ACTIVE line: 10 - 6 = 4.
    expect(batchRemaining(batchId)).toBe(4);
    expect(binRow(batchId, locId)).toEqual({ physical: 4, reserved: 0, available: 4 });

    // Every consumed unit has a matching restore: 4 + 5 consumed, 4 + 5 back.
    // The active lines alone are 6, which the mirror assertions above hold to.
    expect(movementTotals(withdrawalNo)).toEqual({ outbound: 15, inbound: 9 });

    // Accounting: exactly ONE live balanced entry, 6 units at 5.00 = 30.
    const doc = db.prepare('SELECT amount, status FROM owner_withdrawals WHERE id = ?')
      .get(withdrawalId) as { amount: number; status: string };
    expect(doc.status).toBe('posted');
    expect(Number(doc.amount)).toBe(30);
    expect(glOf(withdrawalId)).toEqual({
      liveDebit: 30, liveCredit: 30, liveEntries: 1, voidedDebit: 45,
    });

    // ── the withdrawal is still voidable: restore exactly 6, back to 10 ─
    const voided = await del(`/api/owner-equity/withdrawals/${withdrawalId}`);
    expect([200, 204]).toContain(voided.status);
    expect(batchRemaining(batchId)).toBe(10);
    expect(binRow(batchId, locId)).toEqual({ physical: 10, reserved: 0, available: 10 });
    expect(glOf(withdrawalId)).toEqual({
      liveDebit: 0, liveCredit: 0, liveEntries: 0, voidedDebit: 75,
    });
  });
});

describe('goods owner-withdrawal: void after an edit restores the active consumption only', () => {
  it('void after one edit succeeds and restores 5 units, not 4 + 5', async () => {
    const itemId = await createItem('OWE-EDIT-THEN-VOID', cookie);
    await purchaseStock(itemId, warehouseId, 10, 5, cookie);

    const batchId = batchOf(itemId);
    const locId = defaultLocation(warehouseId);

    const created = await post('/api/owner-equity/withdrawals', withdrawalBody(itemId, 4));
    expect([200, 201]).toContain(created.status);
    const withdrawalId = idOf(created);
    const withdrawalNo = String(
      (db.prepare('SELECT withdrawal_no FROM owner_withdrawals WHERE id = ?')
        .get(withdrawalId) as { withdrawal_no: string }).withdrawal_no,
    );

    expect(batchRemaining(batchId)).toBe(6);
    expect(binRow(batchId, locId)).toEqual({ physical: 6, reserved: 0, available: 6 });

    // One edit: 4 → 5. The batch now holds 5, so only 5 units were consumed.
    const edited = await put(`/api/owner-equity/withdrawals/${withdrawalId}`, withdrawalBody(itemId, 5));
    expect(edited.status).toBe(200);
    expect(batchRemaining(batchId)).toBe(5);

    const before = movementTotals(withdrawalNo);
    expect(before.outbound).toBe(9); // superseded -4 and live -5 are both present
    expect(before.inbound).toBe(4);

    // Void must restore the 5 live units only: 5 + 5 = 10, never 14.
    const voided = await del(`/api/owner-equity/withdrawals/${withdrawalId}`);
    expect([200, 204]).toContain(voided.status);

    expect(batchRemaining(batchId)).toBe(10);
    expect(binRow(batchId, locId)).toEqual({ physical: 10, reserved: 0, available: 10 });

    // Ledger now nets to zero: every outbound unit has a matching inbound.
    expect(movementTotals(withdrawalNo)).toEqual({ outbound: 9, inbound: 9 });

    const doc = db.prepare('SELECT status FROM owner_withdrawals WHERE id = ?')
      .get(withdrawalId) as { status: string };
    expect(doc.status).toBe('voided');
    expect(glOf(withdrawalId)).toEqual({
      liveDebit: 0, liveCredit: 0, liveEntries: 0, voidedDebit: 45,
    });
  });
});
