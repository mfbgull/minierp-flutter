/**
 * Scheduled database backup service (audit-remediation task 7.3 / DR-01, DR-02).
 *
 * - Nightly in-process timer; fires on boot if the last backup is > 24h old.
 * - wal_checkpoint(TRUNCATE) before copying; VACUUM INTO for a consistent
 *   snapshot; integrity_check on the copy; the copy is then wrapped in an
 *   encrypted container (D29 option B, database copy only); retention prune
 *   (7 daily / 4 weekly).
 */
import fs from 'fs';
import path from 'path';
import Database from 'better-sqlite3';
import db, { dbDir } from '../config/database';
import logger from '../utils/logger';
import { ActionType } from './activityLogger';
import { pruneIdempotencyKeys } from '../utils/idempotency';
import { resolveUploadsDir } from '../utils/serverRoot';
// D29 option B: same container format the operator scripts use, so a
// backup written by the server can be decrypted by `decrypt-backup.js`.
import { backupPassphrase, encryptFileSync } from '../../scripts/lib/backup-crypto';

// Take the resolved dir from config/database so backups always land beside the
// erp.db this process opened, instead of re-deriving it with other arithmetic.
const DB_DIR = dbDir;
// BACKUP_DIR (same variable the CLI script honours) lets backups go to another
// drive; defaults to <db-dir>/backups. (BK-005)
export const BACKUP_DIR = process.env.BACKUP_DIR || path.join(DB_DIR, 'backups');
// D7: employee documents and other uploads live outside the database, so a
// database-only restore recovered rows whose files were gone. Every backup now
// carries a sibling <name>.uploads snapshot of this directory.
export const UPLOADS_DIR = resolveUploadsDir();
const DAILY_KEEP = 7;
const WEEKLY_KEEP = 4;
const INTERVAL_MS = 24 * 60 * 60 * 1000;

/** Directory modes for anything under BACKUP_DIR (BK-extra). */
const BACKUP_DIR_MODE = 0o700;
/**
 * Files are written 0600: a backup is a second full copy of the books, and
 * `VACUUM INTO` otherwise inherits the process umask, which can make it
 * readable by every account on the machine. `fs.chmodSync` sets the bits
 * explicitly, so the result does not depend on the umask the service runs under.
 */
const BACKUP_FILE_MODE = 0o600;

/**
 * Restricts [target] to [mode], ignoring the process umask. Best effort: a
 * filesystem that cannot carry POSIX modes (or a non-owner) must not turn a
 * good backup into a failed one, so a chmod error is logged and swallowed.
 */
function restrict(target: string, mode: number): void {
  try {
    fs.chmodSync(target, mode);
  } catch (err) {
    logger.warn(`[Backup] could not set mode ${mode.toString(8)} on ${target}:`, err);
  }
}

/** Removes a plaintext snapshot together with its WAL sidecars, which would
 *  otherwise be left behind as orphans of a file that no longer exists. */
function removePlainCopy(plainPath: string): void {
  fs.rmSync(plainPath, { force: true });
  fs.rmSync(`${plainPath}-wal`, { force: true });
  fs.rmSync(`${plainPath}-shm`, { force: true });
}

function ensureBackupDir(): void {
  fs.mkdirSync(BACKUP_DIR, { recursive: true });
  // mkdirSync keeps an existing directory's mode; set the bit anyway.
  restrict(BACKUP_DIR, BACKUP_DIR_MODE);
}

function lastBackupAgeMs(): number {
  const marker = path.join(BACKUP_DIR, '.last_backup');
  if (!fs.existsSync(marker)) return Infinity;
  return Date.now() - fs.statSync(marker).mtimeMs;
}

/**
 * The uploads snapshot that belongs to a given database backup file:
 * erp-<stamp>.db -> erp-<stamp>.uploads, and erp-<stamp>.db.enc ->
 * erp-<stamp>.uploads (same directory, same identity, so a restore finds
 * the matching files by name alone whichever form the copy has).
 */
export function uploadsSnapshotPathFor(backupPath: string): string {
  return backupPath.replace(/\.db(?:\.enc)?$/, '.uploads');
}

/**
 * Copies UPLOADS_DIR next to the backup. Non-fatal: an uploads failure must
 * not discard an otherwise good database backup, but it is logged loudly.
 */
function snapshotUploads(backupPath: string): boolean {
  const snapshot = uploadsSnapshotPathFor(backupPath);
  try {
    fs.rmSync(snapshot, { recursive: true, force: true });
    fs.mkdirSync(snapshot, { recursive: true });
    restrict(snapshot, BACKUP_DIR_MODE);
    if (fs.existsSync(UPLOADS_DIR)) {
      fs.cpSync(UPLOADS_DIR, snapshot, { recursive: true });
    }
    logger.info(`[Backup] uploads snapshot ${path.basename(snapshot)}`);
    return true;
  } catch (err) {
    logger.error(`[Backup] uploads snapshot FAILED for ${path.basename(backupPath)}:`, err);
    return false;
  }
}

/**
 * Removes .uploads snapshots whose .db partner no longer exists, so uploads
 * never outlive the database snapshot they were taken with (D7 retention).
 */
function pruneOrphanedUploads(): void {
  if (!fs.existsSync(BACKUP_DIR)) return;
  for (const name of fs.readdirSync(BACKUP_DIR)) {
    if (!name.endsWith('.uploads')) continue;
    const base = name.slice(0, -'.uploads'.length);
    // The partner may be a plain `.db` (a backup taken before encryption, or
    // one taken while no key was configured) or an encrypted `.db.enc`.
    const plain = path.join(BACKUP_DIR, `${base}.db`);
    const container = path.join(BACKUP_DIR, `${base}.db.enc`);
    if (fs.existsSync(plain) || fs.existsSync(container)) continue;
    fs.rmSync(path.join(BACKUP_DIR, name), { recursive: true, force: true });
    logger.info(`[Backup] pruned orphaned uploads ${name}`);
  }
}

export interface BackupFileInfo {
  name: string;
  sizeBytes: number;
  /** File mtime as ISO string. */
  createdAt: string;
}

// Only filenames the service itself generates are addressable over HTTP —
// anything else (../, arbitrary paths) is rejected before touching the fs.
// Accepts both the in-app form (erp-<ts>.db) and the CLI form (erp-backup-<ts>.db),
// plus a numeric suffix for backups taken within the same second, so everything
// the list shows can also be downloaded, deleted and pruned consistently (BK-003/004).
// A `.db.enc` suffix marks an encrypted container (D29 option B); plain `.db`
// names stay valid so backups taken before encryption remain restorable.
const BACKUP_NAME_RE = /^erp-(?:backup-)?\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}(?:-\d+)?\.db(?:\.enc)?$/;

/**
 * Absolute path of an existing backup file, or null when the name is not
 * a generated backup filename (traversal guard) or the file is missing.
 */
export function resolveBackupFilePath(name: string): string | null {
  if (!BACKUP_NAME_RE.test(name)) return null;
  const backupRoot = path.resolve(BACKUP_DIR);
  const target = path.resolve(backupRoot, name);
  if (!target.startsWith(backupRoot + path.sep)) return null;
  if (!fs.existsSync(target)) return null;
  return target;
}

function pruneRetention(): void {
  const files = fs.readdirSync(BACKUP_DIR)
    .filter(f => BACKUP_NAME_RE.test(f))
    .map(f => ({ f, m: fs.statSync(path.join(BACKUP_DIR, f)).mtimeMs }))
    .sort((a, b) => b.m - a.m);
  const now = Date.now();
  const weekBoundary = now - WEEKLY_KEEP * 7 * INTERVAL_MS;
  const daily = files.filter(x => x.m >= now - DAILY_KEEP * INTERVAL_MS);
  const keep = new Set(daily.map(x => x.f));
  // Keep one per week beyond daily window
  const weeksSeen = new Set<number>();
  for (const x of files) {
    const wk = Math.floor(x.m / (7 * INTERVAL_MS));
    if (x.m < now - DAILY_KEEP * INTERVAL_MS && x.m >= weekBoundary && !weeksSeen.has(wk)) {
      weeksSeen.add(wk);
      keep.add(x.f);
    }
  }
  for (const x of files) {
    if (!keep.has(x.f)) {
      fs.rmSync(path.join(BACKUP_DIR, x.f));
      logger.info(`[Backup] pruned ${x.f}`);
    }
  }
}

export interface RunBackupOptions {
  /** 'manual' (user-triggered via API) or 'nightly' (scheduler, default). */
  trigger?: 'manual' | 'nightly';
  /** Attributing user for manual runs; bound into the activity_log row. */
  userId?: number | null;
}

export function runBackup(opts?: RunBackupOptions): string | null {
  const triggerLabel = opts?.trigger === 'manual' ? 'Manual' : 'Nightly';
  try {
    ensureBackupDir();
    // Task 8.8: nightly planner statistics maintenance
    db.exec('ANALYZE');
    // Pre-backup checkpoint so the main DB file is complete
    db.pragma('wal_checkpoint(TRUNCATE)');

    const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
    // Second-resolution names collide when two backups are taken together; pick
    // a free name instead of letting VACUUM INTO fail (BK-004). Both forms are
    // checked, or a container from the same second would be truncated by the
    // encryption step below.
    let target = path.join(BACKUP_DIR, `erp-${stamp}.db`);
    for (let n = 1; fs.existsSync(target) || fs.existsSync(`${target}.enc`); n++) {
      target = path.join(BACKUP_DIR, `erp-${stamp}-${n}.db`);
    }
    // A single quote in the path (e.g. C:\Users\O'Brien\...) would end the SQL
    // string literal early and make every backup fail (BK-001).
    try {
      db.exec(`VACUUM INTO '${target.replace(/'/g, "''")}'`);
    } catch (err) {
      // never leave a partial file that looks like a backup (and counts toward retention)
      fs.rmSync(target, { force: true });
      throw err;
    }

    // Integrity check on the copy
    let res: unknown;
    try {
      // Narrow the copy before it is opened or paired with its uploads.
      restrict(target, BACKUP_FILE_MODE);
      const copy = new Database(target, { readonly: true });
      res = copy.pragma('integrity_check', { simple: true });
      copy.close();
    } catch (err) {
      fs.rmSync(target, { force: true });
      throw err;
    }
    if (res !== 'ok') {
      logger.error(`[Backup] integrity_check FAILED on ${target}: ${res}`);
      fs.rmSync(target);
      return null;
    }

    // D29 option B (Gull, 2026-11-28): wrap the database copy in an
    // encrypted container now that it is proven sound. The uploads snapshot
    // stays plain — that is the split he chose — and the plaintext copy is
    // removed, so the only thing left on disk is the container.
    const passphrase = backupPassphrase();
    if (passphrase) {
      const container = `${target}.enc`;
      try {
        encryptFileSync(target, container, passphrase);
        restrict(container, BACKUP_FILE_MODE);
        removePlainCopy(target);
        target = container;
      } catch (err) {
        // Fail closed: an unencrypted copy must not survive a request for
        // encryption, and a partial container must not look like a backup.
        fs.rmSync(container, { force: true });
        removePlainCopy(target);
        logger.error('[Backup] encryption FAILED — no backup written:', err);
        return null;
      }
    } else {
      // The deployment has not configured a key. The backup is still taken
      // (a missing backup is worse than an unprotected one), but never
      // silently: this line is the only thing standing between a plain
      // backup and someone assuming it is locked.
      logger.warn(
        '[Backup] NOT encrypted: BACKUP_ENCRYPTION_KEY is not set. '
        + 'Anyone who reads the file can open it.'
      );
    }

    fs.utimesSync(target, new Date(), new Date());
    // D7: pair the database snapshot with the files it references.
    snapshotUploads(target);
    // Staleness marker for startBackupScheduler — previously never written,
    // which made the >24h check true on every boot.
    fs.writeFileSync(path.join(BACKUP_DIR, '.last_backup'), new Date().toISOString());
    pruneRetention();
    pruneOrphanedUploads();

    try {
      const description = `${triggerLabel} backup ${path.basename(target)} `
        + `(integrity ok${passphrase ? ', encrypted' : ', NOT encrypted'})`;
      if (opts?.userId) {
        db.prepare(`INSERT INTO activity_log (user_id, action, entity_type, description) VALUES (?, ?, ?, ?)`)
          .run(opts.userId, ActionType.BACKUP_CREATE, 'Database', description);
      } else {
        db.prepare(`INSERT INTO activity_log (action, entity_type, description) VALUES (?, ?, ?)`)
          .run(ActionType.BACKUP_CREATE, 'Database', description);
      }
    } catch { /* non-fatal */ }

    logger.info(`[Backup] created ${path.basename(target)} (${triggerLabel.toLowerCase()})`);
    return target;
  } catch (err) {
    logger.error('[Backup] failed:', err);
    return null;
  }
}

/** Existing backups, newest first. */
export function listBackups(): BackupFileInfo[] {
  if (!fs.existsSync(BACKUP_DIR)) return [];
  return fs.readdirSync(BACKUP_DIR)
    .filter(f => BACKUP_NAME_RE.test(f))
    .map(f => {
      const st = fs.statSync(path.join(BACKUP_DIR, f));
      return { name: f, sizeBytes: st.size, createdAt: new Date(st.mtimeMs).toISOString() };
    })
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
}

/** ISO timestamp of the most recent backup (newest file; falls back to the
 *  scheduler's staleness marker), or null when none exists. */
export function lastBackupAt(): string | null {
  const backups = listBackups();
  if (backups.length > 0) return backups[0].createdAt;
  const marker = path.join(BACKUP_DIR, '.last_backup');
  if (!fs.existsSync(marker)) return null;
  return new Date(fs.statSync(marker).mtimeMs).toISOString();
}

/** Removes one backup file by validated name. False when the name fails
 *  the traversal guard or the file does not exist. */
export function deleteBackupFile(name: string): boolean {
  const target = resolveBackupFilePath(name);
  if (!target) return false;
  fs.rmSync(target);
  // D7: the paired uploads snapshot dies with its database backup, otherwise
  // deleted backups keep leaving orphaned employee documents behind.
  fs.rmSync(uploadsSnapshotPathFor(target), { recursive: true, force: true });
  logger.info(`[Backup] deleted ${name}`);
  return true;
}

let started = false;

/** Fire-on-boot-if-stale + nightly interval (task 7.3). Call once at server start. */
export function startBackupScheduler(): void {
  if (started) return;
  started = true;
  if (process.env.NODE_ENV === 'test') return; // never in tests
  if (lastBackupAgeMs() > INTERVAL_MS) {
    setTimeout(() => runBackup(), 10_000); // shortly after listen
  }
  setInterval(() => runBackup(), INTERVAL_MS).unref();
  // Idempotency keys past the 30-day retention window (decision 8.4) are
  // swept in the same nightly window, so the table cannot grow unbounded
  // without adding a second scheduler.
  setInterval(() => pruneKeys(), INTERVAL_MS).unref();
}

function pruneKeys(): void {
  try {
    const pruned = pruneIdempotencyKeys(db);
    if (pruned > 0) logger.info(`[Idempotency] pruned ${pruned} key(s) past retention`);
  } catch (err) {
    logger.error('[Idempotency] key retention sweep failed', { error: (err as Error).message });
  }
}
