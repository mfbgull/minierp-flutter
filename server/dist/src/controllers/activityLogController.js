"use strict";
/**
 * Activity Log Controller
 * API endpoints for viewing and managing activity logs
 */
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.getActivityLogs = getActivityLogs;
exports.getActivityStats = getActivityStats;
exports.getUserActivity = getUserActivity;
exports.getEntityActivity = getEntityActivity;
exports.getRecentActivity = getRecentActivity;
exports.getEntityTypes = getEntityTypes;
exports.getActions = getActions;
exports.exportLogs = exportLogs;
exports.cleanupLogs = cleanupLogs;
exports.getUsers = getUsers;
const queryUtils_1 = require("../utils/queryUtils");
const ActivityLog_1 = __importDefault(require("../models/ActivityLog"));
const activityLogger_1 = require("../services/activityLogger");
const queryUtils_2 = require("../utils/queryUtils");
const logger_1 = __importDefault(require("../utils/logger"));
/**
 * Get activity logs with filters and pagination
 * GET /api/activity-logs
 */
function getActivityLogs(req, res) {
    try {
        const { user_id, entity_type, entity_id, action, log_level, start_date, end_date, search, limit = '50', offset = '0' } = req.query;
        const filters = {
            userId: user_id ? parseInt(user_id, 10) : undefined,
            entityType: entity_type,
            entityId: entity_id ? parseInt(entity_id, 10) : undefined,
            action: action,
            logLevel: log_level,
            startDate: start_date,
            endDate: end_date,
            search: search,
            limit: parseInt(limit, 10),
            offset: parseInt(offset, 10)
        };
        const result = ActivityLog_1.default.find(filters);
        res.json({
            success: true,
            data: result.data,
            total: result.total,
            limit: filters.limit,
            offset: filters.offset
        });
    }
    catch (error) {
        logger_1.default.error('[ActivityLogController] Get logs error:', error.message);
        res.status(500).json({ error: 'Failed to fetch activity logs' });
    }
}
/**
 * Get activity statistics
 * GET /api/activity-logs/stats
 */
function getActivityStats(req, res) {
    try {
        const { start_date, end_date } = req.query;
        const stats = ActivityLog_1.default.getStats(start_date, end_date);
        res.json({
            success: true,
            data: stats
        });
    }
    catch (error) {
        logger_1.default.error('[ActivityLogController] Get stats error:', error.message);
        res.status(500).json({ error: 'Failed to fetch activity statistics' });
    }
}
/**
 * Get activity logs for a specific user
 * GET /api/activity-logs/user/:id
 */
function getUserActivity(req, res) {
    try {
        const userId = parseInt((0, queryUtils_2.getRouteParam)(req.params.id), 10);
        const limit = (0, queryUtils_2.getQueryInteger)(req.query.limit, 100);
        if (isNaN(userId)) {
            res.status(400).json({ error: 'Invalid user ID' });
            return;
        }
        const logs = ActivityLog_1.default.findByUser(userId, limit);
        res.json({
            success: true,
            data: logs,
            total: logs.length
        });
    }
    catch (error) {
        logger_1.default.error('[ActivityLogController] Get user activity error:', error.message);
        res.status(500).json({ error: 'Failed to fetch user activity' });
    }
}
/**
 * Get activity logs for a specific entity
 * GET /api/activity-logs/entity/:type/:id
 */
function getEntityActivity(req, res) {
    try {
        const type = (0, queryUtils_2.getRouteParam)(req.params.type);
        const id = (0, queryUtils_2.getRouteParam)(req.params.id);
        const limit = (0, queryUtils_2.getQueryInteger)(req.query.limit, 50);
        const entityId = parseInt(id, 10);
        if (isNaN(entityId)) {
            res.status(400).json({ error: 'Invalid entity ID' });
            return;
        }
        const logs = ActivityLog_1.default.findByEntity(type, entityId, limit);
        res.json({
            success: true,
            data: logs,
            total: logs.length
        });
    }
    catch (error) {
        logger_1.default.error('[ActivityLogController] Get entity activity error:', error.message);
        res.status(500).json({ error: 'Failed to fetch entity activity' });
    }
}
/**
 * Get recent activity (dashboard view)
 * GET /api/activity-logs/recent
 */
function getRecentActivity(req, res) {
    try {
        const limit = (0, queryUtils_2.getQueryInteger)(req.query.limit, 20);
        const logs = ActivityLog_1.default.findRecent(limit);
        res.json({
            success: true,
            data: logs
        });
    }
    catch (error) {
        logger_1.default.error('[ActivityLogController] Get recent activity error:', error.message);
        res.status(500).json({ error: 'Failed to fetch recent activity' });
    }
}
/**
 * Get available entity types for filtering
 * GET /api/activity-logs/entity-types
 */
function getEntityTypes(req, res) {
    try {
        const entityTypes = ActivityLog_1.default.getEntityTypes();
        res.json({
            success: true,
            data: entityTypes
        });
    }
    catch (error) {
        logger_1.default.error('[ActivityLogController] Get entity types error:', error.message);
        res.status(500).json({ error: 'Failed to fetch entity types' });
    }
}
/**
 * Get available actions for filtering
 * GET /api/activity-logs/actions
 */
function getActions(req, res) {
    try {
        const actions = ActivityLog_1.default.getActions();
        res.json({
            success: true,
            data: actions
        });
    }
    catch (error) {
        logger_1.default.error('[ActivityLogController] Get actions error:', error.message);
        res.status(500).json({ error: 'Failed to fetch actions' });
    }
}
/**
 * Export activity logs to CSV
 * GET /api/activity-logs/export
 */
function exportLogs(req, res) {
    try {
        const userIdParam = (0, queryUtils_1.getQueryParam)(req.query.user_id);
        const entityTypeParam = (0, queryUtils_1.getQueryParam)(req.query.entity_type);
        const actionParam = (0, queryUtils_1.getQueryParam)(req.query.action);
        const startDateParam = (0, queryUtils_1.getQueryParam)(req.query.start_date);
        const endDateParam = (0, queryUtils_1.getQueryParam)(req.query.end_date);
        const searchParam = (0, queryUtils_1.getQueryParam)(req.query.search);
        const user_id = userIdParam;
        const entity_type = entityTypeParam;
        const action = actionParam;
        const start_date = startDateParam;
        const end_date = endDateParam;
        const search = searchParam;
        const filters = {
            userId: user_id ? parseInt(user_id, 10) : undefined,
            entityType: entity_type,
            action: action,
            startDate: start_date,
            endDate: end_date,
            search: search,
            limit: 10000
        };
        const csv = ActivityLog_1.default.exportToCSV(filters);
        res.setHeader('Content-Type', 'text/csv');
        res.setHeader('Content-Disposition', `attachment; filename=activity-logs-${Date.now()}.csv`);
        res.send(csv);
    }
    catch (error) {
        logger_1.default.error('[ActivityLogController] Export logs error:', error.message);
        res.status(500).json({ error: 'Failed to export activity logs' });
    }
}
/**
 * Delete old activity logs (admin only, requires manual confirmation)
 * POST /api/activity-logs/cleanup
 */
function cleanupLogs(req, res) {
    try {
        const { days = '365' } = req.body;
        const retentionDays = parseInt(days, 10);
        // Task 4.8: minimum retention is 365 days — the audit trail must not be
        // purgeable sooner than that, regardless of who asks.
        const MIN_RETENTION_DAYS = 365;
        if (isNaN(retentionDays) || retentionDays < MIN_RETENTION_DAYS) {
            res.status(400).json({ error: `Invalid retention days — minimum is ${MIN_RETENTION_DAYS}` });
            return;
        }
        const deletedCount = ActivityLog_1.default.deleteOlderThan(retentionDays);
        // Log this cleanup action
        const userId = req.user?.id;
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.SYSTEM_CLEANUP, 'ActivityLog', undefined, `Cleaned up ${deletedCount} activity log entries older than ${retentionDays} days`, userId);
        req.activityLogged = true;
        res.json({
            success: true,
            message: `Cleaned up ${deletedCount} old log entries`,
            deletedCount
        });
    }
    catch (error) {
        logger_1.default.error('[ActivityLogController] Cleanup logs error:', error.message);
        res.status(500).json({ error: 'Failed to cleanup activity logs' });
    }
}
/**
 * Get all users for filtering dropdown
 * GET /api/activity-logs/users
 */
function getUsers(req, res) {
    try {
        const users = ActivityLog_1.default.getUsers();
        res.json({ success: true, data: users });
    }
    catch (error) {
        logger_1.default.error('[ActivityLogController] Get users error:', error.message);
        res.status(500).json({ error: 'Failed to fetch users' });
    }
}
exports.default = {
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
//# sourceMappingURL=activityLogController.js.map