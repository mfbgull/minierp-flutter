import Database from 'better-sqlite3';
import { afterAll, describe, expect, it } from '@jest/globals';
import OwnerWithdrawalModel from '../models/OwnerWithdrawal';
import { createFixtureDb, cleanupFixtureDbs } from './helpers/productionSchema';

afterAll(() => cleanupFixtureDbs());

/**
 * Fallow health remediation — `OwnerWithdrawal.getCount` (CRAP 90).
 * Covers the default posted filter, explicit status, the all-status escape,
 * kind/date/search filters, and the unfiltered count path.
 */
function createFixture(): Database.Database {
  const db = createFixtureDb();
  const insert = db.prepare(`
    INSERT INTO owner_withdrawals (
      withdrawal_no, withdrawal_date, kind, amount, payment_method, note, status
    ) VALUES (?, ?, ?, ?, ?, ?, ?)
  `);
  insert.run('OW-1', '2026-01-10', 'cash', 100, 'Cash', 'rent january', 'posted');
  insert.run('OW-2', '2026-02-10', 'goods', 200, 'Bank', 'stock february', 'posted');
  insert.run('OW-3', '2026-03-10', 'cash', 50, 'Cash', 'reversal', 'voided');
  insert.run('OW-4', '2026-03-20', 'cash', 300, 'Cash', 'rent march', 'posted');
  return db;
}

describe('OwnerWithdrawal.getCount', () => {
  it('defaults to posted rows', () => {
    const db = createFixture();
    expect(OwnerWithdrawalModel.getCount(db)).toBe(3);
    db.close();
  });

  it('filters an explicit status and the all-status escape', () => {
    const db = createFixture();
    expect(OwnerWithdrawalModel.getCount(db, { status: 'voided' })).toBe(1);
    expect(OwnerWithdrawalModel.getCount(db, { status: 'all' })).toBe(4);
    db.close();
  });

  it('filters by kind and date range', () => {
    const db = createFixture();
    expect(OwnerWithdrawalModel.getCount(db, { kind: 'cash' })).toBe(2);
    expect(
      OwnerWithdrawalModel.getCount(db, {
        from_date: '2026-02-01',
        to_date: '2026-02-28',
      }),
    ).toBe(1);
    db.close();
  });

  it('matches the note and payment method in a search', () => {
    const db = createFixture();
    expect(OwnerWithdrawalModel.getCount(db, { search: 'rent' })).toBe(2);
    expect(OwnerWithdrawalModel.getCount(db, { search: 'Cash' })).toBe(2);
    db.close();
  });
});
