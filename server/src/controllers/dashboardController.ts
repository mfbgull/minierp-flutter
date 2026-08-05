import { Response } from 'express';
import { AuthRequest } from '../types';
import db from '../config/database';
import logger from '../utils/logger';
import DashboardModel from '../models/Dashboard';

// ═══════════════════════════════════════════════════════════════
//  EXISTING
// ═══════════════════════════════════════════════════════════════

function getSummary(req: AuthRequest, res: Response): void {
  try {
    const data = DashboardModel.getSummary(db);
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
    const data = DashboardModel.getSalesSummary(db, period);
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
    const data = DashboardModel.getExpenseSummary(db, period);
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
    const data = DashboardModel.getKPI(db, metric);
    res.json({ success: true, data });
  } catch (error) {
    logger.error('KPI error:', error);
    res.status(500).json({ error: 'Failed to calculate KPI' });
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

export default {
  getSummary,
  getTopCustomers,
  getSalesSummary,
  getExpenseSummary,
  getProductionStatus,
  getStockMovementSummary,
  getKPI,
  getARSummary,
};
