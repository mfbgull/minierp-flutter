#!/usr/bin/env node
/**
 * gl:backfill-ledger-dates (ACC-12) — repopulate historical
 * customer_ledger.transaction_date from the source documents, then rebuild
 * every stored running balance once in (transaction_date, id) order.
 *
 * Rows are joined to their source document via reference_no:
 *   INVOICE / CANCELLATION / RETURN → invoices.invoice_no
 *   PAYMENT / REFUND                → payments.payment_no
 *   OPENING_BALANCE                 → left as-is (already the creation date)
 *
 * Rows whose date cannot be recovered keep their existing transaction_date.
 * Idempotent: re-running finds nothing left to fix. Dry-run by default;
 * pass --apply to write. Run `npm run db:backup` first.
 *
 * Usage:
 *   node dist/scripts/backfill-ledger-dates.js            (dry run)
 *   node dist/scripts/backfill-ledger-dates.js --apply    (write)
 */
const path = require('path');
const fs = require('fs');

function resolveDbPath() {
  const candidates = [
    process.env.DATABASE_PATH && path.join(process.env.DATABASE_PATH, 'erp.db'),
    process.env.DATABASE_PATH,
    path.join(__dirname, '../../../database/erp.db'),
    path.join(__dirname, '../../database/erp.db'),
  ].filter(Boolean);
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  console.error('[backfill-ledger-dates] database not found; set DATABASE_PATH');
  process.exit(1);
}

function main() {
  const apply = process.argv.includes('--apply');
  const dbPath = resolveDbPath();
  const Database = require('better-sqlite3');
  const db = new Database(dbPath);

  try {
    // Candidate rows: any row whose transaction_date does not already match
    // its source document date.
    const rows = db.prepare(`
      SELECT cl.id, cl.customer_id, cl.transaction_type, cl.reference_no,
             cl.transaction_date AS current_date,
             CASE
               WHEN cl.transaction_type IN ('INVOICE', 'CANCELLATION', 'RETURN')
                 THEN (SELECT i.invoice_date FROM invoices i WHERE i.invoice_no = cl.reference_no)
               WHEN cl.transaction_type IN ('PAYMENT', 'REFUND')
                 THEN (SELECT p.payment_date FROM payments p WHERE p.payment_no = cl.reference_no)
               ELSE NULL
             END AS doc_date
      FROM customer_ledger cl
      ORDER BY cl.id
    `).all();

    const fixable = rows.filter(r => r.doc_date && r.doc_date !== r.current_date);
    if (fixable.length === 0) {
      console.log('[backfill-ledger-dates] all ledger dates already match their source documents — nothing to do');
      return;
    }

    let total = 0;
    for (const r of fixable) total += 1;
    console.log(`[backfill-ledger-dates] ${rows.length} ledger row(s) scanned, ${total} need a date backfill`);
    for (const r of fixable.slice(0, 50)) {
      console.log(`  ledger#${r.id} customer=${r.customer_id} type=${r.transaction_type} ref=${r.reference_no} ${r.current_date} -> ${r.doc_date}`);
    }
    if (fixable.length > 50) {
      console.log(`  … and ${fixable.length - 50} more`);
    }

    if (!apply) {
      console.log('[backfill-ledger-dates] dry run only — re-run with --apply to write dates and rebuild balances');
      return;
    }

    const setDate = db.prepare('UPDATE customer_ledger SET transaction_date = ? WHERE id = ?');

    const affectedCustomers = [...new Set(fixable.map(r => r.customer_id))];

    const tx = db.transaction(() => {
      for (const r of fixable) {
        setDate.run(r.doc_date, r.id);
      }
      // Rebuild running balances for every affected customer in
      // (transaction_date, id) order over non-voided rows, then sync
      // customers.current_balance to the ledger-derived figure.
      for (const customerId of affectedCustomers) {
        const entries = db.prepare(
          `SELECT id, debit, credit FROM customer_ledger
           WHERE customer_id = ? AND voided = 0
           ORDER BY transaction_date ASC, id ASC`
        ).all(customerId);
        const update = db.prepare('UPDATE customer_ledger SET balance = ? WHERE id = ?');
        let running = 0;
        for (const e of entries) {
          running += Number(e.debit) - Number(e.credit);
          update.run(Math.round(running * 100) / 100, e.id);
        }
        db.prepare('UPDATE customers SET current_balance = ? WHERE id = ?')
          .run(Math.round(running * 100) / 100, customerId);
        console.log(`[backfill-ledger-dates] rebuilt customer ${customerId}: final balance ${running.toFixed(2)}`);
      }
    });
    tx();

    console.log(`[backfill-ledger-dates] done: ${fixable.length} date(s) corrected across ${affectedCustomers.length} customer(s), balances rebuilt once`);
  } finally {
    db.close();
  }
}

main();
