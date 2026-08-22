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

const BACKUP_DIR = path.join(path.dirname(process.env.DATABASE_PATH || path.join(__dirname, '../../database')), 'backups');
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

export function runBackup(): string | null {
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
    pruneRetention();

    try {
      db.prepare(`INSERT INTO activity_log (action, entity_type, description) VALUES (?, ?, ?)`)
        .run(ActionType.BACKUP_CREATE, 'Database', `Nightly backup ${path.basename(target)} (integrity ok)`);
    } catch { /* non-fatal */ }

    logger.info(`[Backup] created ${path.basename(target)}`);
    return target;
  } catch (err) {
    logger.error('[Backup] failed:', err);
    return null;
  }
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
