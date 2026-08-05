"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const database_1 = __importDefault(require("../config/database"));
const logger_1 = __importDefault(require("../utils/logger"));
const Dashboard_1 = __importDefault(require("../models/Dashboard"));
// ═══════════════════════════════════════════════════════════════
//  EXISTING
// ═══════════════════════════════════════════════════════════════
function getSummary(req, res) {
    try {
        const data = Dashboard_1.default.getSummary(database_1.default);
        res.json({ success: true, data });
    }
    catch (error) {
        logger_1.default.error('Dashboard summary error:', error);
        res.status(500).json({ error: 'Failed to fetch dashboard summary' });
    }
}
// ═══════════════════════════════════════════════════════════════
//  DASHBOARD DATA ENDPOINTS
// ═══════════════════════════════════════════════════════════════
/**
 * GET /api/dashboard/top-customers
 * Top N customers by revenue.
 */
function getTopCustomers(req, res) {
    try {
        const limit = req.query.limit ? Number(req.query.limit) : 5;
        const data = Dashboard_1.default.getTopCustomers(database_1.default, limit);
        res.json({ success: true, data });
    }
    catch (error) {
        logger_1.default.error('Top customers error:', error);
        res.status(500).json({ error: 'Failed to fetch top customers' });
    }
}
/**
 * GET /api/dashboard/sales-summary
 * Sales totals by period (today, week, month).
 */
function getSalesSummary(req, res) {
    try {
        const period = req.query.period || 'today';
        const data = Dashboard_1.default.getSalesSummary(database_1.default, period);
        res.json({ success: true, data });
    }
    catch (error) {
        logger_1.default.error('Sales summary error:', error);
        res.status(500).json({ error: 'Failed to fetch sales summary' });
    }
}
/**
 * GET /api/dashboard/expense-summary
 * Expense totals by period (week, month).
 */
function getExpenseSummary(req, res) {
    try {
        const period = req.query.period || 'month';
        const data = Dashboard_1.default.getExpenseSummary(database_1.default, period);
        res.json({ success: true, data });
    }
    catch (error) {
        logger_1.default.error('Expense summary error:', error);
        res.status(500).json({ error: 'Failed to fetch expense summary' });
    }
}
/**
 * GET /api/dashboard/production-status
 * Production counts (active = last 7 days, completed = older).
 */
function getProductionStatus(req, res) {
    try {
        const data = Dashboard_1.default.getProductionStatus(database_1.default);
        res.json({ success: true, data });
    }
    catch (error) {
        logger_1.default.error('Production status error:', error);
        res.status(500).json({ error: 'Failed to fetch production status' });
    }
}
/**
 * GET /api/dashboard/stock-movement-summary
 * Stock movement totals for the last N days.
 */
function getStockMovementSummary(req, res) {
    try {
        const days = req.query.days ? Number(req.query.days) : 7;
        const data = Dashboard_1.default.getStockMovementSummary(database_1.default, days);
        res.json({ success: true, data });
    }
    catch (error) {
        logger_1.default.error('Stock movement summary error:', error);
        res.status(500).json({ error: 'Failed to fetch stock movement summary' });
    }
}
/**
 * GET /api/dashboard/kpi
 * Calculate a KPI metric by name.
 */
function getKPI(req, res) {
    try {
        const metric = req.query.metric || 'stock_health';
        const data = Dashboard_1.default.getKPI(database_1.default, metric);
        res.json({ success: true, data });
    }
    catch (error) {
        logger_1.default.error('KPI error:', error);
        res.status(500).json({ error: 'Failed to calculate KPI' });
    }
}
/**
 * GET /api/dashboard/ar-summary
 * Aggregated accounts receivable summary with aging buckets.
 */
function getARSummary(req, res) {
    try {
        const data = Dashboard_1.default.getARSummary(database_1.default);
        res.json({ success: true, data });
    }
    catch (error) {
        logger_1.default.error('AR summary error:', error);
        res.status(500).json({ error: 'Failed to fetch AR summary' });
    }
}
exports.default = {
    getSummary,
    getTopCustomers,
    getSalesSummary,
    getExpenseSummary,
    getProductionStatus,
    getStockMovementSummary,
    getKPI,
    getARSummary,
};
//# sourceMappingURL=dashboardController.js.map