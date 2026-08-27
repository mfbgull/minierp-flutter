/**
 * Activity Log Model
 * Database operations for activity logs
 */

import db from '../config/database';
import logger from '../utils/logger';

// Activity log query filters
export interface ActivityLogFilters {
  userId?: number;
  entityType?: string;
  entityId?: number;
  action?: string;
  startDate?: string;
  endDate?: string;
  logLevel?: string;
  search?: string;
  limit?: number;
  offset?: number;
}

// `created_at` is stored in UTC (SQLite `CURRENT_TIMESTAMP`) while the
// client filters by LOCAL calendar dates (`start_date`/`end_date`). The
// query bounds must be converted or a UTC+ timezone pushes the local day
// into the previous UTC calendar day — e.g. local Monday 00:00 in PKT
// (UTC+5) is Sunday 19:00 UTC, so `created_at >= '2026-08-17'` would
// silently exclude the whole local week. Same convention as Dashboard.ts
// (`date('now', 'localtime')`): this desktop app's server runs on the
// user's machine, so the server's local timezone is the client's.
//
// startDate → the UTC instant of local midnight (inclusive lower bound);
// endDate → the UTC instant of the *next* local midnight (exclusive upper
// bound) so the entire end day counts.
//
// Exported for unit tests (activityLog.test.ts) — the conversion is the
// crux of the local-date-vs-UTC-storage fix.
export function localDateToUtcBound(dateStr: string, endOfRange: boolean): string {
  const [y, m, d] = dateStr.split('-').map(Number);
  const local = endOfRange
    ? new Date(y, m - 1, d + 1)
    : new Date(y, m - 1, d);
  return local.toISOString().slice(0, 19).replace('T', ' ');
}

// Activity log entry with user info
export interface ActivityLogWithUser {
  id: number;
  user_id: number | null;
  username: string | null;
  action: string;
  entity_type: string;
  entity_id: number | null;
  description: string;
  log_level: string;
  ip_address: string | null;
  user_agent: string | null;
  metadata: string | null;
  duration_ms: number | null;
  created_at: string;
}

class ActivityLogModel {
  /**
   * Insert a new activity log entry
   */
  insert(
    userId: number | null,
    action: string,
    entityType: string,
    entityId: number | null,
    description: string,
    logLevel: string = 'INFO',
    ipAddress?: string,
    userAgent?: string,
    metadata?: Record<string, any>,
    durationMs?: number
  ): number {
    try {
      const stmt = db.prepare(`
        INSERT INTO activity_log (
          user_id, action, entity_type, entity_id, description,
          log_level, ip_address, user_agent, metadata, duration_ms
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `);

      const result = stmt.run(
        userId,
        action,
        entityType,
        entityId,
        description,
        logLevel,
        ipAddress || null,
        userAgent || null,
        metadata ? JSON.stringify(metadata) : null,
        durationMs || null
      );

      return result.lastInsertRowid as number;
    } catch (error: any) {
      logger.error('[ActivityLogModel] Insert failed:', error.message);
      return 0;
    }
  }

  /**
   * Get activity logs with filters and pagination
   */
  find(filters: ActivityLogFilters): { data: ActivityLogWithUser[]; total: number } {
    try {
      let whereClause = '1=1';
      const params: any[] = [];

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
        params.push(localDateToUtcBound(filters.startDate, false));
      }

      if (filters.endDate) {
        // Exclusive upper bound — `<= endDate` would drop the whole end
        // day (a `YYYY-MM-DD HH:MM:SS` string sorts after a bare date).
        whereClause += ' AND al.created_at < ?';
        params.push(localDateToUtcBound(filters.endDate, true));
      }

      if (filters.search) {
        whereClause += ' AND (al.description LIKE ? OR al.entity_type LIKE ?)';
        params.push(`%${filters.search}%`, `%${filters.search}%`);
      }

      // Get total count
      const countResult = db.prepare(`
        SELECT COUNT(*) as total
        FROM activity_log al
        WHERE ${whereClause}
      `).get(...params) as { total: number };

      // Get paginated data
      const limit = filters.limit || 50;
      const offset = filters.offset || 0;

      const data = db.prepare(`
        SELECT al.*, u.username
        FROM activity_log al
        LEFT JOIN users u ON al.user_id = u.id
        WHERE ${whereClause}
        ORDER BY al.created_at DESC
        LIMIT ? OFFSET ?
      `).all(...params, limit, offset) as ActivityLogWithUser[];

      return { data, total: countResult.total };
    } catch (error: any) {
      logger.error('[ActivityLogModel] Find failed:', error.message);
      return { data: [], total: 0 };
    }
  }

  /**
   * Get activity logs for a specific user
   */
  findByUser(userId: number, limit: number = 100): ActivityLogWithUser[] {
    try {
      return db.prepare(`
        SELECT al.*, u.username
        FROM activity_log al
        LEFT JOIN users u ON al.user_id = u.id
        WHERE al.user_id = ?
        ORDER BY al.created_at DESC
        LIMIT ?
      `).all(userId, limit) as ActivityLogWithUser[];
    } catch (error: any) {
      logger.error('[ActivityLogModel] Find by user failed:', error.message);
      return [];
    }
  }

  /**
   * Get activity logs for a specific entity
   */
  findByEntity(entityType: string, entityId: number, limit: number = 50): ActivityLogWithUser[] {
    try {
      return db.prepare(`
        SELECT al.*, u.username
        FROM activity_log al
        LEFT JOIN users u ON al.user_id = u.id
        WHERE al.entity_type = ? AND al.entity_id = ?
        ORDER BY al.created_at DESC
        LIMIT ?
      `).all(entityType, entityId, limit) as ActivityLogWithUser[];
    } catch (error: any) {
      logger.error('[ActivityLogModel] Find by entity failed:', error.message);
      return [];
    }
  }

  /**
   * Get recent activity across all entities
   */
  findRecent(limit: number = 50): ActivityLogWithUser[] {
    try {
      return db.prepare(`
        SELECT al.*, u.username
        FROM activity_log al
        LEFT JOIN users u ON al.user_id = u.id
        ORDER BY al.created_at DESC
        LIMIT ?
      `).all(limit) as ActivityLogWithUser[];
    } catch (error: any) {
      logger.error('[ActivityLogModel] Find recent failed:', error.message);
      return [];
    }
  }

  /**
   * Get activity statistics
   */
  getStats(startDate?: string, endDate?: string): {
    actions: { action: string; count: number }[];
    users: { username: string | null; count: number }[];
    dailyActivity: { date: string; count: number }[];
    totalLogs: number;
  } {
    try {
      let dateFilter = '';
      const params: any[] = [];

      if (startDate && endDate) {
        dateFilter = ' WHERE created_at >= ? AND created_at < ?';
        params.push(
          localDateToUtcBound(startDate, false),
          localDateToUtcBound(endDate, true),
        );
      }

      // Get action breakdown
      const actions = db.prepare(`
        SELECT action, COUNT(*) as count
        FROM activity_log
        ${dateFilter}
        GROUP BY action
        ORDER BY count DESC
      `).all(...params) as { action: string; count: number }[];

      // Get top users
      const users = db.prepare(`
        SELECT u.username, COUNT(*) as count
        FROM activity_log al
        LEFT JOIN users u ON al.user_id = u.id
        ${dateFilter ? dateFilter.replace('WHERE', 'WHERE al.user_id IS NOT NULL AND') : 'WHERE al.user_id IS NOT NULL'}
        GROUP BY al.user_id
        ORDER BY count DESC
        LIMIT 10
      `).all(...params) as { username: string | null; count: number }[];

      // Get daily activity
      const dailyActivity = db.prepare(`
        SELECT DATE(created_at) as date, COUNT(*) as count
        FROM activity_log
        ${dateFilter}
        GROUP BY DATE(created_at)
        ORDER BY date DESC
        LIMIT 30
      `).all(...params) as { date: string; count: number }[];

      // Get total count
      const totalResult = db.prepare(`
        SELECT COUNT(*) as total FROM activity_log ${dateFilter}
      `).get(...params) as { total: number };

      return { actions, users, dailyActivity, totalLogs: totalResult.total };
    } catch (error: any) {
      logger.error('[ActivityLogModel] Get stats failed:', error.message);
      return { actions: [], users: [], dailyActivity: [], totalLogs: 0 };
    }
  }

  /**
   * Get unique entity types
   */
  getEntityTypes(): string[] {
    try {
      const results = db.prepare(`
        SELECT DISTINCT entity_type
        FROM activity_log
        ORDER BY entity_type
      `).all() as { entity_type: string }[];

      return results.map(r => r.entity_type);
    } catch (error: any) {
      logger.error('[ActivityLogModel] Get entity types failed:', error.message);
      return [];
    }
  }

  /**
   * Get unique actions
   */
  getActions(): string[] {
    try {
      const results = db.prepare(`
        SELECT DISTINCT action
        FROM activity_log
        ORDER BY action
      `).all() as { action: string }[];

      return results.map(r => r.action);
    } catch (error: any) {
      logger.error('[ActivityLogModel] Get actions failed:', error.message);
      return [];
    }
  }

  /**
   * Delete old logs based on retention policy
   */
  deleteOlderThan(days: number): number {
    try {
      const result = db.prepare(`
        DELETE FROM activity_log
        WHERE created_at < datetime('now', '-' || ? || ' days')
      `).run(days);

      return result.changes;
    } catch (error: any) {
      logger.error('[ActivityLogModel] Delete older than failed:', error.message);
      return 0;
    }
  }

  /**
   * Delete a specific log entry
   */
  delete(id: number): boolean {
    try {
      const result = db.prepare('DELETE FROM activity_log WHERE id = ?').run(id);
      return result.changes > 0;
    } catch (error: any) {
      logger.error('[ActivityLogModel] Delete failed:', error.message);
      return false;
    }
  }

  /**
   * Export logs to CSV format
   */
  exportToCSV(filters: ActivityLogFilters): string {
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
    return db.prepare(`
      SELECT id, username, full_name
      FROM users
      WHERE is_active = 1
      ORDER BY username
    `).all();
  }
}

// Export singleton instance
const activityLogModel = new ActivityLogModel();
export default activityLogModel;
