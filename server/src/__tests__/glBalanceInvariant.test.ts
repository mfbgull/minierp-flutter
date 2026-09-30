import db from '../config/database';
import AccountingService, { type PostEntryInput } from '../services/accountingService';
import { roundCurrency, toMinorUnits } from '../utils/currency';

/**
 * The GL balance invariant is total debits === total credits, exactly.
 *
 * It used to be `Math.abs(totalDebit - totalCredit) > 0.01`, which let a
 * genuinely unbalanced entry through whenever the drift was 0.01 or less,
 * and let unrounded sub-paisa amounts reach journal_lines. The check now
 * compares integer minor units, so it admits no epsilon.
 */
describe('GL balance invariant (audit-3 task 01)', () => {
  function accountId(code: string): number {
    const row = db.prepare('SELECT id FROM chart_of_accounts WHERE code = ?').get(code) as
      | { id: number }
      | undefined;
    if (!row) throw new Error(`chart of accounts is missing ${code}`);
    return row.id;
  }

  const cash = () => accountId('1000');
  const revenue = () => accountId('4000');

  function entry(debits: number[], credits: number[], date = '2026-06-15'): PostEntryInput {
    const lines = [
      ...debits.map((amount, i) => ({
        account_id: cash(),
        debit: amount,
        credit: 0,
        description: `dr ${i}`,
      })),
      ...credits.map((amount, i) => ({
        account_id: revenue(),
        debit: 0,
        credit: amount,
        description: `cr ${i}`,
      })),
    ];
    return { entry_date: date, description: 'balance invariant probe', lines };
  }

  function storedTotals(entryId: number): { debit: number; credit: number } {
    const row = db.prepare(`
      SELECT COALESCE(SUM(debit), 0) AS debit, COALESCE(SUM(credit), 0) AS credit
      FROM journal_lines WHERE journal_entry_id = ?
    `).get(entryId) as { debit: number; credit: number };
    return { debit: Number(row.debit), credit: Number(row.credit) };
  }

  describe('rejects imbalances', () => {
    it('rejects a one-paisa imbalance that the old 0.01 tolerance admitted', () => {
      expect(() => AccountingService.postEntry(db, entry([100.0], [100.01])))
        .toThrow(/Unbalanced journal entry/);
    });

    it('rejects a sub-paisa float-summation gap once lines are normalized', () => {
      // 10.005 and 10.005 normalize to 10.01 each; the 20.01 credit no
      // longer matches, and the entry must be refused rather than posted.
      expect(() => AccountingService.postEntry(db, entry([10.005, 10.005], [20.01])))
        .toThrow(/Unbalanced journal entry/);
    });

    it('rejects a large imbalance', () => {
      expect(() => AccountingService.postEntry(db, entry([100], [250])))
        .toThrow(/Unbalanced journal entry/);
    });

    it('rejects an entry that does not balance after minor-unit rounding', () => {
      // 33.333 rounds down to 33.33, so the pair foots to 66.66 and the
      // 66.67 credit no longer matches. Refusing is correct: silently
      // posting a 0.01 gap is exactly what the old tolerance permitted.
      expect(() => AccountingService.postEntry(db, entry([33.333, 33.333], [66.67])))
        .toThrow(/Unbalanced journal entry/);
    });

    it('leaves no rows behind when it rejects', () => {
      const before = (db.prepare('SELECT COUNT(*) AS n FROM journal_entries').get() as { n: number }).n;
      expect(() => AccountingService.postEntry(db, entry([100], [100.01]))).toThrow();
      const after = (db.prepare('SELECT COUNT(*) AS n FROM journal_entries').get() as { n: number }).n;
      expect(after).toBe(before);
    });
  });

  describe('accepts legitimate rounding', () => {
    it('accepts the classic float-summation case the tolerance existed for', () => {
      // 0.1 + 0.2 !== 0.3 in IEEE 754. This must still post.
      const posted = AccountingService.postEntry(db, entry([0.1, 0.2], [0.3]));
      expect(posted.total_debit).toBe(0.3);
      expect(posted.total_credit).toBe(0.3);
      // Not `stored.debit === stored.credit`: SQLite sums REAL columns in
      // float, so 0.1 + 0.2 aggregates to 0.30000000000000004 against a
      // single 0.3 credit. Rows are exact; the aggregate is not, which is
      // why the read side keeps a tolerance and storage stays REAL.
      const stored = storedTotals(posted.journal_entry_id);
      expect(toMinorUnits(stored.debit)).toBe(toMinorUnits(stored.credit));
    });

    it('accepts many small lines whose float sum drifts', () => {
      const debits = Array.from({ length: 10 }, () => 0.1);
      const posted = AccountingService.postEntry(db, entry(debits, [1.0]));
      expect(toMinorUnits(posted.total_debit)).toBe(100);
      expect(toMinorUnits(posted.total_credit)).toBe(100);
    });

    it('accepts an entry that balances only once lines are normalized', () => {
      // 33.335 rounds up to 33.34 each, so the pair foots to 66.68 and
      // the caller's 66.68 credit matches exactly.
      const posted = AccountingService.postEntry(db, entry([33.335, 33.335], [66.68]));
      const stored = storedTotals(posted.journal_entry_id);
      expect(toMinorUnits(stored.debit)).toBe(6668);
      expect(toMinorUnits(stored.credit)).toBe(6668);
    });
  });

  describe('normalization at the posting boundary', () => {
    it('stores lines at the currency minor unit so the GL foots exactly', () => {
      const posted = AccountingService.postEntry(db, entry([12.005], [12.01]));
      const rows = db.prepare(
        'SELECT debit, credit FROM journal_lines WHERE journal_entry_id = ?',
      ).all(posted.journal_entry_id) as Array<{ debit: number; credit: number }>;

      for (const row of rows) {
        expect(roundCurrency(Number(row.debit))).toBe(Number(row.debit));
        expect(roundCurrency(Number(row.credit))).toBe(Number(row.credit));
      }
      const stored = storedTotals(posted.journal_entry_id);
      expect(toMinorUnits(stored.debit)).toBe(toMinorUnits(stored.credit));
    });

    it('reports totals that convert back to the stored minor units', () => {
      const posted = AccountingService.postEntry(db, entry([250.55], [250.55]));
      expect(toMinorUnits(posted.total_debit)).toBe(25055);
      expect(toMinorUnits(posted.total_credit)).toBe(25055);
    });
  });

  describe('toMinorUnits', () => {
    it('is exact for values that floats cannot represent', () => {
      expect(toMinorUnits(0.1 + 0.2)).toBe(30);
      expect(toMinorUnits(20.01)).toBe(2001);
      expect(toMinorUnits(1.005)).toBe(101);
    });

    it('round-trips through the minor unit without drift', () => {
      for (const value of [0, 0.01, 1.15, 99.99, 1234.56, 1_000_000.07]) {
        expect(toMinorUnits(value) / 100).toBe(roundCurrency(value));
      }
    });

    it('keeps sums of minor units exact', () => {
      // The defect this replaces: a float sum that drifts by ~1e-13.
      const floatSum = 0.1 + 0.2;
      expect(floatSum).not.toBe(0.3);
      const minorSum = toMinorUnits(0.1) + toMinorUnits(0.2);
      expect(minorSum).toBe(toMinorUnits(0.3));
    });
  });
});