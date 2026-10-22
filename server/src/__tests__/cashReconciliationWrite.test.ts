import { afterAll, describe, expect, it } from '@jest/globals';
import ReportsModel from '../models/Reports';
import { createFixtureDb, cleanupFixtureDbs } from './helpers/productionSchema';

afterAll(() => cleanupFixtureDbs());

function fixtureDb() {
  const db = createFixtureDb();
  const user = db.prepare(`
    INSERT INTO users (username, email, password_hash, full_name, role, is_active)
    VALUES ('recon-user', 'recon@example.test', 'hash', 'Recon User', 'admin', 1)
  `).run();
  return { db, userId: Number(user.lastInsertRowid) };
}

type ReconciliationRow = {
  account_key: string;
  expected_balance: number;
  counted_balance: number | null;
  variance: number | null;
  notes: string | null;
  reconciled_by: number | null;
};

const readRow = (db: ReturnType<typeof fixtureDb>['db'], date: string, key: string) =>
  db.prepare(`
    SELECT account_key, expected_balance, counted_balance, variance, notes, reconciled_by
    FROM cash_reconciliations
    WHERE reconciliation_date = ? AND account_key = ?
  `).get(date, key) as ReconciliationRow | undefined;

describe('ReportsModel.saveCashReconciliation', () => {
  it('upserts counted amounts, snapshots expected, rounds and trims notes', () => {
    const { db, userId } = fixtureDb();

    const saved = ReportsModel.saveCashReconciliation(db, '2026-10-22', [
      { key: 'cash', counted_balance: 10.006, notes: '  counted  ' },
      { key: 'bank', counted_balance: null, notes: '   ' },
    ], userId);

    const cash = readRow(db, '2026-10-22', 'cash');
    expect(cash).toBeDefined();
    expect(cash!.counted_balance).toBe(10.01);
    expect(cash!.notes).toBe('counted');
    expect(cash!.variance).toBe(Math.round((10.01 - cash!.expected_balance) * 100) / 100);
    expect(cash!.reconciled_by).toBe(userId);

    const bank = readRow(db, '2026-10-22', 'bank');
    expect(bank).toBeDefined();
    expect(bank!.counted_balance).toBeNull();
    expect(bank!.variance).toBeNull();
    expect(bank!.notes).toBeNull();

    expect(saved.date).toBe('2026-10-22');
    expect(saved.accounts.find((a) => a.key === 'cash')).toMatchObject({
      counted_balance: 10.01,
      reconciled: true,
    });
    expect(saved.accounts.find((a) => a.key === 'bank')).toMatchObject({
      counted_balance: null,
      reconciled: false,
    });

    ReportsModel.saveCashReconciliation(db, '2026-10-22', [
      { key: 'cash', counted_balance: 20, notes: 'second' },
    ], userId);

    const rows = db.prepare(`
      SELECT counted_balance, notes FROM cash_reconciliations
      WHERE reconciliation_date = '2026-10-22' AND account_key = 'cash'
    `).all() as Array<{ counted_balance: number; notes: string | null }>;
    expect(rows).toEqual([{ counted_balance: 20, notes: 'second' }]);
  });

  it('treats an omitted counted amount as null', () => {
    const { db, userId } = fixtureDb();

    ReportsModel.saveCashReconciliation(db, '2026-10-24', [
      { key: 'cash', counted_balance: undefined as unknown as number | null },
    ], userId);

    const cash = readRow(db, '2026-10-24', 'cash');
    expect(cash).toBeDefined();
    expect(cash!.counted_balance).toBeNull();
    expect(cash!.variance).toBeNull();
  });

  it('rolls back every entry when one account key is unknown', () => {
    const { db, userId } = fixtureDb();

    expect(() => ReportsModel.saveCashReconciliation(db, '2026-10-23', [
      { key: 'cash', counted_balance: 5 },
      { key: 'bogus', counted_balance: 1 },
    ], userId)).toThrow(/Unknown account key: bogus/);

    const count = db.prepare(`
      SELECT COUNT(*) AS count FROM cash_reconciliations WHERE reconciliation_date = '2026-10-23'
    `).get() as { count: number };
    expect(count.count).toBe(0);
  });
});
