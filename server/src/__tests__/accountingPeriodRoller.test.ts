/**
 * Accounting period rollover regression tests (ACC-11).
 *
 * Posting must never fail because the calendar crossed into a month
 * with no pre-created accounting period. postEntry auto-creates the
 * calendar-month period inside the caller's transaction.
 */
import Database from 'better-sqlite3';
import AccountingService from '../services/accountingService';

// Test DB comes from __tests__/setup.ts via DATABASE_PATH; migrations run
// on import, seeding the current month as the only open period.
import db from '../config/database';

interface PeriodRow {
  id: number;
  period_name: string;
  start_date: string;
  end_date: string;
  status: string;
}

function countPeriods(periodName: string): number {
  return (db.prepare('SELECT COUNT(*) AS c FROM accounting_periods WHERE period_name = ?').get(periodName) as { c: number }).c;
}

describe('AccountingService.postEntry period rollover', () => {
  const SEPT = '2026-09-01';
  const SEPT_PERIOD = '2026-09';

  beforeAll(() => {
    // Deterministic baseline: exactly one open period (2026-08), none for September.
    db.exec(`DELETE FROM journal_lines`);
    db.prepare(`DELETE FROM accounting_periods WHERE period_name != '2026-08'`).run();
    db.prepare(`
      INSERT INTO accounting_periods (period_name, start_date, end_date, status)
      VALUES ('2026-08', '2026-08-01', '2026-08-31', 'open')
      ON CONFLICT(period_name) DO NOTHING
    `).run();
  });

  afterEach(() => {
    db.prepare('DELETE FROM journal_lines').run();
    db.prepare(`DELETE FROM accounting_periods WHERE period_name = ?`).run(SEPT_PERIOD);
  });

  function balancedLines() {
    return [
      { account_id: 1, debit: 100, credit: 0 },
      { account_id: 2, debit: 0, credit: 100 },
    ];
  }

  it('auto-creates the September period when only 2026-08 exists and posts successfully', () => {
    expect(countPeriods(SEPT_PERIOD)).toBe(0);

    const posted = AccountingService.postEntry(db, {
      entry_date: SEPT,
      description: 'Rollover test entry',
      lines: balancedLines(),
    });

    expect(posted.journal_entry_id).toBeGreaterThan(0);
    expect(countPeriods(SEPT_PERIOD)).toBe(1);

    const sept = db.prepare(
      `SELECT period_name, start_date, end_date, status FROM accounting_periods WHERE period_name = ?`
    ).get(SEPT_PERIOD) as PeriodRow;
    expect(sept.period_name).toBe('2026-09');
    expect(sept.start_date).toBe('2026-09-01');
    expect(sept.end_date).toBe('2026-09-30');
    expect(sept.status).toBe('open');
  });

  it('creates no new row when the entry date is inside an existing open period', () => {
    const before = countPeriods('2026-08');

    AccountingService.postEntry(db, {
      entry_date: '2026-08-15',
      description: 'In-period test entry',
      lines: balancedLines(),
    });

    expect(countPeriods('2026-08')).toBe(before);
  });

  it('rolls back an auto-created period when the posting fails after rollover', () => {
    expect(countPeriods(SEPT_PERIOD)).toBe(0);

    // Balanced lines pass validation, then the insert fails on a bogus account id.
    const badLines = [
      { account_id: 999999, debit: 50, credit: 0 },
      { account_id: 999998, debit: 0, credit: 50 },
    ];
    expect(() =>
      AccountingService.postEntry(db, {
        entry_date: SEPT,
        description: 'Failing rollover test entry',
        lines: badLines,
      })
    ).toThrow();

    expect(countPeriods(SEPT_PERIOD)).toBe(0);
  });
});
