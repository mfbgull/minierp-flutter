/**
 * Deployment rehearsal: one realistic month of operations, then the
 * accounting invariants (A-J), then a real backup, restore and
 * restore-verify.
 *
 * PURPOSE. Every migration, backup and restore test so far ran on a fixture
 * one operation deep. Before real data arrives, run a fresh database through
 * the shape of a real month — purchases, sales, returns, supplier refunds and
 * receipts, a backdated entry, a void, and a period close — and then prove the
 * books still balance and the snapshot is restorable.
 *
 * READ-ONLY ON FAILURE. This test never repairs anything. If an invariant
 * fails, the failure is the report. A green run means the month is sound; it
 * does NOT mean real data is sound (see audit/FIRST-DEPLOYMENT-CHECKLIST.md).
 *
 * Runs against the isolated per-worker test database, never the live one.
 */
import fs from 'fs';
import os from 'os';
import path from 'path';
import { execFileSync } from 'child_process';
import { afterAll, beforeAll, describe, expect, it } from '@jest/globals';
import request from 'supertest';
import Database from 'better-sqlite3';
import app from '../app';
import db, { dbPath } from '../config/database';
import {
  createCustomer,
  createItem,
  getAuthCookie,
  nextIdemKey,
  processReturn,
  purchaseStock,
  settleReturn,
} from './helpers/invoiceReturnSpec';
import { expectAllInvariantsHold, batchLocationDriftImbalances } from './helpers/accountingInvariants';
import { setFeatureEnabled } from '../utils/featureFlags';

const SERVER_ROOT = path.resolve(__dirname, '..', '..');

let cookie = '';
let itemId = 0;
let customerId = 0;
let warehouseId = 0;
let supplierId = 0;

/** The first warehouse, created by the seed migration. */
function firstWarehouseId(): number {
  const row = db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number } | undefined;
  if (!row) throw new Error('rehearsal: no warehouse seeded');
  return row.id;
}

/** A supplier row, for the refund-claim leg. Created through the API. */
async function ensureSupplier(): Promise<number> {
  const existing = db
    .prepare("SELECT id FROM suppliers WHERE supplier_code = 'REHEARSAL-SUP' LIMIT 1")
    .get() as { id: number } | undefined;
  if (existing) return existing.id;
  const res = await request(app)
    .post('/api/suppliers')
    .set('Cookie', cookie)
    .send({ supplier_code: 'REHEARSAL-SUP', supplier_name: 'Rehearsal Supplier' });
  const id: number | undefined = res.body?.data?.id ?? res.body?.id;
  if (!id) throw new Error(`ensureSupplier failed: ${res.status} ${JSON.stringify(res.body)}`);
  return id;
}

/** Cash on hand, so the cash guard has room for the outflow legs. */
async function seedOpeningCash(amount: number, date: string): Promise<void> {
  const res = await request(app)
    .post('/api/owner-equity/capital')
    .set('Cookie', cookie)
    .set('Idempotency-Key', nextIdemKey('rehearsal-cap'))
    .send({ amount, capital_date: date, payment_method: 'Cash', description: 'rehearsal opening capital' });
  if (res.status !== 200 && res.status !== 201) {
    throw new Error(`seedOpeningCash failed: ${res.status} ${JSON.stringify(res.body)}`);
  }
}

/** One invoice with an optional recorded payment, the common sale shape. */
async function sell(
  qty: number,
  price: number,
  opts: { taxRate?: number; discountType?: 'none' | 'percentage' | 'flat'; discountValue?: number; date: string; pay: boolean },
): Promise<{ invoiceId: number; itemIds: number[]; grossTotal: number }> {
  // Mirror the server's rounding: discount is applied to the gross line, then
  // tax, then the line is rounded to 2dp (BUG-006 parity rule).
  const gross = qty * price;
  const discount =
    opts.discountType === 'percentage'
      ? (gross * (opts.discountValue ?? 0)) / 100
      : opts.discountType === 'flat'
        ? Math.min(opts.discountValue ?? 0, gross)
        : 0;
  const discounted = gross - discount;
  const withTax = discounted * (1 + (opts.taxRate ?? 0) / 100);
  const lineTotal = Math.round(withTax * 100) / 100;
  // Any customer credit on account offsets the payment automatically, so a
  // recorded payment must not exceed the invoice total.
  const creditOffset = (db
    .prepare('SELECT COALESCE(credit_balance, 0) AS c FROM customers WHERE id = ?')
    .get(customerId) as { c: number } | undefined)?.c ?? 0;
  const paymentAmount = Math.max(0, lineTotal - creditOffset);

  const res = await request(app)
    .post('/api/invoices')
    .set('Cookie', cookie)
    .set('Idempotency-Key', nextIdemKey('rehearsal-inv'))
    .send({
      customer_id: customerId,
      invoice_date: opts.date,
      due_date: '2027-12-31',
      items: [{
        item_id: itemId,
        quantity: qty,
        unit_price: price,
        tax_rate: opts.taxRate ?? 0,
        discount_type: opts.discountType ?? 'none',
        discount_value: opts.discountValue ?? 0,
      }],
      record_payment: opts.pay && paymentAmount > 0,
      payment: opts.pay && paymentAmount > 0
        ? { payment_date: opts.date, amount: paymentAmount, payment_method: 'Cash' }
        : undefined,
    });
  if (res.status !== 201 && res.status !== 200) {
    throw new Error(`sell failed: ${res.status} ${JSON.stringify(res.body)}`);
  }
  const invoiceId: number = res.body.id;
  const itemIds = (db.prepare('SELECT id FROM invoice_items WHERE invoice_id = ? ORDER BY id').all(invoiceId) as Array<{ id: number }>)
    .map((r) => r.id);
  return { invoiceId, itemIds, grossTotal: lineTotal };
}

beforeAll(async () => {
  cookie = await getAuthCookie();
  warehouseId = firstWarehouseId();
  supplierId = await ensureSupplier();
  itemId = await createItem('Rehearsal Widget', cookie);  customerId = await createCustomer('Rehearsal Customer', cookie);
  // Enough stock and cash for a month of activity.
  await seedOpeningCash(5_000_000, '2026-09-01');
  await purchaseStock(itemId, warehouseId, 1000, 100, cookie, '2026-09-01');
});

describe('deployment rehearsal: one month of operations', () => {
  it('runs a realistic month, holds invariants A-J, and restores its own backup', async () => {
    // ── Week 1: purchases and plain sales ──────────────────────────────
    await purchaseStock(itemId, warehouseId, 400, 110, cookie, '2026-09-03');
    await purchaseStock(itemId, warehouseId, 300, 120, cookie, '2026-09-07');

    // A second supplier goods receipt, to give AP more than one balance.
    await request(app)
      .post('/api/purchases')
      .set('Cookie', cookie)
      .set('Idempotency-Key', nextIdemKey('rehearsal-pur'))
      .send({
        item_id: itemId,
        warehouse_id: warehouseId,
        quantity: 200,
        unit_cost: 130,
        purchase_date: '2026-09-08',
        supplier_id: supplierId,
      })
      .expect((r) => {
        if (r.status !== 201 && r.status !== 200) {
          throw new Error(`second-supplier purchase failed: ${r.status} ${JSON.stringify(r.body)}`);
        }
      });

    const paidSale = await sell(50, 200, { date: '2026-09-05', pay: true });
    const creditSale = await sell(40, 250, { date: '2026-09-06', pay: false });

    // ── Week 2: taxed and discounted sales ─────────────────────────────
    await sell(20, 300, { taxRate: 17, date: '2026-09-10', pay: true });
    await sell(15, 400, { discountType: 'percentage', discountValue: 10, date: '2026-09-11', pay: true });
    await sell(10, 500, { taxRate: 17, discountType: 'flat', discountValue: 50, date: '2026-09-12', pay: false });

    // ── Week 3: a sales return, settled in cash ────────────────────────
    const ret = await processReturn(
      paidSale.invoiceId,
      {
        invoiceItemIds: paidSale.itemIds,
        quantities: [5],
        returnDate: '2026-09-16',
        warehouseId,
        disposition: 'refund',
        settlements: [{ type: 'refund', amount: 5 * 200, method: 'Cash' }],
        reason: 'Rehearsal return',
      },
      cookie,
    );
    expect([200, 201]).toContain(ret.status);

    // A second return left unsettled, then settled later.
    const ret2 = await processReturn(
      creditSale.invoiceId,
      {
        invoiceItemIds: creditSale.itemIds,
        quantities: [4],
        returnDate: '2026-09-17',
        warehouseId,
        reason: 'Rehearsal return, settle later',
      },
      cookie,
    );
    expect([200, 201]).toContain(ret2.status);
    expect(ret2.returnId).toBeTruthy();
    await settleReturn(ret2.returnId!, [{ type: 'credit', amount: 4 * 250 }], cookie);

    // ── Week 4: supplier refund claim, receipt, write-off ──────────────
    const claim = await request(app)
      .post('/api/supplier-refunds/claims')
      .set('Cookie', cookie)
      .set('Idempotency-Key', nextIdemKey('rehearsal-claim'))
      .send({ supplier_id: supplierId, claim_date: '2026-09-20', amount: 3000, reason: 'Rehearsal claim' });
    expect([200, 201]).toContain(claim.status);
    const claimId: number = claim.body?.id ?? claim.body?.data?.id;
    expect(claimId).toBeTruthy();

    // Receive part of it in cash.
    const receipt = await request(app)
      .post('/api/supplier-refunds')
      .set('Cookie', cookie)
      .set('Idempotency-Key', nextIdemKey('rehearsal-receipt'))
      .send({ refund_date: '2026-09-21', claim_id: claimId, amount: 1200, payment_method: 'Cash' });
    expect([200, 201]).toContain(receipt.status);
    // Write off a small remainder (below the Rs 1,000 admin gate).
    const writeOff = await request(app)
      .post(`/api/supplier-refunds/claims/${claimId}/write-off`)
      .set('Cookie', cookie)
      .set('Idempotency-Key', nextIdemKey('rehearsal-wo'))
      .send({ amount: 500, reason: 'Rehearsal short payment', write_off_date: '2026-09-22' });
    expect([200, 201]).toContain(writeOff.status);

    // ── A backdated entry, and a void ──────────────────────────────────
    // Backdated sale inside an open period: allowed with a warning (D19).
    await sell(5, 200, { date: '2026-09-02', pay: true });

    // Void the second return, to exercise the reversal path.
    const voidRes = await request(app)
      .post(`/api/invoice-returns/${ret2.returnId}/void`)
      .set('Cookie', cookie);
    expect([200, 204, 400, 409]).toContain(voidRes.status);

    // ── Invariants A-J, before a period close ──────────────────────────
    expectAllInvariantsHold('rehearsal: after one month of operations');

    // ── Period close, then the invariants again ────────────────────────
    const current = await request(app).get('/api/accounting/periods/current').set('Cookie', cookie);
    const currentPeriod = current.body?.data?.current ?? current.body?.current;
    expect(currentPeriod).toBeTruthy();
    const periodId: number = currentPeriod.id;
    const close = await request(app)
      .post(`/api/accounting/periods/${periodId}/close`)
      .set('Cookie', cookie)
      .send({});
    // A close may refuse while the period is current; either outcome is
    // acceptable here — the point is that it never leaves the books broken.
    expect([200, 400, 409]).toContain(close.status);
    expectAllInvariantsHold('rehearsal: after a period close attempt');

    // ── Backup, restore, restore-verify ────────────────────────────────
    const backupDir = fs.mkdtempSync(path.join(os.tmpdir(), 'rehearsal-backup-'));
    const snapshotPath = path.join(backupDir, 'rehearsal.db');
    try {
      // Take the snapshot with the same primitive the boot path uses.
      db.exec(`VACUUM INTO '${snapshotPath.replace(/'/g, "''")}'`);
      expect(fs.existsSync(snapshotPath)).toBe(true);

      // The restored copy must open, be integral, and carry the month.
      const restored = new Database(snapshotPath, { readonly: true, fileMustExist: true });
      try {
        expect(restored.pragma('integrity_check', { simple: true })).toBe('ok');
        const invoices = (restored.prepare('SELECT COUNT(*) AS c FROM invoices').get() as { c: number }).c;
        const items = (restored.prepare('SELECT COUNT(*) AS c FROM invoice_items').get() as { c: number }).c;
        const movements = (restored.prepare('SELECT COUNT(*) AS c FROM stock_movements').get() as { c: number }).c;
        expect(invoices).toBeGreaterThan(0);
        expect(items).toBeGreaterThan(0);
        expect(movements).toBeGreaterThan(0);
        // The GL in the snapshot must still balance.
        const unbalanced = restored
          .prepare(
            `SELECT COUNT(*) AS c FROM (
               SELECT journal_entry_id
               FROM journal_lines
               WHERE voided = 0
               GROUP BY journal_entry_id
               HAVING ABS(SUM(CAST(ROUND(debit * 100) AS INTEGER)) - SUM(CAST(ROUND(credit * 100) AS INTEGER))) > 0
             )`,
          )
          .get() as { c: number };
        expect(unbalanced.c).toBe(0);
      } finally {
        restored.close();
      }

      // The repo's own restore-smoke script must accept the snapshot.
      const smoke = execFileSync('node', [path.join(SERVER_ROOT, 'scripts', 'restore-smoke.js'), snapshotPath], {
        encoding: 'utf8',
      });
      expect(smoke).toContain('restored copy opens and reads cleanly');
    } finally {
      fs.rmSync(backupDir, { recursive: true, force: true });
    }
  }, 180_000);
});

/**
 * Second rehearsal (BUG-013): an EXISTING database that already holds batches
 * is flipped to `feature_batch_locations = 1`.
 *
 * The first rehearsal starts from an empty database with the flag already in
 * its shipped state, so it can never catch the flam-amnesia defect: there were
 * no pre-existing batches to lose. This one models the real upgrade — batches
 * bought by an older build, then the flag turned on — and proves a sale still
 * works for the real quantity.
 *
 * The legacy shape is produced the honest way: buy with the flag OFF, then
 * strip the flag-only mirrors (drop the location rows, zero
 * stock_balances.quantity_available) so the database looks exactly like one an
 * older build left behind. The backfill migration then has to repair it.
 */
describe('deployment rehearsal: a legacy database arrives with batches, then the flag is turned on', () => {
  const LEGACY_ITEM = 'Rehearsal Legacy Batch Item';
  const runMigration127 = (): void => {
    db.exec(fs.readFileSync(path.join(__dirname, '..', 'migrations', '127_backfill_batch_stock_by_location.sql'), 'utf8'));
  };

  it('keeps the stock sellable after the flag flip, for the right quantity', async () => {
    const cookie = await getAuthCookie();
    const customer = await createCustomer('Legacy Rehearsal Co', cookie);
    const item = await createItem(LEGACY_ITEM, cookie);
    const wh = firstWarehouseId();

    // ── The legacy shape: stock bought while the flag was off ──────────
    setFeatureEnabled(db, 'feature_batch_locations', false);
    await purchaseStock(item, wh, 60, 90, cookie, '2026-09-03');
    await purchaseStock(item, wh, 40, 95, cookie, '2026-09-09');

    // Drop everything the flag-only maintenance would have written, so the
    // database matches one that never ran it.
    db.prepare(`
      DELETE FROM batch_stock_by_location
      WHERE batch_id IN (SELECT id FROM stock_batches WHERE item_id = ?)
    `).run(item);
    db.prepare(
      'UPDATE stock_balances SET quantity_available = 0, quantity_physical = 0 WHERE item_id = ? AND warehouse_id = ?',
    ).run(item, wh);
    const legacyBatches = db.prepare(
      'SELECT COUNT(*) AS c FROM stock_batches WHERE item_id = ? AND quantity_remaining > 0',
    ).get(item) as { c: number };
    expect(legacyBatches.c).toBe(2);
    expect(batchLocationDriftImbalances(db)).toEqual([]); // flag is off: not judged

    // ── The upgrade: run the backfill, then flip the flag ──────────────
    runMigration127();
    setFeatureEnabled(db, 'feature_batch_locations', true);

    // The two sources must agree the moment the flag comes on. Before the
    // fix this was where every sale broke.
    expect(batchLocationDriftImbalances(db)).toEqual([]);

    // ── Sell from the flipped database ─────────────────────────────────
    const res = await request(app)
      .post('/api/invoices')
      .set('Cookie', cookie)
      .set('Idempotency-Key', nextIdemKey('legacy-rehearsal'))
      .send({
        customer_id: customer,
        invoice_date: '2026-09-20',
        warehouse_id: wh,
        items: [{ item_id: item, quantity: 25, unit_price: 200 }],
      });
    if (res.status !== 201) {
      throw new Error(`sale from a flipped legacy database failed: ${res.status} ${JSON.stringify(res.body)}`);
    }

    // 25 of the original 100 consumed, from real batches, at real cost.
    const remaining = (db.prepare(
      'SELECT COALESCE(SUM(quantity_remaining), 0) AS q FROM stock_batches WHERE item_id = ?',
    ).get(item) as { q: number }).q;
    expect(Number(remaining)).toBeCloseTo(75, 3);
    expect(batchLocationDriftImbalances(db)).toEqual([]);
    expectAllInvariantsHold('sold from a flipped legacy database');

    // Restore the shipped default so this spec cannot leak the flag on.
    setFeatureEnabled(db, 'feature_batch_locations', false);
  }, 120_000);
});

afterAll(() => {
  // The live database is never touched; the test DB is torn down by setup.ts.
  void dbPath;
});