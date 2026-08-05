"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
function getSummary(db) {
    const itemCount = db.prepare('SELECT COUNT(*) as count FROM items WHERE is_active = 1').get();
    const stockValue = db.prepare(`
    SELECT COALESCE(SUM(quantity_remaining * unit_cost), 0) as total
    FROM stock_batches WHERE quantity_remaining > 0
  `).get();
    const salesRevenue = db.prepare(`
    SELECT COALESCE(SUM(total_amount), 0) as total FROM invoices
  `).get();
    const purchaseTotal = db.prepare(`
    SELECT COALESCE(SUM(total_cost), 0) as total FROM purchases
  `).get();
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
    const salesByDay = db.prepare(`
    SELECT invoice_date as date, COALESCE(SUM(total_amount), 0) as total
    FROM invoices
    WHERE invoice_date >= date('now', '-7 days')
    GROUP BY invoice_date
    ORDER BY invoice_date
  `).all();
    const purchasesByDay = db.prepare(`
    SELECT purchase_date as date, COALESCE(SUM(total_cost), 0) as total
    FROM purchases
    WHERE purchase_date >= date('now', '-7 days')
    GROUP BY purchase_date
    ORDER BY purchase_date
  `).all();
    const productionCount = db.prepare(`
    SELECT COUNT(*) as count FROM productions
    WHERE production_date >= date('now', '-30 days')
  `).get();
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
/**
 * Get sales summary for a given period.
 * period: 'today' | 'week' | 'month'
 */
function getSalesSummary(db, period = 'today') {
    let dateFilter;
    switch (period) {
        case 'today':
            dateFilter = "invoice_date = date('now')";
            break;
        case 'week':
            dateFilter = "invoice_date >= date('now', '-7 days')";
            break;
        case 'month':
            dateFilter = "invoice_date >= date('now', '-1 month')";
            break;
        default:
            dateFilter = "invoice_date = date('now')";
    }
    return db.prepare(`
    SELECT
      COALESCE(SUM(total_amount), 0) as period_total,
      COUNT(*) as count
    FROM invoices
    WHERE ${dateFilter}
      AND status != 'Cancelled'
  `).get();
}
/**
 * Get expense summary for a given period.
 * period: 'week' | 'month'
 */
function getExpenseSummary(db, period = 'month') {
    let dateFilter;
    switch (period) {
        case 'week':
            dateFilter = "expense_date >= date('now', '-7 days')";
            break;
        case 'month':
            dateFilter = "expense_date >= date('now', '-1 month')";
            break;
        default:
            dateFilter = "expense_date >= date('now', '-1 month')";
    }
    return db.prepare(`
    SELECT
      COALESCE(SUM(amount), 0) as period_total,
      COUNT(*) as count
    FROM expenses
    WHERE ${dateFilter}
      AND status != 'Cancelled'
  `).get();
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
    getTopCustomers,
    getSalesSummary,
    getExpenseSummary,
    getProductionStatus,
    getStockMovementSummary,
    getKPI,
    getARSummary,
};
//# sourceMappingURL=Dashboard.js.map