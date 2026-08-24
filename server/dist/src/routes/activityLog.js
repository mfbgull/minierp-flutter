"use strict";
/**
 * Activity Log Routes
 * API endpoints for viewing and managing activity logs
 */
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const auth_1 = require("../middleware/auth");
const requirePermission_1 = require("../middleware/requirePermission");
const activityLogController_1 = __importDefault(require("../controllers/activityLogController"));
const router = (0, express_1.Router)();
// All routes require authentication
router.use(auth_1.authenticateToken);
// Get activity logs with filters and pagination
router.get('/', (0, requirePermission_1.requirePermission)('activity_log', 'read'), activityLogController_1.default.getActivityLogs);
// Get activity statistics
router.get('/stats', (0, requirePermission_1.requirePermission)('activity_log', 'read'), activityLogController_1.default.getActivityStats);
// Get recent activity (for dashboard)
router.get('/recent', (0, requirePermission_1.requirePermission)('activity_log', 'read'), activityLogController_1.default.getRecentActivity);
// Get available entity types for filtering
router.get('/entity-types', (0, requirePermission_1.requirePermission)('activity_log', 'read'), activityLogController_1.default.getEntityTypes);
// Get available actions for filtering
router.get('/actions', (0, requirePermission_1.requirePermission)('activity_log', 'read'), activityLogController_1.default.getActions);
// Get all users for filtering dropdown
router.get('/users', (0, requirePermission_1.requirePermission)('activity_log', 'read'), activityLogController_1.default.getUsers);
// Get activity logs for a specific user
router.get('/user/:id', (0, requirePermission_1.requirePermission)('activity_log', 'read'), activityLogController_1.default.getUserActivity);
// Get activity logs for a specific entity
router.get('/entity/:type/:id', (0, requirePermission_1.requirePermission)('activity_log', 'read'), activityLogController_1.default.getEntityActivity);
// Export activity logs to CSV
router.get('/export', (0, requirePermission_1.requirePermission)('activity_log', 'read'), activityLogController_1.default.exportLogs);
// Cleanup old logs (admin only)
router.post('/cleanup', (0, requirePermission_1.requirePermission)('activity_log', 'purge'), activityLogController_1.default.cleanupLogs);
exports.default = router;
//# sourceMappingURL=activityLog.js.map