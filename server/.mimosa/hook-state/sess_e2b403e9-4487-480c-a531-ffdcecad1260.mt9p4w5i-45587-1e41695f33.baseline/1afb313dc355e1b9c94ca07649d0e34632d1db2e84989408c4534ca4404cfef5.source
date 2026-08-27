/**
 * reportSql
 * ---------
 * Single-definition money formulas for every routed report
 * (reporting-search-remediation / report-query-integrity). Before this
 * module, revenue appeared as ≥3 SQL variants with different
 * Cancelled/returns handling and COGS SQL was pasted three times with a
 * divergent `movement_type='OUT'` term that no writer ever produces.
 */
import type Database from 'better-sqlite3';

/**
 * Local-timezone "today" as YYYY-MM-DD (report-query-integrity). This is
 * the JS counterpart of Dashboard's `date('now','localtime')` — using
 * `toISOString().split('T')[0]` instead resolves to UTC and silently
 * moves a UTC+5 user's default period end back to yesterday between
 * 00:00 and 05:00 local.
 */
export function todayLocal(): string {
  return toLocalDateString(new Date());
}

/** Format an arbitrary Date in the server's local timezone (YYYY-MM-DD). */
export function toLocalDateString(d: Date): string {
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
export function netRevenueSum(alias = ''): string {
  const p = alias ? `${alias}.` : '';
  return `COALESCE(SUM(${p}total_amount - COALESCE(${p}returned_amount, 0)), 0)`;
}

/** Status predicate that pairs with netRevenueSum. */
export const NET_REVENUE_STATUS = (alias = ''): string =>
  `${alias ? `${alias}.` : ''}status != 'Cancelled'`;

/**
 * COGS condition over stock_movements: SALE movements plus the
 * ADJUSTMENT reversals that undo sold cost (returns / deletes / updates).
 * The legacy balance-sheet variant additionally matched 'OUT', but no
 * writer emits that type (verified against live data) and including it
 * desynchronised P&L from the balance sheet.
 */
export function cogsCondition(alias = 'sm'): string {
  const p = alias ? `${alias}.` : '';
  return `(
    ${p}movement_type = 'SALE'
    OR (${p}movement_type = 'ADJUSTMENT'
        AND ${p}reference_doctype IN ('RETURN', 'INVOICE_DELETE', 'INVOICE_UPDATE'))
  )`;
}

function cogsAggregate(db: Database.Database, where: string, params: string[]): number {
  const row = db.prepare(`
    SELECT COALESCE(ABS(SUM(sm.quantity * sm.unit_cost)), 0) as total
    FROM stock_movements sm
    WHERE ${where}
  `).get(...params) as { total: number };
  return row.total;
}

/** COGS for the closed period [startDate, endDate]. */
export function cogsForPeriod(db: Database.Database, startDate: string, endDate: string): number {
  return cogsAggregate(db, `sm.movement_date BETWEEN ? AND ? AND ${cogsCondition()}`, [startDate, endDate]);
}

/** Cumulative COGS up to and including asOfDate (balance-sheet YTD). */
export function cogsUpTo(db: Database.Database, asOfDate: string): number {
  return cogsAggregate(db, `sm.movement_date <= ? AND ${cogsCondition()}`, [asOfDate]);
}
