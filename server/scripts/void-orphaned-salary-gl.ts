/**
 * Void orphaned salary-payment GL lines (AUD/repair).
 * ---------------------------------------------------
 * deleteSalaryPayment voided GL lines only when the payment row carried a
 * journal_entry_id link (see employeeController). Payments backfilled or
 * created before that link was recorded were hard-deleted while their GL
 * lines stayed active — phantom bank/cash outflows that corrupted the
 * dashboard cash-position balances.
 *
 * Detection: active (voided = 0) journal_lines with
 * reference_type = 'SALARY_PAYMENT' whose reference_id resolves to no row
 * in salary_payments. Both legs of each entry are voided together (the
 * check asserts the entry stays balanced).
 *
 * Usage:
 *   npm run repair:salary-gl            — dry run (report only, no writes)
 *   npm run repair:salary-gl -- --apply — void the orphaned lines
 *
 * Targets the same DB the server uses (DATABASE_PATH env or
 * server/database/erp.db).
 */
import Database from 'better-sqlite3';
import path from 'path';

const apply = process.argv.includes('--apply');

// Open the app DB directly (same path resolution as check-gl-integrity.ts).
// Importing src/config/database would drag in the whole boot/migration chain
// and — under ts-node's __dirname — resolve to <repo-root>/database/erp.db,
// a fresh empty DB instead of the real server/database/erp.db.
const dbDir = process.env.DATABASE_PATH || path.join(__dirname, '../database');
const db = new Database(path.join(dbDir, 'erp.db'), { readonly: !apply });
if (apply) {
  db.pragma('busy_timeout = 5000');
} else {
  // Dry run is physically incapable of writing.
  db.pragma('query_only = 1');
}

// A salary payment can legitimately exist with status='cancelled'; only a
// missing row makes the GL lines orphaned.
const orphans = db.prepare(`
  SELECT jl.id, jl.journal_entry_id, jl.reference_id, jl.account_id,
         jl.debit, jl.credit, jl.line_date, jl.description
  FROM journal_lines jl
  WHERE jl.voided = 0
    AND jl.reference_type = 'SALARY_PAYMENT'
    AND NOT EXISTS (
      SELECT 1 FROM salary_payments sp WHERE sp.id = jl.reference_id
    )
  ORDER BY jl.reference_id, jl.id
`).all() as Array<{
  id: number;
  journal_entry_id: number;
  reference_id: number;
  account_id: number;
  debit: number;
  credit: number;
  line_date: string;
  description: string | null;
}>;

if (orphans.length === 0) {
  console.log('[INFO] No orphaned salary-payment GL lines found. Nothing to do.');
  process.exit(0);
}

console.log(`[INFO] Found ${orphans.length} orphaned salary-payment GL line(s):`);
for (const o of orphans) {
  console.log(
    `  line #${o.id} entry ${o.journal_entry_id} ref SALARY_PAYMENT:${o.reference_id} | ` +
    `acct ${o.account_id} D ${o.debit} C ${o.credit} | ${o.line_date} | ${o.description ?? ''}`
  );
}

// Per-entry impact report: the cash/bank/wallet legs of each orphan group.
const impact = db.prepare(`
  SELECT jl.account_id, coa.code, coa.name, SUM(jl.credit - jl.debit) AS net_outflow
  FROM journal_lines jl
  JOIN chart_of_accounts coa ON coa.id = jl.account_id
  WHERE jl.voided = 0
    AND jl.reference_type = 'SALARY_PAYMENT'
    AND NOT EXISTS (
      SELECT 1 FROM salary_payments sp WHERE sp.id = jl.reference_id
    )
  GROUP BY jl.account_id, coa.code, coa.name
  ORDER BY coa.code
`).all() as Array<{ account_id: number; code: string; name: string; net_outflow: number }>;
console.log('');
console.log('[INFO] Balance impact of the orphaned lines (per account):');
for (const i of impact) {
  console.log(`  ${i.code} ${i.name}: net outflow ${i.net_outflow.toFixed(2)}`);
}

// Safety: every affected journal entry must stay balanced after voiding
// (both legs of each entry are orphans together — a partial entry would
// mean a different bug and must not be silently voided).
const unbalanced = db.prepare(`
  SELECT jl.journal_entry_id
  FROM journal_lines jl
  WHERE jl.voided = 0
    AND jl.reference_type = 'SALARY_PAYMENT'
    AND NOT EXISTS (
      SELECT 1 FROM salary_payments sp WHERE sp.id = jl.reference_id
    )
  GROUP BY jl.journal_entry_id
  HAVING ABS(SUM(jl.debit) - SUM(jl.credit)) > 0.005
`).all() as Array<{ journal_entry_id: number }>;
if (unbalanced.length > 0) {
  console.error(`[FAIL] ${unbalanced.length} affected journal entr${unbalanced.length === 1 ? 'y is' : 'ies are'} internally unbalanced — refusing to void:`);
  for (const u of unbalanced) console.error(`  entry ${u.journal_entry_id}`);
  process.exit(1);
}

if (!apply) {
  console.log('');
  console.log('[DRY] Dry run — no lines were voided. Re-run with -- --apply to void them.');
  process.exit(0);
}

const voidThem = db.transaction(() => {
  const stmt = db.prepare(`
    UPDATE journal_lines
    SET voided = 1,
        voided_at = CURRENT_TIMESTAMP,
        voided_by = NULL,
        void_reason = 'Orphaned GL line: salary payment row deleted without GL void (audit repair)'
    WHERE voided = 0
      AND reference_type = 'SALARY_PAYMENT'
      AND NOT EXISTS (
        SELECT 1 FROM salary_payments sp WHERE sp.id = reference_id
      )
  `);
  const result = stmt.run();
  return result.changes;
});

const voided = voidThem();
console.log('');
console.log(`[OK] Voided ${voided} orphaned salary-payment GL line(s). Bank/cash balances are now backed by real payments.`);
