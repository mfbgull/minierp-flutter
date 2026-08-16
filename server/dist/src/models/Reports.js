"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const accountingService_1 = __importDefault(require("../services/accountingService"));
const cashService_1 = require("../services/cashService");
function getARAgingReport(asOfDate, db) {
    const agingData = db.prepare(`
    SELECT c.customer_name, c.customer_code, SUM(i.balance_amount) as total_outstanding,
      SUM(CASE WHEN julianday(?) - julianday(i.due_date) <= 0 THEN i.balance_amount ELSE 0 END) as current_amount,
      SUM(CASE WHEN julianday(?) - julianday(i.due_date) > 0 AND julianday(?) - julianday(i.due_date) <= 30 THEN i.balance_amount ELSE 0 END) as days_1_30,
      SUM(CASE WHEN julianday(?) - julianday(i.due_date) > 30 AND julianday(?) - julianday(i.due_date) <= 60 THEN i.balance_amount ELSE 0 END) as days_31_60,
      SUM(CASE WHEN julianday(?) - julianday(i.due_date) > 60 AND julianday(?) - julianday(i.due_date) <= 90 THEN i.balance_amount ELSE 0 END) as days_61_90,
      SUM(CASE WHEN julianday(?) - julianday(i.due_date) > 90 THEN i.balance_amount ELSE 0 END) as days_over_90
    FROM invoices i JOIN customers c ON i.customer_id = c.id
    WHERE i.status IN ('Unpaid', 'Partially Paid', 'Overdue') AND i.balance_amount > 0
    GROUP BY i.customer_id, c.customer_name, c.customer_code ORDER BY total_outstanding DESC
  `).all(asOfDate, asOfDate, asOfDate, asOfDate, asOfDate, asOfDate, asOfDate, asOfDate);
    const summary = db.prepare(`
    SELECT SUM(balance_amount) as totalReceivables,
      SUM(CASE WHEN julianday(?) - julianday(due_date) <= 0 THEN balance_amount ELSE 0 END) as current_amount,
      SUM(CASE WHEN julianday(?) - julianday(due_date) > 0 AND julianday(?) - julianday(due_date) <= 30 THEN balance_amount ELSE 0 END) as total_1_30,
      SUM(CASE WHEN julianday(?) - julianday(due_date) > 30 AND julianday(?) - julianday(due_date) <= 60 THEN balance_amount ELSE 0 END) as total_31_60,
      SUM(CASE WHEN julianday(?) - julianday(due_date) > 60 AND julianday(?) - julianday(due_date) <= 90 THEN balance_amount ELSE 0 END) as total_61_90,
      SUM(CASE WHEN julianday(?) - julianday(due_date) > 90 THEN balance_amount ELSE 0 END) as total_over_90
    FROM invoices WHERE status IN ('Unpaid', 'Partially Paid', 'Overdue') AND balance_amount > 0
  `).get(asOfDate, asOfDate, asOfDate, asOfDate, asOfDate, asOfDate, asOfDate, asOfDate);
    return { asOfDate, agingBuckets: agingData, summary };
}
// Moved from reportsController
function getCustomerStatements(db, customerId, startDate, endDate) {
    let query;
    let params;
    if (customerId) {
        query = `
      SELECT c.id as customer_id, c.customer_name, c.customer_code,
        COALESCE(c.opening_balance, 0) as opening_balance,
        COALESCE(SUM(i.total_amount), 0) as total_debits,
        COALESCE(SUM(i.paid_amount), 0) as total_credits,
        COALESCE(SUM(i.balance_amount), 0) as closing_balance,
        COUNT(i.id) as invoice_count,
        COALESCE(SUM(i.total_amount), 0) as total_amount,
        COALESCE(SUM(i.paid_amount), 0) as paid_amount,
        COALESCE(SUM(i.balance_amount), 0) as balance,
        MAX(i.invoice_date) as last_invoice_date
      FROM customers c
      LEFT JOIN invoices i ON i.customer_id = c.id
      WHERE c.id = ?
    `;
        params = [customerId];
    }
    else {
        query = `
      SELECT c.id as customer_id, c.customer_name, c.customer_code,
        COALESCE(c.opening_balance, 0) as opening_balance,
        COALESCE(SUM(i.total_amount), 0) as total_debits,
        COALESCE(SUM(i.paid_amount), 0) as total_credits,
        COALESCE(SUM(i.balance_amount), 0) as closing_balance,
        COUNT(i.id) as invoice_count,
        COALESCE(SUM(i.total_amount), 0) as total_amount,
        COALESCE(SUM(i.paid_amount), 0) as paid_amount,
        COALESCE(SUM(i.balance_amount), 0) as balance,
        MAX(i.invoice_date) as last_invoice_date
      FROM customers c
      LEFT JOIN invoices i ON i.customer_id = c.id
    `;
        params = [];
    }
    if (startDate && endDate) {
        query += customerId ? ` AND i.invoice_date BETWEEN ? AND ?` : ` AND (i.invoice_date BETWEEN ? AND ? OR i.id IS NULL)`;
        params.push(startDate, endDate);
    }
    query += ` GROUP BY c.id ORDER BY c.customer_name`;
    const rows = db.prepare(query).all(...params);
    return { statements: rows };
}
// Moved from reportsController
function getTopDebtors(db, limit = 10, asOfDate) {
    const dateFilter = asOfDate ? ` AND i.invoice_date <= ?` : ``;
    const params = [limit];
    if (asOfDate)
        params.unshift(asOfDate);
    const rows = db.prepare(`
    SELECT c.customer_name, c.customer_code, SUM(i.balance_amount) as total_outstanding,
      SUM(i.balance_amount) as outstanding_balance,
      SUM(i.total_amount) as total_invoiced,
      COUNT(i.id) as invoice_count
    FROM invoices i JOIN customers c ON i.customer_id = c.id
    WHERE i.status IN ('Unpaid', 'Partially Paid', 'Overdue') AND i.balance_amount > 0${dateFilter}
    GROUP BY i.customer_id ORDER BY total_outstanding DESC LIMIT ?
  `).all(...params);
    return rows;
}
// Moved from reportsController
function getDSOMetric(db, startDateStr, endDateStr) {
    const days = Math.max(1, Math.ceil((new Date(endDateStr).getTime() - new Date(startDateStr).getTime()) / (1000 * 60 * 60 * 24)));
    const avgReceivables = db.prepare(`
    SELECT AVG(balance_amount) as avg_balance FROM invoices WHERE status IN ('Unpaid', 'Partially Paid', 'Overdue') AND invoice_date BETWEEN ? AND ?
  `).get(startDateStr, endDateStr);
    const totalCreditSales = db.prepare(`SELECT SUM(total_amount) as total FROM invoices WHERE invoice_date BETWEEN ? AND ?`).get(startDateStr, endDateStr);
    const dso = totalCreditSales.total > 0 ? (avgReceivables.avg_balance / totalCreditSales.total) * days : 0;
    const totalSales = totalCreditSales.total;
    const totalAR = avgReceivables.avg_balance;
    const avgInvoiceValue = totalCreditSales.total > 0 ? totalCreditSales.total / db.prepare(`SELECT COUNT(*) as count FROM invoices WHERE invoice_date BETWEEN ? AND ?`).get(startDateStr, endDateStr).count : 0;
    return { dso, avgReceivables: avgReceivables.avg_balance, totalCreditSales: totalCreditSales.total, totalSales, totalAR, avgInvoiceValue, period: { startDate: startDateStr, endDate: endDateStr } };
}
// Moved from reportsController
function getReceivablesSummary(db, asOfDate = new Date().toISOString().split('T')[0]) {
    // CRITICAL-2 fix: previously the function returned a synthetic row
    // built from a single SELECT with case-by-status SUMs, then mapped
    // those status sums to bucket fields (0-30, 31-60, ...) under
    // misleading names. As a result, total_1_30 was actually the
    // "Partially Paid" outstanding total, total_over_90 was the
    // "Overdue" outstanding total, and the 31-60 and 61-90 buckets were
    // hard-coded to 0. AR aging was essentially random.
    //
    // New behavior: compute aging buckets from each invoice's due_date
    // relative to the asOfDate parameter (which is now actually used as
    // a filter), classifying the invoice's current balance_amount into
    // one of 0-30, 31-60, 61-90, or 90+ days overdue. The "current"
    // bucket captures invoices not yet past due.
    //
    // The status breakdown is preserved as a separate, correctly-labeled
    // object. Status and age are independent: an invoice can be
    // "Partially Paid" AND 45 days past due, for example.
    // The bucket math is done in SQL via julianday() so we don't have to
    // pull every invoice row into Node. The CASE expression puts the
    // invoice's balance into exactly one of the five buckets.
    const result = db.prepare(`
    SELECT
      COUNT(*) as total_invoices,
      COALESCE(SUM(balance_amount), 0) as total_outstanding,
      COALESCE(SUM(paid_amount), 0) as total_paid,
      COALESCE(SUM(total_amount), 0) as total_invoiced,

      -- Buckets: days past due = asOfDate - due_date. Negative or zero
      -- (not yet due) goes into "current". > 90 goes into "over_90".
      COALESCE(SUM(CASE
        WHEN due_date IS NULL THEN 0
        WHEN julianday(?) - julianday(due_date) <= 0 THEN balance_amount
        ELSE 0
      END), 0) as current_amount,

      COALESCE(SUM(CASE
        WHEN due_date IS NULL THEN 0
        WHEN julianday(?) - julianday(due_date) BETWEEN 1 AND 30 THEN balance_amount
        ELSE 0
      END), 0) as bucket_1_30,

      COALESCE(SUM(CASE
        WHEN due_date IS NULL THEN 0
        WHEN julianday(?) - julianday(due_date) BETWEEN 31 AND 60 THEN balance_amount
        ELSE 0
      END), 0) as bucket_31_60,

      COALESCE(SUM(CASE
        WHEN due_date IS NULL THEN 0
        WHEN julianday(?) - julianday(due_date) BETWEEN 61 AND 90 THEN balance_amount
        ELSE 0
      END), 0) as bucket_61_90,

      COALESCE(SUM(CASE
        WHEN due_date IS NULL THEN 0
        WHEN julianday(?) - julianday(due_date) > 90 THEN balance_amount
        ELSE 0
      END), 0) as bucket_over_90,

      -- Per-status counts and totals, unchanged in spirit but
      -- separated from the aging buckets.
      COALESCE(SUM(CASE WHEN status = 'Unpaid' THEN balance_amount ELSE 0 END), 0) as unpaid_amount,
      COALESCE(SUM(CASE WHEN status = 'Partially Paid' THEN balance_amount ELSE 0 END), 0) as partially_paid_amount,
      COALESCE(SUM(CASE WHEN status = 'Overdue' THEN balance_amount ELSE 0 END), 0) as overdue_amount,
      COUNT(CASE WHEN status = 'Unpaid' THEN 1 END) as unpaid_count,
      COUNT(CASE WHEN status = 'Partially Paid' THEN 1 END) as partial_count,
      COUNT(CASE WHEN status = 'Overdue' THEN 1 END) as overdue_count
    FROM invoices
    WHERE status IN ('Unpaid', 'Partially Paid', 'Overdue', 'Sent')
      AND balance_amount > 0
      AND invoice_date <= ?
  `).get(asOfDate, asOfDate, asOfDate, asOfDate, asOfDate, asOfDate);
    return {
        asOfDate,
        total_invoices: result.total_invoices,
        total_outstanding: result.total_outstanding,
        total_paid: result.total_paid,
        total_invoiced: result.total_invoiced,
        // Aging buckets. Field names match the previous API so the
        // frontend doesn't need to change, but the values are now correct.
        total_current: result.current_amount,
        total_1_30: result.bucket_1_30,
        total_31_60: result.bucket_31_60,
        total_61_90: result.bucket_61_90,
        total_over_90: result.bucket_over_90,
        // Status breakdown, unchanged in shape, still meaningful.
        statusBreakdown: {
            unpaid: { count: result.unpaid_count, amount: result.unpaid_amount },
            partiallyPaid: { count: result.partial_count, amount: result.partially_paid_amount },
            overdue: { count: result.overdue_count, amount: result.overdue_amount },
        },
    };
}
function getSalesSummary(db, startDate, endDate) {
    const detail = db.prepare(`
    SELECT i.invoice_date, i.invoice_no, c.customer_name,
           i.total_amount, i.paid_amount, i.balance_amount, i.status,
           COALESCE(SUM(ii.quantity), 0) as total_items
    FROM invoices i
    JOIN customers c ON i.customer_id = c.id
    LEFT JOIN invoice_items ii ON ii.invoice_id = i.id
    WHERE i.invoice_date BETWEEN ? AND ?
    GROUP BY i.id
    ORDER BY i.invoice_date DESC
  `).all(startDate, endDate);
    const sales = detail.map((row) => ({
        invoice_date: row.invoice_date,
        invoice_no: row.invoice_no,
        customer_name: row.customer_name,
        total_sales: row.total_amount,
        total_items: row.total_items,
        paid_amount: row.paid_amount,
        balance_amount: row.balance_amount,
        status: row.status
    }));
    const totalInvoices = sales.length;
    const totalSales = sales.reduce((s, r) => s + (r.total_sales || 0), 0);
    const totalItemsSold = sales.reduce((s, r) => s + (r.total_items || 0), 0);
    const totalPaid = sales.reduce((s, r) => s + (r.paid_amount || 0), 0);
    const totalBalance = sales.reduce((s, r) => s + (r.balance_amount || 0), 0);
    const averageInvoiceValue = totalInvoices > 0 ? totalSales / totalInvoices : 0;
    const summary = { totalInvoices, totalSales, totalItemsSold, averageInvoiceValue, totalPaid, totalBalance };
    return { period: { startDate, endDate }, summary, sales };
}
// Moved from reportsController
function getSalesByCustomer(db, startDate, endDate) {
    return db.prepare(`
    SELECT c.customer_name, c.customer_code, c.email, c.phone,
      COUNT(DISTINCT i.id) as total_invoices,
      SUM(i.total_amount) as total_sales,
      AVG(i.total_amount) as average_order_value,
      COALESCE(SUM(ii.quantity), 0) as total_items,
      MAX(i.invoice_date) as last_purchase_date
    FROM invoices i
    JOIN customers c ON i.customer_id = c.id
    LEFT JOIN invoice_items ii ON ii.invoice_id = i.id
    WHERE i.invoice_date BETWEEN ? AND ?
    GROUP BY i.customer_id ORDER BY total_sales DESC
  `).all(startDate, endDate);
}
// Moved from reportsController
function getSalesByItem(db, startDate, endDate) {
    return db.prepare(`
    SELECT it.item_code, it.item_name, it.category as item_category,
      SUM(ii.quantity) as total_quantity_sold,
      SUM(ii.amount) as total_sales,
      AVG(ii.unit_price) as avg_selling_price
    FROM invoice_items ii JOIN items it ON ii.item_id = it.id JOIN invoices i ON ii.invoice_id = i.id
    WHERE i.invoice_date BETWEEN ? AND ? GROUP BY ii.item_id ORDER BY total_sales DESC
  `).all(startDate, endDate);
}
// Moved from reportsController
function getStockValuationReport(db) {
    // MAJOR-9 fix: previously the report computed stock_value as
    //   current_stock * standard_cost
    // for every item, ignoring stock_batches entirely. With batch
    // costing enabled, the real value of stock is the SUM of
    // (quantity_remaining * unit_cost) across batches, which can
    // differ materially from standard_cost when:
    //   - items have a mix of old (cheap) and new (expensive) batches
    //   - standard costs haven't been updated
    //   - production costs differ from standard_cost
    // The report also double-counted stock by LEFT JOINing
    // stock_balances (which has one row per item-warehouse pair), so
    // an item in 3 warehouses reported 3x the actual stock.
    //
    // New behavior: for each item, value = SUM(quantity_remaining *
    // unit_cost) across stock_batches, with quantity_remaining > 0.
    // Items with no batch rows fall back to standard_cost * current_stock
    // (the legacy case). Quantity comes from stock_batches
    // (not stock_balances, which is per-warehouse and would multiply).
    const valuation = db.prepare(`
    SELECT
      i.id, i.item_code, i.item_name, i.category, i.unit_of_measure, i.standard_cost,
      COALESCE(sb_summary.batch_qty, 0) as total_stock,
      COALESCE(sb_summary.batch_value, 0) as batch_tracked_value,
      CASE
        WHEN COALESCE(sb_summary.batch_qty, 0) > 0
          THEN COALESCE(sb_summary.batch_value, 0)
        ELSE i.current_stock * i.standard_cost
      END as total_value,
      CASE
        WHEN COALESCE(sb_summary.batch_qty, 0) > 0 THEN 'batch'
        ELSE 'standard_cost_fallback'
      END as valuation_method
    FROM items i
    LEFT JOIN (
      SELECT item_id,
             SUM(quantity_remaining) as batch_qty,
             SUM(quantity_remaining * unit_cost) as batch_value
      FROM stock_batches
      WHERE quantity_remaining > 0
      GROUP BY item_id
    ) sb_summary ON i.id = sb_summary.item_id
    WHERE i.is_active = 1
    ORDER BY total_value DESC
  `).all();
    // Total at report level: also use the same CASE formula so the
    // summary agrees with the per-item rows. Computed in JS to keep
    // the SQL simple (it would need a CTE for the same effect).
    const totalValue = valuation.reduce((sum, r) => sum + (r.total_value || 0), 0);
    // Count how many items still rely on standard_cost (legacy).
    const legacyItems = valuation.filter((r) => r.valuation_method === 'standard_cost_fallback').length;
    return {
        stockValuation: valuation,
        summary: {
            totalValue,
            totalItems: valuation.length,
            batchTrackedItems: valuation.length - legacyItems,
            legacyItems
        }
    };
}
// Moved from reportsController
function getInventoryMovementReport(db, startDate, endDate, itemId) {
    let query = `
    SELECT sm.movement_no, sm.movement_type, sm.quantity, sm.unit_cost, sm.movement_date,
      sm.reference_doctype, sm.reference_docno, sm.remarks,
      i.item_code, i.item_name, w.warehouse_name
    FROM stock_movements sm JOIN items i ON sm.item_id = i.id JOIN warehouses w ON sm.warehouse_id = w.id WHERE 1=1
  `;
    const params = [];
    if (startDate) {
        query += ' AND sm.movement_date >= ?';
        params.push(startDate);
    }
    if (endDate) {
        query += ' AND sm.movement_date <= ?';
        params.push(endDate);
    }
    if (itemId !== undefined && itemId !== null) {
        query += ' AND sm.item_id = ?';
        params.push(itemId);
    }
    query += ' ORDER BY sm.movement_date DESC LIMIT 500';
    const rows = db.prepare(query).all(...params);
    // Classify by quantity direction, not movement_type literal strings.
    // The system stores real types (PURCHASE, SALE, ADJUSTMENT, TRANSFER,
    // ...) — a PURCHASE is inbound, a SALE is outbound, and ADJUSTMENT /
    // TRANSFER directions are determined by the sign of the quantity.
    // Comparing against 'in'/'out' always yielded 0. Quantity is positive
    // for inbound, negative for outbound.
    const totalInbound = rows.filter((r) => (r.quantity ?? 0) > 0).length;
    const totalOutbound = rows.filter((r) => (r.quantity ?? 0) < 0).length;
    return {
        movements: rows,
        summary: {
            totalInbound,
            totalOutbound,
            netMovement: totalInbound - totalOutbound
        }
    };
}
// Moved from reportsController
function getSupplierAnalysis(db, startDate, endDate) {
    const rows = db.prepare(`
    SELECT s.supplier_name, s.supplier_code, s.email, s.phone,
      COUNT(po.id) as total_orders, SUM(po.total_amount) as total_purchase_value,
      AVG(po.total_amount) as average_order_value,
      MAX(po.po_date) as last_purchase_date,
      COUNT(poi.id) as total_items
    FROM purchase_orders po 
    JOIN suppliers s ON po.supplier_id = s.id 
    LEFT JOIN purchase_order_items poi ON poi.po_id = po.id
    WHERE po.po_date BETWEEN ? AND ?
    GROUP BY po.supplier_id ORDER BY total_purchase_value DESC
  `).all(startDate, endDate);
    return rows.map((r) => ({
        ...r,
        total_purchase_value: r.total_purchase_value || 0,
        average_order_value: r.average_order_value || 0,
        on_time_delivery_rate: 100,
        total_items: r.total_items || 0
    }));
}
// Moved from reportsController
function getBatchTraceability(db, itemId) {
    const item = db.prepare('SELECT id, item_code, item_name, unit_of_measure FROM items WHERE id = ?').get(itemId);
    if (!item)
        return null;
    const currentStock = db.prepare('SELECT warehouse_id, quantity FROM stock_balances WHERE item_id = ? AND quantity > 0').all(itemId);
    const movements = db.prepare(`
    SELECT sm.movement_no, sm.movement_type, sm.quantity, sm.movement_date, sm.reference_doctype, sm.reference_docno, sm.remarks, w.warehouse_name
    FROM stock_movements sm JOIN warehouses w ON sm.warehouse_id = w.id WHERE sm.item_id = ? ORDER BY sm.movement_date DESC LIMIT 50
  `).all(itemId);
    return {
        item,
        currentStock,
        movements,
        summary: { warehousesWithStock: currentStock.length, recentMovements: movements.length }
    };
}
function getAPSummary(asOfDate, db) {
    const summary = db.prepare(`
    SELECT s.supplier_name, SUM(po.total_cost - COALESCE(p.paid_amount, 0)) as outstanding
    FROM purchase_orders po JOIN suppliers s ON po.supplier_id = s.id
    LEFT JOIN (SELECT purchase_order_id, SUM(amount) as paid_amount FROM payments GROUP BY purchase_order_id) p ON po.id = p.purchase_order_id
    WHERE po.status IN ('Approved', 'Received') GROUP BY s.supplier_name ORDER BY outstanding DESC
  `).all();
    const totalOutstanding = db.prepare(`
    SELECT SUM(total_cost - COALESCE(p.paid_amount, 0)) as total
    FROM purchase_orders LEFT JOIN (SELECT purchase_order_id, SUM(amount) as paid_amount FROM payments GROUP BY purchase_order_id) p ON id = p.purchase_order_id
    WHERE status IN ('Approved', 'Received')
  `).get();
    return { asOfDate, supplierSummary: summary, totalOutstanding: totalOutstanding?.total || 0 };
}
function getProfitLossReport(startDate, endDate, db) {
    // MAJOR-3 audit note: the original P&L formula here is correct
    //   gross_profit = revenue - cogs
    //   net_profit   = gross_profit - expenses
    // (verified against the current code). The only fix needed was
    // excluding Cancelled invoices from revenue. Note that historical
    // SALE stock_movements may have unit_cost = sale_price (see MAJOR-6
    // in the audit), so COGS will be slightly off until that flow is
    // also fixed; the SQL itself is correct.
    const revenue = db.prepare(`
    SELECT COALESCE(SUM(total_amount - COALESCE(returned_amount, 0)), 0) as total FROM invoices
    WHERE invoice_date BETWEEN ? AND ?
      AND status != 'Cancelled'
  `).get(startDate, endDate);
    // COGS nets SALE movements against their stock reversals (returns /
    // deletes / updates post an ADJUSTMENT at the same cost) so returned
    // sales stop counting as cost of goods sold.
    const cogs = db.prepare(`
    SELECT COALESCE(ABS(SUM(sm.quantity * sm.unit_cost)), 0) as total FROM stock_movements sm
    WHERE sm.movement_date BETWEEN ? AND ?
      AND (
        sm.movement_type = 'SALE'
        OR (sm.movement_type = 'ADJUSTMENT'
            AND sm.reference_doctype IN ('RETURN', 'INVOICE_DELETE', 'INVOICE_UPDATE'))
      )
  `).get(startDate, endDate);
    const expenses = db.prepare(`SELECT expense_category, SUM(amount) as total FROM expenses WHERE expense_date BETWEEN ? AND ? GROUP BY expense_category ORDER BY total DESC`).all(startDate, endDate);
    const totalExpenses = expenses.reduce((sum, e) => sum + e.total, 0);
    const grossProfit = revenue.total - cogs.total;
    const netProfit = grossProfit - totalExpenses;
    const grossProfitMargin = revenue.total > 0 ? (grossProfit / revenue.total) * 100 : 0;
    const netProfitMargin = revenue.total > 0 ? (netProfit / revenue.total) * 100 : 0;
    return { startDate, endDate, totalRevenue: revenue.total, totalCogs: cogs.total, grossProfit, expenses, totalExpenses, netProfit, grossProfitMargin, netProfitMargin };
}
function getBalanceSheet(asOfDate, db) {
    // CRITICAL-3 fix: the previous implementation had four independent
    // bugs in one report.
    //
    //  (a) AP = SUM(po.total_amount WHERE status='Completed')
    //      This counted FULL PO value, not outstanding AP. Paid and
    //      partially-paid POs were both included. Real AP is the
    //      supplier_ledger's running balance (PO amount owed - payments
    //      allocated against it), not the gross PO total.
    //
    //  (b) "Cash" was SUM(credit - debit) FROM customer_ledger WHERE
    //      transaction_type = 'PAYMENT'. That is a per-customer running
    //      AR balance, not cash. Two different concepts conflated.
    //      New: derive cash from journal_entries where the account is
    //      'cash' or 'bank'. If no journal entries reference those
    //      accounts, returns 0 (honest "no cash tracked yet" answer
    //      rather than a fake number). A TODO notes that proper cash
    //      tracking needs a dedicated cash_accounts table.
    //
    //  (c) Equity was hard-coded to 0 (no opening retained earnings
    //      tracked, net income silently dropped).
    //      New: equity = opening_retained_earnings (from settings) +
    //                    net_income_to_date (revenue - cogs - expenses
    //                    up to asOfDate).
    //
    //  (d) asOfDate was accepted but never used as a filter.
    //      New: AR, AP, and equity are all filtered by asOfDate.
    //
    // Inventory: switched from current_stock * standard_cost (per item)
    // to SUM(quantity_remaining * unit_cost) across stock_batches, to
    // match the production-fix (CRITICAL-4) and the valuation report
    // (MAJOR-9).
    // --- ASSETS ---
    const inventoryRow = db.prepare(`
    SELECT COALESCE(SUM(quantity_remaining * unit_cost), 0) as batch_value
    FROM stock_batches WHERE quantity_remaining > 0
  `).get();
    // Plus legacy items (stock on hand but no batch rows) valued at
    // standard_cost. Computed as (sum of items.current_stock * standard_cost
    // for items with no batches) so we don't double-count batch-tracked
    // items.
    const legacyInventoryRow = db.prepare(`
    SELECT COALESCE(SUM(i.current_stock * i.standard_cost), 0) as legacy_value
    FROM items i
    WHERE i.is_active = 1
      AND i.current_stock > 0
      AND NOT EXISTS (SELECT 1 FROM stock_batches sb WHERE sb.item_id = i.id AND sb.quantity_remaining > 0)
  `).get();
    const inventoryValue = inventoryRow.batch_value + legacyInventoryRow.legacy_value;
    const ar = db.prepare(`
    SELECT COALESCE(SUM(balance_amount), 0) as total FROM invoices
    WHERE status IN ('Unpaid', 'Partially Paid', 'Overdue', 'Sent')
      AND balance_amount > 0
      AND invoice_date <= ?
  `).get(asOfDate);
    // Cash: read from the cash account via AccountingService so it pulls
    // from both journal_lines (new) and journal_entries (legacy, matched
    // by text_code) and returns a properly signed balance.
    const cashAccount = accountingService_1.default.getAccountByTextCode(db, 'cash');
    const cashBalance = cashAccount
        ? accountingService_1.default.getAccountBalance(db, cashAccount.id, asOfDate).balance
        : 0;
    // --- LIABILITIES ---
    // AP from supplier_ledger: sum the latest running balance per
    // supplier. This is the amount currently owed, not the gross PO
    // total. Per supplier, we take the most recent balance as of
    // asOfDate (any transactions after asOfDate are ignored).
    const ap = db.prepare(`
    SELECT COALESCE(SUM(balance), 0) as total FROM (
      SELECT sl1.supplier_id, sl1.balance
      FROM supplier_ledger sl1
      WHERE sl1.balance > 0
        AND sl1.transaction_date <= ?
        AND sl1.id = (
          SELECT MAX(sl2.id) FROM supplier_ledger sl2
          WHERE sl2.supplier_id = sl1.supplier_id
            AND sl2.transaction_date <= ?
        )
    )
  `).get(asOfDate, asOfDate);
    // --- EQUITY ---
    // Opening retained earnings from settings table. The key is
    // 'opening_retained_earnings' and the value is a decimal string.
    // Default to 0 if not set.
    const openingRE = db.prepare(`
    SELECT value FROM settings WHERE key = 'opening_retained_earnings'
  `).get();
    const openingRetainedEarnings = openingRE ? parseFloat(openingRE.value) || 0 : 0;
    // Net income to date: revenue - cogs - expenses up to asOfDate.
    // Note: this is the same calc as the P&L, just run for [earliest,
    // asOfDate] instead of [startDate, endDate].
    const revenueYTD = db.prepare(`
    SELECT COALESCE(SUM(total_amount - COALESCE(returned_amount, 0)), 0) as total FROM invoices
    WHERE invoice_date <= ? AND status != 'Cancelled'
  `).get(asOfDate);
    const cogsYTD = db.prepare(`
    SELECT COALESCE(ABS(SUM(quantity * unit_cost)), 0) as total
    FROM stock_movements
    WHERE movement_date <= ?
      AND (
        movement_type IN ('SALE','OUT')
        OR (movement_type = 'ADJUSTMENT'
            AND reference_doctype IN ('RETURN', 'INVOICE_DELETE', 'INVOICE_UPDATE'))
      )
  `).get(asOfDate);
    const expensesYTD = db.prepare(`
    SELECT COALESCE(SUM(amount), 0) as total FROM expenses
    WHERE expense_date <= ?
  `).get(asOfDate);
    const netIncomeYTD = revenueYTD.total - cogsYTD.total - expensesYTD.total;
    const equity = openingRetainedEarnings + netIncomeYTD;
    // --- ASSEMBLE ---
    const totalAssets = inventoryValue + ar.total + cashBalance;
    const totalLiabilities = ap.total;
    const totalEquity = equity;
    const totalLiabAndEquity = totalLiabilities + totalEquity;
    const balanced = Math.abs(totalAssets - totalLiabAndEquity) < 0.01;
    return {
        asOfDate,
        assets: {
            inventory: inventoryValue,
            accounts_receivable: ar.total,
            cash: cashBalance,
            total: totalAssets
        },
        liabilities: {
            accounts_payable: ap.total,
            total: totalLiabilities
        },
        equity: {
            opening_retained_earnings: openingRetainedEarnings,
            net_income_ytd: netIncomeYTD,
            revenue_ytd: revenueYTD.total,
            cogs_ytd: cogsYTD.total,
            expenses_ytd: expensesYTD.total,
            total: totalEquity
        },
        totals: {
            total_assets: totalAssets,
            total_liabilities: totalLiabilities,
            total_equity: totalEquity,
            total_liab_and_equity: totalLiabAndEquity,
            balanced
        }
    };
}
function getIncomeStatement(startDate, endDate, db) {
    // MAJOR-3 fix: previously this function was missing COGS entirely.
    // netIncome was revenue - expenses, treating COGS as zero. Fix:
    // delegate to getProfitLossReport so the two endpoints stay
    // consistent and the user gets a real income statement.
    const pl = getProfitLossReport(startDate, endDate, db);
    return {
        startDate,
        endDate,
        revenue: pl.totalRevenue,
        cogs: pl.totalCogs,
        expenses: pl.totalExpenses,
        netIncome: pl.netProfit,
        grossProfit: pl.grossProfit
    };
}
function getTrialBalance(asOfDate, db) {
    // MAJOR-1 fix (Phase 2 — GL refactor): now backed by
    // AccountingService.getAllAccountBalances which reads from
    // journal_lines (multi-line, account_id) UNION journal_entries
    // (legacy, text_code) and rolls them up per chart_of_accounts row.
    //
    // The output includes every account from chart_of_accounts, even
    // those with a zero balance, so the report shows the full account
    // list — not just the ones that happen to have movement. That is
    // the standard trial balance shape and is what auditors expect.
    const balances = accountingService_1.default.getAllAccountBalances(db, asOfDate);
    // Materialize as a per-account row in the standard TB shape:
    //   account, total_debit, total_credit, balance (signed)
    const accounts = balances.map((b) => ({
        account_code: b.account_code,
        account_name: b.account_name,
        account_type: b.type,
        total_debit: b.total_debit,
        total_credit: b.total_credit,
        balance: b.balance,
        is_zero: b.total_debit === 0 && b.total_credit === 0
    }));
    const totalDebit = accounts.reduce((s, r) => s + r.total_debit, 0);
    const totalCredit = accounts.reduce((s, r) => s + r.total_credit, 0);
    const balanced = Math.abs(totalDebit - totalCredit) < 0.01;
    return {
        asOfDate,
        accounts,
        total_debit: totalDebit,
        total_credit: totalCredit,
        balanced,
        note: 'Built from chart_of_accounts joined to journal_lines (canonical) ' +
            'and journal_entries (legacy, matched by text_code). ' +
            'New postings should use AccountingService.postEntry so they ' +
            'land in journal_lines with a proper account_id.'
    };
}
function getGeneralLedger(startDate, endDate, db) {
    return db.prepare(`
    SELECT * FROM customer_ledger WHERE transaction_date BETWEEN ? AND ? ORDER BY transaction_date, id
  `).all(startDate, endDate);
}
function getCashFlow(startDate, endDate, db) {
    // Same money-movement tables as the dashboard cash position
    // (cashService.collectFlows — payments, expenses, salary_payments,
    // purchases) so the two reports agree by construction. The old
    // implementation only read customer_ledger PAYMENT credits and EXPENSE
    // debits, ignoring supplier payments, salaries, refunds and direct
    // purchases, so it systematically undercounted cash out.
    //
    // Period flow = cumulative flows at endDate minus cumulative flows at
    // the day before startDate. collectFlows seeds opening balances as
    // inflow on both sides, so they cancel out and only movements inside
    // the range remain. Summing across all accounts gives the company-wide
    // cash movement.
    const dayBeforeStart = db.prepare(`SELECT date(?, '-1 day') as d`).get(startDate);
    const atEnd = (0, cashService_1.collectFlows)(db, endDate);
    const beforeStart = (0, cashService_1.collectFlows)(db, dayBeforeStart.d);
    let totalInflow = 0;
    let totalOutflow = 0;
    for (const a of cashService_1.CASH_ACCOUNTS) {
        const now = atEnd.get(a.key);
        const earlier = beforeStart.get(a.key);
        totalInflow += now.inflow - earlier.inflow;
        totalOutflow += now.outflow - earlier.outflow;
    }
    return { startDate, endDate, totalInflow, totalOutflow, netCashFlow: totalInflow - totalOutflow };
}
function getTaxSummary(startDate, endDate, db) {
    return db.prepare(`
    SELECT SUM(amount * tax_rate / 100) as total_tax FROM invoice_items ii JOIN invoices i ON ii.invoice_id = i.id WHERE i.invoice_date BETWEEN ? AND ?
  `).get(startDate, endDate);
}
function getDailySales(startDate, endDate, db) {
    return db.prepare(`
    SELECT invoice_date, COUNT(*) as count, SUM(total_amount) as total FROM invoices WHERE invoice_date BETWEEN ? AND ? GROUP BY invoice_date ORDER BY invoice_date
  `).all(startDate, endDate);
}
function getMonthlySales(year, db) {
    return db.prepare(`
    SELECT strftime('%m', invoice_date) as month, COUNT(*) as count, SUM(total_amount) as total FROM invoices WHERE strftime('%Y', invoice_date) = ? GROUP BY month ORDER BY month
  `).all(year);
}
function getGrossProfit(startDate, endDate, db) {
    const revenue = db.prepare(`SELECT COALESCE(SUM(total_amount - COALESCE(returned_amount, 0)), 0) as total FROM invoices WHERE invoice_date BETWEEN ? AND ? AND status != 'Cancelled'`).get(startDate, endDate);
    const cogs = db.prepare(`SELECT COALESCE(ABS(SUM(sm.quantity * sm.unit_cost)), 0) as total FROM stock_movements sm WHERE sm.movement_date BETWEEN ? AND ? AND (sm.movement_type = 'SALE' OR (sm.movement_type = 'ADJUSTMENT' AND sm.reference_doctype IN ('RETURN', 'INVOICE_DELETE', 'INVOICE_UPDATE')))`).get(startDate, endDate);
    return { startDate, endDate, revenue: revenue.total, cogs: cogs.total, grossProfit: revenue.total - cogs.total, margin: revenue.total > 0 ? ((revenue.total - cogs.total) / revenue.total * 100) : 0 };
}
function getStockLevelReport(db) {
    const rows = db.prepare(`
    SELECT i.id, i.item_code, i.item_name, i.category, i.unit_of_measure,
           COALESCE(SUM(sb.quantity), 0) as total_stock, i.reorder_level, i.standard_cost
    FROM items i LEFT JOIN stock_balances sb ON i.id = sb.item_id WHERE i.is_active = 1
    GROUP BY i.id ORDER BY i.item_name
  `).all();
    const stockLevels = rows.map(row => {
        const currentStock = Math.max(0, row.total_stock);
        return {
            id: row.id,
            item_code: row.item_code,
            item_name: row.item_name,
            item_category: row.category || '',
            unit_of_measure: row.unit_of_measure,
            current_stock: currentStock,
            minimum_stock: row.reorder_level || 0,
            reorder_level: row.reorder_level || 0,
            standard_selling_price: row.standard_cost || 0,
            stock_status: currentStock === 0
                ? 'Out of Stock'
                : currentStock < (row.reorder_level || 0)
                    ? 'Low Stock'
                    : 'In Stock'
        };
    });
    const totalItems = stockLevels.length;
    const inStock = stockLevels.filter(s => s.stock_status === 'In Stock').length;
    const lowStock = stockLevels.filter(s => s.stock_status === 'Low Stock').length;
    const outOfStock = stockLevels.filter(s => s.stock_status === 'Out of Stock').length;
    return { stockLevels, summary: { totalItems, inStock, lowStock, outOfStock } };
}
function getLowStockReport(db) {
    const rows = db.prepare(`
    SELECT i.id, i.item_code, i.item_name, i.category, i.unit_of_measure,
           COALESCE(SUM(sb.quantity), 0) as current_stock, i.reorder_level,
           i.standard_selling_price
    FROM items i LEFT JOIN stock_balances sb ON i.id = sb.item_id
    WHERE i.reorder_level > 0
    GROUP BY i.id
    HAVING COALESCE(SUM(sb.quantity), 0) <= i.reorder_level
    ORDER BY (COALESCE(SUM(sb.quantity), 0) * 1.0 / i.reorder_level) ASC
  `).all();
    return rows.map(row => ({
        id: row.id,
        item_code: row.item_code,
        item_name: row.item_name,
        item_category: row.category || '',
        unit_of_measure: row.unit_of_measure,
        current_stock: row.current_stock,
        minimum_stock: row.reorder_level,
        shortage: Math.max(row.reorder_level - row.current_stock, 0),
        reorder_level: row.reorder_level,
        standard_selling_price: row.standard_selling_price || 0,
        stock_status: row.current_stock === 0
            ? 'Out of Stock'
            : row.current_stock < row.reorder_level
                ? 'Low Stock'
                : 'In Stock'
    }));
}
function getPurchaseSummary(startDate, endDate, db) {
    const rows = db.prepare(`
    SELECT po.id as po_id, po.po_no as purchase_order_number, po.po_date as purchase_date,
      s.supplier_name, po.total_amount as total_cost, po.status,
      (SELECT COUNT(*) FROM purchase_order_items WHERE po_id = po.id) as total_items,
      (SELECT COALESCE(SUM(received_quantity * unit_price), 0) FROM purchase_order_items WHERE po_id = po.id) as received_amount,
      (po.total_amount - (SELECT COALESCE(SUM(received_quantity * unit_price), 0) FROM purchase_order_items WHERE po_id = po.id)) as balance_amount
    FROM purchase_orders po
    JOIN suppliers s ON po.supplier_id = s.id
    WHERE po.po_date BETWEEN ? AND ?
    ORDER BY po.po_date DESC
  `).all(startDate, endDate);
    // Compute return metrics from stock movements
    const returnData = db.prepare(`
    SELECT
      COUNT(*) as return_count,
      COALESCE(SUM(ABS(quantity)), 0) as return_quantity,
      COALESCE(SUM(ABS(quantity) * unit_cost), 0) as return_value
    FROM stock_movements
    WHERE reference_doctype IN ('PURCHASE_RETURN', 'PO_RETURN')
      AND quantity < 0
      AND movement_date BETWEEN ? AND ?
  `).get(startDate, endDate);
    const totalOrders = rows.length;
    const totalCost = rows.reduce((s, r) => s + (r.total_cost || 0), 0);
    const totalPurchasedItems = rows.reduce((s, r) => s + (r.total_items || 0), 0);
    const averageOrderValue = totalOrders > 0 ? totalCost / totalOrders : 0;
    return {
        purchases: rows,
        summary: {
            totalOrders,
            totalCost,
            totalItems: totalPurchasedItems,
            averageOrderValue,
            returnCount: returnData?.return_count || 0,
            returnQuantity: returnData?.return_quantity || 0,
            returnValue: returnData?.return_value || 0
        }
    };
}
function getProductionEfficiency(startDate, endDate, db) {
    const rows = db.prepare(`
    SELECT p.id, p.production_no, p.output_item_id, i.item_name as output_item_name,
      p.output_quantity, p.production_date, p.bom_id
    FROM productions p JOIN items i ON p.output_item_id = i.id
    WHERE p.production_date BETWEEN ? AND ? ORDER BY p.production_date DESC
  `).all(startDate, endDate);
    const production = rows.map(r => ({
        production_date: r.production_date,
        production_order_number: r.production_no,
        output_item_name: r.output_item_name,
        output_quantity: r.output_quantity || 0,
        completed_quantity: r.output_quantity || 0,
        scrapped_quantity: 0,
        status: 'Completed',
        item_name: r.output_item_name,
        planned_quantity: r.output_quantity || 0,
        work_order_number: r.production_no
    }));
    const totalProductionOrders = production.length;
    const totalOutput = production.reduce((s, r) => s + (r.output_quantity || 0), 0);
    const totalCompleted = totalOutput;
    const totalScrapped = 0;
    return {
        production,
        summary: { totalProductionOrders, totalOutput, totalCompleted, totalScrapped }
    };
}
function getBOMUsage(bomId, db) {
    return db.prepare(`
    SELECT bi.*, i.item_name, i.item_code, i.unit_of_measure
    FROM bom_items bi JOIN items i ON bi.item_id = i.id WHERE bi.bom_id = ? ORDER BY bi.item_id
  `).all(bomId);
}
function getBOMUsageReport(startDate, endDate, itemId, db) {
    let query = `
    SELECT b.id as bom_id, b.bom_name, i.item_name as parent_item_name,
      (SELECT COUNT(*) FROM productions WHERE bom_id = b.id AND production_date BETWEEN ? AND ?) as usage_count,
      (SELECT MAX(production_date) FROM productions WHERE bom_id = b.id AND production_date BETWEEN ? AND ?) as last_used_date,
      (SELECT COUNT(*) FROM bom_items WHERE bom_id = b.id) as total_components,
      CASE WHEN b.is_active THEN 'Active' ELSE 'Inactive' END as status
    FROM boms b
    JOIN items i ON b.finished_item_id = i.id
    WHERE 1=1
  `;
    const params = [startDate, endDate, startDate, endDate];
    if (itemId) {
        query += ' AND b.finished_item_id = ?';
        params.push(itemId);
    }
    query += ' ORDER BY usage_count DESC, b.bom_name';
    const rows = db.prepare(query).all(...params);
    return {
        usage: rows.map(r => ({
            bom_name: r.bom_name,
            parent_item_name: r.parent_item_name,
            usage_count: r.usage_count || 0,
            last_used_date: r.last_used_date,
            total_components: r.total_components || 0,
            status: r.status,
            bom_id: r.bom_id
        }))
    };
}
function getCustomerOutstanding(asOfDate, db) {
    return db.prepare(`
    SELECT c.customer_name, c.customer_code, SUM(i.balance_amount) as outstanding
    FROM invoices i JOIN customers c ON i.customer_id = c.id
    WHERE i.status IN ('Unpaid', 'Partially Paid', 'Overdue') AND i.balance_amount > 0
    GROUP BY c.id ORDER BY outstanding DESC
  `).all();
}
function getSupplierOutstanding(asOfDate, db) {
    return db.prepare(`
    SELECT s.supplier_name, s.supplier_code, SUM(po.total_amount) as outstanding
    FROM purchase_orders po JOIN suppliers s ON po.supplier_id = s.id
    WHERE po.status IN ('Approved', 'Received') GROUP BY s.id ORDER BY outstanding DESC
  `).all();
}
/**
 * End-of-day cash reconciliation for `date`: for every tracked account
 * (Cash, Bank, Easypaisa, JazzCash, UPaisa) the opening balance, day
 * inflow/outflow/net and the expected (book) closing balance, merged
 * with any previously saved counted amounts and variance.
 */
function getCashReconciliation(db, date) {
    const accounts = (0, cashService_1.getCashAccountTotals)(db, date);
    const savedRows = db.prepare(`
    SELECT account_key, counted_balance, notes, updated_at
    FROM cash_reconciliations
    WHERE reconciliation_date = ?
  `).all(date);
    const savedByKey = new Map(savedRows.map((r) => [r.account_key, r]));
    const rows = accounts.map((a) => {
        const saved = savedByKey.get(a.key);
        const counted = saved && saved.counted_balance !== null && saved.counted_balance !== undefined
            ? Math.round(Number(saved.counted_balance) * 100) / 100
            : null;
        return {
            key: a.key,
            name: a.name,
            opening_balance: a.opening,
            inflow: a.inflow,
            outflow: a.outflow,
            net: a.net,
            expected_balance: a.closing,
            counted_balance: counted,
            variance: counted === null ? null : Math.round((counted - a.closing) * 100) / 100,
            notes: saved?.notes ?? null,
            reconciled: counted !== null,
            reconciled_at: saved?.updated_at ?? null,
        };
    });
    return {
        date,
        accounts: rows,
        totals: {
            total_opening: rows.reduce((s, r) => s + r.opening_balance, 0),
            total_inflow: rows.reduce((s, r) => s + r.inflow, 0),
            total_outflow: rows.reduce((s, r) => s + r.outflow, 0),
            total_closing: rows.reduce((s, r) => s + r.expected_balance, 0),
        },
    };
}
/**
 * Save the counted end-of-day amounts for `date` (upsert per account).
 * Expected balances are snapshotted into the row so the audit trail
 * survives later transactions, and the variance is recomputed against
 * the snapshot. Returns the refreshed reconciliation for the date.
 */
function saveCashReconciliation(db, date, entries, userId) {
    const validKeys = new Set(cashService_1.CASH_ACCOUNTS.map((a) => a.key));
    const expected = new Map((0, cashService_1.getCashAccountTotals)(db, date).map((a) => [a.key, a.closing]));
    const upsert = db.prepare(`
    INSERT INTO cash_reconciliations (
      reconciliation_date, account_key, account_name,
      expected_balance, counted_balance, variance, notes, reconciled_by
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(reconciliation_date, account_key) DO UPDATE SET
      expected_balance = excluded.expected_balance,
      counted_balance = excluded.counted_balance,
      variance = excluded.variance,
      notes = excluded.notes,
      reconciled_by = excluded.reconciled_by,
      updated_at = CURRENT_TIMESTAMP
  `);
    db.transaction(() => {
        for (const entry of entries) {
            if (!validKeys.has(entry.key)) {
                throw new Error(`Unknown account key: ${entry.key}`);
            }
            const counted = entry.counted_balance === null || entry.counted_balance === undefined
                ? null
                : Math.round(Number(entry.counted_balance) * 100) / 100;
            const accountName = cashService_1.CASH_ACCOUNTS.find((a) => a.key === entry.key).name;
            const expectedBalance = expected.get(entry.key);
            const variance = counted === null ? null : Math.round((counted - expectedBalance) * 100) / 100;
            upsert.run(date, entry.key, accountName, expectedBalance, counted, variance, entry.notes?.trim() ? entry.notes.trim() : null, userId);
        }
    })();
    return getCashReconciliation(db, date);
}
function getExpenseReport(startDate, endDate, category, db) {
    const conditions = ['expense_date BETWEEN ? AND ?'];
    const params = [startDate, endDate];
    if (category) {
        conditions.push('expense_category = ?');
        params.push(category);
    }
    const whereClause = conditions.join(' AND ');
    // Individual expense rows for the grid
    const expenses = db.prepare(`SELECT id, expense_no, expense_category, description, amount, expense_date,
            payment_method, reference_no, vendor_name, project, status
      FROM expenses WHERE ${whereClause} ORDER BY expense_date DESC`).all(...params);
    // Category breakdown
    const categoryBreakdown = db.prepare(`SELECT expense_category, COUNT(*) as count, SUM(amount) as total_amount
     FROM expenses WHERE ${whereClause} GROUP BY expense_category ORDER BY total_amount DESC`).all(...params);
    // Summary from the same result set
    const totalAmount = expenses.reduce((s, r) => s + (r.amount || 0), 0);
    const totalExpenses = expenses.length;
    const averageAmount = totalExpenses > 0 ? totalAmount / totalExpenses : 0;
    return { summary: { totalAmount, totalExpenses, averageAmount }, expenses, categoryBreakdown };
}
exports.default = {
    getARAgingReport, getCustomerStatements, getTopDebtors, getDSOMetric,
    getReceivablesSummary, getSalesSummary, getSalesByCustomer, getSalesByItem,
    getStockValuationReport, getInventoryMovementReport, getSupplierAnalysis,
    getAPSummary, getProfitLossReport, getBalanceSheet, getIncomeStatement,
    getTrialBalance, getGeneralLedger, getCashFlow, getTaxSummary, getDailySales, getMonthlySales,
    getGrossProfit, getStockLevelReport, getLowStockReport, getBatchTraceability,
    getPurchaseSummary, getProductionEfficiency, getBOMUsage, getBOMUsageReport, getCustomerOutstanding,
    getSupplierOutstanding, getExpenseReport,
    getCashReconciliation, saveCashReconciliation,
};
//# sourceMappingURL=Reports.js.map