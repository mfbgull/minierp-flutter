"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.resolveBackupFilePath = resolveBackupFilePath;
exports.runBackup = runBackup;
exports.listBackups = listBackups;
exports.lastBackupAt = lastBackupAt;
exports.deleteBackupFile = deleteBackupFile;
exports.startBackupScheduler = startBackupScheduler;
/**
 * Scheduled database backup service (audit-remediation task 7.3 / DR-01, DR-02).
 *
 * - Nightly in-process timer; fires on boot if the last backup is > 24h old.
 * - wal_checkpoint(TRUNCATE) before copying; VACUUM INTO for a consistent
 *   snapshot; integrity_check on the copy; retention prune (7 daily / 4 weekly).
 */
const fs_1 = __importDefault(require("fs"));
const path_1 = __importDefault(require("path"));
const better_sqlite3_1 = __importDefault(require("better-sqlite3"));
const database_1 = __importDefault(require("../config/database"));
const logger_1 = __importDefault(require("../utils/logger"));
const activityLogger_1 = require("./activityLogger");
// DATABASE_PATH is the database *directory* (see config/database.ts);
// backups live alongside erp.db inside <db-dir>/backups.
const DB_DIR = process.env.DATABASE_PATH || path_1.default.join(__dirname, '../../database');
const BACKUP_DIR = path_1.default.join(DB_DIR, 'backups');
const DAILY_KEEP = 7;
const WEEKLY_KEEP = 4;
const INTERVAL_MS = 24 * 60 * 60 * 1000;
function ensureBackupDir() {
    fs_1.default.mkdirSync(BACKUP_DIR, { recursive: true });
}
function lastBackupAgeMs() {
    const marker = path_1.default.join(BACKUP_DIR, '.last_backup');
    if (!fs_1.default.existsSync(marker))
        return Infinity;
    return Date.now() - fs_1.default.statSync(marker).mtimeMs;
}
// Only filenames the service itself generates are addressable over HTTP —
// anything else (../, arbitrary paths) is rejected before touching the fs.
const BACKUP_NAME_RE = /^erp-\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}\.db$/;
/**
 * Absolute path of an existing backup file, or null when the name is not
 * a generated backup filename (traversal guard) or the file is missing.
 */
function resolveBackupFilePath(name) {
    if (!BACKUP_NAME_RE.test(name))
        return null;
    const backupRoot = path_1.default.resolve(BACKUP_DIR);
    const target = path_1.default.resolve(backupRoot, name);
    if (!target.startsWith(backupRoot + path_1.default.sep))
        return null;
    if (!fs_1.default.existsSync(target))
        return null;
    return target;
}
function pruneRetention() {
    const files = fs_1.default.readdirSync(BACKUP_DIR)
        .filter(f => f.startsWith('erp-') && f.endsWith('.db'))
        .map(f => ({ f, m: fs_1.default.statSync(path_1.default.join(BACKUP_DIR, f)).mtimeMs }))
        .sort((a, b) => b.m - a.m);
    const now = Date.now();
    const weekBoundary = now - WEEKLY_KEEP * 7 * INTERVAL_MS;
    const daily = files.filter(x => x.m >= now - DAILY_KEEP * INTERVAL_MS);
    const keep = new Set(daily.map(x => x.f));
    // Keep one per week beyond daily window
    const weeksSeen = new Set();
    for (const x of files) {
        const wk = Math.floor(x.m / (7 * INTERVAL_MS));
        if (x.m < now - DAILY_KEEP * INTERVAL_MS && x.m >= weekBoundary && !weeksSeen.has(wk)) {
            weeksSeen.add(wk);
            keep.add(x.f);
        }
    }
    for (const x of files) {
        if (!keep.has(x.f)) {
            fs_1.default.rmSync(path_1.default.join(BACKUP_DIR, x.f));
            logger_1.default.info(`[Backup] pruned ${x.f}`);
        }
    }
}
function runBackup(opts) {
    const triggerLabel = opts?.trigger === 'manual' ? 'Manual' : 'Nightly';
    try {
        ensureBackupDir();
        // Task 8.8: nightly planner statistics maintenance
        database_1.default.exec('ANALYZE');
        // Pre-backup checkpoint so the main DB file is complete
        database_1.default.pragma('wal_checkpoint(TRUNCATE)');
        const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
        const target = path_1.default.join(BACKUP_DIR, `erp-${stamp}.db`);
        database_1.default.exec(`VACUUM INTO '${target}'`);
        // Integrity check on the copy
        const copy = new better_sqlite3_1.default(target, { readonly: true });
        const res = copy.pragma('integrity_check', { simple: true });
        copy.close();
        if (res !== 'ok') {
            logger_1.default.error(`[Backup] integrity_check FAILED on ${target}: ${res}`);
            fs_1.default.rmSync(target);
            return null;
        }
        fs_1.default.utimesSync(target, new Date(), new Date());
        // Staleness marker for startBackupScheduler — previously never written,
        // which made the >24h check true on every boot.
        fs_1.default.writeFileSync(path_1.default.join(BACKUP_DIR, '.last_backup'), new Date().toISOString());
        pruneRetention();
        try {
            const description = `${triggerLabel} backup ${path_1.default.basename(target)} (integrity ok)`;
            if (opts?.userId) {
                database_1.default.prepare(`INSERT INTO activity_log (user_id, action, entity_type, description) VALUES (?, ?, ?, ?)`)
                    .run(opts.userId, activityLogger_1.ActionType.BACKUP_CREATE, 'Database', description);
            }
            else {
                database_1.default.prepare(`INSERT INTO activity_log (action, entity_type, description) VALUES (?, ?, ?)`)
                    .run(activityLogger_1.ActionType.BACKUP_CREATE, 'Database', description);
            }
        }
        catch { /* non-fatal */ }
        logger_1.default.info(`[Backup] created ${path_1.default.basename(target)} (${triggerLabel.toLowerCase()})`);
        return target;
    }
    catch (err) {
        logger_1.default.error('[Backup] failed:', err);
        return null;
    }
}
/** Existing backups, newest first. */
function listBackups() {
    if (!fs_1.default.existsSync(BACKUP_DIR))
        return [];
    return fs_1.default.readdirSync(BACKUP_DIR)
        .filter(f => f.startsWith('erp-') && f.endsWith('.db'))
        .map(f => {
        const st = fs_1.default.statSync(path_1.default.join(BACKUP_DIR, f));
        return { name: f, sizeBytes: st.size, createdAt: new Date(st.mtimeMs).toISOString() };
    })
        .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
}
/** ISO timestamp of the most recent backup (newest file; falls back to the
 *  scheduler's staleness marker), or null when none exists. */
function lastBackupAt() {
    const backups = listBackups();
    if (backups.length > 0)
        return backups[0].createdAt;
    const marker = path_1.default.join(BACKUP_DIR, '.last_backup');
    if (!fs_1.default.existsSync(marker))
        return null;
    return new Date(fs_1.default.statSync(marker).mtimeMs).toISOString();
}
/** Removes one backup file by validated name. False when the name fails
 *  the traversal guard or the file does not exist. */
function deleteBackupFile(name) {
    const target = resolveBackupFilePath(name);
    if (!target)
        return false;
    fs_1.default.rmSync(target);
    logger_1.default.info(`[Backup] deleted ${name}`);
    return true;
}
let started = false;
/** Fire-on-boot-if-stale + nightly interval (task 7.3). Call once at server start. */
function startBackupScheduler() {
    if (started)
        return;
    started = true;
    if (process.env.NODE_ENV === 'test')
        return; // never in tests
    if (lastBackupAgeMs() > INTERVAL_MS) {
        setTimeout(() => runBackup(), 10000); // shortly after listen
    }
    setInterval(() => runBackup(), INTERVAL_MS).unref();
}
