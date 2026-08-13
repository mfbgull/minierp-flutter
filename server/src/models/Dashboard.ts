import Database from 'better-sqlite3';
import { getForUser } from './UserPreferences';
import { weekBounds } from '../utils/weekMath';

interface DashboardSummary {
  totalItems: number;
  totalStockValue: number;
  totalSalesRevenue: number;
  totalPurchases: number;
  warehouseStockCount: number;
  lowStockItems: Array<{
    id: number;
    item_code: string;
    item_name: string;
    current_stock: number;
    reorder_level: number;
    category: string;
  }>;
  stockByCategory: Array<{ category: string; total_stock: number }>;
  salesByDay: Array<{ date: string; total: number }>;
  purchasesByDay: Array<{ date: string; total: number }>;
  recentProductions: number;
}

// ============================================================
//  DASHBOARD DATA ENDPOINT RETURN TYPES
// ============================================================

interface TopCustomer {
  customer_name: string;
  total_revenue: number;
  invoice_count: number;
}

interface SalesSummaryResult {
  period_total: number;
  count: number;
}

interface ExpenseSummaryResult {
  period_total: number;
  count: number;
}

interface ProductionStatusResult {
  total: number;
  active: number;
  completed: number;
  cancelled: number;
}

interface StockMovementSummaryResult {
  inbound_qty: number;
  outbound_qty: number;
  net: number;
}

interface KPIResult {
  metric: string;
  value: number;
  unit: string;
  label: string;
}

interface ARSummaryResult {
  total_ar: number;
  current_amount: number;
  amount_1_30: number;
  amount_31_60: number;
  amount_61_90: number;
  amount_over_90: number;
  customer_count: number;
}

function getSummary(db: Database.Database): DashboardSummary {
  const itemCount = db.prepare('SELECT COUNT(*) as count FROM items WHERE is_active = 1').get() as { count: number };

  const stockValue = db.prepare(`
    SELECT COALESCE(SUM(quantity_remaining * unit_cost), 0) as total
    FROM stock_batches WHERE quantity_remaining > 0
  `).get() as { total: number };

  const salesRevenue = db.prepare(`
    SELECT COALESCE(SUM(total_amount), 0) as total FROM invoices
  `).get() as { total: number };

  const purchaseTotal = db.prepare(`
    SELECT COALESCE(SUM(total_cost), 0) as total FROM purchases
  `).get() as { total: number };

  const warehouseStocks = db.prepare(`
    SELECT COUNT(*) as count FROM stock_balances WHERE quantity > 0
  `).get() as { count: number };

  const lowStockItems = db.prepare(`
    SELECT id, item_code, item_name, current_stock, reorder_level, category
    FROM items
    WHERE is_active = 1 AND reorder_level > 0 AND current_stock <= reorder_level
    ORDER BY (current_stock * 1.0 / reorder_level) ASC
    LIMIT 20
  `).all() as DashboardSummary['lowStockItems'];

  const stockByCategory = db.prepare(`
    SELECT category, COALESCE(SUM(current_stock), 0) as total_stock
    FROM items
    WHERE is_active = 1 AND category IS NOT NULL AND category != ''
    GROUP BY category
    ORDER BY total_stock DESC
  `).all() as DashboardSummary['stockByCategory'];

  const salesByDay = db.prepare(`
    SELECT invoice_date as date, COALESCE(SUM(total_amount), 0) as total
    FROM invoices
    WHERE invoice_date >= date('now', '-7 days')
    GROUP BY invoice_date
    ORDER BY invoice_date
  `).all() as DashboardSummary['salesByDay'];

  const purchasesByDay = db.prepare(`
    SELECT purchase_date as date, COALESCE(SUM(total_cost), 0) as total
    FROM purchases
    WHERE purchase_date >= date('now', '-7 days')
    GROUP BY purchase_date
    ORDER BY purchase_date
  `).all() as DashboardSummary['purchasesByDay'];

  const productionCount = db.prepare(`
    SELECT COUNT(*) as count FROM productions
    WHERE production_date >= date('now', '-30 days')
  `).get() as { count: number };

  return {
    totalItems: itemCount.count,
    totalStockValue: stockValue.total,
    totalSalesRevenue: salesRevenue.total,
    totalPurchases: purchaseTotal.total,
    warehouseStockCount: warehouseStocks.count,
    lowStockItems,
    stockByCategory,
    salesByDay,
    purchasesByDay,
    recentProductions: productionCount.count,
  };
}

// ═══════════════════════════════════════════════════════════════
//  DASHBOARD DATA ENDPOINTS
// ═══════════════════════════════════════════════════════════════

/**
 * Get top N customers by total revenue.
 */
function getTopCustomers(db: Database.Database, limit: number = 5): TopCustomer[] {
  return db.prepare(`
    SELECT
      customer_name,
      COALESCE(SUM(total_amount), 0) as total_revenue,
      COUNT(*) as invoice_count
    FROM invoices
    WHERE status != 'Cancelled'
    GROUP BY customer_name
    ORDER BY total_revenue DESC
    LIMIT ?
  `).all(limit) as TopCustomer[];
}

/** SQLite's notion of today, in the wire `YYYY-MM-DD` format. */
function todayISO(db: Database.Database): string {
  return (db.prepare(`SELECT date('now') as d`).get() as { d: string }).d;
}

/**
 * The WHERE fragment + parameters for a period filter. `column` is the
 * date column (hard-coded by the caller — never user input). `period` is
 * `today` | `week` | `month`:
 *
 * - `today` / `month` keep their existing rolling semantics;
 * - `week` becomes a **calendar week** aligned to the user's saved
 *   week-start day when a `userId` is given (spec §6.3), falling back to
 *   the rolling 7-day window otherwise.
 */
function periodWhereClause(
  db: Database.Database,
  period: string,
  column: string,
  userId?: number,
): { where: string; params: string[] } {
  switch (period) {
    case 'today':
      return { where: `${column} = date('now')`, params: [] };
    case 'week':
      if (userId !== undefined) {
        const { from, to } = weekBounds(todayISO(db), getForUser(db, userId).weekStart);
        return { where: `${column} BETWEEN ? AND ?`, params: [from, to] };
      }
      return { where: `${column} >= date('now', '-7 days')`, params: [] };
    case 'month':
      return { where: `${column} >= date('now', '-1 month')`, params: [] };
    default:
      return { where: `${column} = date('now')`, params: [] };
  }
}

/**
 * Get sales summary for a given period.
 * period: 'today' | 'week' | 'month' (week is week-start-aware per user).
 */
function getSalesSummary(db: Database.Database, period: string = 'today', userId?: number): SalesSummaryResult {
  const { where, params } = periodWhereClause(db, period, 'invoice_date', userId);

  return db.prepare(`
    SELECT
      COALESCE(SUM(total_amount), 0) as period_total,
      COUNT(*) as count
    FROM invoices
    WHERE ${where}
      AND status != 'Cancelled'
  `).get(...params) as SalesSummaryResult;
}

/**
 * Get expense summary for a given period.
 * period: 'week' | 'month' (week is week-start-aware per user).
 */
function getExpenseSummary(db: Database.Database, period: string = 'month', userId?: number): ExpenseSummaryResult {
  const { where, params } = periodWhereClause(db, period, 'expense_date', userId);

  return db.prepare(`
    SELECT
      COALESCE(SUM(amount), 0) as period_total,
      COUNT(*) as count
    FROM expenses
    WHERE ${where}
      AND status != 'Cancelled'
  `).get(...params) as ExpenseSummaryResult;
}

/**
 * Get production status counts.
 * Note: The productions table may not have a native `status` column.
 * This query counts total productions and uses production_date to
 * classify "active" (last 7 days) vs "completed" (older than 7 days).
 */
function getProductionStatus(db: Database.Database): ProductionStatusResult {
  const result = db.prepare(`
    SELECT
      COUNT(*) as total,
      COALESCE(SUM(CASE WHEN julianday('now') - julianday(production_date) <= 7 THEN 1 ELSE 0 END), 0) as active,
      COALESCE(SUM(CASE WHEN julianday('now') - julianday(production_date) > 7 THEN 1 ELSE 0 END), 0) as completed,
      0 as cancelled
    FROM productions
  `).get() as { total: number; active: number; completed: number; cancelled: number };

  return {
    total: result.total,
    active: result.active,
    completed: result.completed,
    cancelled: result.cancelled,
  };
}

/**
 * Get stock movement summary for the last N days.
 */
function getStockMovementSummary(db: Database.Database, days: number = 7): StockMovementSummaryResult {
  const result = db.prepare(`
    SELECT
      movement_type,
      SUM(quantity) as total
    FROM stock_movements
    WHERE movement_date >= date('now', '-' || ? || ' days')
    GROUP BY movement_type
  `).all(days) as { movement_type: string; total: number }[];

  let inbound = 0;
  let outbound = 0;

  for (const row of result) {
    if (row.total > 0) {
      inbound += row.total;
    } else {
      outbound += Math.abs(row.total);
    }
  }

  return {
    inbound_qty: inbound,
    outbound_qty: outbound,
    net: inbound - outbound,
  };
}

/**
 * Calculate a KPI metric.
 * Supported metrics: inventory_turnover, avg_days_to_pay, total_active_items,
 * stock_health, outstanding_receivables, monthly_revenue
 */
function getKPI(db: Database.Database, metric: string): KPIResult {
  switch (metric) {
    case 'inventory_turnover': {
      const purchases = db.prepare(`
        SELECT COALESCE(SUM(total_cost), 0) as total FROM purchases
        WHERE purchase_date >= date('now', '-12 months')
      `).get() as { total: number };

      const avgStock = db.prepare(`
        SELECT COALESCE(AVG(current_stock * standard_cost), 0) as avg_val FROM items
        WHERE is_active = 1
      `).get() as { avg_val: number };

      const value = avgStock.avg_val > 0 ? purchases.total / avgStock.avg_val : 0;
      return { metric, value: Math.round(value * 100) / 100, unit: 'ratio', label: 'Inventory Turnover' };
    }

    case 'avg_days_to_pay': {
      const result = db.prepare(`
        SELECT
          COALESCE(AVG(julianday(
            COALESCE((SELECT MIN(payment_date) FROM payments WHERE invoice_id = invoices.id), invoice_date)
          ) - julianday(invoice_date)), 0) as avg_days
        FROM invoices
        WHERE status = 'Paid' AND paid_amount > 0
      `).get() as { avg_days: number };

      return { metric, value: Math.round(result.avg_days * 10) / 10, unit: 'days', label: 'Avg Days to Pay' };
    }

    case 'total_active_items': {
      const result = db.prepare('SELECT COUNT(*) as count FROM items WHERE is_active = 1').get() as { count: number };
      return { metric, value: result.count, unit: 'count', label: 'Active Items' };
    }

    case 'stock_health': {
      const result = db.prepare(`
        SELECT
          ROUND(100.0 * SUM(CASE WHEN current_stock > reorder_level THEN 1 ELSE 0 END) /
            NULLIF(COUNT(*), 0), 1) as pct
        FROM items
        WHERE is_active = 1
      `).get() as { pct: number | null };

      return { metric, value: result.pct ?? 0, unit: '%', label: 'Stock Health' };
    }

    case 'outstanding_receivables': {
      const result = db.prepare(`
        SELECT COALESCE(SUM(balance_amount), 0) as total FROM invoices
        WHERE status IN ('Unpaid', 'Partially Paid', 'Overdue')
      `).get() as { total: number };

      return { metric, value: result.total, unit: 'currency', label: 'Outstanding Receivables' };
    }

    case 'monthly_revenue': {
      const result = db.prepare(`
        SELECT COALESCE(SUM(total_amount), 0) as total FROM invoices
        WHERE strftime('%Y-%m', invoice_date) = strftime('%Y-%m', 'now')
          AND status != 'Cancelled'
      `).get() as { total: number };

      return { metric, value: result.total, unit: 'currency', label: 'Monthly Revenue' };
    }

    default:
      return { metric, value: 0, unit: '', label: 'Unknown Metric' };
  }
}

/**
 * Get aggregated AR summary with aging buckets.
 */
function getARSummary(db: Database.Database): ARSummaryResult {
  const result = db.prepare(`
    SELECT
      COALESCE(SUM(balance_amount), 0) as total_ar,
      COALESCE(SUM(CASE WHEN julianday('now') - julianday(due_date) <= 0 THEN balance_amount ELSE 0 END), 0) as current_amount,
      COALESCE(SUM(CASE WHEN julianday('now') - julianday(due_date) BETWEEN 1 AND 30 THEN balance_amount ELSE 0 END), 0) as amount_1_30,
      COALESCE(SUM(CASE WHEN julianday('now') - julianday(due_date) BETWEEN 31 AND 60 THEN balance_amount ELSE 0 END), 0) as amount_31_60,
      COALESCE(SUM(CASE WHEN julianday('now') - julianday(due_date) BETWEEN 61 AND 90 THEN balance_amount ELSE 0 END), 0) as amount_61_90,
      COALESCE(SUM(CASE WHEN julianday('now') - julianday(due_date) > 90 THEN balance_amount ELSE 0 END), 0) as amount_over_90,
      (SELECT COUNT(DISTINCT customer_id) FROM invoices WHERE balance_amount > 0 AND status IN ('Unpaid', 'Partially Paid', 'Overdue')) as customer_count
    FROM invoices
    WHERE balance_amount > 0
      AND status IN ('Unpaid', 'Partially Paid', 'Overdue')
  `).get() as ARSummaryResult;

  return result;
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
