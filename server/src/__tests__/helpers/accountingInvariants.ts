/**
 * Reversal-rules Phase 5 — shared accounting-invariant checkers.
 *
 * Five invariants over the whole database:
 *   A. GL balance: every journal_lines reference group sums debit == credit.
 *   B. Customer subledger: customers.current_balance == customer_ledger sum
 *      (voided and reversed rows excluded, matching the authoritative
 *      writer in ledgerUtils).
 *   C. Invoice allocations: invoices.paid_amount == non-voided allocation sum.
 *   D. Supplier subledger: suppliers.current_balance == supplier_ledger sum.
 *   E. Stock vs batches: stock_balances.quantity == Σ stock_batches
 *      .quantity_remaining per item/warehouse.
 *
 * `expectAllInvariantsHold(context)` asserts all five; the individual
 * collectors are exported for targeted assertions.
 */
import db from '../../config/database';

export interface Violation {
  label: string;
  diff: number;
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

  const paidDrift = db.prepare(`
    SELECT i.id, i.invoice_no,
           i.paid_amount - COALESCE(a.paid, 0) AS diff
    FROM invoices i
    LEFT JOIN (
      SELECT invoice_id, SUM(amount) AS paid
      FROM payment_allocations WHERE voided_at IS NULL
      GROUP BY invoice_id
    ) a ON a.invoice_id = i.id
    WHERE ABS(i.paid_amount - COALESCE(a.paid, 0)) > 0.005
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

/** Assert all five invariants; `context` aids debugging on failure. */
export function expectAllInvariantsHold(context: string): void {
  const gl = glImbalances();
  expect(gl.groups).toEqual([]);
  expect(gl.totalDiff).toBeCloseTo(0, 2);
  expect(customerArImbalances()).toEqual([]);
  expect(supplierApImbalances()).toEqual([]);
  expect(stockImbalances()).toEqual([]);
  void context;
}
