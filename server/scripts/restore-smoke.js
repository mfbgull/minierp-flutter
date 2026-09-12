#!/usr/bin/env node
/**
 * Restore smoke test (DR-02 companion to verify-backup.js).
 *
 * Copies a backup snapshot to a temp path, opens it read-only, and reads
 * core row counts — proving the snapshot actually opens as a database
 * with the expected seeded content, not just that it passes integrity.
 *
 * Usage: node scripts/restore-smoke.js <path-to-snapshot.db>
 * Exit code 0 = smoke test passed, 1 = failure.
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const Database = require('better-sqlite3');

const backupPath = process.argv[2];
if (!backupPath || !fs.existsSync(backupPath)) {
  console.error(`[restore-smoke] backup not found: ${backupPath}`);
  process.exit(1);
}

const tmp = path.join(os.tmpdir(), `restored-smoke-${Date.now()}.db`);
fs.copyFileSync(backupPath, tmp);

let db;
try {
  db = new Database(tmp, { readonly: true });
} catch (err) {
  console.error(`[restore-smoke] cannot open restored copy: ${err.message}`);
  process.exit(1);
}

const counts = {};
let failed = false;
for (const t of ['items', 'warehouses', 'customers', 'users']) {
  try {
    counts[t] = db.prepare(`SELECT COUNT(*) AS c FROM ${t}`).get().c;
  } catch (err) {
    console.error(`[restore-smoke] cannot read table ${t}: ${err.message}`);
    failed = true;
  }
}
console.log('Restored DB row counts:', JSON.stringify(counts));

if (counts.users === undefined || counts.users < 1) {
  console.error('[restore-smoke] no users in restored DB');
  failed = true;
}

db.close();
fs.rmSync(tmp, { force: true });

if (failed) process.exit(1);
console.log('[restore-smoke] restored copy opens and reads cleanly');
