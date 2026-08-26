/**
 * Orphaned customer-ledger repair (ACC-14 style)
 * ----------------------------------------------
 * Hard-deleted invoices/payments from legacy code paths left customer_ledger
 * rows whose source document no longer exists. Those phantom debits/credits
 * corrupt the running balance (ACC-13), so customer screens show balances
 * that disagree with the invoice-based outstanding totals.
 *
 * Detection: active rows (voided = 0, reversed_by IS NULL) whose
 * reference_no resolves to no row in the parent table:
 *   - INVOICE / RETURN  → invoices.invoice_no
 *   - PAYMENT / REFUND  → payments.payment_no
 *
 * Correction: append-only. Each orphan gets an equal-and-opposite
 * REVERSAL row (reversed_by → original) and the original is marked
 * voided = 1 — the same mechanism ledgerUtils.reverseLedgerEntry uses
 * for payment deletions. Running balances are rebuilt and the
 * authoritative customer balance writer re-runs per affected customer.
 *
 * Usage:
 *   npm run repair:ledger             — dry run (report only, no writes)
 *   npm run repair:ledger -- --apply  — apply the corrections
 */

import db from '../src/config/database';
import ledgerUtils from '../src/utils/ledgerUtils';

const apply = process.argv.includes('--apply');

interface OrphanRow {
  id: number;
  customer_id: number;
  transaction_type: string;
  reference_no: string;
  debit: number;
  credit: number;
  transaction_date: string;
}

const orphans = db.prepare(`
  SELECT cl.id, cl.customer_id, cl.transaction_type, cl.reference_no,
         cl.debit, cl.credit, cl.transaction_date
  FROM customer_ledger cl
  WHERE cl.voided = 0 AND cl.reversed_by IS NULL
    AND (
      (cl.transaction_type IN ('INVOICE', 'RETURN')
        AND cl.reference_no NOT IN (SELECT invoice_no FROM invoices))
      OR
      (cl.transaction_type IN ('PAYMENT', 'REFUND')
        AND cl.reference_no NOT IN (SELECT payment_no FROM payments))
    )
  ORDER BY cl.customer_id, cl.transaction_date, cl.id
`).all() as OrphanRow[];

if (orphans.length === 0) {
  console.log('[INFO] No orphaned customer-ledger entries found. Nothing to do.');
  process.exit(0);
}

console.log(`[INFO] Found ${orphans.length} orphaned ledger entr${orphans.length === 1 ? 'y' : 'ies'}:`);
for (const o of orphans) {
  const amount = o.debit > 0 ? `debit ${o.debit}` : `credit ${o.credit}`;
  console.log(`  ledger#${o.id} customer=${o.customer_id} ${o.transaction_date} ${o.transaction_type} ${o.reference_no} (${amount})`);
}

const affectedCustomers = [...new Set(orphans.map(o => o.customer_id))];

const netsBefore = new Map<number, number>();
for (const cid of affectedCustomers) {
  const row = db.prepare(`
    SELECT COALESCE(SUM(debit), 0) - COALESCE(SUM(credit), 0) AS net
    FROM customer_ledger
    WHERE customer_id = ? AND voided = 0 AND reversed_by IS NULL
  `).get(cid) as { net: number };
  netsBefore.set(cid, row.net);
}

if (!apply) {
  console.log('[INFO] Dry run — no changes written. Re-run with --apply to correct.');
  process.exit(0);
}

const applyAll = db.transaction(() => {
  for (const o of orphans) {
    ledgerUtils.reverseLedgerEntry(
      'customer_ledger',
      o.id,
      `Orphaned ${o.transaction_type} entry: source document ${o.reference_no} no longer exists (repair-orphaned-ledger)`
    );
  }
  for (const cid of affectedCustomers) {
    ledgerUtils.recalcCustomerBalanceFromLedger(cid);
  }
});
applyAll();

console.log('[INFO] Applied corrections:');
for (const cid of affectedCustomers) {
  const row = db.prepare(`
    SELECT COALESCE(SUM(debit), 0) - COALESCE(SUM(credit), 0) AS net
    FROM customer_ledger
    WHERE customer_id = ? AND voided = 0 AND reversed_by IS NULL
  `).get(cid) as { net: number };
  const stored = db.prepare('SELECT current_balance FROM customers WHERE id = ?').get(cid) as { current_balance: number };
  console.log(`  customer ${cid}: balance ${netsBefore.get(cid)} -> ${row.net} (customers.current_balance = ${stored.current_balance})`);
}
console.log('[INFO] Done.');
process.exit(0);
