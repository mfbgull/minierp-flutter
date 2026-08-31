"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const database_1 = __importDefault(require("../config/database"));
const logger_1 = __importDefault(require("../utils/logger"));
const queryUtils_1 = require("../utils/queryUtils");
const Dashboard_1 = __importDefault(require("../models/Dashboard"));
const EmployeeLoan_1 = require("../models/EmployeeLoan");
const Reports_1 = __importDefault(require("../models/Reports"));
const cashService_1 = require("../services/cashService");
// ═══════════════════════════════════════════════════════════════
//  EXISTING
// ═══════════════════════════════════════════════════════════════
function getSummary(req, res) {
    try {
        const fromDate = String(req.query.fromDate || req.query.from_date || '');
        const toDate = String(req.query.toDate || req.query.to_date || '');
        const data = Dashboard_1.default.getSummary(database_1.default, fromDate || undefined, toDate || undefined);
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
        // The user id makes `period=week` a calendar week aligned to the
        // user's saved week-start day (spec §6.3).
        const data = Dashboard_1.default.getSalesSummary(database_1.default, period, req.user?.id);
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
        // The user id makes `period=week` a calendar week aligned to the
        // user's saved week-start day (spec §6.3).
        const data = Dashboard_1.default.getExpenseSummary(database_1.default, period, req.user?.id);
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
        const fromDate = String(((0, queryUtils_1.getQueryParam)(req.query.fromDate)) || '');
        const toDate = String(((0, queryUtils_1.getQueryParam)(req.query.toDate)) || '');
        const data = Dashboard_1.default.getKPI(database_1.default, metric, fromDate || undefined, toDate || undefined);
        res.json({ success: true, data });
    }
    catch (error) {
        logger_1.default.error('KPI error:', error);
        res.status(500).json({ error: 'Failed to calculate KPI' });
    }
}
/**
 * GET /api/dashboard/kpi-batch?metrics=a,b,c (task 8.4)
 * Multiple KPIs in one round trip. Unknown metrics return null for their key.
 */
function getKPIBatch(req, res) {
    try {
        const raw = String(req.query.metrics || '');
        const metrics = raw.split(',').map(s => s.trim()).filter(Boolean).slice(0, 12);
        const fromDate = String((0, queryUtils_1.getQueryParam)(req.query.fromDate) || '') || undefined;
        const toDate = String((0, queryUtils_1.getQueryParam)(req.query.toDate) || '') || undefined;
        const data = {};
        for (const metric of metrics) {
            try {
                data[metric] = Dashboard_1.default.getKPI(database_1.default, metric, fromDate, toDate);
            }
            catch {
                data[metric] = null;
            }
        }
        res.json({ success: true, data });
    }
    catch (error) {
        logger_1.default.error('KPI batch error:', error);
        res.status(500).json({ error: 'Failed to calculate KPIs' });
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
/**
 * GET /api/dashboard/cash-position
 * Closing balance per cash account (Cash, Bank, Easypaisa, JazzCash,
 * UPaisa) as of today + the grand total.
 */
function getCashPosition(req, res) {
    try {
        const data = Dashboard_1.default.getCashPosition(database_1.default);
        res.json({ success: true, data });
    }
    catch (error) {
        logger_1.default.error('Cash position error:', error);
        res.status(500).json({ error: 'Failed to fetch cash position' });
    }
}
/**
 * GET /api/dashboard/expiry-alerts?days=30
 * Batches with stock remaining whose expiry_date falls within `days`
 * (already-expired batches sort first). Backs the dashboard expiry feed.
 */
function getExpiryAlerts(req, res) {
    try {
        const days = Math.max(0, parseInt(String(req.query.days ?? '30'), 10) || 30);
        res.json({ success: true, data: Reports_1.default.getExpiryAlerts(database_1.default, days) });
    }
    catch (error) {
        logger_1.default.error('Expiry alerts error:', error);
        res.status(500).json({ error: 'Failed to fetch expiry alerts' });
    }
}
/**
 * GET /api/dashboard/cash-opening-balances
 * The per-account opening (seed) balances a new business starts with.
 */
function getCashOpeningBalances(req, res) {
    try {
        const opening = (0, cashService_1.getOpeningBalances)(database_1.default);
        const accounts = cashService_1.CASH_ACCOUNTS.map((a) => ({
            key: a.key,
            name: a.name,
            amount: opening.get(a.key) ?? 0,
        }));
        res.json({ success: true, data: { accounts } });
    }
    catch (error) {
        logger_1.default.error('Cash opening balances error:', error);
        res.status(500).json({ error: 'Failed to fetch cash opening balances' });
    }
}
/**
 * PUT /api/dashboard/cash-opening-balances
 * Save the opening (seed) balance per account — the starting cash a
 * business was founded with. Body: `{ accounts: [{ key, amount }] }`.
 */
function saveCashOpeningBalances(req, res) {
    try {
        const { accounts } = req.body;
        if (!accounts || !Array.isArray(accounts)) {
            res.status(400).json({ error: 'accounts array is required' });
            return;
        }
        const validKeys = new Set(cashService_1.CASH_ACCOUNTS.map((a) => a.key));
        for (const entry of accounts) {
            if (!validKeys.has(entry.key)) {
                res.status(400).json({ error: `Unknown account key: ${entry.key}` });
                return;
            }
            (0, cashService_1.saveOpeningBalance)(database_1.default, entry.key, Number(entry.amount) || 0);
        }
        const opening = (0, cashService_1.getOpeningBalances)(database_1.default);
        const data = cashService_1.CASH_ACCOUNTS.map((a) => ({
            key: a.key,
            name: a.name,
            amount: opening.get(a.key) ?? 0,
        }));
        res.json({ success: true, data: { accounts: data } });
    }
    catch (error) {
        logger_1.default.error('Save cash opening balances error:', error);
        res.status(500).json({ error: 'Failed to save cash opening balances' });
    }
}
// ═══════════════════════════════════════════════════════════════
//  EMPLOYEE LOANS DASHBOARD
// ═══════════════════════════════════════════════════════════════
/**
 * GET /api/dashboard/active-loans
 * Active loans across all employees with aging summary.
 */
function getActiveLoans(req, res) {
    try {
        const loans = EmployeeLoan_1.EmployeeLoanModel.getGlobalActiveLoans(database_1.default);
        const summary = EmployeeLoan_1.EmployeeLoanModel.getGlobalLoanSummary(database_1.default);
        res.json({
            success: true,
            data: {
                ...summary,
                loans,
            },
        });
    }
    catch (error) {
        logger_1.default.error('Active loans error:', error);
        res.status(500).json({ error: 'Failed to fetch active loans' });
    }
}
exports.default = {
    getSummary,
    getCashPosition,
    getExpiryAlerts,
    getCashOpeningBalances,
    saveCashOpeningBalances,
    getTopCustomers,
    getSalesSummary,
    getExpenseSummary,
    getProductionStatus,
    getStockMovementSummary,
    getKPI,
    getKPIBatch,
    getARSummary,
    getActiveLoans,
};
