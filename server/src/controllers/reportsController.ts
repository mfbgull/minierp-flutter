import { Request, Response } from 'express';
import { AuthRequest } from '../types';
import { getQueryParam } from '../utils/queryUtils';
import db from '../config/database';
import logger from '../utils/logger';
import ReportsModel from '../models/Reports';
import { todayLocal, toLocalDateString } from '../utils/reportSql';

function getARAgingReport(req: Request, res: Response): void {
  try {
    const asOfDate = (getQueryParam(req.query.asOfDate)) || todayLocal();
    res.json({ success: true, data: ReportsModel.getARAgingReport(asOfDate as string, db) });
  } catch (error) {
    logger.error('Error fetching AR aging report:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch AR aging report' });
  }
}

function getAPAgingReport(req: Request, res: Response): void {
  try {
    const asOfDate = (getQueryParam(req.query.asOfDate)) || todayLocal();
    res.json({ success: true, data: ReportsModel.getAPAgingReport(asOfDate as string, db) });
  } catch (error) {
    logger.error('Error fetching AP aging report:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch AP aging report' });
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
      const defaultFrom = toLocalDateString(defaultStart);
      const defaultTo = toLocalDateString(defaultEnd);
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
    const asOfDate = (req.query.asOfDate as string) || todayLocal();
    const summary = ReportsModel.getReceivablesSummary(db, asOfDate);
    res.json({ success: true, data: { asOfDate, ...summary } });
  } catch (error) {
    logger.error('Error fetching receivables summary:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch receivables summary' });
  }
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

function getTrialBalanceReport(req: Request, res: Response): void {
  try {
    const { asOfDate = todayLocal() } = req.query;
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
    const { asOfDate = todayLocal() } = req.query;
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
    const date = String(getQueryParam(req.query.date)) || todayLocal();
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
    const dateStr = date || todayLocal();
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

function getExpiryReport(req: Request, res: Response): void {
  try {
    const warehouseId = req.query.warehouse_id ? parseInt(String(req.query.warehouse_id), 10) : undefined;
    const thresholdDays = req.query.threshold_days ? parseInt(String(req.query.threshold_days), 10) : undefined;
    const status = req.query.status ? String(req.query.status) : undefined;
    res.json({ success: true, data: ReportsModel.getExpiryReport(db, { warehouseId, thresholdDays, status }) });
  } catch (error) {
    logger.error('Error fetching expiry report:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch expiry report' });
  }
}

export default {
  getARAgingReport, getAPAgingReport, getCustomerStatements, getTopDebtors, getDSOMetric, getReceivablesSummary,
  getProfitLossReport, getCashFlowReport,
  getTrialBalanceReport, getGeneralLedgerReport, getBalanceSheetReport,
  getIncomeStatementReport, getTaxSummaryReport, getCashReconciliation, saveCashReconciliation,
  getBatchTraceabilityReport, getExpiryReport,
};
