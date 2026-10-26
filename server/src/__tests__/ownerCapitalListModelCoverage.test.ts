import Database from 'better-sqlite3';
import { afterAll, beforeAll, describe, expect, it } from '@jest/globals';
import OwnerCapitalModel from '../models/OwnerCapital';

describe('owner capital list SQL', () => {
  const db = new Database(':memory:');

  beforeAll(() => {
    db.exec(`
      CREATE TABLE users (id INTEGER PRIMARY KEY, full_name TEXT);
      CREATE TABLE owner_capital (
        id INTEGER PRIMARY KEY, capital_no TEXT, capital_date TEXT,
        amount REAL, payment_method TEXT, note TEXT, status TEXT,
        created_at TEXT, created_by INTEGER
      );
      INSERT INTO users VALUES (1, 'Capital author');
    `);
    const insert = db.prepare(`INSERT INTO owner_capital
      (id, capital_no, capital_date, amount, payment_method, note, status, created_by)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)`);
    insert.run(1, 'CAP-A', '2026-01-10', 100, 'Cash', 'opening funds', 'posted', 1);
    insert.run(2, 'CAP-B', '2026-02-10', 300, 'Bank', 'expansion', 'posted', null);
    insert.run(3, 'CAP-C', '2026-03-10', 200, 'Cash', 'cancelled funds', 'voided', 1);
  });

  afterAll(() => {
    db.close();
  });

  it('defaults to posted rows in descending date order and preserves the author join', () => {
    expect(OwnerCapitalModel.getAll(db)).toEqual([
      expect.objectContaining({ capital_no: 'CAP-B', created_by_name: null }),
      expect.objectContaining({ capital_no: 'CAP-A', created_by_name: 'Capital author' }),
    ]);
  });

  it('supports all statuses, specific statuses and inclusive date boundaries', () => {
    expect(OwnerCapitalModel.getAll(db, { status: 'all' })).toHaveLength(3);
    expect(OwnerCapitalModel.getAll(db, { status: 'voided' })).toEqual([
      expect.objectContaining({ capital_no: 'CAP-C' }),
    ]);
    expect(OwnerCapitalModel.getAll(db, {
      status: 'posted', from_date: '2026-02-10', to_date: '2026-02-10',
    })).toEqual([expect.objectContaining({ capital_no: 'CAP-B' })]);
  });

  it.each(['CAP-B', 'expansion', 'Bank'])('searches number, note and payment method: %s', search => {
    expect(OwnerCapitalModel.getAll(db, { search })).toEqual([
      expect.objectContaining({ capital_no: 'CAP-B' }),
    ]);
  });

  it('binds search text literally and combines filters', () => {
    expect(OwnerCapitalModel.getAll(db, { search: "' OR 1=1 --" })).toEqual([]);
    expect(OwnerCapitalModel.getAll(db, { search: 'funds', from_date: '2026-02-01' })).toEqual([]);
  });

  it('applies sort direction and pagination together', () => {
    expect(OwnerCapitalModel.getAll(db, {
      status: 'all', page: 2, limit: 1, sortBy: 'oc.amount', sortOrder: 'ASC',
    })).toEqual([expect.objectContaining({ capital_no: 'CAP-C' })]);
  });
});
