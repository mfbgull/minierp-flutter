"use strict";
/**
 * Activity Logger Service
 * Centralized service for logging user activities across the application.
 * Uses fire-and-forget pattern with queue-based processing for minimal performance impact.
 */
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.cleanupLogs = exports.getActivityStats = exports.getEntityLogs = exports.getUserLogs = exports.getRecentLogs = exports.flushLogs = exports.logWithRequest = exports.logCRUD = exports.logAuth = exports.log = exports.LogLevel = exports.ActionType = void 0;
const database_1 = __importDefault(require("../config/database"));
const logger_1 = __importDefault(require("../utils/logger"));
// Activity types enumeration
var ActionType;
(function (ActionType) {
    // Authentication
    ActionType["LOGIN"] = "LOGIN";
    ActionType["LOGOUT"] = "LOGOUT";
    ActionType["LOGIN_FAILED"] = "LOGIN_FAILED";
    ActionType["PASSWORD_CHANGE"] = "PASSWORD_CHANGE";
    // Inventory
    ActionType["ITEM_CREATE"] = "ITEM_CREATE";
    ActionType["ITEM_UPDATE"] = "ITEM_UPDATE";
    ActionType["ITEM_DELETE"] = "ITEM_DELETE";
    ActionType["ITEM_RESTORE"] = "ITEM_RESTORE";
    ActionType["WAREHOUSE_CREATE"] = "WAREHOUSE_CREATE";
    ActionType["WAREHOUSE_UPDATE"] = "WAREHOUSE_UPDATE";
    ActionType["WAREHOUSE_DELETE"] = "WAREHOUSE_DELETE";
    ActionType["STOCK_MOVEMENT"] = "STOCK_MOVEMENT";
    // Purchases
    ActionType["PO_CREATE"] = "PO_CREATE";
    ActionType["PO_UPDATE"] = "PO_UPDATE";
    ActionType["PO_APPROVE"] = "PO_APPROVE";
    ActionType["PO_CANCEL"] = "PO_CANCEL";
    ActionType["PO_DELETE"] = "PO_DELETE";
    ActionType["GRN_CREATE"] = "GRN_CREATE";
    ActionType["GRN_UPDATE"] = "GRN_UPDATE";
    // Suppliers
    ActionType["SUPPLIER_CREATE"] = "SUPPLIER_CREATE";
    ActionType["SUPPLIER_UPDATE"] = "SUPPLIER_UPDATE";
    ActionType["SUPPLIER_DELETE"] = "SUPPLIER_DELETE";
    // Sales
    ActionType["SO_CREATE"] = "SO_CREATE";
    ActionType["SO_UPDATE"] = "SO_UPDATE";
    ActionType["SO_CONFIRM"] = "SO_CONFIRM";
    ActionType["SO_DELIVER"] = "SO_DELIVER";
    ActionType["SO_INVOICE"] = "SO_INVOICE";
    ActionType["SO_CANCEL"] = "SO_CANCEL";
    ActionType["SO_DELETE"] = "SO_DELETE";
    // Invoices
    ActionType["INVOICE_CREATE"] = "INVOICE_CREATE";
    ActionType["INVOICE_UPDATE"] = "INVOICE_UPDATE";
    ActionType["INVOICE_POST"] = "INVOICE_POST";
    ActionType["INVOICE_CANCEL"] = "INVOICE_CANCEL";
    ActionType["INVOICE_DELETE"] = "INVOICE_DELETE";
    // Payments
    ActionType["PAYMENT_CREATE"] = "PAYMENT_CREATE";
    ActionType["PAYMENT_UPDATE"] = "PAYMENT_UPDATE";
    ActionType["PAYMENT_DELETE"] = "PAYMENT_DELETE";
    // Customers
    ActionType["CUSTOMER_CREATE"] = "CUSTOMER_CREATE";
    ActionType["CUSTOMER_UPDATE"] = "CUSTOMER_UPDATE";
    ActionType["CUSTOMER_DELETE"] = "CUSTOMER_DELETE";
    // Manufacturing
    ActionType["BOM_CREATE"] = "BOM_CREATE";
    ActionType["BOM_UPDATE"] = "BOM_UPDATE";
    ActionType["BOM_DELETE"] = "BOM_DELETE";
    ActionType["WO_CREATE"] = "WO_CREATE";
    ActionType["WO_START"] = "WO_START";
    ActionType["WO_COMPLETE"] = "WO_COMPLETE";
    ActionType["WO_CANCEL"] = "WO_CANCEL";
    ActionType["WO_DELETE"] = "WO_DELETE";
    ActionType["MATERIAL_CONSUME"] = "MATERIAL_CONSUME";
    // Employees
    ActionType["EMPLOYEE_CREATE"] = "EMPLOYEE_CREATE";
    ActionType["EMPLOYEE_UPDATE"] = "EMPLOYEE_UPDATE";
    ActionType["EMPLOYEE_DELETE"] = "EMPLOYEE_DELETE";
    // Expenses
    ActionType["EXPENSE_CREATE"] = "EXPENSE_CREATE";
    ActionType["EXPENSE_UPDATE"] = "EXPENSE_UPDATE";
    ActionType["EXPENSE_DELETE"] = "EXPENSE_DELETE";
    ActionType["EXPENSE_CATEGORY_CREATE"] = "EXPENSE_CATEGORY_CREATE";
    ActionType["EXPENSE_CATEGORY_UPDATE"] = "EXPENSE_CATEGORY_UPDATE";
    ActionType["EXPENSE_CATEGORY_DELETE"] = "EXPENSE_CATEGORY_DELETE";
    // Settings & System
    ActionType["SETTING_UPDATE"] = "SETTING_UPDATE";
    ActionType["BACKUP_CREATE"] = "BACKUP_CREATE";
    ActionType["DATA_IMPORT"] = "DATA_IMPORT";
    ActionType["DATA_EXPORT"] = "DATA_EXPORT";
    ActionType["SYSTEM_CLEANUP"] = "SYSTEM_CLEANUP";
    // POS
    ActionType["POS_SALE"] = "POS_SALE";
    ActionType["POS_RETURN"] = "POS_RETURN";
    // Reports
    ActionType["REPORT_GENERATE"] = "REPORT_GENERATE";
    ActionType["REPORT_EXPORT"] = "REPORT_EXPORT";
})(ActionType || (exports.ActionType = ActionType = {}));
// Log levels
var LogLevel;
(function (LogLevel) {
    LogLevel["DEBUG"] = "DEBUG";
    LogLevel["INFO"] = "INFO";
    LogLevel["WARNING"] = "WARNING";
    LogLevel["ERROR"] = "ERROR";
})(LogLevel || (exports.LogLevel = LogLevel = {}));
// Activity logger service class
class ActivityLoggerService {
    constructor() {
        this.logQueue = [];
        this.isProcessing = false;
        this.BATCH_SIZE = 10;
        this.FLUSH_INTERVAL = 1000; // 1 second
        // Start periodic flush
        setInterval(() => this.flush(), this.FLUSH_INTERVAL);
    }
    /**
     * Log an activity entry
     * Uses fire-and-forget pattern - adds to queue and returns immediately
     */
    log(entry) {
        // Validate required fields
        if (!entry.action || !entry.entityType) {
            // Validation failure - log skipped silently
            return;
        }
        // Add to queue for async processing
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
    logAuth(action, userId, description, metadata, ipAddress) {
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
    logCRUD(action, entityType, entityId, description, userId, metadata) {
        this.log({
            userId,
            action,
            entityType,
            entityId,
            description,
            metadata
        });
    }
    /**
     * Log with request metadata
     */
    logWithRequest(entry, req) {
        this.log({
            ...entry,
            ipAddress: req.ip || req.get?.('x-forwarded-for') || req.get?.('x-real-ip'),
            userAgent: req.get?.('user-agent')
        });
    }
    /**
     * Flush the log queue to database
     */
    flush() {
        if (this.isProcessing || this.logQueue.length === 0) {
            return;
        }
        this.isProcessing = true;
        const batch = this.logQueue.splice(0, this.BATCH_SIZE);
        try {
            const stmt = database_1.default.prepare(`
        INSERT INTO activity_log (
          user_id, action, entity_type, entity_id, description,
          log_level, ip_address, user_agent, metadata, duration_ms
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `);
            for (const entry of batch) {
                stmt.run(entry.userId || null, entry.action, entry.entityType, entry.entityId || null, entry.description, entry.logLevel || LogLevel.INFO, entry.ipAddress || null, entry.userAgent || null, entry.metadata ? JSON.stringify(entry.metadata) : null, entry.durationMs || null);
            }
        }
        catch (error) {
            logger_1.default.error('[ActivityLogger] Failed to flush logs:', { error: error.message });
            // Re-add failed entries to queue
            this.logQueue.unshift(...batch);
        }
        finally {
            this.isProcessing = false;
        }
    }
    /**
     * Get recent activity logs
     */
    getRecent(limit = 50) {
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
            logger_1.default.error('[ActivityLogger] Failed to get recent logs:', { error: error.message });
            return [];
        }
    }
    /**
     * Get activity logs by user
     */
    getByUser(userId, limit = 100) {
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
            logger_1.default.error('[ActivityLogger] Failed to get user logs:', { error: error.message });
            return [];
        }
    }
    /**
     * Get activity logs by entity
     */
    getByEntity(entityType, entityId, limit = 50) {
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
            logger_1.default.error('[ActivityLogger] Failed to get entity logs:', { error: error.message });
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
            const actions = database_1.default.prepare(`
        SELECT action, COUNT(*) as count
        FROM activity_log
        ${dateFilter}
        GROUP BY action
        ORDER BY count DESC
      `).all(...params);
            const users = database_1.default.prepare(`
        SELECT u.username, COUNT(*) as count
        FROM activity_log al
        LEFT JOIN users u ON al.user_id = u.id
        ${dateFilter.replace('WHERE', 'WHERE al.user_id IS NOT NULL AND')}
        GROUP BY al.user_id
        ORDER BY count DESC
        LIMIT 10
      `).all(...params);
            const dailyActivity = database_1.default.prepare(`
        SELECT DATE(created_at) as date, COUNT(*) as count
        FROM activity_log
        ${dateFilter}
        GROUP BY DATE(created_at)
        ORDER BY date DESC
        LIMIT 30
      `).all(...params);
            return { actions, users, dailyActivity };
        }
        catch (error) {
            logger_1.default.error('[ActivityLogger] Failed to get stats:', { error: error.message });
            return { actions: [], users: [], dailyActivity: [] };
        }
    }
    /**
     * Cleanup old logs (retention policy)
     */
    cleanup(retentionDays = 90) {
        try {
            const result = database_1.default.prepare(`
        DELETE FROM activity_log
        WHERE created_at < datetime('now', '-' || ? || ' days')
      `).run(retentionDays);
            if (result.changes > 0) {
                logger_1.default.info(`[ActivityLogger] Cleaned up ${result.changes} old log entries`);
            }
            return result.changes;
        }
        catch (error) {
            logger_1.default.error('[ActivityLogger] Failed to cleanup logs:', { error: error.message });
            return 0;
        }
    }
}
// Export singleton instance
const activityLogger = new ActivityLoggerService();
// Export individual functions for convenience
const log = (entry) => activityLogger.log(entry);
exports.log = log;
const logAuth = (...args) => activityLogger.logAuth(...args);
exports.logAuth = logAuth;
const logCRUD = (...args) => activityLogger.logCRUD(...args);
exports.logCRUD = logCRUD;
const logWithRequest = (...args) => activityLogger.logWithRequest(...args);
exports.logWithRequest = logWithRequest;
const flushLogs = () => activityLogger.flush();
exports.flushLogs = flushLogs;
const getRecentLogs = (...args) => activityLogger.getRecent(...args);
exports.getRecentLogs = getRecentLogs;
const getUserLogs = (...args) => activityLogger.getByUser(...args);
exports.getUserLogs = getUserLogs;
const getEntityLogs = (...args) => activityLogger.getByEntity(...args);
exports.getEntityLogs = getEntityLogs;
const getActivityStats = (...args) => activityLogger.getStats(...args);
exports.getActivityStats = getActivityStats;
const cleanupLogs = (...args) => activityLogger.cleanup(...args);
exports.cleanupLogs = cleanupLogs;
exports.default = activityLogger;
//# sourceMappingURL=activityLogger.js.map