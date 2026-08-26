/**
 * Activity Log Routes
 * API endpoints for viewing and managing activity logs
 */

import { Router } from 'express';
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import activityLogController from '../controllers/activityLogController';

const router: Router = Router();

// All routes require authentication
router.use(authenticateToken);

// Get activity logs with filters and pagination
router.get('/', requirePermission('activity_log', 'read'), activityLogController.getActivityLogs);

// Get activity statistics
router.get('/stats', requirePermission('activity_log', 'read'), activityLogController.getActivityStats);

// Get recent activity (for dashboard)
router.get('/recent', requirePermission('activity_log', 'read'), activityLogController.getRecentActivity);

// Get available entity types for filtering
router.get('/entity-types', requirePermission('activity_log', 'read'), activityLogController.getEntityTypes);

// Get available actions for filtering
router.get('/actions', requirePermission('activity_log', 'read'), activityLogController.getActions);

// Get all users for filtering dropdown
router.get('/users', requirePermission('activity_log', 'read'), activityLogController.getUsers);

// Get activity logs for a specific user
router.get('/user/:id', requirePermission('activity_log', 'read'), activityLogController.getUserActivity);

// Get activity logs for a specific entity
router.get('/entity/:type/:id', requirePermission('activity_log', 'read'), activityLogController.getEntityActivity);

// Export activity logs to CSV
router.get('/export', requirePermission('activity_log', 'read'), activityLogController.exportLogs);

// Cleanup old logs (admin only)
router.post('/cleanup', requirePermission('activity_log', 'purge'), activityLogController.cleanupLogs);

export default router;
