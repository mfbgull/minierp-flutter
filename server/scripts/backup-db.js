#!/usr/bin/env node
/**
 * Database backup script (DR-01).
 *
 * Creates a consistent snapshot of the live SQLite database — safe to run
 * while the server holds the DB open in WAL mode, because better-sqlite3's
 * db.backup() pages content out and retries on busy.
 *
 * Output: server/database/backups/erp-backup-<timestamp>.db
 *   - PRAGMA integrity_check runs on the finished snapshot
 *   - keeps the newest MAX_BACKUPS files, prunes older ones
 *   - exit code 0 on success, 1 on any failure
 *
 * Usage: npm run db:backup   (from server/)
 */
const fs = require('fs');
const path = require('path');
const Database = require('better-sqlite3');
const { verifySnapshotAt } = require('./lib/backup-verify');

const MAX_BACKUPS = 30;

// Same resolution as src/config/database.ts: DATABASE_PATH env var
// (Electron) wins, otherwise <repo>/server/database.
const repoRoot = path.join(__dirname, '..', '..');
const dbDir = process.env.DATABASE_PATH || path.join(repoRoot, 'server', 'database');
const dbPath = path.join(dbDir, 'erp.db');
const backupDir = process.env.BACKUP_DIR || path.join(dbDir, 'backups');

function fail(message) {
  console.error(`[db:backup] ERROR: ${message}`);
  process.exit(1);
}

/** Human-readable message for an unknown thrown value. */
function snapshotErrorMessage(err) {
  return err && err.message ? err.message : String(err);
}

/** Best-effort delete: a missing file is not an error worth reporting. */
function removeQuietly(target) {
  try {
    fs.rmSync(target, { force: true });
  } catch {
    /* ignore */
  }
}

/** Best-effort close: a handle that refuses to close must not mask the real error. */
function closeQuietly(handle) {
  try {
    handle.close();
  } catch {
    /* ignore */
  }
}

if (!fs.existsSync(dbPath)) {
  fail(`database not found at ${dbPath}`);
}

fs.mkdirSync(backupDir, { recursive: true });

const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
const backupPath = path.join(backupDir, `erp-backup-${timestamp}.db`);

async function createSnapshot() {
  let source;
  try {
    source = new Database(dbPath, { readonly: true });
    // Copies the database page-by-page into a consistent snapshot.
    // Returns a Promise; retries on SQLITE_BUSY so it is safe while
    // the server holds the DB open in WAL mode.
    await source.backup(backupPath);
  } catch (err) {
    removeQuietly(backupPath);
    fail(snapshotErrorMessage(err));
  } finally {
    if (source) closeQuietly(source);
  }
}

function verifySnapshot() {
  const result = verifySnapshotAt(backupPath);
  if (!result.ok) fail(result.message);
  console.log('[db:backup] integrity_check: ok');
}

async function run() {
  await createSnapshot();
  verifySnapshot();
  const bytes = fs.statSync(backupPath).size;

  // Prune to the newest MAX_BACKUPS snapshots.
  const backups = fs.readdirSync(backupDir)
    .filter((f) => /^erp-backup-\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}\.db$/.test(f))
    .sort()
    .reverse();
  for (const stale of backups.slice(MAX_BACKUPS)) {
    const stalePath = path.join(backupDir, stale);
    try {
      fs.rmSync(stalePath, { force: true });
      console.log(`[db:backup] pruned old backup: ${stale}`);
    } catch (err) {
      console.warn(`[db:backup] could not prune ${stale}: ${err.message}`);
    }
  }

  console.log(`[db:backup] done (${(bytes / 1024 / 1024).toFixed(2)} MB), ${Math.min(backups.length, MAX_BACKUPS)} snapshot(s) retained`);
}

run();
