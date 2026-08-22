/**
 * GL integrity checker (audit-remediation task 5.5 / AUD-06).
 * Read-only: orphaned journal-line references, missing-ledger documents,
 * per-entry imbalance. Exit 1 on any violation so scheduling surfaces it.
 *
 * Usage: npx ts-node scripts/check-gl-integrity.ts
 */
import Database from 'better-sqlite3';
import path from 'path';

const dbDir = process.env.DATABASE_PATH || path.join(__dirname, '../database');
const db = new Database(path.join(dbDir, 'erp.db'), { readonly: true });
db.pragma('query_only = 1');

let violations = 0;

function check(name: string, rows: unknown[]): void {
  if (rows.length > 0) {
    violations += rows.length;
    console.error(`[FAIL] ${name}: ${rows.length} row(s)`);
    console.error(JSON.stringify(rows.slice(0, 10), null, 2));
  } else {
    console.log(`[OK]   ${name}`);
  }
}

// 1. Journal lines referencing a missing entry
check('journal_lines with missing journal_entry',
  db.prepare(`
    SELECT jl.id, jl.journal_entry_id FROM journal_lines jl
    LEFT JOIN journal_entries je ON je.id = jl.journal_entry_id
    WHERE jl.journal_entry_id IS NOT NULL AND je.id IS NULL
  `).all());

// 2. Unbalanced (non-voided) entries
check('unbalanced non-voided journal_entries',
  db.prepare(`
    SELECT je.id, SUM(jl.debit) AS dr, SUM(jl.credit) AS cr
    FROM journal_entries je JOIN journal_lines jl ON jl.journal_entry_id = je.id
    WHERE jl.voided = 0
    GROUP BY je.id
    HAVING ABS(SUM(jl.debit) - SUM(jl.credit)) > 0.005
  `).all());

// 3. INVOICE-referencing lines whose invoice no longer exists (and not voided)
check('active journal_lines referencing deleted invoices',
  db.prepare(`
    SELECT jl.id, je.reference_id FROM journal_lines jl
    JOIN journal_entries je ON je.id = jl.journal_entry_id
    WHERE jl.voided = 0 AND je.reference_type = 'INVOICE' AND je.reference_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM invoices i WHERE i.id = je.reference_id)
  `).all());

// 4. stock_movements dangling JE references
check('stock_movements with missing journal_entry',
  db.prepare(`
    SELECT sm.id, sm.journal_entry_id FROM stock_movements sm
    LEFT JOIN journal_entries je ON je.id = sm.journal_entry_id
    WHERE sm.journal_entry_id IS NOT NULL AND je.id IS NULL
  `).all());

db.close();
if (violations > 0) {
  console.error(`\n❌ GL integrity check FAILED — ${violations} violation(s)`);
  process.exit(1);
}
console.log('\n✅ GL integrity check passed');
