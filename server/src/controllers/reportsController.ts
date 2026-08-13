import { Request, Response } from 'express';
import { AuthRequest } from '../types';
import { getQueryParam } from '../utils/queryUtils';
import db from '../config/database';
import logger from '../utils/logger';
import ReportsModel from '../models/Reports';

function getARAgingReport(req: Request, res: Response): void {
  try {
    const asOfDate = (getQueryParam(req.query.asOfDate)) || new Date().toISOString().split('T')[0];
    res.json({ success: true, data: ReportsModel.getARAgingReport(asOfDate as string, db) });
  } catch (error) {
    logger.error('Error fetching AR aging report:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch AR aging report' });
  }
}

function getCustomerStatements(req: Request, res: Response): void {
  try {
    const customerId = String(req.query.customerId || '');
    const startDate = String((getQueryParam(req.query.startDate)) ||
      (getQueryParam(req.query.fromDate)) || '');
    const endDate = String((getQueryParam(req.query.endDate)) ||
      (getQueryParam(req.query.toDate)) || '');
    const statements = ReportsModel.getCustomerStatements(
      db,
      parseInt(customerId, 10) || 0,
      startDate || undefined,
      endDate || undefined
    );
    res.json({ success: true, data: statements });
  } catch (error) {
    logger.error('Error fetching customer statements:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch customer statements' });
  }
}

function getTopDebtors(req: Request, res: Response): void {
  try {
    const { limit = 10 } = req.query;
    const asOfDate = (getQueryParam(req.query.asOfDate)) as string | undefined;
    const debtors = ReportsModel.getTopDebtors(db, parseInt(limit as string, 10), asOfDate);
    res.json({ success: true, data: debtors });
  } catch (error) {
    logger.error('Error fetching top debtors:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch top debtors' });
  }
}

function getDSOMetric(req: Request, res: Response): void {
  try {
    const fromDate = String((getQueryParam(req.query.fromDate)) || '');
    const toDate = String((getQueryParam(req.query.toDate)) || '');
    if (!fromDate || !toDate) {
      const defaultEnd = new Date();
      const defaultStart = new Date();
      defaultStart.setDate(defaultStart.getDate() - 30);
      const defaultFrom = defaultStart.toISOString().split('T')[0];
      const defaultTo = defaultEnd.toISOString().split('T')[0];
      const dsoData = ReportsModel.getDSOMetric(db, defaultFrom, defaultTo);
      res.json({ success: true, data: dsoData });
      return;
    }
    const dsoData = ReportsModel.getDSOMetric(db, fromDate, toDate);
    res.json({ success: true, data: dsoData });
  } catch (error) {
    logger.error('Error fetching DSO metric:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch DSO metric' });
  }
}

function getReceivablesSummary(req: Request, res: Response): void {
  try {
    const asOfDate = (req.query.asOfDate as string) || new Date().toISOString().split('T')[0];
    const summary = ReportsModel.getReceivablesSummary(db, asOfDate);
    res.json({ success: true, data: { asOfDate, ...summary } });
  } catch (error) {
    logger.error('Error fetching receivables summary:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch receivables summary' });
  }
}

function getSalesSummary(req: Request, res: Response): void {
  try {
    const _defaultEnd = new Date();
    const _defaultStart = new Date();
    _defaultStart.setMonth(_defaultStart.getMonth() - 1);
    const startDefault = _defaultStart.toISOString().split('T')[0];
    const endDefault = _defaultEnd.toISOString().split('T')[0];
    const startDate = String((getQueryParam(req.query.startDate)) ||
      (getQueryParam(req.query.fromDate)) || startDefault);
    const endDate = String((getQueryParam(req.query.endDate)) ||
      (getQueryParam(req.query.toDate)) || endDefault);
    const salesData = ReportsModel.getSalesSummary(db, startDate, endDate);
    res.json({ success: true, data: salesData });
  } catch (error) {
    logger.error('Error fetching sales summary:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch sales summary' });
  }
}

function getSalesByCustomer(req: Request, res: Response): void {
  try {
    const startDate = String((getQueryParam(req.query.startDate)) ||
      (getQueryParam(req.query.fromDate)) || '');
    const endDate = String((getQueryParam(req.query.endDate)) ||
      (getQueryParam(req.query.toDate)) || '');
    if (!startDate || !endDate) { res.status(400).json({ success: false, error: 'startDate and endDate are required' }); return; }
    const sales = ReportsModel.getSalesByCustomer(db, startDate as string, endDate as string);
    res.json({ success: true, data: sales });
  } catch (error) {
    logger.error('Error fetching sales by customer:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch sales by customer' });
  }
}

function getSalesByItem(req: Request, res: Response): void {
  try {
    const startDate = String((getQueryParam(req.query.startDate)) ||
      (getQueryParam(req.query.fromDate)) || '');
    const endDate = String((getQueryParam(req.query.endDate)) ||
      (getQueryParam(req.query.toDate)) || '');
    if (!startDate || !endDate) { res.status(400).json({ success: false, error: 'startDate and endDate are required' }); return; }
    const sales = ReportsModel.getSalesByItem(db, startDate as string, endDate as string);
    res.json({ success: true, data: sales });
  } catch (error) {
    logger.error('Error fetching sales by item:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch sales by item' });
  }
}

function getStockLevelReport(req: Request, res: Response): void {
  try { res.json({ success: true, data: ReportsModel.getStockLevelReport(db) }); }
  catch (error) { logger.error('Error fetching stock level report:', error); res.status(500).json({ success: false, error: 'Failed to fetch stock level report' }); }
}

function getLowStockReport(req: Request, res: Response): void {
  try { res.json({ success: true, data: ReportsModel.getLowStockReport(db) }); }
  catch (error) { logger.error('Error fetching low stock report:', error); res.status(500).json({ success: false, error: 'Failed to fetch low stock report' }); }
}

function getStockValuationReport(req: Request, res: Response): void {
  try {
    const reportData = ReportsModel.getStockValuationReport(db);
    res.json({ success: true, data: reportData });
  } catch (error) { logger.error('Error fetching stock valuation report:', error); res.status(500).json({ success: false, error: 'Failed to fetch stock valuation report' }); }
}

function getInventoryMovementReport(req: Request, res: Response): void {
  try {
    const startDate = String((getQueryParam(req.query.startDate)) ||
      (getQueryParam(req.query.fromDate)) || '');
    const endDate = String((getQueryParam(req.query.endDate)) ||
      (getQueryParam(req.query.toDate)) || '');
    const { itemId } = req.query;
    const reportData = ReportsModel.getInventoryMovementReport(db, startDate, endDate, itemId ? parseInt(itemId as string, 10) : undefined);
    res.json({ success: true, data: reportData });
  } catch (error) { logger.error('Error fetching inventory movement report:', error); res.status(500).json({ success: false, error: 'Failed to fetch inventory movement report' }); }
}

function getProfitLossReport(req: Request, res: Response): void {
  try {
    const fromDate = String((getQueryParam(req.query.fromDate)) || '');
    const toDate = String((getQueryParam(req.query.toDate)) || '');
    if (!fromDate || !toDate) { res.status(400).json({ success: false, error: 'fromDate and toDate are required' }); return; }
    res.json({ success: true, data: ReportsModel.getProfitLossReport(fromDate, toDate, db) });
  } catch (error) { logger.error('Error fetching P&L report:', error); res.status(500).json({ success: false, error: 'Failed to fetch P&L report' }); }
}

function getCashFlowReport(req: Request, res: Response): void {
  try {
    const fromDate = String((getQueryParam(req.query.fromDate)) || '');
    const toDate = String((getQueryParam(req.query.toDate)) || '');
    if (!fromDate || !toDate) { res.status(400).json({ success: false, error: 'fromDate and toDate are required' }); return; }
    res.json({ success: true, data: ReportsModel.getCashFlow(fromDate, toDate, db) });
  } catch (error) { logger.error('Error fetching cash flow report:', error); res.status(500).json({ success: false, error: 'Failed to fetch cash flow report' }); }
}

function getPurchaseSummary(req: Request, res: Response): void {
  try {
    const startDate = String((getQueryParam(req.query.startDate)) ||
      (getQueryParam(req.query.fromDate)) || '');
    const endDate = String((getQueryParam(req.query.endDate)) ||
      (getQueryParam(req.query.toDate)) || '');
    if (!startDate || !endDate) { res.status(400).json({ success: false, error: 'startDate and endDate are required' }); return; }
    res.json({ success: true, data: ReportsModel.getPurchaseSummary(startDate as string, endDate as string, db) });
  } catch (error) { logger.error('Error fetching purchase summary:', error); res.status(500).json({ success: false, error: 'Failed to fetch purchase summary' }); }
}

function getSupplierAnalysis(req: Request, res: Response): void {
  try {
    const startDate = String((getQueryParam(req.query.startDate)) ||
      (getQueryParam(req.query.fromDate)) || '');
    const endDate = String((getQueryParam(req.query.endDate)) ||
      (getQueryParam(req.query.toDate)) || '');
    if (!startDate || !endDate) { res.status(400).json({ success: false, error: 'startDate and endDate are required' }); return; }
    const analysis = ReportsModel.getSupplierAnalysis(db, startDate as string, endDate as string);
    res.json({ success: true, data: analysis });
  } catch (error) { logger.error('Error fetching supplier analysis:', error); res.status(500).json({ success: false, error: 'Failed to fetch supplier analysis' }); }
}

function getProductionSummary(req: Request, res: Response): void {
  try {
    const startDate = String((getQueryParam(req.query.startDate)) ||
      (getQueryParam(req.query.fromDate)) || '');
    const endDate = String((getQueryParam(req.query.endDate)) ||
      (getQueryParam(req.query.toDate)) || '');
    if (!startDate || !endDate) { res.status(400).json({ success: false, error: 'startDate and endDate are required' }); return; }
    res.json({ success: true, data: ReportsModel.getProductionEfficiency(startDate as string, endDate as string, db) });
  } catch (error) { logger.error('Error fetching production summary:', error); res.status(500).json({ success: false, error: 'Failed to fetch production summary' }); }
}

function getBOMUsageReport(req: Request, res: Response): void {
  try {
    const startDate = String((getQueryParam(req.query.startDate)) ||
      (getQueryParam(req.query.fromDate)) || '');
    const endDate = String((getQueryParam(req.query.endDate)) ||
      (getQueryParam(req.query.toDate)) || '');
    const itemId = req.query.itemId ? parseInt(req.query.itemId as string, 10) : null;
    res.json({ success: true, data: ReportsModel.getBOMUsageReport(startDate || '2000-01-01', endDate || '2099-12-31', itemId, db) });
  } catch (error) { logger.error('Error fetching BOM usage report:', error); res.status(500).json({ success: false, error: 'Failed to fetch BOM usage report' }); }
}

function getExpensesReport(req: Request, res: Response): void {
  try {
    const fromDate = String((getQueryParam(req.query.fromDate)) || req.query.from_date || '');
    const toDate = String((getQueryParam(req.query.toDate)) || req.query.to_date || '');
    const category = String((getQueryParam(req.query.category)) || '');
    if (!fromDate || !toDate) { res.status(400).json({ success: false, error: 'fromDate and toDate are required' }); return; }
    res.json({ success: true, data: ReportsModel.getExpenseReport(fromDate, toDate, category, db) });
  } catch (error) { logger.error('Error fetching expenses report:', error); res.status(500).json({ success: false, error: 'Failed to fetch expenses report' }); }
}

function getTrialBalanceReport(req: Request, res: Response): void {
  try {
    const { asOfDate = new Date().toISOString().split('T')[0] } = req.query;
    res.json({ success: true, data: ReportsModel.getTrialBalance(asOfDate as string, db) });
  } catch (error) { logger.error('Error fetching trial balance report:', error); res.status(500).json({ success: false, error: 'Failed to fetch trial balance report' }); }
}

function getGeneralLedgerReport(req: Request, res: Response): void {
  try {
    const { startDate, endDate } = req.query;
    if (!startDate || !endDate) { res.status(400).json({ success: false, error: 'startDate and endDate are required' }); return; }
    res.json({ success: true, data: ReportsModel.getGeneralLedger(startDate as string, endDate as string, db) });
  } catch (error) { logger.error('Error fetching general ledger report:', error); res.status(500).json({ success: false, error: 'Failed to fetch general ledger report' }); }
}

function getBalanceSheetReport(req: Request, res: Response): void {
  try {
    const { asOfDate = new Date().toISOString().split('T')[0] } = req.query;
    res.json({ success: true, data: ReportsModel.getBalanceSheet(asOfDate as string, db) });
  } catch (error) { logger.error('Error fetching balance sheet report:', error); res.status(500).json({ success: false, error: 'Failed to fetch balance sheet report' }); }
}

function getIncomeStatementReport(req: Request, res: Response): void {
  try {
    const { startDate, endDate } = req.query;
    if (!startDate || !endDate) { res.status(400).json({ success: false, error: 'startDate and endDate are required' }); return; }
    res.json({ success: true, data: ReportsModel.getIncomeStatement(startDate as string, endDate as string, db) });
  } catch (error) { logger.error('Error fetching income statement report:', error); res.status(500).json({ success: false, error: 'Failed to fetch income statement report' }); }
}

function getTaxSummaryReport(req: Request, res: Response): void {
  try {
    const { startDate, endDate } = req.query;
    if (!startDate || !endDate) { res.status(400).json({ success: false, error: 'startDate and endDate are required' }); return; }
    res.json({ success: true, data: ReportsModel.getTaxSummary(startDate as string, endDate as string, db) });
  } catch (error) { logger.error('Error fetching tax summary report:', error); res.status(500).json({ success: false, error: 'Failed to fetch tax summary report' }); }
}

function getCashReconciliation(req: AuthRequest, res: Response): void {
  try {
    const date = String(getQueryParam(req.query.date)) || new Date().toISOString().split('T')[0];
    res.json({ success: true, data: ReportsModel.getCashReconciliation(db, date) });
  } catch (error) {
    logger.error('Error fetching cash reconciliation:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch cash reconciliation' });
  }
}

function saveCashReconciliation(req: AuthRequest, res: Response): void {
  try {
    const { date, accounts } = req.body as {
      date?: string;
      accounts?: Array<{ key: string; counted_balance: number | null; notes?: string | null }>;
    };
    const dateStr = date || new Date().toISOString().split('T')[0];
    if (!accounts || !Array.isArray(accounts) || accounts.length === 0) {
      res.status(400).json({ success: false, error: 'accounts array is required' });
      return;
    }
    const data = ReportsModel.saveCashReconciliation(db, dateStr, accounts, req.user!.id);
    res.json({ success: true, message: 'Cash reconciliation saved', data });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Failed to save cash reconciliation';
    logger.error('Error saving cash reconciliation:', error);
    res.status(400).json({ success: false, error: message });
  }
}

function getBatchTraceabilityReport(req: Request, res: Response): void {
  try {
    const { itemId } = req.params;
    if (!itemId) { res.status(400).json({ success: false, error: 'itemId is required' }); return; }
    const itemIdNum = parseInt(itemId as string, 10);
    res.json({ success: true, data: ReportsModel.getBatchTraceability(db, itemIdNum) });
  } catch (error) { logger.error('Error fetching batch traceability report:', error); res.status(500).json({ success: false, error: 'Failed to fetch batch traceability report' }); }
}

export default {
  getARAgingReport, getCustomerStatements, getTopDebtors, getDSOMetric, getReceivablesSummary,
  getSalesSummary, getSalesByCustomer, getSalesByItem, getStockLevelReport, getLowStockReport,
  getStockValuationReport, getInventoryMovementReport, getProfitLossReport, getCashFlowReport,
  getPurchaseSummary, getSupplierAnalysis, getProductionSummary, getBOMUsageReport,
  getExpensesReport, getTrialBalanceReport, getGeneralLedgerReport, getBalanceSheetReport,
  getIncomeStatementReport, getTaxSummaryReport, getCashReconciliation, saveCashReconciliation,
  getBatchTraceabilityReport,
};
