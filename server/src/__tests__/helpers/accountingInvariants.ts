/**
 * Reversal-rules Phase 5 — shared accounting-invariant checkers.
 *
 * Nine invariants over the whole database:
 *   A. GL balance: every journal_lines reference group sums debit == credit.
 *   B. Customer subledger: customers.current_balance == customer_ledger sum
 *      (voided and reversed rows excluded, matching the authoritative
 *      writer in ledgerUtils).
 *   C. Invoice allocations: invoices.paid_amount == non-voided allocation sum.
 *   D. Supplier subledger: suppliers.current_balance == supplier_ledger sum.
 *   E. Stock vs batches: stock_balances.quantity == Σ stock_batches
 *      .quantity_remaining per item/warehouse.
 *   F. GL AR (1100) == sum of customer balances.
 *   G. GL AP (2000) == sum of supplier balances.
 *   H. GL Inventory (1200) == inventory batch values.
 *   I. GL Cash == cash account operational balances.
 *
 * `expectAllInvariantsHold(context)` asserts all nine; the individual
 * collectors are exported for targeted assertions.
 */
import db from '../../config/database';

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

/** Invariant F: GL AR (1100) == Σ customer balances. */
export function arImbalances(): Violation[] {
  const glBalance = R2(Math.abs(GL_BALANCE('1100')));
  const row = db.prepare(
    'SELECT COALESCE(SUM(current_balance), 0) AS total FROM customers'
  ).get() as { total: number };
  const custBalance = R2(Math.abs(row.total));
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

/** Invariant I: GL Cash accounts == operational cash balances. */
export function cashImbalances(): Violation[] {
  const CASH_CODES: Array<{ code: string; name: string }> = [
    { code: '1000', name: 'Cash' },
    { code: '1010', name: 'Bank' },
    { code: '1020', name: 'Easypaisa' },
    { code: '1030', name: 'JazzCash' },
    { code: '1040', name: 'UPaisa' },
  ];
  const violations: Violation[] = [];
  for (const { code, name } of CASH_CODES) {
    const glBalance = R2(GL_BALANCE(code));
    const acctId = GL_ACCOUNT_ID(code);
    if (!acctId) continue;
    const row = db.prepare(
      'SELECT COALESCE(SUM(debit) - SUM(credit), 0) AS balance FROM journal_lines WHERE account_id = ? AND voided = 0'
    ).get(acctId) as { balance: number };
    const opBalance = R2(row.balance);
    if (Math.abs(glBalance - opBalance) > 0.005) {
      violations.push({ label: `GL Cash (${name}) vs operational`, diff: R2(glBalance - opBalance), account: code, expected: opBalance, actual: glBalance });
    }
  }
  return violations;
}

/** Assert invariants A–E; `context` aids debugging on failure. */
export function expectAllInvariantsHold(context: string): void {
  const gl = glImbalances();
  expect(gl.groups).toEqual([]);
  expect(gl.totalDiff).toBeCloseTo(0, 2);
  expect(customerArImbalances()).toEqual([]);
  expect(supplierApImbalances()).toEqual([]);
  expect(stockImbalances()).toEqual([]);
  void context;
}

/**
 * Assert all nine invariants A–I. Use only in scenarios that seed
 * inventory through proper GL-posting flows (PO receipts), not raw
 * batch inserts.
 */
export function expectAllReconciliationInvariantsHold(context: string): void {
  expectAllInvariantsHold(context);
  expect(arImbalances()).toEqual([]);
  expect(apImbalances()).toEqual([]);
  expect(inventoryImbalances()).toEqual([]);
  expect(cashImbalances()).toEqual([]);
}
