"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const queryUtils_1 = require("../utils/queryUtils");
const database_1 = __importDefault(require("../config/database"));
const logger_1 = __importDefault(require("../utils/logger"));
const Reports_1 = __importDefault(require("../models/Reports"));
function getARAgingReport(req, res) {
    try {
        const asOfDate = ((0, queryUtils_1.getQueryParam)(req.query.asOfDate)) || new Date().toISOString().split('T')[0];
        res.json({ success: true, data: Reports_1.default.getARAgingReport(asOfDate, database_1.default) });
    }
    catch (error) {
        logger_1.default.error('Error fetching AR aging report:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch AR aging report' });
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
            const defaultFrom = defaultStart.toISOString().split('T')[0];
            const defaultTo = defaultEnd.toISOString().split('T')[0];
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
        const asOfDate = req.query.asOfDate || new Date().toISOString().split('T')[0];
        const summary = Reports_1.default.getReceivablesSummary(database_1.default, asOfDate);
        res.json({ success: true, data: { asOfDate, ...summary } });
    }
    catch (error) {
        logger_1.default.error('Error fetching receivables summary:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch receivables summary' });
    }
}
function getSalesSummary(req, res) {
    try {
        const _defaultEnd = new Date();
        const _defaultStart = new Date();
        _defaultStart.setMonth(_defaultStart.getMonth() - 1);
        const startDefault = _defaultStart.toISOString().split('T')[0];
        const endDefault = _defaultEnd.toISOString().split('T')[0];
        const startDate = String(((0, queryUtils_1.getQueryParam)(req.query.startDate)) ||
            ((0, queryUtils_1.getQueryParam)(req.query.fromDate)) || startDefault);
        const endDate = String(((0, queryUtils_1.getQueryParam)(req.query.endDate)) ||
            ((0, queryUtils_1.getQueryParam)(req.query.toDate)) || endDefault);
        const salesData = Reports_1.default.getSalesSummary(database_1.default, startDate, endDate);
        res.json({ success: true, data: salesData });
    }
    catch (error) {
        logger_1.default.error('Error fetching sales summary:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch sales summary' });
    }
}
function getSalesByCustomer(req, res) {
    try {
        const startDate = String(((0, queryUtils_1.getQueryParam)(req.query.startDate)) ||
            ((0, queryUtils_1.getQueryParam)(req.query.fromDate)) || '');
        const endDate = String(((0, queryUtils_1.getQueryParam)(req.query.endDate)) ||
            ((0, queryUtils_1.getQueryParam)(req.query.toDate)) || '');
        if (!startDate || !endDate) {
            res.status(400).json({ success: false, error: 'startDate and endDate are required' });
            return;
        }
        const sales = Reports_1.default.getSalesByCustomer(database_1.default, startDate, endDate);
        res.json({ success: true, data: sales });
    }
    catch (error) {
        logger_1.default.error('Error fetching sales by customer:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch sales by customer' });
    }
}
function getSalesByItem(req, res) {
    try {
        const startDate = String(((0, queryUtils_1.getQueryParam)(req.query.startDate)) ||
            ((0, queryUtils_1.getQueryParam)(req.query.fromDate)) || '');
        const endDate = String(((0, queryUtils_1.getQueryParam)(req.query.endDate)) ||
            ((0, queryUtils_1.getQueryParam)(req.query.toDate)) || '');
        if (!startDate || !endDate) {
            res.status(400).json({ success: false, error: 'startDate and endDate are required' });
            return;
        }
        const sales = Reports_1.default.getSalesByItem(database_1.default, startDate, endDate);
        res.json({ success: true, data: sales });
    }
    catch (error) {
        logger_1.default.error('Error fetching sales by item:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch sales by item' });
    }
}
function getStockLevelReport(req, res) {
    try {
        res.json({ success: true, data: Reports_1.default.getStockLevelReport(database_1.default) });
    }
    catch (error) {
        logger_1.default.error('Error fetching stock level report:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch stock level report' });
    }
}
function getLowStockReport(req, res) {
    try {
        res.json({ success: true, data: Reports_1.default.getLowStockReport(database_1.default) });
    }
    catch (error) {
        logger_1.default.error('Error fetching low stock report:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch low stock report' });
    }
}
function getStockValuationReport(req, res) {
    try {
        const reportData = Reports_1.default.getStockValuationReport(database_1.default);
        res.json({ success: true, data: reportData });
    }
    catch (error) {
        logger_1.default.error('Error fetching stock valuation report:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch stock valuation report' });
    }
}
function getInventoryMovementReport(req, res) {
    try {
        const startDate = String(((0, queryUtils_1.getQueryParam)(req.query.startDate)) ||
            ((0, queryUtils_1.getQueryParam)(req.query.fromDate)) || '');
        const endDate = String(((0, queryUtils_1.getQueryParam)(req.query.endDate)) ||
            ((0, queryUtils_1.getQueryParam)(req.query.toDate)) || '');
        const { itemId } = req.query;
        const reportData = Reports_1.default.getInventoryMovementReport(database_1.default, startDate, endDate, itemId ? parseInt(itemId, 10) : undefined);
        res.json({ success: true, data: reportData });
    }
    catch (error) {
        logger_1.default.error('Error fetching inventory movement report:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch inventory movement report' });
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
function getPurchaseSummary(req, res) {
    try {
        const startDate = String(((0, queryUtils_1.getQueryParam)(req.query.startDate)) ||
            ((0, queryUtils_1.getQueryParam)(req.query.fromDate)) || '');
        const endDate = String(((0, queryUtils_1.getQueryParam)(req.query.endDate)) ||
            ((0, queryUtils_1.getQueryParam)(req.query.toDate)) || '');
        if (!startDate || !endDate) {
            res.status(400).json({ success: false, error: 'startDate and endDate are required' });
            return;
        }
        res.json({ success: true, data: Reports_1.default.getPurchaseSummary(startDate, endDate, database_1.default) });
    }
    catch (error) {
        logger_1.default.error('Error fetching purchase summary:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch purchase summary' });
    }
}
function getSupplierAnalysis(req, res) {
    try {
        const startDate = String(((0, queryUtils_1.getQueryParam)(req.query.startDate)) ||
            ((0, queryUtils_1.getQueryParam)(req.query.fromDate)) || '');
        const endDate = String(((0, queryUtils_1.getQueryParam)(req.query.endDate)) ||
            ((0, queryUtils_1.getQueryParam)(req.query.toDate)) || '');
        if (!startDate || !endDate) {
            res.status(400).json({ success: false, error: 'startDate and endDate are required' });
            return;
        }
        const analysis = Reports_1.default.getSupplierAnalysis(database_1.default, startDate, endDate);
        res.json({ success: true, data: analysis });
    }
    catch (error) {
        logger_1.default.error('Error fetching supplier analysis:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch supplier analysis' });
    }
}
function getProductionSummary(req, res) {
    try {
        const startDate = String(((0, queryUtils_1.getQueryParam)(req.query.startDate)) ||
            ((0, queryUtils_1.getQueryParam)(req.query.fromDate)) || '');
        const endDate = String(((0, queryUtils_1.getQueryParam)(req.query.endDate)) ||
            ((0, queryUtils_1.getQueryParam)(req.query.toDate)) || '');
        if (!startDate || !endDate) {
            res.status(400).json({ success: false, error: 'startDate and endDate are required' });
            return;
        }
        res.json({ success: true, data: Reports_1.default.getProductionEfficiency(startDate, endDate, database_1.default) });
    }
    catch (error) {
        logger_1.default.error('Error fetching production summary:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch production summary' });
    }
}
function getBOMUsageReport(req, res) {
    try {
        const startDate = String(((0, queryUtils_1.getQueryParam)(req.query.startDate)) ||
            ((0, queryUtils_1.getQueryParam)(req.query.fromDate)) || '');
        const endDate = String(((0, queryUtils_1.getQueryParam)(req.query.endDate)) ||
            ((0, queryUtils_1.getQueryParam)(req.query.toDate)) || '');
        const itemId = req.query.itemId ? parseInt(req.query.itemId, 10) : null;
        res.json({ success: true, data: Reports_1.default.getBOMUsageReport(startDate || '2000-01-01', endDate || '2099-12-31', itemId, database_1.default) });
    }
    catch (error) {
        logger_1.default.error('Error fetching BOM usage report:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch BOM usage report' });
    }
}
function getExpensesReport(req, res) {
    try {
        const fromDate = String(((0, queryUtils_1.getQueryParam)(req.query.fromDate)) || req.query.from_date || '');
        const toDate = String(((0, queryUtils_1.getQueryParam)(req.query.toDate)) || req.query.to_date || '');
        const category = String(((0, queryUtils_1.getQueryParam)(req.query.category)) || '');
        if (!fromDate || !toDate) {
            res.status(400).json({ success: false, error: 'fromDate and toDate are required' });
            return;
        }
        res.json({ success: true, data: Reports_1.default.getExpenseReport(fromDate, toDate, category, database_1.default) });
    }
    catch (error) {
        logger_1.default.error('Error fetching expenses report:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch expenses report' });
    }
}
function getTrialBalanceReport(req, res) {
    try {
        const { asOfDate = new Date().toISOString().split('T')[0] } = req.query;
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
        const { asOfDate = new Date().toISOString().split('T')[0] } = req.query;
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
exports.default = {
    getARAgingReport, getCustomerStatements, getTopDebtors, getDSOMetric, getReceivablesSummary,
    getSalesSummary, getSalesByCustomer, getSalesByItem, getStockLevelReport, getLowStockReport,
    getStockValuationReport, getInventoryMovementReport, getProfitLossReport, getCashFlowReport,
    getPurchaseSummary, getSupplierAnalysis, getProductionSummary, getBOMUsageReport,
    getExpensesReport, getTrialBalanceReport, getGeneralLedgerReport, getBalanceSheetReport,
    getIncomeStatementReport, getTaxSummaryReport, getBatchTraceabilityReport,
};
//# sourceMappingURL=reportsController.js.map