"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.runBackup = runBackup;
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
const BACKUP_DIR = path_1.default.join(path_1.default.dirname(process.env.DATABASE_PATH || path_1.default.join(__dirname, '../../database')), 'backups');
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
function runBackup() {
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
        pruneRetention();
        try {
            database_1.default.prepare(`INSERT INTO activity_log (action, entity_type, description) VALUES (?, ?, ?)`)
                .run(activityLogger_1.ActionType.BACKUP_CREATE, 'Database', `Nightly backup ${path_1.default.basename(target)} (integrity ok)`);
        }
        catch { /* non-fatal */ }
        logger_1.default.info(`[Backup] created ${path_1.default.basename(target)}`);
        return target;
    }
    catch (err) {
        logger_1.default.error('[Backup] failed:', err);
        return null;
    }
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
//# sourceMappingURL=backupService.js.map