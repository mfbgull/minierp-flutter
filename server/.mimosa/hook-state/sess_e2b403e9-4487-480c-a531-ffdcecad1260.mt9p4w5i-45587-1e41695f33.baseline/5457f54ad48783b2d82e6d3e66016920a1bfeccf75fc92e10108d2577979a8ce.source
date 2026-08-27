#!/usr/bin/env node
/**
 * gl:dedupe-po (ACC-16) — reverse redundant PURCHASE_ORDER supplier-ledger
 * debits.
 *
 * Before this change, PO submission wrote a supplier_ledger debit
 * (transaction_type='PURCHASE_ORDER') AND the goods receipt later wrote
 * another debit ('PURCHASE') for the same economic event, double-counting
 * what the supplier is owed. This script finds each PURCHASE_ORDER debit
 * whose supplier already has a matching PURCHASE debit and writes an
 * equal-and-opposite credit row tagged with a sentinel description, then
 * rebuilds that supplier's running balances.
 *
 * Idempotent via the sentinel description. Dry-run by default; pass
 * --apply to write. Run `npm run db:backup` first.
 *
 * Usage:
 *   node dist/scripts/dedupe-po.js            (dry run)
 *   node dist/scripts/dedupe-po.js --apply    (write)
 */
const path = require('path');
const fs = require('fs');

const SENTINEL = 'PO commitment reversal (backfill)';

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
  console.error('[dedupe-po] database not found; set DATABASE_PATH');
  process.exit(1);
}

function main() {
  const apply = process.argv.includes('--apply');
  const dbPath = resolveDbPath();
  const Database = require('better-sqlite3');
  const db = new Database(dbPath);

  try {
    // PURCHASE_ORDER debits not yet reversed by this script, paired with any
    // subsequent PURCHASE debit for the same supplier on or after the PO date.
    const dupes = db.prepare(`
      SELECT po.id, po.supplier_id, po.reference_no, po.debit, po.transaction_date
      FROM supplier_ledger po
      WHERE po.transaction_type = 'PURCHASE_ORDER'
        AND po.debit > 0
        AND NOT EXISTS (
          SELECT 1 FROM supplier_ledger rev
          WHERE rev.reversed_by = po.id AND rev.description = '${SENTINEL}'
        )
        AND EXISTS (
          SELECT 1 FROM supplier_ledger pur
          WHERE pur.supplier_id = po.supplier_id
            AND pur.transaction_type = 'PURCHASE'
            AND pur.debit > 0
            AND pur.transaction_date >= po.transaction_date
        )
      ORDER BY po.id
    `).all();

    if (dupes.length === 0) {
      console.log(`[dedupe-po] no redundant PURCHASE_ORDER debits found — nothing to do`);
      return;
    }

    let total = 0;
    for (const d of dupes) total += Number(d.debit);
    console.log(`[dedupe-po] found ${dupes.length} redundant commitment debit(s), totalling ${total.toFixed(2)}`);
    for (const d of dupes) {
      console.log(`  ledger#${d.id} supplier=${d.supplier_id} ref=${d.reference_no} date=${d.transaction_date} amount=${Number(d.debit).toFixed(2)}`);
    }

    if (!apply) {
      console.log('[dedupe-po] dry run only — re-run with --apply to write reversals');
      return;
    }

    const insertReversal = db.prepare(`
      INSERT INTO supplier_ledger (
        supplier_id, transaction_date, transaction_type, reference_no,
        debit, credit, balance, description, reversed_by
      ) VALUES (?, date('now'), 'PO_COMMITMENT_REVERSAL', ?, ?, ?, ?, ?, ?)
    `);
    const markOriginal = db.prepare(
      `UPDATE supplier_ledger SET voided = 1 WHERE id = ?`
    );
    const lastBalance = db.prepare(
      `SELECT balance FROM supplier_ledger WHERE supplier_id = ? AND voided = 0
       ORDER BY transaction_date DESC, id DESC LIMIT 1`
    );

    const affectedSuppliers = [...new Set(dupes.map(d => d.supplier_id))];

    const tx = db.transaction(() => {
      for (const d of dupes) {
        const latest = lastBalance.get(d.supplier_id);
        const baseBalance = latest ? Number(latest.balance) : 0;
        const creditAmount = Number(d.debit);
        const newBalance = baseBalance - creditAmount;

        const result = insertReversal.run(
          d.supplier_id,
          d.reference_no,
          0,
          creditAmount,
          newBalance,
          SENTINEL,
          d.id
        );
        markOriginal.run(d.id);
        console.log(`[dedupe-po] reversed ledger#${d.id} -> reversal row ${result.lastInsertRowid}`);
      }
      // Rebuild running balances for every affected supplier from scratch so
      // stored chains are consistent regardless of prior drift.
      for (const supplierId of affectedSuppliers) {
        const rows = db.prepare(
          `SELECT id, debit, credit FROM supplier_ledger
           WHERE supplier_id = ? AND voided = 0
           ORDER BY transaction_date ASC, id ASC`
        ).all(supplierId);
        const update = db.prepare(`UPDATE supplier_ledger SET balance = ? WHERE id = ?`);
        let running = 0;
        for (const r of rows) {
          running += Number(r.debit) - Number(r.credit);
          update.run(running, r.id);
        }
        db.prepare('UPDATE suppliers SET current_balance = ? WHERE id = ?').run(running, supplierId);
        console.log(`[dedupe-po] rebuilt supplier ${supplierId}: final balance ${running.toFixed(2)}`);
      }
    });
    tx();

    console.log(`[dedupe-po] done: ${dupes.length} reversal(s) written across ${affectedSuppliers.length} supplier(s)`);
  } finally {
    db.close();
  }
}

main();
