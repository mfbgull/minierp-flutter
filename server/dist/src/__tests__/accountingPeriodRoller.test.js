"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const accountingService_1 = __importDefault(require("../services/accountingService"));
// Test DB comes from __tests__/setup.ts via DATABASE_PATH; migrations run
// on import, seeding the current month as the only open period.
const database_1 = __importDefault(require("../config/database"));
function countPeriods(periodName) {
    return database_1.default.prepare('SELECT COUNT(*) AS c FROM accounting_periods WHERE period_name = ?').get(periodName).c;
}
describe('AccountingService.postEntry period rollover', () => {
    const SEPT = '2026-09-01';
    const SEPT_PERIOD = '2026-09';
    beforeAll(() => {
        // Deterministic baseline: exactly one open period (2026-08), none for September.
        database_1.default.exec(`DELETE FROM journal_lines`);
        database_1.default.prepare(`DELETE FROM accounting_periods WHERE period_name != '2026-08'`).run();
        database_1.default.prepare(`
      INSERT INTO accounting_periods (period_name, start_date, end_date, status)
      VALUES ('2026-08', '2026-08-01', '2026-08-31', 'open')
      ON CONFLICT(period_name) DO NOTHING
    `).run();
    });
    afterEach(() => {
        database_1.default.prepare('DELETE FROM journal_lines').run();
        database_1.default.prepare(`DELETE FROM accounting_periods WHERE period_name = ?`).run(SEPT_PERIOD);
    });
    function balancedLines() {
        return [
            { account_id: 1, debit: 100, credit: 0 },
            { account_id: 2, debit: 0, credit: 100 },
        ];
    }
    it('auto-creates the September period when only 2026-08 exists and posts successfully', () => {
        expect(countPeriods(SEPT_PERIOD)).toBe(0);
        const posted = accountingService_1.default.postEntry(database_1.default, {
            entry_date: SEPT,
            description: 'Rollover test entry',
            lines: balancedLines(),
        });
        expect(posted.journal_entry_id).toBeGreaterThan(0);
        expect(countPeriods(SEPT_PERIOD)).toBe(1);
        const sept = database_1.default.prepare(`SELECT period_name, start_date, end_date, status FROM accounting_periods WHERE period_name = ?`).get(SEPT_PERIOD);
        expect(sept.period_name).toBe('2026-09');
        expect(sept.start_date).toBe('2026-09-01');
        expect(sept.end_date).toBe('2026-09-30');
        expect(sept.status).toBe('open');
    });
    it('creates no new row when the entry date is inside an existing open period', () => {
        const before = countPeriods('2026-08');
        accountingService_1.default.postEntry(database_1.default, {
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
        expect(() => accountingService_1.default.postEntry(database_1.default, {
            entry_date: SEPT,
            description: 'Failing rollover test entry',
            lines: badLines,
        })).toThrow();
        expect(countPeriods(SEPT_PERIOD)).toBe(0);
    });
});
