/**
 * Scheduled database backup service (audit-remediation task 7.3 / DR-01, DR-02).
 *
 * - Nightly in-process timer; fires on boot if the last backup is > 24h old.
 * - wal_checkpoint(TRUNCATE) before copying; VACUUM INTO for a consistent
 *   snapshot; integrity_check on the copy; retention prune (7 daily / 4 weekly).
 */
import fs from 'fs';
import path from 'path';
import Database from 'better-sqlite3';
import db from '../config/database';
import logger from '../utils/logger';
import { ActionType } from './activityLogger';

// DATABASE_PATH is the database *directory* (see config/database.ts);
// backups live alongside erp.db inside <db-dir>/backups.
const DB_DIR = process.env.DATABASE_PATH || path.join(__dirname, '../../database');
const BACKUP_DIR = path.join(DB_DIR, 'backups');
const DAILY_KEEP = 7;
const WEEKLY_KEEP = 4;
const INTERVAL_MS = 24 * 60 * 60 * 1000;

function ensureBackupDir(): void {
  fs.mkdirSync(BACKUP_DIR, { recursive: true });
}

function lastBackupAgeMs(): number {
  const marker = path.join(BACKUP_DIR, '.last_backup');
  if (!fs.existsSync(marker)) return Infinity;
  return Date.now() - fs.statSync(marker).mtimeMs;
}

export interface BackupFileInfo {
  name: string;
  sizeBytes: number;
  /** File mtime as ISO string. */
  createdAt: string;
}

// Only filenames the service itself generates are addressable over HTTP —
// anything else (../, arbitrary paths) is rejected before touching the fs.
const BACKUP_NAME_RE = /^erp-\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}\.db$/;

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
    .filter(f => f.startsWith('erp-') && f.endsWith('.db'))
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
    const target = path.join(BACKUP_DIR, `erp-${stamp}.db`);
    db.exec(`VACUUM INTO '${target}'`);

    // Integrity check on the copy
    const copy = new Database(target, { readonly: true });
    const res = copy.pragma('integrity_check', { simple: true }) as unknown;
    copy.close();
    if (res !== 'ok') {
      logger.error(`[Backup] integrity_check FAILED on ${target}: ${res}`);
      fs.rmSync(target);
      return null;
    }

    fs.utimesSync(target, new Date(), new Date());
    // Staleness marker for startBackupScheduler — previously never written,
    // which made the >24h check true on every boot.
    fs.writeFileSync(path.join(BACKUP_DIR, '.last_backup'), new Date().toISOString());
    pruneRetention();

    try {
      const description = `${triggerLabel} backup ${path.basename(target)} (integrity ok)`;
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
    .filter(f => f.startsWith('erp-') && f.endsWith('.db'))
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
}
