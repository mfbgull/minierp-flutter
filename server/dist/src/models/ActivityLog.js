"use strict";
/**
 * Activity Log Model
 * Database operations for activity logs
 */
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const database_1 = __importDefault(require("../config/database"));
const logger_1 = __importDefault(require("../utils/logger"));
class ActivityLogModel {
    /**
     * Insert a new activity log entry
     */
    insert(userId, action, entityType, entityId, description, logLevel = 'INFO', ipAddress, userAgent, metadata, durationMs) {
        try {
            const stmt = database_1.default.prepare(`
        INSERT INTO activity_log (
          user_id, action, entity_type, entity_id, description,
          log_level, ip_address, user_agent, metadata, duration_ms
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `);
            const result = stmt.run(userId, action, entityType, entityId, description, logLevel, ipAddress || null, userAgent || null, metadata ? JSON.stringify(metadata) : null, durationMs || null);
            return result.lastInsertRowid;
        }
        catch (error) {
            logger_1.default.error('[ActivityLogModel] Insert failed:', error.message);
            return 0;
        }
    }
    /**
     * Get activity logs with filters and pagination
     */
    find(filters) {
        try {
            let whereClause = '1=1';
            const params = [];
            if (filters.userId) {
                whereClause += ' AND al.user_id = ?';
                params.push(filters.userId);
            }
            if (filters.entityType) {
                whereClause += ' AND al.entity_type = ?';
                params.push(filters.entityType);
            }
            if (filters.entityId) {
                whereClause += ' AND al.entity_id = ?';
                params.push(filters.entityId);
            }
            if (filters.action) {
                whereClause += ' AND al.action = ?';
                params.push(filters.action);
            }
            if (filters.logLevel) {
                whereClause += ' AND al.log_level = ?';
                params.push(filters.logLevel);
            }
            if (filters.startDate) {
                whereClause += ' AND al.created_at >= ?';
                params.push(filters.startDate);
            }
            if (filters.endDate) {
                whereClause += ' AND al.created_at <= ?';
                params.push(filters.endDate);
            }
            if (filters.search) {
                whereClause += ' AND (al.description LIKE ? OR al.entity_type LIKE ?)';
                params.push(`%${filters.search}%`, `%${filters.search}%`);
            }
            // Get total count
            const countResult = database_1.default.prepare(`
        SELECT COUNT(*) as total
        FROM activity_log al
        WHERE ${whereClause}
      `).get(...params);
            // Get paginated data
            const limit = filters.limit || 50;
            const offset = filters.offset || 0;
            const data = database_1.default.prepare(`
        SELECT al.*, u.username
        FROM activity_log al
        LEFT JOIN users u ON al.user_id = u.id
        WHERE ${whereClause}
        ORDER BY al.created_at DESC
        LIMIT ? OFFSET ?
      `).all(...params, limit, offset);
            return { data, total: countResult.total };
        }
        catch (error) {
            logger_1.default.error('[ActivityLogModel] Find failed:', error.message);
            return { data: [], total: 0 };
        }
    }
    /**
     * Get activity logs for a specific user
     */
    findByUser(userId, limit = 100) {
        try {
            return database_1.default.prepare(`
        SELECT al.*, u.username
        FROM activity_log al
        LEFT JOIN users u ON al.user_id = u.id
        WHERE al.user_id = ?
        ORDER BY al.created_at DESC
        LIMIT ?
      `).all(userId, limit);
        }
        catch (error) {
            logger_1.default.error('[ActivityLogModel] Find by user failed:', error.message);
            return [];
        }
    }
    /**
     * Get activity logs for a specific entity
     */
    findByEntity(entityType, entityId, limit = 50) {
        try {
            return database_1.default.prepare(`
        SELECT al.*, u.username
        FROM activity_log al
        LEFT JOIN users u ON al.user_id = u.id
        WHERE al.entity_type = ? AND al.entity_id = ?
        ORDER BY al.created_at DESC
        LIMIT ?
      `).all(entityType, entityId, limit);
        }
        catch (error) {
            logger_1.default.error('[ActivityLogModel] Find by entity failed:', error.message);
            return [];
        }
    }
    /**
     * Get recent activity across all entities
     */
    findRecent(limit = 50) {
        try {
            return database_1.default.prepare(`
        SELECT al.*, u.username
        FROM activity_log al
        LEFT JOIN users u ON al.user_id = u.id
        ORDER BY al.created_at DESC
        LIMIT ?
      `).all(limit);
        }
        catch (error) {
            logger_1.default.error('[ActivityLogModel] Find recent failed:', error.message);
            return [];
        }
    }
    /**
     * Get activity statistics
     */
    getStats(startDate, endDate) {
        try {
            let dateFilter = '';
            const params = [];
            if (startDate && endDate) {
                dateFilter = ' WHERE created_at BETWEEN ? AND ?';
                params.push(startDate, endDate);
            }
            // Get action breakdown
            const actions = database_1.default.prepare(`
        SELECT action, COUNT(*) as count
        FROM activity_log
        ${dateFilter}
        GROUP BY action
        ORDER BY count DESC
      `).all(...params);
            // Get top users
            const users = database_1.default.prepare(`
        SELECT u.username, COUNT(*) as count
        FROM activity_log al
        LEFT JOIN users u ON al.user_id = u.id
        ${dateFilter ? dateFilter.replace('WHERE', 'WHERE al.user_id IS NOT NULL AND') : 'WHERE al.user_id IS NOT NULL'}
        GROUP BY al.user_id
        ORDER BY count DESC
        LIMIT 10
      `).all(...params);
            // Get daily activity
            const dailyActivity = database_1.default.prepare(`
        SELECT DATE(created_at) as date, COUNT(*) as count
        FROM activity_log
        ${dateFilter}
        GROUP BY DATE(created_at)
        ORDER BY date DESC
        LIMIT 30
      `).all(...params);
            // Get total count
            const totalResult = database_1.default.prepare(`
        SELECT COUNT(*) as total FROM activity_log ${dateFilter}
      `).get(...params);
            return { actions, users, dailyActivity, totalLogs: totalResult.total };
        }
        catch (error) {
            logger_1.default.error('[ActivityLogModel] Get stats failed:', error.message);
            return { actions: [], users: [], dailyActivity: [], totalLogs: 0 };
        }
    }
    /**
     * Get unique entity types
     */
    getEntityTypes() {
        try {
            const results = database_1.default.prepare(`
        SELECT DISTINCT entity_type
        FROM activity_log
        ORDER BY entity_type
      `).all();
            return results.map(r => r.entity_type);
        }
        catch (error) {
            logger_1.default.error('[ActivityLogModel] Get entity types failed:', error.message);
            return [];
        }
    }
    /**
     * Get unique actions
     */
    getActions() {
        try {
            const results = database_1.default.prepare(`
        SELECT DISTINCT action
        FROM activity_log
        ORDER BY action
      `).all();
            return results.map(r => r.action);
        }
        catch (error) {
            logger_1.default.error('[ActivityLogModel] Get actions failed:', error.message);
            return [];
        }
    }
    /**
     * Delete old logs based on retention policy
     */
    deleteOlderThan(days) {
        try {
            const result = database_1.default.prepare(`
        DELETE FROM activity_log
        WHERE created_at < datetime('now', '-' || ? || ' days')
      `).run(days);
            return result.changes;
        }
        catch (error) {
            logger_1.default.error('[ActivityLogModel] Delete older than failed:', error.message);
            return 0;
        }
    }
    /**
     * Delete a specific log entry
     */
    delete(id) {
        try {
            const result = database_1.default.prepare('DELETE FROM activity_log WHERE id = ?').run(id);
            return result.changes > 0;
        }
        catch (error) {
            logger_1.default.error('[ActivityLogModel] Delete failed:', error.message);
            return false;
        }
    }
    /**
     * Export logs to CSV format
     */
    exportToCSV(filters) {
        const { data } = this.find({ ...filters, limit: 10000 });
        const headers = ['ID', 'User', 'Action', 'Entity Type', 'Entity ID', 'Description', 'Level', 'IP Address', 'Created At'];
        const rows = data.map(log => [
            log.id,
            log.username || 'System',
            log.action,
            log.entity_type,
            log.entity_id || '',
            `"${(log.description || '').replace(/"/g, '""')}"`,
            log.log_level,
            log.ip_address || '',
            log.created_at
        ]);
        return [headers.join(','), ...rows.map(r => r.join(','))].join('\n');
    }
    getUsers() {
        return database_1.default.prepare(`
      SELECT id, username, full_name
      FROM users
      WHERE is_active = 1
      ORDER BY username
    `).all();
    }
}
// Export singleton instance
const activityLogModel = new ActivityLogModel();
exports.default = activityLogModel;
//# sourceMappingURL=ActivityLog.js.map