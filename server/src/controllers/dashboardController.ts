import { Response } from 'express';
import { AuthRequest } from '../types';
import db from '../config/database';
import logger from '../utils/logger';
import { getQueryParam } from '../utils/queryUtils';
import DashboardModel from '../models/Dashboard';
import DashboardLayoutModel from '../models/DashboardLayout';
import { EmployeeLoanModel } from '../models/EmployeeLoan';
import ReportsModel from '../models/Reports';
import {
  CASH_ACCOUNTS,
  getOpeningBalances,
  saveOpeningBalance,
} from '../services/cashService';

// ═══════════════════════════════════════════════════════════════
//  EXISTING
// ═══════════════════════════════════════════════════════════════

function getSummary(req: AuthRequest, res: Response): void {
  try {
    const fromDate = String((req.query.fromDate as string) || (req.query.from_date as string) || '');
    const toDate = String((req.query.toDate as string) || (req.query.to_date as string) || '');
    const data = DashboardModel.getSummary(db, fromDate || undefined, toDate || undefined);
    res.json({ success: true, data });
  } catch (error) {
    logger.error('Dashboard summary error:', error);
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
function getTopCustomers(req: AuthRequest, res: Response): void {
  try {
    const limit = req.query.limit ? Number(req.query.limit) : 5;
    const data = DashboardModel.getTopCustomers(db, limit);
    res.json({ success: true, data });
  } catch (error) {
    logger.error('Top customers error:', error);
    res.status(500).json({ error: 'Failed to fetch top customers' });
  }
}

/**
 * GET /api/dashboard/sales-summary
 * Sales totals by period (today, week, month).
 */
function getSalesSummary(req: AuthRequest, res: Response): void {
  try {
    const period = (req.query.period as string) || 'today';
    // The user id makes `period=week` a calendar week aligned to the
    // user's saved week-start day (spec §6.3).
    const data = DashboardModel.getSalesSummary(db, period, req.user?.id);
    res.json({ success: true, data });
  } catch (error) {
    logger.error('Sales summary error:', error);
    res.status(500).json({ error: 'Failed to fetch sales summary' });
  }
}

/**
 * GET /api/dashboard/expense-summary
 * Expense totals by period (week, month).
 */
function getExpenseSummary(req: AuthRequest, res: Response): void {
  try {
    const period = (req.query.period as string) || 'month';
    // The user id makes `period=week` a calendar week aligned to the
    // user's saved week-start day (spec §6.3).
    const data = DashboardModel.getExpenseSummary(db, period, req.user?.id);
    res.json({ success: true, data });
  } catch (error) {
    logger.error('Expense summary error:', error);
    res.status(500).json({ error: 'Failed to fetch expense summary' });
  }
}

/**
 * GET /api/dashboard/production-status
 * Production counts (active = last 7 days, completed = older).
 */
function getProductionStatus(req: AuthRequest, res: Response): void {
  try {
    const data = DashboardModel.getProductionStatus(db);
    res.json({ success: true, data });
  } catch (error) {
    logger.error('Production status error:', error);
    res.status(500).json({ error: 'Failed to fetch production status' });
  }
}

/**
 * GET /api/dashboard/stock-movement-summary
 * Stock movement totals for the last N days.
 */
function getStockMovementSummary(req: AuthRequest, res: Response): void {
  try {
    const days = req.query.days ? Number(req.query.days) : 7;
    const data = DashboardModel.getStockMovementSummary(db, days);
    res.json({ success: true, data });
  } catch (error) {
    logger.error('Stock movement summary error:', error);
    res.status(500).json({ error: 'Failed to fetch stock movement summary' });
  }
}

/**
 * GET /api/dashboard/kpi
 * Calculate a KPI metric by name.
 */
function getKPI(req: AuthRequest, res: Response): void {
  try {
    const metric = (req.query.metric as string) || 'stock_health';
    const fromDate = String((getQueryParam(req.query.fromDate)) || '');
    const toDate = String((getQueryParam(req.query.toDate)) || '');
    const data = DashboardModel.getKPI(
      db,
      metric,
      fromDate || undefined,
      toDate || undefined,
    );
    res.json({ success: true, data });
  } catch (error) {
    logger.error('KPI error:', error);
    res.status(500).json({ error: 'Failed to calculate KPI' });
  }
}

/**
 * GET /api/dashboard/kpi-batch?metrics=a,b,c (task 8.4)
 * Multiple KPIs in one round trip. Unknown metrics return null for their key.
 */
function getKPIBatch(req: AuthRequest, res: Response): void {
  try {
    const raw = String(req.query.metrics || '');
    const metrics = raw.split(',').map(s => s.trim()).filter(Boolean).slice(0, 12);
    const fromDate = String(getQueryParam(req.query.fromDate) || '') || undefined;
    const toDate = String(getQueryParam(req.query.toDate) || '') || undefined;

    const data: Record<string, unknown> = {};
    for (const metric of metrics) {
      try {
        data[metric] = DashboardModel.getKPI(db, metric, fromDate, toDate);
      } catch {
        data[metric] = null;
      }
    }
    res.json({ success: true, data });
  } catch (error) {
    logger.error('KPI batch error:', error);
    res.status(500).json({ error: 'Failed to calculate KPIs' });
  }
}

/**
 * GET /api/dashboard/ar-summary
 * Aggregated accounts receivable summary with aging buckets.
 */
function getARSummary(req: AuthRequest, res: Response): void {
  try {
    const data = DashboardModel.getARSummary(db);
    res.json({ success: true, data });
  } catch (error) {
    logger.error('AR summary error:', error);
    res.status(500).json({ error: 'Failed to fetch AR summary' });
  }
}

/**
 * GET /api/dashboard/cash-position
 * Closing balance per cash account (Cash, Bank, Easypaisa, JazzCash,
 * UPaisa) as of today + the grand total.
 */
function getCashPosition(req: AuthRequest, res: Response): void {
  try {
    const data = DashboardModel.getCashPosition(db);
    res.json({ success: true, data });
  } catch (error) {
    logger.error('Cash position error:', error);
    res.status(500).json({ error: 'Failed to fetch cash position' });
  }
}

/**
 * GET /api/dashboard/expiry-alerts?days=30
 * Batches with stock remaining whose expiry_date falls within `days`
 * (already-expired batches sort first). Backs the dashboard expiry feed.
 */
function getExpiryAlerts(req: AuthRequest, res: Response): void {
  try {
    const days = Math.max(0, parseInt(String((req.query.days as string) ?? '30'), 10) || 30);
    res.json({ success: true, data: ReportsModel.getExpiryAlerts(db, days) });
  } catch (error) {
    logger.error('Expiry alerts error:', error);
    res.status(500).json({ error: 'Failed to fetch expiry alerts' });
  }
}

/**
 * GET /api/dashboard/boot?metrics=a,b,c&fromDate&toDate  (spec 7.1)
 * The whole dashboard's initial payload in ONE round trip: summary,
 * active layout, KPI batch, cash position, AR summary, expiry alerts
 * and top customers. Cuts the login boot from 8 parallel GETs to 1
 * (plus /auth/me + /preferences = the <= 3 boot-call criterion).
 * Field failures degrade independently: only summary/layout can 500 —
 * the KPI loop and optional blocks never throw (null / empty on error).
 */
function getBoot(req: AuthRequest, res: Response): void {
  try {
    const userId = req.user!.id;
    const fromDate = String((req.query.fromDate as string) || (req.query.from_date as string) || '') || undefined;
    const toDate = String((req.query.toDate as string) || (req.query.to_date as string) || '') || undefined;
    const rawMetrics = String(req.query.metrics || '');
    const metrics = rawMetrics.split(',').map(s => s.trim()).filter(Boolean).slice(0, 12);

    const kpis: Record<string, unknown> = {};
    for (const metric of metrics) {
      try {
        kpis[metric] = DashboardModel.getKPI(db, metric, fromDate, toDate);
      } catch {
        kpis[metric] = null;
      }
    }

    let topCustomers: unknown = [];
    try {
      topCustomers = DashboardModel.getTopCustomers(db, 5);
    } catch (error) {
      logger.error('Boot top-customers error:', error);
    }

    let expiryAlerts: unknown = [];
    try {
      expiryAlerts = ReportsModel.getExpiryAlerts(db, 30);
    } catch (error) {
      logger.error('Boot expiry-alerts error:', error);
    }

    let ar: unknown = null;
    try {
      ar = DashboardModel.getARSummary(db);
    } catch (error) {
      logger.error('Boot AR-summary error:', error);
    }

    let cash: unknown = null;
    try {
      cash = DashboardModel.getCashPosition(db);
    } catch (error) {
      logger.error('Boot cash-position error:', error);
    }

    res.json({
      success: true,
      data: {
        summary: DashboardModel.getSummary(db, fromDate, toDate),
        layout: DashboardLayoutModel.getActiveLayout(userId),
        kpis,
        cash,
        ar,
        expiryAlerts,
        topCustomers,
      },
    });
  } catch (error) {
    logger.error('Dashboard boot error:', error);
    res.status(500).json({ error: 'Failed to fetch dashboard boot data' });
  }
}

/**
 * GET /api/dashboard/cash-opening-balances
 * The per-account opening (seed) balances a new business starts with.
 */
function getCashOpeningBalances(req: AuthRequest, res: Response): void {
  try {
    const opening = getOpeningBalances(db);
    const accounts = CASH_ACCOUNTS.map((a) => ({
      key: a.key,
      name: a.name,
      amount: opening.get(a.key) ?? 0,
    }));
    res.json({ success: true, data: { accounts } });
  } catch (error) {
    logger.error('Cash opening balances error:', error);
    res.status(500).json({ error: 'Failed to fetch cash opening balances' });
  }
}

/**
 * PUT /api/dashboard/cash-opening-balances
 * Save the opening (seed) balance per account — the starting cash a
 * business was founded with. Body: `{ accounts: [{ key, amount }] }`.
 */
function saveCashOpeningBalances(req: AuthRequest, res: Response): void {
  try {
    const { accounts } = req.body as {
      accounts?: Array<{ key: string; amount: number }>;
    };
    if (!accounts || !Array.isArray(accounts)) {
      res.status(400).json({ error: 'accounts array is required' });
      return;
    }
    const validKeys = new Set(CASH_ACCOUNTS.map((a) => a.key));
    for (const entry of accounts) {
      if (!validKeys.has(entry.key)) {
        res.status(400).json({ error: `Unknown account key: ${entry.key}` });
        return;
      }
      saveOpeningBalance(db, entry.key, Number(entry.amount) || 0);
    }
    const opening = getOpeningBalances(db);
    const data = CASH_ACCOUNTS.map((a) => ({
      key: a.key,
      name: a.name,
      amount: opening.get(a.key) ?? 0,
    }));
    res.json({ success: true, data: { accounts: data } });
  } catch (error) {
    logger.error('Save cash opening balances error:', error);
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
function getActiveLoans(req: AuthRequest, res: Response): void {
  try {
    const loans = EmployeeLoanModel.getGlobalActiveLoans(db);
    const summary = EmployeeLoanModel.getGlobalLoanSummary(db);

    res.json({
      success: true,
      data: {
        ...summary,
        loans,
      },
    });
  } catch (error) {
    logger.error('Active loans error:', error);
    res.status(500).json({ error: 'Failed to fetch active loans' });
  }
}

export default {
  getBoot,
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
