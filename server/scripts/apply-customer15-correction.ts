/**
 * Strategy C' — REVERSAL-RULES-compliant correction for customer 15.
 *
 * Composes the real production primitives rather than raw SQL so the
 * simulation proves the shipping code path works:
 *   1. AccountingService.voidJournalLinesByReference  (canonical GL, both legs)
 *   2. StockMovementModel.voidJournalEntry             (legacy GL header store)
 *   3. reverseLedgerEntry                              (append-only subledger)
 *   4. calculateInvoiceBalance / updateInvoiceStatus    (headers)
 *   5. rebuildLedgerBalances / recalcCustomerBalanceFromLedger (no manual patch)
 * All inside ONE transaction (rule 1.3).
 */
import fs from 'fs';
import { assertCorrectionAuthorized } from './lib/correctionSafety';

// ── Safety gate: runs before any write. Without CORRECTION_AUTHORIZED, an
// explicit DATABASE_PATH, and --apply, this script exits without touching data.
assertCorrectionAuthorized('apply-customer15-correction');

// CommonJS preserves this order: even database initialization follows the gate.
import db from '../src/config/database';
import { AccountingService } from '../src/services/accountingService';
import StockMovementModel from '../src/models/StockMovement';
import ledger from '../src/utils/ledgerUtils';

const {
  reverseLedgerEntry,
  rebuildLedgerBalances,
  recalcCustomerBalanceFromLedger,
  calculateInvoiceBalance,
  updateInvoiceStatus,
} = ledger;

const CUSTOMER_ID = 15;
const REASON = 'audit-remediation: legacy CREDIT_OFFSET double-count (customer 15)';
const USER_ID = null;

// invoiceId -> legacy journal_entries header id, and the ledger rows to reverse.
const TARGETS = [
  { invoiceId: 50, entryId: 203, ledgerRowId: 104 },
  { invoiceId: 51, entryId: 209, ledgerRowId: 108 },
  { invoiceId: 59, entryId: 257, ledgerRowId: null },
];

// ── Preconditions. These read only; they never repair. Each failure means the
// database is not the state this correction was written against, so applying it
// anyway would either double-reverse or void an unrelated document.
interface Precond { label: string; ok: boolean; detail: string }
const preconds: Precond[] = [];

for (const t of TARGETS) {
  const inv = db
    .prepare('SELECT customer_id, credit_offset, balance_amount FROM invoices WHERE id = ?')
    .get(t.invoiceId) as { customer_id: number; credit_offset: number; balance_amount: number } | undefined;
  preconds.push({
    label: `invoice ${t.invoiceId} belongs to customer ${CUSTOMER_ID}`,
    ok: inv?.customer_id === CUSTOMER_ID,
    detail: inv ? `customer_id=${inv.customer_id}` : 'invoice missing',
  });

  const active = db
    .prepare(`SELECT COUNT(*) n FROM journal_lines
              WHERE reference_type='CREDIT_OFFSET' AND reference_id=? AND voided=0`)
    .get(t.invoiceId) as { n: number };
  preconds.push({
    label: `invoice ${t.invoiceId} has ACTIVE CREDIT_OFFSET lines (not already reversed)`,
    ok: active.n > 0,
    detail: `active lines=${active.n}`,
  });

  if (t.ledgerRowId) {
    const led = db
      .prepare('SELECT voided, reversed_by FROM customer_ledger WHERE id = ? AND customer_id = ?')
      .get(t.ledgerRowId, CUSTOMER_ID) as { voided: number; reversed_by: number | null } | undefined;
    preconds.push({
      label: `ledger #${t.ledgerRowId} exists and is not already reversed`,
      ok: !!led && !led.voided && led.reversed_by === null,
      detail: led ? `voided=${led.voided} reversed_by=${led.reversed_by}` : 'row missing',
    });
  }
}

const inv59 = db.prepare('SELECT credit_offset FROM invoices WHERE id = 59').get() as
  | { credit_offset: number }
  | undefined;
preconds.push({
  label: 'invoice 59 carries the disputed credit_offset of 1800',
  ok: inv59?.credit_offset === 1800,
  detail: `credit_offset=${inv59?.credit_offset}`,
});

const bal = db.prepare('SELECT current_balance FROM customers WHERE id = ?').get(CUSTOMER_ID) as
  | { current_balance: number }
  | undefined;
preconds.push({
  label: 'customer 15 balance is the expected pre-correction 0',
  ok: bal?.current_balance === 0,
  detail: `current_balance=${bal?.current_balance}`,
});

console.log('=== preconditions ===');
for (const p of preconds) console.log(`  ${p.ok ? 'OK  ' : 'FAIL'}  ${p.label}  (${p.detail})`);
const failed = preconds.filter((p) => !p.ok);
if (failed.length > 0) {
  console.error(
    `\nREFUSED: apply-customer15-correction — ${failed.length} precondition(s) failed.\n` +
      `  The database is not in the state this correction was written against.\n` +
      `  No data was modified.\n`,
  );
  process.exit(1);
}

const r2 = (v: unknown): string =>
  v === null || v === undefined ? '' : String(Math.round((+v as number) * 100) / 100);

const snap = () => ({
  bal: db.prepare('SELECT current_balance FROM customers WHERE id=?').get(CUSTOMER_ID) as { current_balance: number },
  ledger: db.prepare('SELECT COALESCE(SUM(debit),0)-COALESCE(SUM(credit),0) n FROM customer_ledger WHERE customer_id=? AND voided=0 AND reversed_by IS NULL').get(CUSTOMER_ID) as { n: number },
  headers: db.prepare('SELECT COALESCE(SUM(balance_amount),0) s FROM invoices WHERE customer_id=?').get(CUSTOMER_ID) as { s: number },
});

const before = snap();

// Snapshot the touched rows: invoice 49's stored -1200 and invoice 59's
// 'Unpaid' status are NOT reproducible by the production formula (which floors
// at 0), so rollback must restore facts rather than recompute them.
const SNAPSHOT_PATH = process.env.ROLLBACK_SNAPSHOT ?? '/tmp/opencode/d4/rollback-snapshot.json';
const snapshot = {
  customer: db.prepare('SELECT current_balance FROM customers WHERE id=?').get(CUSTOMER_ID),
  invoices: db.prepare(
    'SELECT id,paid_amount,credit_offset,balance_amount,status,payment_status,return_status FROM invoices WHERE customer_id=?',
  ).all(CUSTOMER_ID),
  journalLines: db.prepare(
    `SELECT id,voided,voided_at,voided_by,void_reason FROM journal_lines
      WHERE reference_type='CREDIT_OFFSET' AND reference_id IN (50,51,59)`,
  ).all(),
  journalEntries: db.prepare(
    "SELECT id,voided FROM journal_entries WHERE reference_type='CREDIT_OFFSET' AND reference_id IN (50,51,59)",
  ).all(),
  ledger: db.prepare('SELECT * FROM customer_ledger WHERE customer_id=? ORDER BY id').all(CUSTOMER_ID),
  maxActivityLogId: (db.prepare('SELECT COALESCE(MAX(id),0) m FROM activity_log').get() as { m: number }).m,
  maxLedgerId: (db.prepare('SELECT COALESCE(MAX(id),0) m FROM customer_ledger').get() as { m: number }).m,
};
fs.writeFileSync(SNAPSHOT_PATH, JSON.stringify(snapshot, null, 2));
console.log(`  rollback snapshot written: ${SNAPSHOT_PATH}`);

db.transaction(() => {
  for (const t of TARGETS) {
    const voided = AccountingService.voidJournalLinesByReference(
      db, 'CREDIT_OFFSET', t.invoiceId, { voidedBy: USER_ID, voidReason: REASON },
    );
    StockMovementModel.voidJournalEntry(t.entryId, db);
    if (t.ledgerRowId) reverseLedgerEntry('customer_ledger', t.ledgerRowId, REASON);
    console.log(`  invoice ${t.invoiceId}: ${voided} canonical lines + je#${t.entryId} header voided` +
      (t.ledgerRowId ? `, ledger #${t.ledgerRowId} reversed` : ''));
  }

  // Invoice 59's sale-time credit offset was never matched by cash or a
  // subledger row; it is what made the header show it settled.
  db.prepare('UPDATE invoices SET credit_offset = 0 WHERE id = 59').run();

  for (const inv of db.prepare('SELECT id FROM invoices WHERE customer_id=?').all(CUSTOMER_ID) as Array<{ id: number }>) {
    calculateInvoiceBalance(inv.id);
    updateInvoiceStatus(inv.id);
  }
  rebuildLedgerBalances(CUSTOMER_ID);
  recalcCustomerBalanceFromLedger(CUSTOMER_ID);

  db.prepare(`INSERT INTO activity_log (action, entity_type, description) VALUES (?,?,?)`)
    .run('CREDIT_OFFSET_REVERSAL', 'Customer', `Reversed legacy CREDIT_OFFSET for customer ${CUSTOMER_ID}: ${REASON}`);
})();

const after = snap();

console.log('\n=== customer 15 reconciliation ===');
console.log(`  customers.current_balance : ${r2(before.bal.current_balance)} -> ${r2(after.bal.current_balance)}`);
console.log(`  ledger (active rows)      : ${r2(before.ledger.n)} -> ${r2(after.ledger.n)}`);
console.log(`  invoice header sum        : ${r2(before.headers.s)} -> ${r2(after.headers.s)}`);

console.log('\n=== invoice headers after ===');
interface InvRow { id: number; total_amount: number; returned_amount: number; return_fee: number; paid_amount: number; credit_offset: number; balance_amount: number; status: string }
for (const r of db.prepare('SELECT id,total_amount,returned_amount,return_fee,paid_amount,credit_offset,balance_amount,status FROM invoices WHERE customer_id=? ORDER BY id').all(CUSTOMER_ID) as InvRow[]) {
  console.log(`  inv#${r.id}  total=${r2(r.total_amount)} ret=${r2(r.returned_amount)} fee=${r2(r.return_fee)} paid=${r2(r.paid_amount)} off=${r2(r.credit_offset)} bal=${r2(r.balance_amount)} ${r.status}`);
}

console.log('\n=== per-entry GL balance (invariant A) ===');
const gl = db.prepare(`
  SELECT jl.reference_type rt, jl.reference_id rid,
         SUM(jl.debit) d, SUM(jl.credit) c
  FROM journal_lines jl WHERE jl.voided=0
  GROUP BY jl.reference_type, jl.reference_id
  HAVING SUM(jl.debit) <> SUM(jl.credit)`).all() as Array<{ rt: string; rid: number; d: number; c: number }>;
console.log(gl.length === 0 ? '  all active GL reference groups balanced' : JSON.stringify(gl));

console.log('\n=== voided CREDIT_OFFSET entries ===');
interface CoRow { je: number; rid: number; hvoid: number; vlines: number; tlines: number }
for (const r of db.prepare(`
  SELECT je.id je, je.reference_id rid, je.voided hvoid,
         (SELECT COUNT(*) FROM journal_lines l WHERE l.journal_entry_id=je.id AND l.voided=1) vlines,
         (SELECT COUNT(*) FROM journal_lines l WHERE l.journal_entry_id=je.id) tlines
  FROM journal_entries je WHERE je.reference_type='CREDIT_OFFSET' ORDER BY je.id`).all() as CoRow[]) {
  console.log(`  je#${r.je} CREDIT_OFFSET#${r.rid}  header_voided=${r.hvoid}  lines ${r.vlines}/${r.tlines} voided`);
}
