/**
 * Activity Logger Service
 * Centralized service for logging user activities across the application.
 * Uses fire-and-forget pattern with queue-based processing for minimal performance impact.
 */

import db from '../config/database';
import logger from '../utils/logger';
import { ActivityLogDbEntry, ActivityStat } from '../types';

// Activity types enumeration
export enum ActionType {
  // Authentication
  LOGIN = 'LOGIN',
  LOGOUT = 'LOGOUT',
  LOGIN_FAILED = 'LOGIN_FAILED',
  PASSWORD_CHANGE = 'PASSWORD_CHANGE',

  // Inventory
  ITEM_CREATE = 'ITEM_CREATE',
  ITEM_UPDATE = 'ITEM_UPDATE',
  ITEM_DELETE = 'ITEM_DELETE',
  ITEM_RESTORE = 'ITEM_RESTORE',
  WAREHOUSE_CREATE = 'WAREHOUSE_CREATE',
  WAREHOUSE_UPDATE = 'WAREHOUSE_UPDATE',
  WAREHOUSE_DELETE = 'WAREHOUSE_DELETE',
  STOCK_MOVEMENT = 'STOCK_MOVEMENT',

  // Purchases
  PO_CREATE = 'PO_CREATE',
  PO_UPDATE = 'PO_UPDATE',
  PO_APPROVE = 'PO_APPROVE',
  PO_CANCEL = 'PO_CANCEL',
  PO_DELETE = 'PO_DELETE',
  GRN_CREATE = 'GRN_CREATE',
  GRN_UPDATE = 'GRN_UPDATE',

  // Suppliers
  SUPPLIER_CREATE = 'SUPPLIER_CREATE',
  SUPPLIER_UPDATE = 'SUPPLIER_UPDATE',
  SUPPLIER_DELETE = 'SUPPLIER_DELETE',

  // Sales
  SO_CREATE = 'SO_CREATE',
  SO_UPDATE = 'SO_UPDATE',
  SO_CONFIRM = 'SO_CONFIRM',
  SO_DELIVER = 'SO_DELIVER',
  SO_INVOICE = 'SO_INVOICE',
  SO_CANCEL = 'SO_CANCEL',
  SO_DELETE = 'SO_DELETE',

  // Invoices
  INVOICE_CREATE = 'INVOICE_CREATE',
  INVOICE_UPDATE = 'INVOICE_UPDATE',
  INVOICE_POST = 'INVOICE_POST',
  INVOICE_CANCEL = 'INVOICE_CANCEL',
  INVOICE_DELETE = 'INVOICE_DELETE',
  INVOICE_RETURN = 'INVOICE_RETURN',

  // Payments
  PAYMENT_CREATE = 'PAYMENT_CREATE',
  PAYMENT_UPDATE = 'PAYMENT_UPDATE',
  PAYMENT_DELETE = 'PAYMENT_DELETE',

  // Customers
  CUSTOMER_CREATE = 'CUSTOMER_CREATE',
  CUSTOMER_UPDATE = 'CUSTOMER_UPDATE',
  CUSTOMER_DELETE = 'CUSTOMER_DELETE',

  // Manufacturing
  BOM_CREATE = 'BOM_CREATE',
  BOM_UPDATE = 'BOM_UPDATE',
  BOM_DELETE = 'BOM_DELETE',
  WO_CREATE = 'WO_CREATE',
  WO_START = 'WO_START',
  WO_COMPLETE = 'WO_COMPLETE',
  WO_CANCEL = 'WO_CANCEL',
  WO_DELETE = 'WO_DELETE',
  MATERIAL_CONSUME = 'MATERIAL_CONSUME',

  // Employees
  EMPLOYEE_CREATE = 'EMPLOYEE_CREATE',
  EMPLOYEE_UPDATE = 'EMPLOYEE_UPDATE',
  EMPLOYEE_DELETE = 'EMPLOYEE_DELETE',

  // Expenses
  EXPENSE_CREATE = 'EXPENSE_CREATE',
  EXPENSE_UPDATE = 'EXPENSE_UPDATE',
  EXPENSE_DELETE = 'EXPENSE_DELETE',
  EXPENSE_CATEGORY_CREATE = 'EXPENSE_CATEGORY_CREATE',
  EXPENSE_CATEGORY_UPDATE = 'EXPENSE_CATEGORY_UPDATE',
  EXPENSE_CATEGORY_DELETE = 'EXPENSE_CATEGORY_DELETE',

  // Settings & System
  SETTING_UPDATE = 'SETTING_UPDATE',
  BACKUP_CREATE = 'BACKUP_CREATE',
  DATA_IMPORT = 'DATA_IMPORT',
  DATA_EXPORT = 'DATA_EXPORT',
  SYSTEM_CLEANUP = 'SYSTEM_CLEANUP',

  // POS
  POS_SALE = 'POS_SALE',
  POS_RETURN = 'POS_RETURN',

  // Reports
  REPORT_GENERATE = 'REPORT_GENERATE',
  REPORT_EXPORT = 'REPORT_EXPORT'
}

// Log levels
export enum LogLevel {
  DEBUG = 'DEBUG',
  INFO = 'INFO',
  WARNING = 'WARNING',
  ERROR = 'ERROR'
}

// Activity log entry interface
export interface ActivityLogEntry {
  userId?: number;
  action: ActionType | string;
  entityType: string;
  entityId?: number;
  description: string;
  logLevel?: LogLevel;
  ipAddress?: string;
  userAgent?: string;
  metadata?: Record<string, any>;
  durationMs?: number;
  /** Prior row snapshot (task 4.2) — JSON, capped at 8KB */
  oldValue?: unknown;
  /** New row snapshot (task 4.2) — JSON, capped at 8KB */
  newValue?: unknown;
  /** Why the mutation happened (task 4.2) */
  reason?: string;
  /** Links all trail rows from one request / document flow (task 4.2) */
  correlationId?: string;
}

/** Cap a JSON snapshot at 8KB (task 4.2). Oversized snapshots are truncated with a marker. */
function capSnapshot(value: unknown): string | null {
  if (value === undefined || value === null) return null;
  const MAX = 8 * 1024;
  let json = typeof value === 'string' ? value : JSON.stringify(value);
  if (json.length > MAX) {
    json = json.slice(0, MAX - 32) + '...[truncated]';
  }
  return json;
}

// Activity logger service class
class ActivityLoggerService {
  private logQueue: ActivityLogEntry[] = [];
  private isProcessing = false;
  private readonly BATCH_SIZE = 10;
  private readonly FLUSH_INTERVAL = 1000; // 1 second

  constructor() {
    // Start periodic flush
    setInterval(() => this.flush(), this.FLUSH_INTERVAL);
  }

  /**
   * Log an activity entry
   * Uses fire-and-forget pattern - adds to queue and returns immediately
   */
  log(entry: ActivityLogEntry): void {
    // Validate required fields
    if (!entry.action || !entry.entityType) {
      // Validation failure - log skipped silently
      return;
    }

    // Add to queue for async processing. Bound the retry queue at 1000 —
    // drop-oldest with an error log so a DB outage can't grow memory forever (task 4.7).
    if (this.logQueue.length >= 1000) {
      const dropped = this.logQueue.shift();
      logger.error('[ActivityLogger] Queue overflow — dropped oldest entry:', {
        action: dropped?.action,
        entityType: dropped?.entityType
      });
    }
    this.logQueue.push({
      ...entry,
      logLevel: entry.logLevel || LogLevel.INFO
    });

    // Flush if queue is large
    if (this.logQueue.length >= this.BATCH_SIZE) {
      this.flush();
    }
  }

  /**
   * Log authentication activity
   */
  logAuth(
    action: ActionType.LOGIN | ActionType.LOGOUT | ActionType.LOGIN_FAILED | ActionType.PASSWORD_CHANGE,
    userId: number | undefined,
    description: string,
    metadata?: Record<string, any>,
    ipAddress?: string
  ): void {
    this.log({
      userId,
      action,
      entityType: 'Authentication',
      description,
      metadata,
      ipAddress
    });
  }

  /**
   * Log CRUD activity
   */
  logCRUD(
    action: ActionType | string,
    entityType: string,
    entityId: number | undefined,
    description: string,
    userId?: number,
    metadata?: Record<string, any>,
    audit?: {
      oldValue?: unknown;
      newValue?: unknown;
      reason?: string;
      correlationId?: string;
    }
  ): void {
    this.log({
      userId,
      action,
      entityType,
      entityId,
      description,
      metadata,
      oldValue: audit?.oldValue,
      newValue: audit?.newValue,
      reason: audit?.reason,
      correlationId: audit?.correlationId
    });
  }

  /**
   * Log with request metadata
   */
  logWithRequest(
    entry: ActivityLogEntry,
    req: { ip?: string; get?: (header: string) => string | undefined }
  ): void {
    this.log({
      ...entry,
      ipAddress: req.ip || req.get?.('x-forwarded-for') || req.get?.('x-real-ip'),
      userAgent: req.get?.('user-agent')
    });
  }

  /**
   * Flush the log queue to database
   */
  flush(): boolean {
    if (this.isProcessing || this.logQueue.length === 0) {
      return true;
    }

    this.isProcessing = true;
    const batch = this.logQueue.splice(0, this.BATCH_SIZE);

    try {
      const stmt = db.prepare(`
        INSERT INTO activity_log (
          user_id, action, entity_type, entity_id, description,
          log_level, ip_address, user_agent, metadata, duration_ms,
          old_value, new_value, reason, correlation_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `);

      for (const entry of batch) {
        stmt.run(
          entry.userId || null,
          entry.action,
          entry.entityType,
          entry.entityId || null,
          entry.description,
          entry.logLevel || LogLevel.INFO,
          entry.ipAddress || null,
          entry.userAgent || null,
          entry.metadata ? JSON.stringify(entry.metadata) : null,
          entry.durationMs || null,
          capSnapshot(entry.oldValue),
          capSnapshot(entry.newValue),
          entry.reason || null,
          entry.correlationId || null
        );
      }
    } catch (error: any) {
      // Task 4.7: re-queue so nothing is silently lost; caller can detect failure.
      this.logQueue.unshift(...batch);
      logger.error('[ActivityLogger] Failed to flush logs:', { error: error.message });
      return false;
      // Re-add failed entries to queue
      this.logQueue.unshift(...batch);
    } finally {
      this.isProcessing = false;
    }
  }

  /**
   * Get recent activity logs
   */
  getRecent(limit: number = 50): any[] {
    try {
      return db.prepare(`
        SELECT al.*, u.username
        FROM activity_log al
        LEFT JOIN users u ON al.user_id = u.id
        ORDER BY al.created_at DESC
        LIMIT ?
      `).all(limit) as ActivityLogDbEntry[];
    } catch (error: any) {
      logger.error('[ActivityLogger] Failed to get recent logs:', { error: error.message });
      return [];
    }
  }

  /**
   * Get activity logs by user
   */
  getByUser(userId: number, limit: number = 100): any[] {
    try {
      return db.prepare(`
        SELECT al.*, u.username
        FROM activity_log al
        LEFT JOIN users u ON al.user_id = u.id
        WHERE al.user_id = ?
        ORDER BY al.created_at DESC
        LIMIT ?
      `).all(userId, limit) as ActivityLogDbEntry[];
    } catch (error: any) {
      logger.error('[ActivityLogger] Failed to get user logs:', { error: error.message });
      return [];
    }
  }

  /**
   * Get activity logs by entity
   */
  getByEntity(entityType: string, entityId: number, limit: number = 50): any[] {
    try {
      return db.prepare(`
        SELECT al.*, u.username
        FROM activity_log al
        LEFT JOIN users u ON al.user_id = u.id
        WHERE al.entity_type = ? AND al.entity_id = ?
        ORDER BY al.created_at DESC
        LIMIT ?
      `).all(entityType, entityId, limit) as ActivityLogDbEntry[];
    } catch (error: any) {
      logger.error('[ActivityLogger] Failed to get entity logs:', { error: error.message });
      return [];
    }
  }

  /**
   * Get activity statistics
   */
  getStats(startDate?: string, endDate?: string): any {
    try {
      let dateFilter = '';
      const params: any[] = [];

      if (startDate && endDate) {
        dateFilter = ' WHERE created_at BETWEEN ? AND ?';
        params.push(startDate, endDate);
      }

      const actions = db.prepare(`
        SELECT action, COUNT(*) as count
        FROM activity_log
        ${dateFilter}
        GROUP BY action
        ORDER BY count DESC
      `).all(...params) as ActivityStat[];

      const users = db.prepare(`
        SELECT u.username, COUNT(*) as count
        FROM activity_log al
        LEFT JOIN users u ON al.user_id = u.id
        ${dateFilter.replace('WHERE', 'WHERE al.user_id IS NOT NULL AND')}
        GROUP BY al.user_id
        ORDER BY count DESC
        LIMIT 10
      `).all(...params) as ActivityStat[];

      const dailyActivity = db.prepare(`
        SELECT DATE(created_at) as date, COUNT(*) as count
        FROM activity_log
        ${dateFilter}
        GROUP BY DATE(created_at)
        ORDER BY date DESC
        LIMIT 30
      `).all(...params) as ActivityStat[];

      return { actions, users, dailyActivity };
    } catch (error: any) {
      logger.error('[ActivityLogger] Failed to get stats:', { error: error.message });
      return { actions: [], users: [], dailyActivity: [] };
    }
  }

  /**
   * Cleanup old logs (retention policy)
   */
  cleanup(retentionDays: number = 90): number {
    try {
      const result = db.prepare(`
        DELETE FROM activity_log
        WHERE created_at < datetime('now', '-' || ? || ' days')
      `).run(retentionDays);

      if (result.changes > 0) {
        logger.info(`[ActivityLogger] Cleaned up ${result.changes} old log entries`);
      }
      return result.changes;
    } catch (error: any) {
      logger.error('[ActivityLogger] Failed to cleanup logs:', { error: error.message });
      return 0;
    }
  }
}

// Export singleton instance
const activityLogger = new ActivityLoggerService();

// Export individual functions for convenience
export const log = (entry: ActivityLogEntry) => activityLogger.log(entry);
export const logAuth = (...args: Parameters<typeof activityLogger.logAuth>) => activityLogger.logAuth(...args);
export const logCRUD = (...args: Parameters<typeof activityLogger.logCRUD>) => activityLogger.logCRUD(...args);
export const logWithRequest = (...args: Parameters<typeof activityLogger.logWithRequest>) => activityLogger.logWithRequest(...args);
export const flushLogs = () => activityLogger.flush();
export const getRecentLogs = (...args: Parameters<typeof activityLogger.getRecent>) => activityLogger.getRecent(...args);
export const getUserLogs = (...args: Parameters<typeof activityLogger.getByUser>) => activityLogger.getByUser(...args);
export const getEntityLogs = (...args: Parameters<typeof activityLogger.getByEntity>) => activityLogger.getByEntity(...args);
export const getActivityStats = (...args: Parameters<typeof activityLogger.getStats>) => activityLogger.getStats(...args);
export const cleanupLogs = (...args: Parameters<typeof activityLogger.cleanup>) => activityLogger.cleanup(...args);
/** Task 4.2: per-request correlation id shared by all trail rows of one flow. */
export function newCorrelationId(): string {
  return `corr-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
}

export default activityLogger;

/**
 * Transactional activity-log write for model-layer code that runs INSIDE a
 * database transaction (audit-remediation task 4.5). Unlike the queued
 * service, this row commits/rolls back atomically with the business change.
 */
export function logActivityInTx(
  db: import('better-sqlite3').Database,
  entry: {
    userId?: number;
    action: string;
    entityType: string;
    entityId?: number | null;
    description: string;
    oldValue?: unknown;
    newValue?: unknown;
    reason?: string;
    correlationId?: string;
  }
): void {
  const MAX = 8 * 1024;
  const cap = (v: unknown): string | null => {
    if (v === undefined || v === null) return null;
    const raw = typeof v === 'string' ? v : JSON.stringify(v);
    return raw.length > MAX ? raw.slice(0, MAX - 32) + '...[truncated]' : raw;
  };
  db.prepare(`
    INSERT INTO activity_log (
      user_id, action, entity_type, entity_id, description, log_level,
      old_value, new_value, reason, correlation_id
    ) VALUES (?, ?, ?, ?, ?, 'INFO', ?, ?, ?, ?)
  `).run(
    entry.userId ?? null,
    entry.action,
    entry.entityType,
    entry.entityId ?? null,
    entry.description,
    cap(entry.oldValue),
    cap(entry.newValue),
    entry.reason ?? null,
    entry.correlationId ?? null
  );
}
