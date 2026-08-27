/**
 * Activity Log Controller
 * API endpoints for viewing and managing activity logs
 */

import { Request, Response } from 'express';
import { getQueryParam } from '../utils/queryUtils';
import activityLogModel from '../models/ActivityLog';
import { logCRUD, ActionType } from '../services/activityLogger';
import { AuthRequest } from '../types';
import { getQueryInteger, getRouteParam } from '../utils/queryUtils';
import logger from '../utils/logger';

/**
 * Get activity logs with filters and pagination
 * GET /api/activity-logs
 */
export function getActivityLogs(req: Request, res: Response): void {
  try {
    const {
      user_id,
      entity_type,
      entity_id,
      action,
      log_level,
      start_date,
      end_date,
      search,
      limit = '50',
      offset = '0'
    } = req.query;

    const filters = {
      userId: user_id ? parseInt(user_id as string, 10) : undefined,
      entityType: entity_type as string,
      entityId: entity_id ? parseInt(entity_id as string, 10) : undefined,
      action: action as string,
      logLevel: log_level as string,
      startDate: start_date as string,
      endDate: end_date as string,
      search: search as string,
      limit: parseInt(limit as string, 10),
      offset: parseInt(offset as string, 10)
    };

    const result = activityLogModel.find(filters);

    res.json({
      success: true,
      data: result.data,
      total: result.total,
      limit: filters.limit,
      offset: filters.offset
    });
  } catch (error: any) {
    logger.error('[ActivityLogController] Get logs error:', error.message);
    res.status(500).json({ error: 'Failed to fetch activity logs' });
  }
}

/**
 * Get activity statistics
 * GET /api/activity-logs/stats
 */
export function getActivityStats(req: Request, res: Response): void {
  try {
    const { start_date, end_date } = req.query;

    const stats = activityLogModel.getStats(
      start_date as string,
      end_date as string
    );

    res.json({
      success: true,
      data: stats
    });
  } catch (error: any) {
    logger.error('[ActivityLogController] Get stats error:', error.message);
    res.status(500).json({ error: 'Failed to fetch activity statistics' });
  }
}

/**
 * Get activity logs for a specific user
 * GET /api/activity-logs/user/:id
 */
export function getUserActivity(req: Request, res: Response): void {
  try {
    const userId = parseInt(getRouteParam(req.params.id), 10);
    const limit = getQueryInteger(req.query.limit, 100);

    if (isNaN(userId)) {
      res.status(400).json({ error: 'Invalid user ID' });
      return;
    }

    const logs = activityLogModel.findByUser(userId, limit);

    res.json({
      success: true,
      data: logs,
      total: logs.length
    });
  } catch (error: any) {
    logger.error('[ActivityLogController] Get user activity error:', error.message);
    res.status(500).json({ error: 'Failed to fetch user activity' });
  }
}

/**
 * Get activity logs for a specific entity
 * GET /api/activity-logs/entity/:type/:id
 */
export function getEntityActivity(req: Request, res: Response): void {
  try {
    const type = getRouteParam(req.params.type);
    const id = getRouteParam(req.params.id);
    const limit = getQueryInteger(req.query.limit, 50);

    const entityId = parseInt(id, 10);
    if (isNaN(entityId)) {
      res.status(400).json({ error: 'Invalid entity ID' });
      return;
    }

    const logs = activityLogModel.findByEntity(type, entityId, limit);

    res.json({
      success: true,
      data: logs,
      total: logs.length
    });
  } catch (error: any) {
    logger.error('[ActivityLogController] Get entity activity error:', error.message);
    res.status(500).json({ error: 'Failed to fetch entity activity' });
  }
}

/**
 * Get recent activity (dashboard view)
 * GET /api/activity-logs/recent
 */
export function getRecentActivity(req: Request, res: Response): void {
  try {
    const limit = getQueryInteger(req.query.limit, 20);

    const logs = activityLogModel.findRecent(limit);

    res.json({
      success: true,
      data: logs
    });
  } catch (error: any) {
    logger.error('[ActivityLogController] Get recent activity error:', error.message);
    res.status(500).json({ error: 'Failed to fetch recent activity' });
  }
}

/**
 * Get available entity types for filtering
 * GET /api/activity-logs/entity-types
 */
export function getEntityTypes(req: Request, res: Response): void {
  try {
    const entityTypes = activityLogModel.getEntityTypes();

    res.json({
      success: true,
      data: entityTypes
    });
  } catch (error: any) {
    logger.error('[ActivityLogController] Get entity types error:', error.message);
    res.status(500).json({ error: 'Failed to fetch entity types' });
  }
}

/**
 * Get available actions for filtering
 * GET /api/activity-logs/actions
 */
export function getActions(req: Request, res: Response): void {
  try {
    const actions = activityLogModel.getActions();

    res.json({
      success: true,
      data: actions
    });
  } catch (error: any) {
    logger.error('[ActivityLogController] Get actions error:', error.message);
    res.status(500).json({ error: 'Failed to fetch actions' });
  }
}

/**
 * Export activity logs to CSV
 * GET /api/activity-logs/export
 */
export function exportLogs(req: Request, res: Response): void {
  try {
    const userIdParam = getQueryParam(req.query.user_id);
    const entityTypeParam = getQueryParam(req.query.entity_type);
    const actionParam = getQueryParam(req.query.action);
    const startDateParam = getQueryParam(req.query.start_date);
    const endDateParam = getQueryParam(req.query.end_date);
    const searchParam = getQueryParam(req.query.search);

    const user_id = userIdParam as string;
    const entity_type = entityTypeParam as string;
    const action = actionParam as string;
    const start_date = startDateParam as string;
    const end_date = endDateParam as string;
    const search = searchParam as string;

    const filters = {
      userId: user_id ? parseInt(user_id, 10) : undefined,
      entityType: entity_type,
      action: action,
      startDate: start_date,
      endDate: end_date,
      search: search,
      limit: 10000
    };

    const csv = activityLogModel.exportToCSV(filters);

    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', `attachment; filename=activity-logs-${Date.now()}.csv`);
    res.send(csv);
  } catch (error: any) {
    logger.error('[ActivityLogController] Export logs error:', error.message);
    res.status(500).json({ error: 'Failed to export activity logs' });
  }
}

/**
 * Delete old activity logs (admin only, requires manual confirmation)
 * POST /api/activity-logs/cleanup
 */
export function cleanupLogs(req: AuthRequest, res: Response): void {
  try {
    const { days = '365' } = req.body;
    const retentionDays = parseInt(days as string, 10);

    // Task 4.8: minimum retention is 365 days — the audit trail must not be
    // purgeable sooner than that, regardless of who asks.
    const MIN_RETENTION_DAYS = 365;
    if (isNaN(retentionDays) || retentionDays < MIN_RETENTION_DAYS) {
      res.status(400).json({ error: `Invalid retention days — minimum is ${MIN_RETENTION_DAYS}` });
      return;
    }

    const deletedCount = activityLogModel.deleteOlderThan(retentionDays);

    // Log this cleanup action
    const userId = req.user?.id;
    logCRUD(ActionType.SYSTEM_CLEANUP,
    'ActivityLog',
    undefined,
    `Cleaned up ${deletedCount} activity log entries older than ${retentionDays} days`,
    userId);
    req.activityLogged = true;

    res.json({
      success: true,
      message: `Cleaned up ${deletedCount} old log entries`,
      deletedCount
    });
  } catch (error: any) {
    logger.error('[ActivityLogController] Cleanup logs error:', error.message);
    res.status(500).json({ error: 'Failed to cleanup activity logs' });
  }
}

/**
 * Get all users for filtering dropdown
 * GET /api/activity-logs/users
 */
export function getUsers(req: Request, res: Response): void {
  try {
    const users = activityLogModel.getUsers();
    res.json({ success: true, data: users });
  } catch (error: any) {
    logger.error('[ActivityLogController] Get users error:', error.message);
    res.status(500).json({ error: 'Failed to fetch users' });
  }
}

export default {
  getActivityLogs,
  getActivityStats,
  getUserActivity,
  getEntityActivity,
  getRecentActivity,
  getEntityTypes,
  getActions,
  exportLogs,
  cleanupLogs,
  getUsers
};
