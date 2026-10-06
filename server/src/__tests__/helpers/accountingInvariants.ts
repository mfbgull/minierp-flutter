/**
 * Reversal-rules Phase 5 — shared accounting-invariant checkers.
 *
 * Nine invariants over the whole database, each with the collector that checks
 * it. The collectors are exported individually for targeted assertions.
 *
 * `expectAllInvariantsHold(context)` is the master gate but does NOT yet cover
 * all nine. It asserts **A–E, F, G and H**. I is reached only by `checkF_I`
 * inside accountingInvariants.test.ts. It is deferred because it has no
 * planted-drift proof that the MASTER reaches it — the file's existing cash
 * drift test calls `cashImbalances` directly, so it cannot fail if the master's
 * I call were deleted. Land it with a guard of its own; that is the next step,
 * not an oversight.
 *
 * When adding an invariant: add a row below AND a call in the master, or record
 * the reason it is deferred. This list is the checklist.
 *
 *   A. GL balance: every journal_lines reference group sums debit == credit.
 *      → glImbalances
 *   B. Customer subledger: customers.current_balance == customer_ledger sum
 *      (voided and reversed rows excluded, matching the authoritative
 *      writer in ledgerUtils).
 *      → customerArImbalances
 *   C. Invoice allocations: invoices.paid_amount == non-voided allocation sum.
 *      → customerArImbalances
 *   D. Supplier subledger: suppliers.current_balance == supplier_ledger sum.
 *      → supplierApImbalances
 *   E. Stock vs batches: stock_balances.quantity == Σ stock_batches
 *      .quantity_remaining per item/warehouse.
 *      → stockImbalances
 *   F. GL AR (1100 + 1110) == Σ (current_balance - credit_balance).
 *      → arImbalances
 *   G. GL AP (2000) == Σ supplier current_balance.
 *      → apImbalances
 *   H. GL Inventory (1200) == inventory batch values.
 *      → inventoryImbalances
 *   I. GL Cash == cash account operational balances.
 *      → cashImbalances        [deferred — no master-level guard yet]
 *
 * G needs no second subledger term the way F did: `suppliers` has no
 * `credit_balance` column and supplier prepayments are DESIGN-ONLY
 * (docs/supplier-prepayments-design.md), so `current_balance` is the whole
 * supplier position. Note the GL/subledger signs are OPPOSITE for AP — 2000 is
 * credit-normal while the ledger runs debit-positive — so the `Math.abs()` in
 * `apImbalances` is load-bearing here, unlike F's where it is inert.
 *
 * A returns a two-field object rather than `Violation[]`, so the master
 * asserts its `groups`/`totalDiff` pair separately.
 */
import db from '../../config/database';
import { collectFlows, CASH_ACCOUNTS, CASH_GL_CODES } from '../../services/cashService';

export interface Violation {
  label: string;
  diff: number;
  /** Structured detail for reconciliation invariants F-I. */
  account?: string;
  expected?: number;
  actual?: number;
  reference?: string;
}

interface GroupImbalance {
  reference_type: string;
  reference_id: number;
  diff: number;
}

/** Invariant A: every reference group balances; the ledger balances. */
export function glImbalances(): { groups: GroupImbalance[]; totalDiff: number } {
  const groups = db.prepare(`
    SELECT reference_type, reference_id,
           ABS(SUM(debit) - SUM(credit)) AS diff
    FROM journal_lines WHERE voided = 0
    GROUP BY reference_type, reference_id
    HAVING diff > 0.005
  `).all() as unknown as GroupImbalance[];
  const total = db.prepare(`
    SELECT ABS(COALESCE(SUM(debit), 0) - COALESCE(SUM(credit), 0)) AS diff
    FROM journal_lines WHERE voided = 0
  `).get() as { diff: number };
  return { groups, totalDiff: Number(total.diff) };
}

/** Invariants B + C (customer side). */
export function customerArImbalances(): Violation[] {
  const problems: Violation[] = [];

  const custDrift = db.prepare(`
    SELECT c.id, c.customer_name,
           c.current_balance - COALESCE(l.net, 0) AS diff
    FROM customers c
    LEFT JOIN (
      SELECT customer_id, SUM(debit) - SUM(credit) AS net
      FROM customer_ledger WHERE voided = 0 AND reversed_by IS NULL
      GROUP BY customer_id
    ) l ON l.customer_id = c.id
    WHERE ABS(c.current_balance - COALESCE(l.net, 0)) > 0.005
  `).all() as Array<{ id: number; customer_name: string; diff: number }>;
  for (const r of custDrift) {
    problems.push({ label: `customer ${r.id} (${r.customer_name}) balance vs ledger`, diff: r.diff });
  }

  // paid_amount is the gross collected base — positive allocations plus
  // any credit offset applied at sale. Refund allocations are negative
  // out-flows that must not shrink it (invoice-return spec §3.2 /
  // scenario 10), so the comparison excludes them here.
  const paidDrift = db.prepare(`
    SELECT i.id, i.invoice_no,
           i.paid_amount - (COALESCE(a.paid, 0) + COALESCE(i.credit_offset, 0)) AS diff
    FROM invoices i
    LEFT JOIN (
      SELECT invoice_id, SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END) AS paid
      FROM payment_allocations WHERE voided_at IS NULL
      GROUP BY invoice_id
    ) a ON a.invoice_id = i.id
    WHERE ABS(i.paid_amount - (COALESCE(a.paid, 0) + COALESCE(i.credit_offset, 0))) > 0.005
  `).all() as Array<{ id: number; invoice_no: string; diff: number }>;
  for (const r of paidDrift) {
    problems.push({ label: `invoice ${r.id} (${r.invoice_no}) paid_amount vs allocations`, diff: r.diff });
  }

  return problems;
}

/** Invariant D (supplier side). */
export function supplierApImbalances(): Violation[] {
  const drift = db.prepare(`
    SELECT s.id, s.supplier_name,
           s.current_balance - COALESCE(l.net, 0) AS diff
    FROM suppliers s
    LEFT JOIN (
      SELECT supplier_id, SUM(debit) - SUM(credit) AS net
      FROM supplier_ledger WHERE voided = 0 AND reversed_by IS NULL
      GROUP BY supplier_id
    ) l ON l.supplier_id = s.id
    WHERE ABS(s.current_balance - COALESCE(l.net, 0)) > 0.005
  `).all() as Array<{ id: number; supplier_name: string; diff: number }>;
  return drift.map((r) => ({
    label: `supplier ${r.id} (${r.supplier_name}) balance vs ledger`,
    diff: r.diff,
  }));
}

/** Invariant E: balances == remaining batch quantities. */
export function stockImbalances(): Violation[] {
  return db.prepare(`
    SELECT b.item_id || '/' || b.warehouse_id AS label,
           sb.quantity - COALESCE(b.total, 0) AS diff
    FROM stock_balances sb
    JOIN (
      SELECT item_id, warehouse_id, SUM(quantity_remaining) AS total
      FROM stock_batches GROUP BY item_id, warehouse_id
    ) b ON b.item_id = sb.item_id AND b.warehouse_id = sb.warehouse_id
    WHERE ABS(sb.quantity - COALESCE(b.total, 0)) > 0.005
  `).all() as unknown as Violation[];
}

// ============================================================================
// Invariants F–I: GL ↔ operational-balance reconciliation
// ============================================================================

const GL_ACCOUNT_ID = (code: string): number | undefined =>
  (db.prepare('SELECT id FROM chart_of_accounts WHERE code = ?').get(code) as { id: number } | undefined)?.id;

const GL_BALANCE = (code: string): number => {
  const id = GL_ACCOUNT_ID(code);
  if (!id) return 0;
  const row = db.prepare(
    'SELECT COALESCE(SUM(debit) - SUM(credit), 0) AS balance FROM journal_lines WHERE account_id = ? AND voided = 0'
  ).get(id) as { balance: number };
  return Number(row.balance);
};

const R2 = (v: number): number => Math.round(v * 100) / 100;

/** Invariant F: GL AR (1100) + Customer Credit (1110) == Σ customer balances.
 *
 * 1110 (Customer Credit) is a contra of AR: store credit granted on a return
 * is credited to 1110, so a settled credit offset leaves GL AR at zero while
 * customer_ledger is also zero. Comparing 1100 alone drifts by exactly the
 * 1110 balance on credit return/offset flows — measured, not assumed.
 *
 * The subledger side is `SUM(current_balance) - SUM(credit_balance)`, and the
 * minus sign is not cosmetic. H9 (models/AGENTS.md, CREDIT OFFSET BEHAVIOR)
 * defines customer credit as TWO non-overlapping representations:
 *
 *   - `current_balance` — signed. Positive means the customer owes us.
 *   - `credit_balance` — unsigned pool. Positive means WE owe the customer,
 *     granted by a return settled as store credit.
 *
 * `applyCredit` zeroes the RETURN credit out of `current_balance` with a
 * consuming CREDIT debit precisely so the same money is not counted twice, so
 * granted store credit exists ONLY in `credit_balance`. Reading `current_balance`
 * alone therefore drops the entire granted-but-unconsumed pool from the
 * operational side and reports a violation equal to it.
 *
 * Derived by measurement, not assumed. Across the six states of the H9 store
 * credit lifecycle (grant, partial consumption, full consumption, over-
 * application rejection) `current_balance` alone mismatches on three of them;
 * `current_balance + credit_balance` mismatches on three; only the subtraction
 * reconciles on all six. Signs agree on the GL and subledger sides at every
 * state, so the Math.abs() below is inert here and does not mask an inversion.
 *
 * The Math.abs() on both sides is retained deliberately. Measured 2026-10-04
 * across all 17 call sites: GL and Σ current_balance are exactly equal and
 * positive every time, so the abs is inert today. It would mask a future
 * equal-magnitude sign inversion (GL +x against subledger −x). Removing it
 * asserts that a negative AR position must fail the invariant, which is an
 * accounting-policy decision and not a test-mechanics one — so it is left in
 * place until that convention is decided. Do not "simplify" this away. */
export function arImbalances(): Violation[] {
  const glBalance = R2(Math.abs(GL_BALANCE('1100') + GL_BALANCE('1110')));
  const row = db.prepare(
    'SELECT COALESCE(SUM(current_balance), 0) AS receivable, COALESCE(SUM(credit_balance), 0) AS storeCredit FROM customers'
  ).get() as { receivable: number; storeCredit: number };
  const custBalance = R2(Math.abs(R2(row.receivable) - R2(row.storeCredit)));
  if (Math.abs(glBalance - custBalance) > 0.005) {
    return [{ label: 'GL AR vs customer balances', diff: R2(glBalance - custBalance), account: '1100', expected: custBalance, actual: glBalance }];
  }
  return [];
}

/** Invariant G: GL AP (2000) == Σ supplier balances. */
export function apImbalances(): Violation[] {
  const glBalance = R2(Math.abs(GL_BALANCE('2000')));
  const row = db.prepare(
    'SELECT COALESCE(SUM(current_balance), 0) AS total FROM suppliers'
  ).get() as { total: number };
  const supBalance = R2(Math.abs(row.total));
  if (Math.abs(glBalance - supBalance) > 0.005) {
    return [{ label: 'GL AP vs supplier balances', diff: R2(glBalance - supBalance), account: '2000', expected: supBalance, actual: glBalance }];
  }
  return [];
}

/** Invariant H: GL Inventory (1200) == stock batch + legacy item values. */
export function inventoryImbalances(): Violation[] {
  const glBalance = R2(Math.abs(GL_BALANCE('1200')));
  const batchVal = db.prepare(
    'SELECT COALESCE(SUM(quantity_remaining * unit_cost), 0) AS v FROM stock_batches WHERE quantity_remaining > 0'
  ).get() as { v: number };
  const legacyVal = db.prepare(`
    SELECT COALESCE(SUM(i.current_stock * i.standard_cost), 0) AS v
    FROM items i
    WHERE i.is_active = 1 AND i.current_stock > 0
      AND NOT EXISTS (SELECT 1 FROM stock_batches sb WHERE sb.item_id = i.id AND sb.quantity_remaining > 0)
  `).get() as { v: number };
  const opBalance = R2(batchVal.v + legacyVal.v);
  if (Math.abs(glBalance - opBalance) > 0.005) {
    return [{ label: 'GL Inventory vs batch values', diff: R2(glBalance - opBalance), account: '1200', expected: opBalance, actual: glBalance }];
  }
  return [];
}

/** Invariant I: GL Cash accounts == operational cash balances.
 *
 * Operational side is collectFlows (business rows + opening seed), never
 * journal_lines — the pre-audit version compared GL against itself and
 * could not fail. Explicit floor/upto bounds put every row in the main
 * queries so the seed is counted exactly once; 'unclassified' has no GL
 * account and is skipped. */
export function cashImbalances(): Violation[] {
  const flows = collectFlows(db, '9999-12-31', '1970-01-01');
  const violations: Violation[] = [];
  for (const { key, name } of CASH_ACCOUNTS) {
    const code = CASH_GL_CODES[key];
    const acctId = code ? GL_ACCOUNT_ID(code) : undefined;
    if (!acctId) continue;
    const flow = flows.get(key);
    const opBalance = R2((flow?.inflow ?? 0) - (flow?.outflow ?? 0));
    const glBalance = R2(GL_BALANCE(code));
    if (Math.abs(glBalance - opBalance) > 0.005) {
      violations.push({ label: `GL Cash (${name}) vs operational`, diff: R2(glBalance - opBalance), account: code, expected: opBalance, actual: glBalance });
    }
  }
  return violations;
}

/** Assert invariants A–E, F, G and H; `context` labels the call site for the reader.
 *
 *  Still NOT "all nine". I is deferred pending its own planted-drift proof:
 *  the existing cash drift test calls `cashImbalances` DIRECTLY, so it cannot
 *  fail if the master's I call were deleted. See the file header for the map. */
export function expectAllInvariantsHold(context: string): void {
  const gl = glImbalances();
  expect(gl.groups).toEqual([]);
  expect(gl.totalDiff).toBeCloseTo(0, 2);
  expect(customerArImbalances()).toEqual([]);
  expect(supplierApImbalances()).toEqual([]);
  expect(stockImbalances()).toEqual([]);
  expect(arImbalances()).toEqual([]);
  expect(apImbalances()).toEqual([]);
  expect(inventoryImbalances()).toEqual([]);
  void context;
}
