#!/usr/bin/env node
/**
 * Decrypt a backup container (audit D29, option B — database copy only).
 *
 * Backups taken while BACKUP_ENCRYPTION_KEY is set are written as
 * erp-<timestamp>.db.enc — an AES-256-GCM container, not a database. Restore
 * needs this script first: it writes the plain database next to the container
 * (or to the path you give), verifies it, and leaves the container untouched.
 *
 * Usage:
 *   node scripts/decrypt-backup.js <path-to-.db.enc> [output.db]
 *
 * The passphrase comes from BACKUP_ENCRYPTION_KEY (server/.env is read, so
 * running it from server/ needs no extra setup).
 *
 * Exit code 0 = plain database written and verified, 1 = failure.
 *
 * KEY LOSS IS PERMANENT. There is no back door and no recovery: if the
 * passphrase is gone, every encrypted backup is unreadable forever.
 */
const fs = require('fs');
const path = require('path');
const Database = require('better-sqlite3');
const { decryptFileSync, backupPassphrase, isEncryptedFileSync } = require('./lib/backup-crypto');

require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

function fail(message) {
  console.error(`[decrypt-backup] ERROR: ${message}`);
  process.exit(1);
}

const source = process.argv[2];
if (!source) fail('usage: node scripts/decrypt-backup.js <path-to-.db.enc> [output.db]');
if (!fs.existsSync(source)) fail(`backup not found: ${source}`);
if (!isEncryptedFileSync(source)) {
  fail(`${source} is not an encrypted backup — nothing to decrypt`);
}

const passphrase = backupPassphrase();
if (!passphrase) {
  fail('BACKUP_ENCRYPTION_KEY is not set (check server/.env)');
}

const destination = process.argv[3] || source.replace(/\.enc$/, '');
if (fs.existsSync(destination)) {
  fail(`${destination} already exists — remove it or choose another output path`);
}

try {
  decryptFileSync(source, destination, passphrase);
} catch (err) {
  const message = err && err.message ? err.message : String(err);
  // GCM reports a wrong key and a damaged file the same way. Say both, so
  // nobody spends an afternoon suspecting corruption when the key is merely
  // mistyped.
  fail(
    message.includes('unable to authenticate')
      ? 'wrong passphrase, or the file is damaged — nothing was written'
      : message
  );
}

// The file is only useful if it opens as a database.
try {
  const db = new Database(destination, { readonly: true });
  const result = db.pragma('integrity_check', { simple: true });
  db.close();
  if (result !== 'ok') fail(`integrity_check failed on the decrypted copy: ${result}`);
} catch (err) {
  fail(`decrypted copy is not a usable database: ${err && err.message ? err.message : err}`);
}

// Restoring means swapping this file in for erp.db, so it must not be
// readable by anyone but the owner.
try {
  fs.chmodSync(destination, 0o600);
} catch (err) {
  console.warn(`[decrypt-backup] could not set mode 600 on ${destination}: ${err.message}`);
}

// Opening a WAL-mode database leaves -wal/-shm sidecars behind. They are
// not part of the backup, and a stale pair beside a restored erp.db is a
// known way to confuse SQLite, so they go.
for (const side of ['-wal', '-shm']) {
  try { fs.rmSync(`${destination}${side}`, { force: true }); } catch { /* best effort */ }
}

const bytes = fs.statSync(destination).size;
console.log(`[decrypt-backup] wrote ${destination} (${(bytes / 1024 / 1024).toFixed(2)} MB), integrity ok`);
console.log('[decrypt-backup] the container was not modified — keep it until the restore is checked');
