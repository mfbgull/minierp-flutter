"use strict";
/**
 * Admin Backup Routes
 * -------------------
 * Manual trigger, listing, download and deletion of database backups that
 * live in the server's <db-dir>/backups folder (managed by backupService).
 *
 * Mount point: /api/admin
 *
 * Auth:
 *   - All routes gated by authenticateToken + requirePermission('admin', …).
 *     The Admin role bypasses permission checks, so effectively admins-only.
 *
 * Filename safety: every :name parameter must pass resolveBackupFilePath,
 * which only accepts generated `erp-<timestamp>.db` names and rejects any
 * path that would escape the backup directory.
 */
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const path_1 = __importDefault(require("path"));
const express_1 = require("express");
const auth_1 = require("../middleware/auth");
const requirePermission_1 = require("../middleware/requirePermission");
const backupService_1 = require("../services/backupService");
const activityLogger_1 = require("../services/activityLogger");
const logger_1 = __importDefault(require("../utils/logger"));
const router = (0, express_1.Router)();
// Express 5 types params as string | string[]; named params are single strings.
function paramName(value) {
    return Array.isArray(value) ? value[0] : value;
}
// All endpoints require authentication.
router.use(auth_1.authenticateToken);
/**
 * GET /api/admin/backup
 * Backup folder status — existing files (newest first) + last backup time.
 */
router.get('/backup', (0, requirePermission_1.requirePermission)('admin', 'read'), (_req, res) => {
    try {
        res.json({
            success: true,
            data: {
                backups: (0, backupService_1.listBackups)(),
                lastBackupAt: (0, backupService_1.lastBackupAt)(),
            },
            error: null,
        });
    }
    catch (error) {
        logger_1.default.error('[AdminBackup] list failed:', error);
        res.status(500).json({
            success: false,
            data: null,
            error: 'Failed to list backups',
        });
    }
});
/**
 * POST /api/admin/backup
 * Trigger an on-demand backup; attributed to the calling user in the
 * activity trail. 202-style long jobs are unnecessary — VACUUM INTO on
 * this database size completes within a request.
 */
router.post('/backup', (0, requirePermission_1.requirePermission)('admin', 'create'), (req, res) => {
    try {
        const target = (0, backupService_1.runBackup)({ trigger: 'manual', userId: req.user?.id ?? null });
        if (!target) {
            res.status(500).json({
                success: false,
                data: null,
                error: 'Backup failed — check server logs',
            });
            return;
        }
        res.json({
            success: true,
            data: { fileName: path_1.default.basename(target) },
            error: null,
        });
    }
    catch (error) {
        logger_1.default.error('[AdminBackup] manual backup failed:', error);
        res.status(500).json({
            success: false,
            data: null,
            error: 'Backup failed — check server logs',
        });
    }
});
/**
 * GET /api/admin/backup/:name/download
 * Stream one backup file to the client as an attachment.
 */
router.get('/backup/:name/download', (0, requirePermission_1.requirePermission)('admin', 'read'), (req, res) => {
    const target = (0, backupService_1.resolveBackupFilePath)(paramName(req.params.name));
    if (!target) {
        res.status(404).json({
            success: false,
            data: null,
            error: 'Backup not found',
        });
        return;
    }
    // res.download sets Content-Disposition: attachment itself.
    res.download(target, (err) => {
        if (err && !res.headersSent) {
            res.status(500).json({
                success: false,
                data: null,
                error: 'Failed to stream backup file',
            });
        }
    });
});
/**
 * DELETE /api/admin/backup/:name
 * Remove one backup file from the server's backup folder.
 */
router.delete('/backup/:name', (0, requirePermission_1.requirePermission)('admin', 'delete'), (req, res) => {
    try {
        const name = paramName(req.params.name);
        if (!(0, backupService_1.deleteBackupFile)(name)) {
            res.status(404).json({
                success: false,
                data: null,
                error: 'Backup not found',
            });
            return;
        }
        (0, activityLogger_1.logWithRequest)({
            userId: req.user?.id,
            action: activityLogger_1.ActionType.BACKUP_DELETE,
            entityType: 'Database',
            description: `Deleted backup ${name}`,
        }, req);
        res.json({ success: true, data: { deleted: name }, error: null });
    }
    catch (error) {
        logger_1.default.error('[AdminBackup] delete failed:', error);
        res.status(500).json({
            success: false,
            data: null,
            error: 'Failed to delete backup',
        });
    }
});
exports.default = router;
