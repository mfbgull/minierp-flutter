"use strict";
/**
 * Period Model
 * ------------
 * Data access for the accounting_periods table.
 *
 * A period represents a date range during which journal entries can
 * be posted. The trial balance / balance sheet can be run for any
 * date, but actual postings to journal_lines are gated by an open
 * period covering the entry date (enforced in AccountingService.postEntry).
 *
 * Periods are immutable once closed — they cannot be reopened from
 * the API. To re-open a closed period an admin would need to flip
 * the row directly in the database.
 */
Object.defineProperty(exports, "__esModule", { value: true });
function rowToPeriod(row) {
    return row;
}
function getAll(db) {
    return db
        .prepare(`
      SELECT id, period_name, start_date, end_date, status,
             closed_at, closed_by, created_at
      FROM accounting_periods
      ORDER BY start_date DESC
    `).all().map(rowToPeriod);
}
function getById(db, id) {
    const row = db
        .prepare(`
      SELECT id, period_name, start_date, end_date, status,
             closed_at, closed_by, created_at
      FROM accounting_periods
      WHERE id = ?
    `).get(id);
    return row ? rowToPeriod(row) : undefined;
}
function getByName(db, name) {
    const row = db
        .prepare(`
      SELECT id, period_name, start_date, end_date, status,
             closed_at, closed_by, created_at
      FROM accounting_periods
      WHERE period_name = ?
    `).get(name);
    return row ? rowToPeriod(row) : undefined;
}
/**
 * The open period covering the given date (inclusive), if any.
 */
function getOpenPeriodForDate(db, isoDate) {
    const row = db
        .prepare(`
      SELECT id, period_name, start_date, end_date, status,
             closed_at, closed_by, created_at
      FROM accounting_periods
      WHERE status = 'open'
        AND start_date <= ?
        AND end_date   >= ?
      ORDER BY start_date DESC
      LIMIT 1
    `).get(isoDate, isoDate);
    return row ? rowToPeriod(row) : undefined;
}
function getCurrentOpen(db) {
    const today = new Date().toISOString().slice(0, 10);
    return getOpenPeriodForDate(db, today);
}
function openPeriod(db, args) {
    const result = db
        .prepare(`
      INSERT INTO accounting_periods (period_name, start_date, end_date, status)
      VALUES (?, ?, ?, 'open')
    `)
        .run(args.period_name, args.start_date, args.end_date);
    return getById(db, Number(result.lastInsertRowid));
}
/**
 * Idempotent close — returns the number of rows actually changed
 * (0 if the period was already closed or doesn't exist).
 */
function closePeriod(db, id, closedBy) {
    const result = db
        .prepare(`
      UPDATE accounting_periods
      SET status = 'closed',
          closed_at = CURRENT_TIMESTAMP,
          closed_by = ?
      WHERE id = ? AND status = 'open'
    `)
        .run(closedBy, id);
    return result.changes;
}
exports.default = {
    getAll,
    getById,
    getByName,
    getOpenPeriodForDate,
    getCurrentOpen,
    openPeriod,
    closePeriod,
};
