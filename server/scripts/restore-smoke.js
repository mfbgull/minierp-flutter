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
const { isEncryptedFileSync, decryptFileSync, backupPassphrase } = require('./lib/backup-crypto');

// Same .env the server reads, so the passphrase is available without the
// operator having to export it by hand.
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const backupPath = process.argv[2];
if (!backupPath || !fs.existsSync(backupPath)) {
  console.error(`[restore-smoke] backup not found: ${backupPath}`);
  process.exit(1);
}

const tmp = path.join(os.tmpdir(), `restored-smoke-${Date.now()}.db`);
if (isEncryptedFileSync(backupPath)) {
  const passphrase = backupPassphrase();
  if (!passphrase) {
    console.error('[restore-smoke] backup is encrypted but BACKUP_ENCRYPTION_KEY is not set');
    process.exit(1);
  }
  decryptFileSync(backupPath, tmp, passphrase);
  console.log('[restore-smoke] decrypted container before smoke test');
} else {
  fs.copyFileSync(backupPath, tmp);
}
// A decrypted copy must not outlive the run, even on a crash.
process.on('exit', () => {
  try { fs.rmSync(tmp, { force: true }); } catch { /* best effort */ }
});

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
