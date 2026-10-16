/**
 * Rollback of Strategy C' by restoring the snapshot taken before the forward
 * path ran.
 *
 * Recomputing is not sufficient: invoice 49's stored -1200 and invoice 59's
 * 'Unpaid' status were stale values no production rebuild can reproduce, and
 * AccountingService.restoreJournalLinesByReference clears voided/voided_by/
 * void_reason but not voided_at. So this restores recorded facts.
 *
 * activity_log is deliberately left alone — it is append-only audit, and a
 * reversal that happened must keep its trail.
 */
import fs from 'fs';
import db from '../src/config/database';
import { assertCorrectionAuthorized } from './lib/correctionSafety';

// ── Safety gate: must stay above the snapshot read, which is the first write
// (it truncates customer_ledger back to the recorded high-water mark).
assertCorrectionAuthorized('rollback-customer15-correction');

const CUSTOMER_ID = 15;
const SNAPSHOT_PATH = process.env.ROLLBACK_SNAPSHOT ?? '/tmp/opencode/d4/rollback-snapshot.json';

interface Snap {
  customer: { current_balance: number };
  invoices: Array<{
    id: number; paid_amount: number; credit_offset: number; balance_amount: number;
    status: string; payment_status: string | null; return_status: string | null;
  }>;
  journalLines: Array<{ id: number; voided: number; voided_at: string | null; voided_by: number | null; void_reason: string | null }>;
  journalEntries: Array<{ id: number; voided: number }>;
  ledger: Array<{ id: number; voided: number; reversed_by: number | null; balance: number; reference_no: string | null }>;
  maxActivityLogId: number;
  maxLedgerId: number;
}

const snap: Snap = JSON.parse(fs.readFileSync(SNAPSHOT_PATH, 'utf8'));

db.transaction(() => {
  const before = (db.prepare('SELECT COUNT(*) n FROM customer_ledger').get() as { n: number }).n;
  db.prepare('DELETE FROM customer_ledger WHERE id > ?').run(snap.maxLedgerId);
  const after = (db.prepare('SELECT COUNT(*) n FROM customer_ledger').get() as { n: number }).n;

  const restoreLedger = db.prepare(
    'UPDATE customer_ledger SET voided=?, reversed_by=?, balance=? WHERE id=?',
  );
  for (const r of snap.ledger) restoreLedger.run(r.voided, r.reversed_by, r.balance, r.id);

  const restoreLine = db.prepare(
    'UPDATE journal_lines SET voided=?, voided_at=?, voided_by=?, void_reason=? WHERE id=?',
  );
  for (const l of snap.journalLines) restoreLine.run(l.voided, l.voided_at, l.voided_by, l.void_reason, l.id);

  const restoreEntry = db.prepare('UPDATE journal_entries SET voided=? WHERE id=?');
  for (const e of snap.journalEntries) restoreEntry.run(e.voided, e.id);

  const restoreInv = db.prepare(
    `UPDATE invoices SET paid_amount=?, credit_offset=?, balance_amount=?,
        status=?, payment_status=?, return_status=? WHERE id=?`,
  );
  for (const i of snap.invoices) {
    restoreInv.run(i.paid_amount, i.credit_offset, i.balance_amount, i.status, i.payment_status, i.return_status, i.id);
  }

  db.prepare('UPDATE customers SET current_balance=? WHERE id=?').run(snap.customer.current_balance, CUSTOMER_ID);

  console.log(`  ledger rows removed      : ${before - after}`);
  console.log(`  journal_lines restored   : ${snap.journalLines.length}`);
  console.log(`  journal_entries restored : ${snap.journalEntries.length}`);
  console.log(`  invoice headers restored : ${snap.invoices.length}`);
  console.log(`  customer balance restored: ${snap.customer.current_balance}`);
})();

const R2 = (v: unknown): string => String(Math.round(Number(v || 0) * 100) / 100);
const bal = (db.prepare('SELECT current_balance FROM customers WHERE id=?').get(CUSTOMER_ID) as { current_balance: number }).current_balance;
const led = (db.prepare('SELECT COALESCE(SUM(debit),0)-COALESCE(SUM(credit),0) n FROM customer_ledger WHERE customer_id=? AND voided=0 AND reversed_by IS NULL').get(CUSTOMER_ID) as { n: number }).n;
const hdr = (db.prepare('SELECT COALESCE(SUM(balance_amount),0) s FROM invoices WHERE customer_id=?').get(CUSTOMER_ID) as { s: number }).s;

console.log('\n=== customer 15 after rollback ===');
console.log(`  customers.current_balance : ${R2(bal)}   (expected 0)`);
console.log(`  ledger (active rows)      : ${R2(led)}   (expected 0)`);
console.log(`  invoice header sum        : ${R2(hdr)}   (expected -1200)`);
