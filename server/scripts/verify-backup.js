#!/usr/bin/env node
/**
 * Backup restore verification (DR-02).
 *
 * A backup is only a backup if it can be restored. This script takes a
 * snapshot produced by backup-db.js, copies it to a temp path (so the
 * snapshot itself is never touched), and verifies the copy is a viable
 * restored database:
 *   1. PRAGMA integrity_check passes
 *   2. Core schema tables exist
 *   3. GL invariant: every journal_lines reference group sums debit == credit
 *   4. Inventory invariant: stock_balances.quantity == Σ stock_batches remaining
 *
 * Usage: node scripts/verify-backup.js <path-to-snapshot.db>
 * Exit code 0 = restorable and consistent, 1 = any check failed.
 */
const fs = require('fs');
const path = require('path');
const os = require('os');
const Database = require('better-sqlite3');

const backupPath = process.argv[2];
if (!backupPath || !fs.existsSync(backupPath)) {
  console.error(`[restore-verify] backup not found: ${backupPath}`);
  process.exit(1);
}

// Copy to a temp path so verification never touches the snapshot. A
// snapshot written by better-sqlite3's .backup() has no WAL sidecars,
// but copy them if present so a raw-file copy still sees the tail.
const tmp = path.join(os.tmpdir(), `restore-verify-${Date.now()}.db`);
fs.copyFileSync(backupPath, tmp);
for (const ext of ['-wal', '-shm']) {
  const side = backupPath + ext;
  if (fs.existsSync(side)) fs.copyFileSync(side, tmp + ext);
}

const db = new Database(tmp, { readonly: true });
const failures = [];
function check(cond, label) {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}`);
  if (!cond) failures.push(label);
}

// 1. Physical integrity.
check(db.pragma('integrity_check', { simple: true }) === 'ok', 'integrity_check ok');

// 2. Core schema present.
const tables = new Set(
  db.prepare("SELECT name FROM sqlite_master WHERE type = 'table'").all().map((r) => r.name)
);
for (const t of ['items', 'warehouses', 'customers', 'suppliers', 'invoices', 'stock_movements', 'journal_lines', 'customer_ledger']) {
  check(tables.has(t), `table ${t} exists`);
}

// 3. GL balanced: every non-voided journal_lines reference group sums debit == credit.
const unbalanced = db.prepare(`
  SELECT COUNT(*) AS c FROM (
    SELECT reference_type, reference_id
    FROM journal_lines
    WHERE voided = 0
    GROUP BY reference_type, reference_id
    HAVING ABS(SUM(debit) - SUM(credit)) > 0.005
  )
`).get().c;
check(unbalanced === 0, `journal_lines balanced by reference group (${unbalanced} unbalanced)`);

// 4. Batches vs balances: stock_balances.quantity == sum of remaining batch qty.
const drift = db.prepare(`
  SELECT COUNT(*) AS c FROM (
    SELECT b.item_id, b.warehouse_id
    FROM stock_balances b
    LEFT JOIN stock_batches s ON s.item_id = b.item_id AND s.warehouse_id = b.warehouse_id
    GROUP BY b.item_id, b.warehouse_id
    HAVING ABS(b.quantity - COALESCE(SUM(s.quantity_remaining), 0)) > 0.005
  )
`).get().c;
check(drift === 0, `stock_balances match batch layers (${drift} drifted)`);

db.close();
fs.rmSync(tmp, { force: true });
for (const ext of ['-wal', '-shm']) {
  try { fs.rmSync(tmp + ext, { force: true }); } catch { /* ignore */ }
}

if (failures.length > 0) {
  console.error(`[restore-verify] FAILED: ${failures.length} check(s)`);
  process.exit(1);
}
console.log('[restore-verify] backup is restorable and internally consistent');
