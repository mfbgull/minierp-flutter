"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.NET_REVENUE_STATUS = void 0;
exports.todayLocal = todayLocal;
exports.toLocalDateString = toLocalDateString;
exports.netRevenueSum = netRevenueSum;
exports.cogsCondition = cogsCondition;
exports.cogsForPeriod = cogsForPeriod;
exports.cogsUpTo = cogsUpTo;
/**
 * Local-timezone "today" as YYYY-MM-DD (report-query-integrity). This is
 * the JS counterpart of Dashboard's `date('now','localtime')` — using
 * `toISOString().split('T')[0]` instead resolves to UTC and silently
 * moves a UTC+5 user's default period end back to yesterday between
 * 00:00 and 05:00 local.
 */
function todayLocal() {
    return toLocalDateString(new Date());
}
/** Format an arbitrary Date in the server's local timezone (YYYY-MM-DD). */
function toLocalDateString(d) {
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${d.getFullYear()}-${month}-${day}`;
}
/**
 * Net-revenue aggregate for invoices: gross minus returned amounts,
 * Cancelled excluded. `alias` is the invoices table alias ('' when the
 * query reads invoices unjoined). Use inside SUM context-free:
 * `SELECT ${netRevenueSum('i')} FROM invoices i WHERE ...`.
 */
function netRevenueSum(alias = '') {
    const p = alias ? `${alias}.` : '';
    return `COALESCE(SUM(${p}total_amount - COALESCE(${p}returned_amount, 0)), 0)`;
}
/** Status predicate that pairs with netRevenueSum. */
const NET_REVENUE_STATUS = (alias = '') => `${alias ? `${alias}.` : ''}status != 'Cancelled'`;
exports.NET_REVENUE_STATUS = NET_REVENUE_STATUS;
/**
 * COGS condition over stock_movements: SALE movements plus the
 * ADJUSTMENT reversals that undo sold cost (returns / deletes / updates).
 * The legacy balance-sheet variant additionally matched 'OUT', but no
 * writer emits that type (verified against live data) and including it
 * desynchronised P&L from the balance sheet.
 */
function cogsCondition(alias = 'sm') {
    const p = alias ? `${alias}.` : '';
    return `(
    ${p}movement_type = 'SALE'
    OR (${p}movement_type = 'ADJUSTMENT'
        AND ${p}reference_doctype IN ('RETURN', 'INVOICE_DELETE', 'INVOICE_UPDATE'))
  )`;
}
function cogsAggregate(db, where, params) {
    const row = db.prepare(`
    SELECT COALESCE(ABS(SUM(sm.quantity * sm.unit_cost)), 0) as total
    FROM stock_movements sm
    WHERE ${where}
  `).get(...params);
    return row.total;
}
/** COGS for the closed period [startDate, endDate]. */
function cogsForPeriod(db, startDate, endDate) {
    return cogsAggregate(db, `sm.movement_date BETWEEN ? AND ? AND ${cogsCondition()}`, [startDate, endDate]);
}
/** Cumulative COGS up to and including asOfDate (balance-sheet YTD). */
function cogsUpTo(db, asOfDate) {
    return cogsAggregate(db, `sm.movement_date <= ? AND ${cogsCondition()}`, [asOfDate]);
}
