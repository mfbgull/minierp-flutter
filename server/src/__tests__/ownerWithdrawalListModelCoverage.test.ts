import { beforeEach, describe, expect, it } from '@jest/globals';
import db from '../config/database';
import OwnerWithdrawalModel from '../models/OwnerWithdrawal';

/**
 * Fallow health remediation — `OwnerWithdrawal.getAll` (CRAP 182) and
 * `getCount` (CRAP 90) filter branches.
 */
describe('owner withdrawal list model', () => {
  beforeEach(() => {
    db.prepare('DELETE FROM owner_withdrawal_items').run();
    db.prepare('DELETE FROM owner_withdrawals').run();
    const insert = db.prepare(
      `INSERT INTO owner_withdrawals (
         withdrawal_no, withdrawal_date, kind, amount, payment_method, note, status
       ) VALUES (?, ?, ?, ?, ?, ?, ?)`
    );
    insert.run('OW-A', '2026-01-10', 'cash', 100, 'Cash', 'rent', 'posted');
    insert.run('OW-B', '2026-02-10', 'goods', 0, 'Bank', 'stock', 'posted');
    insert.run('OW-C', '2026-03-10', 'cash', 200, 'Cash', 'voided one', 'voided');
  });

  it('defaults to posted withdrawals', () => {
    const rows = OwnerWithdrawalModel.getAll(db) as Array<{ withdrawal_no: string }>;
    expect(rows.map(r => r.withdrawal_no).sort()).toEqual(['OW-A', 'OW-B']);
  });

  it('applies status, kind, date and search filters', () => {
    const numbers = (filters: Parameters<typeof OwnerWithdrawalModel.getAll>[1]) =>
      (OwnerWithdrawalModel.getAll(db, filters) as Array<{ withdrawal_no: string }>)
        .map(r => r.withdrawal_no)
        .sort();

    expect(numbers({ status: 'all' })).toEqual(['OW-A', 'OW-B', 'OW-C']);
    expect(numbers({ status: 'voided' })).toEqual(['OW-C']);
    expect(numbers({ status: 'posted', kind: 'cash' })).toEqual(['OW-A']);
    expect(numbers({ status: 'all', kind: 'all' })).toEqual(['OW-A', 'OW-B', 'OW-C']);
    expect(numbers({ status: 'all', from_date: '2026-02-01' })).toEqual(['OW-B', 'OW-C']);
    expect(numbers({ status: 'all', to_date: '2026-01-31' })).toEqual(['OW-A']);
    expect(numbers({ search: 'rent' })).toEqual(['OW-A']);
    expect(numbers({ status: 'all', search: 'Bank' })).toEqual(['OW-B']);
  });

  it('pages and sorts by the supplied column', () => {
    const page = OwnerWithdrawalModel.getAll(db, {
      status: 'all',
      page: 2,
      limit: 1,
      sortBy: 'ow.withdrawal_no',
      sortOrder: 'ASC',
    }) as Array<{ withdrawal_no: string }>;
    expect(page.map(r => r.withdrawal_no)).toEqual(['OW-B']);

    const counted = OwnerWithdrawalModel.getCount(db, { status: 'all' });
    expect(counted).toBe(3);
    expect(OwnerWithdrawalModel.getCount(db, { kind: 'cash' })).toBe(1);
    expect(OwnerWithdrawalModel.getCount(db, { from_date: '2026-02-01' })).toBe(1);
    expect(OwnerWithdrawalModel.getCount(db, { search: 'Cash' })).toBe(1);
  });
});
