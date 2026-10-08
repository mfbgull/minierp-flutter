/**
 * settlement-cash-integrity — five paths where a document could claim or
 * extract money that was never collected.
 *
 * C-01  `return_settlements.payment_id` was never written. The adjust branch
 *       already voided `payment_allocations` by that id, so a NULL made the
 *       allocation-undo a silent no-op AND left the CREDIT_OFFSET GL group
 *       live: void → refund paid the supplier a second time.
 * C-02  `refund_expected` on a purchase return refunded the FULL return value
 *       regardless of what had been collected, manufacturing `Dr Cash / Cr AP`
 *       out of an unpaid purchase.
 * H-03  The same fabrication on the goods-receipt leg.
 * SALES-005  `postInvoiceEntry` returns null for a non-positive total, so
 *       editing a paid invoice's lines down to zero voided Dr 1100 / Cr 4000
 *       and reposted nothing — a bare Cr 1100 on a debit-normal asset.
 * SALES-008  The settlement allocation ceiling counted returned goods but not
 *       prior payments, so an already-paid invoice could be settled again for
 *       the full total: cash collected twice.
 *
 * Each block asserts the LEDGER consequence, not just the HTTP status. A 400
 * with a repaired trial balance is the pass condition for the guards; a 400
 * that leaves the books wrong is not a fix.
 */
import fs from 'fs';
import path from 'path';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { SupplierPaymentService } from '../services/SupplierPaymentService';
import {
  createCustomer,
  createInvoice,
  createItem,
  getAuthCookie,
  glTotalsFor,
  processReturn,
  purchaseStock,
  purchaseWithNamedSupplier,
  resolveSupplierByName,
  settlementsFor,
  voidSettlement,
} from './helpers/invoiceReturnSpec';

let authCookie = '';
let warehouseId = 0;

beforeAll(async () => {
  authCookie = await getAuthCookie();
  expect(authCookie).not.toBe('');
  warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
});

/** Live trial balance must foot. A "fix" that unbalances the books is not one. */
function assertTrialBalanceBalanced(where: string): void {
  const r = db.prepare(`
    SELECT COALESCE(SUM(debit),0) AS d, COALESCE(SUM(credit),0) AS c
    FROM journal_lines WHERE voided = 0
  `).get() as { d: number; c: number };
  expect(`${where}: Dr ${r.d} vs Cr ${r.c}`).toBeTruthy();
  expect(Math.abs(Number(r.d) - Number(r.c))).toBeLessThanOrEqual(0.01);
}

/** Net cash (account 1000) across all live lines. */
function netCash(): number {
  const r = db.prepare(`
    SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS n
    FROM journal_lines jl JOIN chart_of_accounts a ON a.id = jl.account_id
    WHERE jl.voided = 0 AND a.code = '1000'
  `).get() as { n: number };
  return Number(r.n);
}

const idOf = (res: request.Response): number =>
  res.body?.id ?? res.body?.data?.id;

describe('C-01 — voiding an adjusted settlement must undo the offset it recorded', () => {
  it('adjust → void returns the payment and releases its allocation', async () => {
    const itemId = await createItem(`C01 item ${Date.now()}`, authCookie);
    await purchaseStock(itemId, warehouseId, 50, 20, authCookie);
    const customerId = await createCustomer(`C01 customer ${Date.now()}`, authCookie);

    const inv = await createInvoice(
      {
        customerId,
        itemId,
        lines: [{ quantity: 4, unitPrice: 400 }],
        invoiceDate: '2026-09-01',
        payment: { amount: 1600 },
      },
      authCookie,
    );

    // The adjust target must be a SEPARATE, unpaid invoice: `applyAdjust`
    // caps `applied` at the target's outstanding balance, so aiming at the
    // fully-paid invoice A yields applied = 0, records no payment, and leaves
    // payment_id legitimately NULL. Adjust is "apply this return credit to
    // another open invoice" — that is the only shape that moves money.
    const target = await createInvoice(
      {
        customerId,
        itemId,
        lines: [{ quantity: 4, unitPrice: 400 }],
        invoiceDate: '2026-09-02',
        payment: null,
      },
      authCookie,
    );

    const ret = await processReturn(
      inv.invoiceId,
      {
        invoiceItemIds: inv.invoiceItemIds,
        quantities: [4],
        warehouseId,
        reason: 'C-01 audit repro',
        settlements: [{ type: 'adjust', amount: 1600, target_invoice_id: target.invoiceId }],
      },
      authCookie,
    );
    expect(ret.status).toBe(200);
    expect(ret.returnId).toBeGreaterThan(0);

    const settlements = settlementsFor(ret.returnId!);
    expect(settlements.length).toBe(1);

    // The whole defect in one assertion: an adjust settlement that recorded a
    // payment MUST carry that payment's id, or its void cannot find it.
    const paymentId = settlements[0].payment_id;
    expect(paymentId).toBeGreaterThan(0);

    // A CREDIT_APPLICATION posts no cash, so its GL is a CREDIT_OFFSET group
    // keyed by the TARGET invoice — not a PAYMENT group keyed by payment id.
    // Asserting on ('PAYMENT', paymentId) reads an empty group before and
    // after the void and would pass on completely unfixed code.
    const offset = glTotalsFor('CREDIT_OFFSET', target.invoiceId);
    expect(offset.debit).toBeGreaterThan(0.01);
    expect(offset.debit).toBeCloseTo(offset.credit, 2);

    const voided = await voidSettlement(settlements[0].id, authCookie);
    expect(voided).toBe(200);

    // Voiding must actually reverse the offset group…
    const after = glTotalsFor('CREDIT_OFFSET', target.invoiceId);
    expect(after.debit).toBeCloseTo(0, 2);
    expect(after.credit).toBeCloseTo(0, 2);

    // …and release the allocation, so the target invoice is collectable again.
    const live = db.prepare(
      'SELECT COUNT(*) AS n FROM payment_allocations WHERE invoice_id = ? AND voided_at IS NULL',
    ).get(target.invoiceId) as { n: number };
    expect(live.n).toBe(0);

    expect(settlementsFor(ret.returnId!)[0].voided_at).not.toBeNull();
    assertTrialBalanceBalanced('C-01 after adjust → void');
  });

  it('voiding twice does not re-run the reversal', async () => {
    const itemId = await createItem(`C01 idempotent item ${Date.now()}`, authCookie);
    await purchaseStock(itemId, warehouseId, 20, 30, authCookie);
    const customerId = await createCustomer(`C01 idempotent customer ${Date.now()}`, authCookie);

    const inv = await createInvoice(
      {
        customerId,
        itemId,
        lines: [{ quantity: 2, unitPrice: 300 }],
        invoiceDate: '2026-09-01',
        payment: { amount: 600 },
      },
      authCookie,
    );

    const ret = await processReturn(
      inv.invoiceId,
      {
        invoiceItemIds: inv.invoiceItemIds,
        quantities: [2],
        warehouseId,
        reason: 'C-01 idempotency',
        settlements: [{ type: 'adjust', amount: 600, target_invoice_id: inv.invoiceId }],
      },
      authCookie,
    );
    expect(ret.status).toBe(200);

    const settlementId = settlementsFor(ret.returnId!)[0].id;
    const cashBefore = netCash();
    expect(await voidSettlement(settlementId, authCookie)).toBe(200);
    // The second void must be rejected, not silently accepted.
    expect(await voidSettlement(settlementId, authCookie)).toBeGreaterThanOrEqual(400);
    expect(netCash()).toBeCloseTo(cashBefore, 2);
    assertTrialBalanceBalanced('C-01 after double void attempt');
  });
});

describe('C-02 / H-03 — a refund cannot exceed what was actually collected', () => {
  /** Create a purchase via the API and return its id. */
  async function seedPurchase(
    itemId: number, quantity: number, unitCost: number, supplierName: string,
  ): Promise<number> {
    await purchaseStock(itemId, warehouseId, quantity, unitCost, authCookie);
    const res = await purchaseWithNamedSupplier(
      supplierName,
      {
        item_id: itemId,
        warehouse_id: warehouseId,
        quantity,
        unit_cost: unitCost,
        purchase_date: '2026-09-01',
        supplier_id: await resolveSupplierByName(supplierName, authCookie),
      },
      authCookie,
    );
    expect([200, 201]).toContain(res.status);
    return idOf(res);
  }

  it('refund_expected is refused when nothing was ever paid', async () => {
    const stamp = Date.now();
    const itemId = await createItem(`C02 unpaid item ${stamp}`, authCookie);
    const purchaseId = await seedPurchase(itemId, 20, 30, `C02 unpaid supplier ${stamp}`);

    const cashBefore = netCash();

    const res = await request(app).post('/api/purchase-returns')
      .set('Cookie', authCookie)
      .send({
        return_date: '2026-09-05',
        source_type: 'PURCHASE',
        source_id: purchaseId,
        warehouse_id: warehouseId,
        reason: 'C-02 refund from an unpaid purchase',
        disposition: 'refund_expected',
        items: [{ source_item_id: purchaseId, quantity: 10 }],
      });

    expect(res.status).toBeGreaterThanOrEqual(400);
    expect(JSON.stringify(res.body)).toMatch(/nothing has been collected/i);
    // The refusal must not have created cash on the way out.
    expect(netCash()).toBeCloseTo(cashBefore, 2);
    assertTrialBalanceBalanced('C-02 unpaid purchase refund');
  });

  it('a partially paid purchase refunds at most the collected amount', async () => {
    const stamp = Date.now();
    const itemId = await createItem(`C02 partial item ${stamp}`, authCookie);
    const supplierName = `C02 partial supplier ${stamp}`;
    const supplierId = await resolveSupplierByName(supplierName, authCookie);
    const purchaseId = await seedPurchase(itemId, 20, 25, supplierName);

    // Pay only 100 against the 500 purchase, through the real payment path.
    new SupplierPaymentService(db).recordSupplierPayment({
      supplierId,
      paymentDate: '2026-09-02',
      amount: 100,
      paymentMethod: 'Cash',
      allocations: [{ kind: 'purchase', id: purchaseId, amount: 100 }],
    });

    const cashBefore = netCash();

    // Return 10 units @ 25 = 250, i.e. 150 MORE than was ever collected.
    const res = await request(app).post('/api/purchase-returns')
      .set('Cookie', authCookie)
      .send({
        return_date: '2026-09-05',
        source_type: 'PURCHASE',
        source_id: purchaseId,
        warehouse_id: warehouseId,
        reason: 'C-02 refund above the collected amount',
        disposition: 'refund_expected',
        items: [{ source_item_id: purchaseId, quantity: 10 }],
      });

    expect(res.status).toBe(201);
    // The cap is the 100 collected — never the 250 return value.
    const collected = netCash() - cashBefore;
    expect(collected).toBeLessThanOrEqual(100.01);
    expect(collected).toBeGreaterThan(0);
    assertTrialBalanceBalanced('C-02 partially paid refund');
  });

  it('credit_on_account on an unpaid purchase is still accepted and moves no cash', async () => {
    const stamp = Date.now();
    const itemId = await createItem(`C02 credit item ${stamp}`, authCookie);
    const purchaseId = await seedPurchase(itemId, 20, 30, `C02 credit supplier ${stamp}`);

    const cashBefore = netCash();
    const res = await request(app).post('/api/purchase-returns')
      .set('Cookie', authCookie)
      .send({
        return_date: '2026-09-05',
        source_type: 'PURCHASE',
        source_id: purchaseId,
        warehouse_id: warehouseId,
        reason: 'C-02 credit instead of refund',
        disposition: 'credit_on_account',
        items: [{ source_item_id: purchaseId, quantity: 10 }],
      });

    expect(res.status).toBe(201);
    expect(netCash()).toBeCloseTo(cashBefore, 2);
    assertTrialBalanceBalanced('C-02 credit_on_account');
  });
});

describe('SALES-005 — an edit that cannot be re-posted is refused, not half-applied', () => {
  it('zeroing a paid invoice returns 400 and leaves the original entry live', async () => {
    const stamp = Date.now();
    const itemId = await createItem(`SALES-005 item ${stamp}`, authCookie);
    await purchaseStock(itemId, warehouseId, 10, 50, authCookie);
    const customerId = await createCustomer(`SALES-005 customer ${stamp}`, authCookie);

    const inv = await createInvoice(
      {
        customerId,
        itemId,
        lines: [{ quantity: 2, unitPrice: 200 }],
        invoiceDate: '2026-09-01',
        payment: { amount: 400 },
      },
      authCookie,
    );

    // Compare the group's SIZE, not debit-minus-credit: a double-entry group
    // is always Dr == Cr, so `debit - credit` is 0 for both a healthy sale
    // and a voided one. Only the magnitude tells them apart.
    const before = glTotalsFor('INVOICE', inv.invoiceId);
    expect(before.debit).toBeGreaterThan(0.01);
    expect(before.debit).toBeCloseTo(before.credit, 2);

    const edit = await request(app).put(`/api/invoices/${inv.invoiceId}`)
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId,
        invoice_date: '2026-09-01',
        items: [{
          item_id: itemId,
          quantity: 0,
          unit_price: 200,
          discount_type: 'none',
          discount_value: 0,
        }],
      });

    expect(edit.status).toBe(400);

    // The refusal must be clean: the original sale is still on the books. A
    // voided group would read debit 0 here, because `glTotalsFor` skips
    // voided lines.
    const after = glTotalsFor('INVOICE', inv.invoiceId);
    expect(after.debit).toBeCloseTo(before.debit, 2);
    expect(after.credit).toBeCloseTo(before.credit, 2);
    const row = db.prepare('SELECT total_amount FROM invoices WHERE id = ?')
      .get(inv.invoiceId) as { total_amount: number };
    expect(Number(row.total_amount)).toBeCloseTo(400, 2);
    assertTrialBalanceBalanced('SALES-005 refused zero-total edit');
  });

  it('reducing a paid invoice while keeping it positive is still allowed', async () => {
    const stamp = Date.now();
    const itemId = await createItem(`SALES-005 reduce item ${stamp}`, authCookie);
    await purchaseStock(itemId, warehouseId, 10, 50, authCookie);
    const customerId = await createCustomer(`SALES-005 reduce customer ${stamp}`, authCookie);

    const inv = await createInvoice(
      {
        customerId,
        itemId,
        lines: [{ quantity: 4, unitPrice: 100 }],
        invoiceDate: '2026-09-01',
        payment: { amount: 400 },
      },
      authCookie,
    );

    // 400 paid, edited down to 200: the payment is untouched and the balance
    // floors at 0. Legitimate, and must NOT be caught by the new guard.
    const edit = await request(app).put(`/api/invoices/${inv.invoiceId}`)
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId,
        invoice_date: '2026-09-01',
        items: [{
          item_id: itemId,
          quantity: 2,
          unit_price: 100,
          discount_type: 'none',
          discount_value: 0,
        }],
      });

    expect(edit.status).toBe(200);
    const row = db.prepare('SELECT total_amount, paid_amount FROM invoices WHERE id = ?')
      .get(inv.invoiceId) as { total_amount: number; paid_amount: number };
    expect(Number(row.total_amount)).toBeCloseTo(200, 2);
    expect(Number(row.paid_amount)).toBeCloseTo(400, 2);
    assertTrialBalanceBalanced('SALES-005 allowed reduce-paid edit');
  });
});

describe('H-03 — a customer refund is capped by the cash actually collected', () => {
  /**
   * Settle an invoice ENTIRELY with store credit, then refund it in cash.
   * The credit pool is seeded the way the app does it: sell, pay in full,
   * return the goods with `disposition: 'credit'`. The offset then settles
   * invoice 2 without a single cash allocation — paid_amount > 0, collected
   * cash = 0. Before the fix, refunding that invoice paid real cash out.
   */
  async function seedCashlessInvoice(): Promise<{ invoiceId: number; itemIds: number[] }> {
    const stamp = Date.now();
    const itemId = await createItem(`H03 item ${stamp}`, authCookie);
    await purchaseStock(itemId, warehouseId, 40, 25, authCookie);
    const customerId = await createCustomer(`H03 customer ${stamp}`, authCookie);

    // Seed the credit pool: a 400 invoice paid in cash, then fully returned to credit.
    const pool = await request(app).post('/api/invoices')
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId,
        invoice_date: '2026-09-01',
        items: [{
          item_id: itemId, quantity: 4, unit_price: 100, tax_rate: 0,
          discount_type: 'none', discount_value: 0,
        }],
        record_payment: true,
        payment: { payment_date: '2026-09-01', amount: 400, payment_method: 'Cash' },
      });
    expect(pool.status).toBe(201);

    const poolItem = db.prepare('SELECT id FROM invoice_items WHERE invoice_id = ?')
      .get(pool.body.id) as { id: number };
    const seeded = await request(app).post(`/api/invoices/${pool.body.id}/return`)
      .set('Cookie', authCookie)
      .send({
        reason: 'H03 seed credit pool',
        disposition: 'credit',
        warehouse_id: warehouseId,
        items: [{ invoice_item_id: poolItem.id, return_quantity: 4 }],
      });
    expect(seeded.status).toBe(200);

    // Settle a 400 invoice with that credit and NO cash.
    const cashless = await request(app).post('/api/invoices')
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId,
        invoice_date: '2026-09-10',
        items: [{
          item_id: itemId, quantity: 4, unit_price: 100, tax_rate: 0,
          discount_type: 'none', discount_value: 0,
        }],
        credit_offset: 400,
      });
    expect(cashless.status).toBe(201);

    const row = db.prepare('SELECT paid_amount, credit_offset FROM invoices WHERE id = ?')
      .get(cashless.body.id) as { paid_amount: number; credit_offset: number };
    // Settled — but by credit, so there is no cash to hand back.
    expect(Number(row.paid_amount)).toBeCloseTo(400, 2);
    expect(Number(row.credit_offset)).toBeCloseTo(400, 2);

    const itemRows = db.prepare('SELECT id FROM invoice_items WHERE invoice_id = ? ORDER BY id')
      .all(cashless.body.id) as Array<{ id: number }>;
    return { invoiceId: cashless.body.id as number, itemIds: itemRows.map((r) => r.id) };
  }

  it('refunding a store-credit-settled invoice is refused', async () => {
    const { invoiceId, itemIds } = await seedCashlessInvoice();

    const cashBefore = netCash();
    const ret = await processReturn(
      invoiceId,
      {
        invoiceItemIds: itemIds,
        quantities: [4],
        warehouseId,
        reason: 'H03 refund a credit-settled invoice',
        settlements: [{ type: 'refund', amount: 400, method: 'Cash' }],
      },
      authCookie,
    );

    expect(ret.status).toBe(400);
    expect(JSON.stringify(ret.body)).toMatch(/exceeds the .* collected/i);
    expect(netCash()).toBeCloseTo(cashBefore, 2);
    assertTrialBalanceBalanced('H-03 credit-settled refund');
  });

  it('a partially cash-settled invoice refunds only its cash portion', async () => {
    const stamp = Date.now();
    const itemId = await createItem(`H03 partial item ${stamp}`, authCookie);
    await purchaseStock(itemId, warehouseId, 20, 50, authCookie);
    const customerId = await createCustomer(`H03 partial customer ${stamp}`, authCookie);

    // 400 total, settled with 100 cash → only 100 may ever come back.
    const inv = await request(app).post('/api/invoices')
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId,
        invoice_date: '2026-09-10',
        items: [{
          item_id: itemId, quantity: 4, unit_price: 100, tax_rate: 0,
          discount_type: 'none', discount_value: 0,
        }],
        record_payment: true,
        payment: { payment_date: '2026-09-10', amount: 100, payment_method: 'Cash' },
      });
    expect(inv.status).toBe(201);

    const itemIds = (db.prepare('SELECT id FROM invoice_items WHERE invoice_id = ? ORDER BY id')
      .all(inv.body.id) as Array<{ id: number }>).map((r) => r.id);

    const tooMuch = await processReturn(
      inv.body.id as number,
      {
        invoiceItemIds: itemIds,
        quantities: [4],
        warehouseId,
        reason: 'H03 over-refund',
        settlements: [{ type: 'refund', amount: 400, method: 'Cash' }],
      },
      authCookie,
    );
    expect(tooMuch.status).toBe(400);

    // The same return refunding within the cap is accepted.
    const ok = await processReturn(
      inv.body.id as number,
      {
        invoiceItemIds: itemIds,
        quantities: [4],
        warehouseId,
        reason: 'H03 refund within cap',
        settlements: [{ type: 'refund', amount: 100, method: 'Cash' }],
      },
      authCookie,
    );
    expect(ok.status).toBe(200);
    assertTrialBalanceBalanced('H-03 partial cash refund');
  });
});

/**
 * SALES-008 — recorded `won't-fix`, so the hazard it describes needs a live
 * guard rather than a docstring.
 *
 * The audit's finding is real as written: `INVOICE_SETTLEMENT`'s ceiling is the
 * invoice GROSS total, so it ignores payments already received. It is not
 * reachable today because that mode has exactly one production caller, which
 * creates the invoice and records its payment in the same transaction — the row
 * is already stored as settled when the ceiling is evaluated, so the gross total
 * is the correct ceiling for it.
 *
 * A docstring is not a guard. This asserts the structural fact that makes the
 * finding unreachable, so a second caller is caught at review time rather than
 * discovered on a customer's overpaid invoice.
 */
describe('SALES-008 — INVOICE_SETTLEMENT stays creation-only', () => {
  const SRC = path.join(__dirname, '..');
  const SCAN_DIRS = ['services', 'models', 'controllers', 'middleware'];

  const walk = (dir: string): string[] => {
    const out: string[] = [];
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        if (entry.name === '__tests__') continue;
        out.push(...walk(full));
      } else if (entry.name.endsWith('.ts')) {
        out.push(full);
      }
    }
    return out;
  };

  /**
   * Matches the object-literal call shape only, so it skips the union member in
   * `paymentRecordingTypes.ts` (`| 'INVOICE_SETTLEMENT'`) and the branch test in
   * `paymentValidation.ts` (`mode === 'INVOICE_SETTLEMENT'`). What is left is
   * exactly the set of places that actually record a payment under this mode.
   */
  const CALL_SITE = /mode:\s*'INVOICE_SETTLEMENT'/g;

  const callSites = (): Array<{ file: string; line: number }> =>
    SCAN_DIRS.flatMap((d) => {
      const dir = path.join(SRC, d);
      if (!fs.existsSync(dir)) return [];
      return walk(dir).flatMap((file) => {
        const src = fs.readFileSync(file, 'utf8');
        const hits: Array<{ file: string; line: number }> = [];
        for (const m of src.matchAll(CALL_SITE)) {
          hits.push({ file: path.relative(SRC, file), line: src.slice(0, m.index).split('\n').length });
        }
        return hits;
      });
    });

  it('has exactly one production caller, and it is the invoice-creation path', () => {
    // Joined into one string so a failure diff names the offending call sites
    // directly. `@types/jest` here does not declare `expect(actual, message)`.
    const sites = callSites().map((s) => `${s.file}:${s.line}`);
    expect(sites.join(', ') || '(no production callers)').toBe('services/InvoiceCreationService.ts:256');
  });

  it('still resolves the ceiling from total minus returned, not from balance', () => {
    // Pins WHY the mode is creation-only: the creation caller stores the row as
    // settled, so a balance-based ceiling would reject every fully-paid invoice.
    const src = fs.readFileSync(path.join(SRC, 'services/paymentValidation.ts'), 'utf8');
    expect(src).toMatch(/mode === 'INVOICE_SETTLEMENT'\)\s*\{\s*return \{ amount: parseCurrency\(invoice\.total_amount\)/);
  });
});
