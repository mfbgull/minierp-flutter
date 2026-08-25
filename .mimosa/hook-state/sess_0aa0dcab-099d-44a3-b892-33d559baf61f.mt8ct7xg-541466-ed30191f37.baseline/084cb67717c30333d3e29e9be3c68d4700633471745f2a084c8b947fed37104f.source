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

import path from 'path';
import { Router, Request, Response } from 'express';
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import {
  deleteBackupFile,
  lastBackupAt,
  listBackups,
  resolveBackupFilePath,
  runBackup,
} from '../services/backupService';
import { ActionType, logWithRequest } from '../services/activityLogger';
import logger from '../utils/logger';

const router = Router();

// Express 5 types params as string | string[]; named params are single strings.
function paramName(value: string | string[]): string {
  return Array.isArray(value) ? value[0] : value;
}

// All endpoints require authentication.
router.use(authenticateToken);

/**
 * GET /api/admin/backup
 * Backup folder status — existing files (newest first) + last backup time.
 */
router.get('/backup', requirePermission('admin', 'read'), (_req: Request, res: Response): void => {
  try {
    res.json({
      success: true,
      data: {
        backups: listBackups(),
        lastBackupAt: lastBackupAt(),
      },
      error: null,
    });
  } catch (error) {
    logger.error('[AdminBackup] list failed:', error);
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
router.post('/backup', requirePermission('admin', 'create'), (req: Request, res: Response): void => {
  try {
    const target = runBackup({ trigger: 'manual', userId: req.user?.id ?? null });
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
      data: { fileName: path.basename(target) },
      error: null,
    });
  } catch (error) {
    logger.error('[AdminBackup] manual backup failed:', error);
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
router.get(
  '/backup/:name/download',
  requirePermission('admin', 'read'),
  (req: Request, res: Response): void => {
    const target = resolveBackupFilePath(paramName(req.params.name));
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
  }
);

/**
 * DELETE /api/admin/backup/:name
 * Remove one backup file from the server's backup folder.
 */
router.delete(
  '/backup/:name',
  requirePermission('admin', 'delete'),
  (req: Request, res: Response): void => {
    try {
      const name = paramName(req.params.name);
      if (!deleteBackupFile(name)) {
        res.status(404).json({
          success: false,
          data: null,
          error: 'Backup not found',
        });
        return;
      }
      logWithRequest(
        {
          userId: req.user?.id,
          action: ActionType.BACKUP_DELETE,
          entityType: 'Database',
          description: `Deleted backup ${name}`,
        },
        req
      );
      res.json({ success: true, data: { deleted: name }, error: null });
    } catch (error) {
      logger.error('[AdminBackup] delete failed:', error);
      res.status(500).json({
        success: false,
        data: null,
        error: 'Failed to delete backup',
      });
    }
  }
);

export default router;
