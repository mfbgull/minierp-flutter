"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const queryUtils_1 = require("../utils/queryUtils");
const database_1 = __importDefault(require("../config/database"));
const logger_1 = __importDefault(require("../utils/logger"));
const Reports_1 = __importDefault(require("../models/Reports"));
const reportSql_1 = require("../utils/reportSql");
function getARAgingReport(req, res) {
    try {
        const asOfDate = ((0, queryUtils_1.getQueryParam)(req.query.asOfDate)) || (0, reportSql_1.todayLocal)();
        res.json({ success: true, data: Reports_1.default.getARAgingReport(asOfDate, database_1.default) });
    }
    catch (error) {
        logger_1.default.error('Error fetching AR aging report:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch AR aging report' });
    }
}
function getAPAgingReport(req, res) {
    try {
        const asOfDate = ((0, queryUtils_1.getQueryParam)(req.query.asOfDate)) || (0, reportSql_1.todayLocal)();
        res.json({ success: true, data: Reports_1.default.getAPAgingReport(asOfDate, database_1.default) });
    }
    catch (error) {
        logger_1.default.error('Error fetching AP aging report:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch AP aging report' });
    }
}
function getCustomerStatements(req, res) {
    try {
        const customerId = String(req.query.customerId || '');
        const startDate = String(((0, queryUtils_1.getQueryParam)(req.query.startDate)) ||
            ((0, queryUtils_1.getQueryParam)(req.query.fromDate)) || '');
        const endDate = String(((0, queryUtils_1.getQueryParam)(req.query.endDate)) ||
            ((0, queryUtils_1.getQueryParam)(req.query.toDate)) || '');
        const statements = Reports_1.default.getCustomerStatements(database_1.default, parseInt(customerId, 10) || 0, startDate || undefined, endDate || undefined);
        res.json({ success: true, data: statements });
    }
    catch (error) {
        logger_1.default.error('Error fetching customer statements:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch customer statements' });
    }
}
function getTopDebtors(req, res) {
    try {
        const { limit = 10 } = req.query;
        const asOfDate = ((0, queryUtils_1.getQueryParam)(req.query.asOfDate));
        const debtors = Reports_1.default.getTopDebtors(database_1.default, parseInt(limit, 10), asOfDate);
        res.json({ success: true, data: debtors });
    }
    catch (error) {
        logger_1.default.error('Error fetching top debtors:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch top debtors' });
    }
}
function getDSOMetric(req, res) {
    try {
        const fromDate = String(((0, queryUtils_1.getQueryParam)(req.query.fromDate)) || '');
        const toDate = String(((0, queryUtils_1.getQueryParam)(req.query.toDate)) || '');
        if (!fromDate || !toDate) {
            const defaultEnd = new Date();
            const defaultStart = new Date();
            defaultStart.setDate(defaultStart.getDate() - 30);
            const defaultFrom = (0, reportSql_1.toLocalDateString)(defaultStart);
            const defaultTo = (0, reportSql_1.toLocalDateString)(defaultEnd);
            const dsoData = Reports_1.default.getDSOMetric(database_1.default, defaultFrom, defaultTo);
            res.json({ success: true, data: dsoData });
            return;
        }
        const dsoData = Reports_1.default.getDSOMetric(database_1.default, fromDate, toDate);
        res.json({ success: true, data: dsoData });
    }
    catch (error) {
        logger_1.default.error('Error fetching DSO metric:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch DSO metric' });
    }
}
function getReceivablesSummary(req, res) {
    try {
        const asOfDate = req.query.asOfDate || (0, reportSql_1.todayLocal)();
        const summary = Reports_1.default.getReceivablesSummary(database_1.default, asOfDate);
        res.json({ success: true, data: { asOfDate, ...summary } });
    }
    catch (error) {
        logger_1.default.error('Error fetching receivables summary:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch receivables summary' });
    }
}
function getProfitLossReport(req, res) {
    try {
        const fromDate = String(((0, queryUtils_1.getQueryParam)(req.query.fromDate)) || '');
        const toDate = String(((0, queryUtils_1.getQueryParam)(req.query.toDate)) || '');
        if (!fromDate || !toDate) {
            res.status(400).json({ success: false, error: 'fromDate and toDate are required' });
            return;
        }
        res.json({ success: true, data: Reports_1.default.getProfitLossReport(fromDate, toDate, database_1.default) });
    }
    catch (error) {
        logger_1.default.error('Error fetching P&L report:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch P&L report' });
    }
}
function getCashFlowReport(req, res) {
    try {
        const fromDate = String(((0, queryUtils_1.getQueryParam)(req.query.fromDate)) || '');
        const toDate = String(((0, queryUtils_1.getQueryParam)(req.query.toDate)) || '');
        if (!fromDate || !toDate) {
            res.status(400).json({ success: false, error: 'fromDate and toDate are required' });
            return;
        }
        res.json({ success: true, data: Reports_1.default.getCashFlow(fromDate, toDate, database_1.default) });
    }
    catch (error) {
        logger_1.default.error('Error fetching cash flow report:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch cash flow report' });
    }
}
function getTrialBalanceReport(req, res) {
    try {
        const { asOfDate = (0, reportSql_1.todayLocal)() } = req.query;
        res.json({ success: true, data: Reports_1.default.getTrialBalance(asOfDate, database_1.default) });
    }
    catch (error) {
        logger_1.default.error('Error fetching trial balance report:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch trial balance report' });
    }
}
function getGeneralLedgerReport(req, res) {
    try {
        const { startDate, endDate } = req.query;
        if (!startDate || !endDate) {
            res.status(400).json({ success: false, error: 'startDate and endDate are required' });
            return;
        }
        res.json({ success: true, data: Reports_1.default.getGeneralLedger(startDate, endDate, database_1.default) });
    }
    catch (error) {
        logger_1.default.error('Error fetching general ledger report:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch general ledger report' });
    }
}
function getBalanceSheetReport(req, res) {
    try {
        const { asOfDate = (0, reportSql_1.todayLocal)() } = req.query;
        res.json({ success: true, data: Reports_1.default.getBalanceSheet(asOfDate, database_1.default) });
    }
    catch (error) {
        logger_1.default.error('Error fetching balance sheet report:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch balance sheet report' });
    }
}
function getIncomeStatementReport(req, res) {
    try {
        const { startDate, endDate } = req.query;
        if (!startDate || !endDate) {
            res.status(400).json({ success: false, error: 'startDate and endDate are required' });
            return;
        }
        res.json({ success: true, data: Reports_1.default.getIncomeStatement(startDate, endDate, database_1.default) });
    }
    catch (error) {
        logger_1.default.error('Error fetching income statement report:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch income statement report' });
    }
}
function getTaxSummaryReport(req, res) {
    try {
        const { startDate, endDate } = req.query;
        if (!startDate || !endDate) {
            res.status(400).json({ success: false, error: 'startDate and endDate are required' });
            return;
        }
        res.json({ success: true, data: Reports_1.default.getTaxSummary(startDate, endDate, database_1.default) });
    }
    catch (error) {
        logger_1.default.error('Error fetching tax summary report:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch tax summary report' });
    }
}
function getCashReconciliation(req, res) {
    try {
        const date = String((0, queryUtils_1.getQueryParam)(req.query.date)) || (0, reportSql_1.todayLocal)();
        res.json({ success: true, data: Reports_1.default.getCashReconciliation(database_1.default, date) });
    }
    catch (error) {
        logger_1.default.error('Error fetching cash reconciliation:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch cash reconciliation' });
    }
}
function saveCashReconciliation(req, res) {
    try {
        const { date, accounts } = req.body;
        const dateStr = date || (0, reportSql_1.todayLocal)();
        if (!accounts || !Array.isArray(accounts) || accounts.length === 0) {
            res.status(400).json({ success: false, error: 'accounts array is required' });
            return;
        }
        const data = Reports_1.default.saveCashReconciliation(database_1.default, dateStr, accounts, req.user.id);
        res.json({ success: true, message: 'Cash reconciliation saved', data });
    }
    catch (error) {
        const message = error instanceof Error ? error.message : 'Failed to save cash reconciliation';
        logger_1.default.error('Error saving cash reconciliation:', error);
        res.status(400).json({ success: false, error: message });
    }
}
function getBatchTraceabilityReport(req, res) {
    try {
        const { itemId } = req.params;
        if (!itemId) {
            res.status(400).json({ success: false, error: 'itemId is required' });
            return;
        }
        const itemIdNum = parseInt(itemId, 10);
        res.json({ success: true, data: Reports_1.default.getBatchTraceability(database_1.default, itemIdNum) });
    }
    catch (error) {
        logger_1.default.error('Error fetching batch traceability report:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch batch traceability report' });
    }
}
function getExpiryReport(req, res) {
    try {
        const warehouseId = req.query.warehouse_id ? parseInt(String(req.query.warehouse_id), 10) : undefined;
        const thresholdDays = req.query.threshold_days ? parseInt(String(req.query.threshold_days), 10) : undefined;
        const status = req.query.status ? String(req.query.status) : undefined;
        res.json({ success: true, data: Reports_1.default.getExpiryReport(database_1.default, { warehouseId, thresholdDays, status }) });
    }
    catch (error) {
        logger_1.default.error('Error fetching expiry report:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch expiry report' });
    }
}
exports.default = {
    getARAgingReport, getAPAgingReport, getCustomerStatements, getTopDebtors, getDSOMetric, getReceivablesSummary,
    getProfitLossReport, getCashFlowReport,
    getTrialBalanceReport, getGeneralLedgerReport, getBalanceSheetReport,
    getIncomeStatementReport, getTaxSummaryReport, getCashReconciliation, saveCashReconciliation,
    getBatchTraceabilityReport, getExpiryReport,
};
//# sourceMappingURL=reportsController.js.map