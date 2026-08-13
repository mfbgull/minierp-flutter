"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const cashService_1 = require("../services/cashService");
const UserPreferences_1 = require("./UserPreferences");
const weekMath_1 = require("../utils/weekMath");
/**
 * Aggregated dashboard KPIs. `fromDate`/`toDate` (the dashboard's
 * global range picker) filter the money figures (sales, purchases,
 * profit), the sales-vs-purchases chart and recent productions; the
 * inventory snapshots (items, stock value, low stock, category split)
 * are current positions and stay unfiltered. When no range is given
 * the chart keeps its 7-day window, productions the 30-day window, and
 * the money totals stay all-time.
 */
function getSummary(db, fromDate, toDate) {
    const ranged = !!(fromDate && toDate);
    const from = fromDate || '2000-01-01';
    const to = toDate || '2099-12-31';
    const itemCount = db.prepare('SELECT COUNT(*) as count FROM items WHERE is_active = 1').get();
    // Inventory value = batch-tracked value (SUM quantity_remaining *
    // unit_cost) plus a legacy fallback for items that still carry stock
    // on `current_stock` but have no batch rows (the balance sheet and
    // stock valuation report already use this exact formula — the
    // dashboard previously only counted batches, so legacy items showed
    // as Rs 0).
    const stockValue = db.prepare(`
    SELECT COALESCE(SUM(quantity_remaining * unit_cost), 0) as total
    FROM stock_batches WHERE quantity_remaining > 0
  `).get();
    const legacyStockValue = db.prepare(`
    SELECT COALESCE(SUM(i.current_stock * i.standard_cost), 0) as total
    FROM items i
    WHERE i.is_active = 1
      AND i.current_stock > 0
      AND NOT EXISTS (
        SELECT 1 FROM stock_batches sb WHERE sb.item_id = i.id AND sb.quantity_remaining > 0
      )
  `).get();
    // Net revenue: excludes Cancelled invoices and subtracts returned
    // amounts (the P&L definition) so a returned invoice stops counting
    // — Sales − COGS = Profit stays exact.
    const salesRevenue = db.prepare(`
    SELECT COALESCE(SUM(total_amount - COALESCE(returned_amount, 0)), 0) as total
    FROM invoices
    WHERE status != 'Cancelled' AND invoice_date BETWEEN ? AND ?
  `).get(from, to);
    // Purchases live in purchase_orders (the purchase module's table) —
    // the legacy `purchases` table is empty and only kept for backward
    // compatibility. Draft/Cancelled POs are not real money spent.
    const purchaseTotal = db.prepare(`
    SELECT COALESCE(SUM(total_amount), 0) as total FROM purchase_orders
    WHERE status NOT IN ('Draft', 'Cancelled') AND po_date BETWEEN ? AND ?
  `).get(from, to);
    // COGS — SALE movements netted against their stock reversals (invoice
    // returns / deletes / updates post an ADJUSTMENT with the same cost),
    // so a returned sale no longer counts as cost of goods sold.
    const cogs = db.prepare(`
    SELECT COALESCE(ABS(SUM(sm.quantity * sm.unit_cost)), 0) as total
    FROM stock_movements sm
    WHERE sm.movement_date BETWEEN ? AND ?
      AND (
        sm.movement_type = 'SALE'
        OR (sm.movement_type = 'ADJUSTMENT'
            AND sm.reference_doctype IN ('RETURN', 'INVOICE_DELETE', 'INVOICE_UPDATE'))
      )
  `).get(from, to);
    const warehouseStocks = db.prepare(`
    SELECT COUNT(*) as count FROM stock_balances WHERE quantity > 0
  `).get();
    const lowStockItems = db.prepare(`
    SELECT id, item_code, item_name, current_stock, reorder_level, category
    FROM items
    WHERE is_active = 1 AND reorder_level > 0 AND current_stock <= reorder_level
    ORDER BY (current_stock * 1.0 / reorder_level) ASC
    LIMIT 20
  `).all();
    const stockByCategory = db.prepare(`
    SELECT category, COALESCE(SUM(current_stock), 0) as total_stock
    FROM items
    WHERE is_active = 1 AND category IS NOT NULL AND category != ''
    GROUP BY category
    ORDER BY total_stock DESC
  `).all();
    const salesByDay = (ranged
        ? db.prepare(`
        SELECT invoice_date as date, COALESCE(SUM(total_amount - COALESCE(returned_amount, 0)), 0) as total
        FROM invoices
        WHERE status != 'Cancelled' AND invoice_date BETWEEN ? AND ?
        GROUP BY invoice_date
        ORDER BY invoice_date
      `).all(from, to)
        : db.prepare(`
        SELECT invoice_date as date, COALESCE(SUM(total_amount - COALESCE(returned_amount, 0)), 0) as total
        FROM invoices
        WHERE status != 'Cancelled' AND invoice_date >= date('now', '-7 days')
        GROUP BY invoice_date
        ORDER BY invoice_date
      `).all());
    const purchasesByDay = (ranged
        ? db.prepare(`
        SELECT po_date as date, COALESCE(SUM(total_amount), 0) as total
        FROM purchase_orders
        WHERE status NOT IN ('Draft', 'Cancelled') AND po_date BETWEEN ? AND ?
        GROUP BY po_date
        ORDER BY po_date
      `).all(from, to)
        : db.prepare(`
        SELECT po_date as date, COALESCE(SUM(total_amount), 0) as total
        FROM purchase_orders
        WHERE po_date >= date('now', '-7 days')
          AND status NOT IN ('Draft', 'Cancelled')
        GROUP BY po_date
        ORDER BY po_date
      `).all());
    const productionCount = (ranged
        ? db.prepare(`
        SELECT COUNT(*) as count FROM productions
        WHERE production_date BETWEEN ? AND ?
      `).get(from, to)
        : db.prepare(`
        SELECT COUNT(*) as count FROM productions
        WHERE production_date >= date('now', '-30 days')
      `).get());
    return {
        totalItems: itemCount.count,
        totalStockValue: stockValue.total + legacyStockValue.total,
        totalSalesRevenue: salesRevenue.total,
        totalPurchases: purchaseTotal.total,
        totalProfit: salesRevenue.total - cogs.total,
        warehouseStockCount: warehouseStocks.count,
        lowStockItems,
        stockByCategory,
        salesByDay,
        purchasesByDay,
        recentProductions: productionCount.count,
    };
}
/**
 * Cash & bank position as of today — one closing balance per tracked
 * account (Cash, Bank, Easypaisa, JazzCash, UPaisa) plus the total.
 * Shared computation with the cash-reconciliation report (cashService).
 */
function getCashPosition(db) {
    const today = db.prepare(`SELECT date('now') as d`).get();
    const accounts = (0, cashService_1.getCashAccountTotals)(db, today.d).map((a) => ({
        key: a.key,
        name: a.name,
        balance: a.closing,
        opening: a.opening,
        inflow: a.inflow,
        outflow: a.outflow,
        net: a.net,
        // The individual movements behind the balance — the drill-down for
        // the dashboard card, so users can see why the position is what it is.
        transactions: (0, cashService_1.getCashAccountTransactions)(db, a.key, today.d),
    }));
    return {
        date: today.d,
        accounts,
        total: accounts.reduce((sum, a) => sum + a.balance, 0),
    };
}
// ═══════════════════════════════════════════════════════════════
//  DASHBOARD DATA ENDPOINTS
// ═══════════════════════════════════════════════════════════════
/**
 * Get top N customers by total revenue.
 */
function getTopCustomers(db, limit = 5) {
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
  `).all(limit);
}
/** SQLite's notion of today, in the wire `YYYY-MM-DD` format. */
function todayISO(db) {
    return db.prepare(`SELECT date('now') as d`).get().d;
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
function periodWhereClause(db, period, column, userId) {
    switch (period) {
        case 'today':
            return { where: `${column} = date('now')`, params: [] };
        case 'week':
            if (userId !== undefined) {
                const { from, to } = (0, weekMath_1.weekBounds)(todayISO(db), (0, UserPreferences_1.getForUser)(db, userId).weekStart);
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
function getSalesSummary(db, period = 'today', userId) {
    const { where, params } = periodWhereClause(db, period, 'invoice_date', userId);
    return db.prepare(`
    SELECT
      COALESCE(SUM(total_amount), 0) as period_total,
      COUNT(*) as count
    FROM invoices
    WHERE ${where}
      AND status != 'Cancelled'
  `).get(...params);
}
/**
 * Get expense summary for a given period.
 * period: 'week' | 'month' (week is week-start-aware per user).
 */
function getExpenseSummary(db, period = 'month', userId) {
    const { where, params } = periodWhereClause(db, period, 'expense_date', userId);
    return db.prepare(`
    SELECT
      COALESCE(SUM(amount), 0) as period_total,
      COUNT(*) as count
    FROM expenses
    WHERE ${where}
      AND status != 'Cancelled'
  `).get(...params);
}
/**
 * Get production status counts.
 * Note: The productions table may not have a native `status` column.
 * This query counts total productions and uses production_date to
 * classify "active" (last 7 days) vs "completed" (older than 7 days).
 */
function getProductionStatus(db) {
    const result = db.prepare(`
    SELECT
      COUNT(*) as total,
      COALESCE(SUM(CASE WHEN julianday('now') - julianday(production_date) <= 7 THEN 1 ELSE 0 END), 0) as active,
      COALESCE(SUM(CASE WHEN julianday('now') - julianday(production_date) > 7 THEN 1 ELSE 0 END), 0) as completed,
      0 as cancelled
    FROM productions
  `).get();
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
function getStockMovementSummary(db, days = 7) {
    const result = db.prepare(`
    SELECT
      movement_type,
      SUM(quantity) as total
    FROM stock_movements
    WHERE movement_date >= date('now', '-' || ? || ' days')
    GROUP BY movement_type
  `).all(days);
    let inbound = 0;
    let outbound = 0;
    for (const row of result) {
        if (row.total > 0) {
            inbound += row.total;
        }
        else {
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
function getKPI(db, metric) {
    switch (metric) {
        case 'inventory_turnover': {
            const purchases = db.prepare(`
        SELECT COALESCE(SUM(total_cost), 0) as total FROM purchases
        WHERE purchase_date >= date('now', '-12 months')
      `).get();
            const avgStock = db.prepare(`
        SELECT COALESCE(AVG(current_stock * standard_cost), 0) as avg_val FROM items
        WHERE is_active = 1
      `).get();
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
      `).get();
            return { metric, value: Math.round(result.avg_days * 10) / 10, unit: 'days', label: 'Avg Days to Pay' };
        }
        case 'total_active_items': {
            const result = db.prepare('SELECT COUNT(*) as count FROM items WHERE is_active = 1').get();
            return { metric, value: result.count, unit: 'count', label: 'Active Items' };
        }
        case 'stock_health': {
            const result = db.prepare(`
        SELECT
          ROUND(100.0 * SUM(CASE WHEN current_stock > reorder_level THEN 1 ELSE 0 END) /
            NULLIF(COUNT(*), 0), 1) as pct
        FROM items
        WHERE is_active = 1
      `).get();
            return { metric, value: result.pct ?? 0, unit: '%', label: 'Stock Health' };
        }
        case 'outstanding_receivables': {
            const result = db.prepare(`
        SELECT COALESCE(SUM(balance_amount), 0) as total FROM invoices
        WHERE status IN ('Unpaid', 'Partially Paid', 'Overdue')
      `).get();
            return { metric, value: result.total, unit: 'currency', label: 'Outstanding Receivables' };
        }
        case 'monthly_revenue': {
            const result = db.prepare(`
        SELECT COALESCE(SUM(total_amount), 0) as total FROM invoices
        WHERE strftime('%Y-%m', invoice_date) = strftime('%Y-%m', 'now')
          AND status != 'Cancelled'
      `).get();
            return { metric, value: result.total, unit: 'currency', label: 'Monthly Revenue' };
        }
        default:
            return { metric, value: 0, unit: '', label: 'Unknown Metric' };
    }
}
/**
 * Get aggregated AR summary with aging buckets.
 */
function getARSummary(db) {
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
  `).get();
    return result;
}
exports.default = {
    getSummary,
    getCashPosition,
    getTopCustomers,
    getSalesSummary,
    getExpenseSummary,
    getProductionStatus,
    getStockMovementSummary,
    getKPI,
    getARSummary,
};
//# sourceMappingURL=Dashboard.js.map