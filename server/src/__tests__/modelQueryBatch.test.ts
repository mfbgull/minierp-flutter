import Database from 'better-sqlite3';
import { afterAll, describe, expect, it } from '@jest/globals';
import EmployeeModel from '../models/Employee';
import OwnerCapitalModel from '../models/OwnerCapital';
import { createFixtureDb, cleanupFixtureDbs } from './helpers/productionSchema';

afterAll(() => cleanupFixtureDbs());

/**
 * Fallow health remediation — `Employee.getAll` (CRAP 56) and
 * `OwnerCapital.getCount` (CRAP 56). Covers active/inactive defaults,
 * search/department filters, sort fallbacks, pagination and count filters.
 */
function employeeFixture(): Database.Database {
  const db = createFixtureDb();
  const insert = db.prepare(`
    INSERT INTO employees (
      employee_code, first_name, last_name, email, phone, department, is_active
    ) VALUES (?, ?, ?, ?, ?, ?, ?)
  `);
  insert.run('EMP-A', 'Alice', 'Smith', 'alice@x.test', '111', 'Ops', 1);
  insert.run('EMP-B', 'Bob', 'Jones', 'bob@x.test', '222', 'Sales', 0);
  insert.run('EMP-C', 'Carol', 'Lee', 'carol@x.test', '333', 'Ops', 1);
  return db;
}

function capitalFixture(): Database.Database {
  const db = createFixtureDb();
  const insert = db.prepare(`
    INSERT INTO owner_capital (
      capital_no, capital_date, amount, payment_method, note, status
    ) VALUES (?, ?, ?, ?, ?, ?)
  `);
  insert.run('OC-1', '2026-01-10', 100, 'Cash', 'rent january', 'posted');
  insert.run('OC-2', '2026-02-10', 200, 'Bank', 'funding', 'posted');
  insert.run('OC-3', '2026-03-10', 50, 'Cash', 'reversal', 'voided');
  insert.run('OC-4', '2026-03-20', 300, 'Cash', 'rent march', 'posted');
  return db;
}

describe('EmployeeModel.getAll', () => {
  it('defaults to active employees and active-page ordering', () => {
    const db = employeeFixture();
    const result = EmployeeModel.getAll(db);
    expect(result.total).toBe(2);
    expect(result.data.map((row) => row.employee_code)).toEqual([
      'EMP-A',
      'EMP-C',
    ]);
    db.close();
  });

  it('filters inactive, department and search terms', () => {
    const db = employeeFixture();
    expect(
      EmployeeModel.getAll(db, { status: 'inactive' }).data.map(
        (row) => row.employee_code,
      ),
    ).toEqual(['EMP-B']);
    expect(
      EmployeeModel.getAll(db, { department: 'Ops' }).total,
    ).toBe(2);
    for (const search of ['Alice', 'EMP-C', 'carol@x', '333']) {
      expect(EmployeeModel.getAll(db, { search }).total).toBe(1);
    }
    db.close();
  });

  it('sorts by a whitelisted column and falls back for invalid ones', () => {
    const db = employeeFixture();
    const desc = EmployeeModel.getAll(
      db,
      {},
      'first_name',
      'DESC',
      1,
      20,
    );
    expect(desc.data.map((row) => row.first_name)).toEqual(['Carol', 'Alice']);

    const fallback = EmployeeModel.getAll(
      db,
      {},
      'first_name; DROP TABLE x',
      'sideways',
      1,
      20,
    );
    expect(fallback.data.map((row) => row.employee_code)).toEqual([
      'EMP-A',
      'EMP-C',
    ]);
    db.close();
  });

  it('clamps and paginates the limit', () => {
    const db = employeeFixture();
    const page = EmployeeModel.getAll(db, {}, 'employee_code', 'ASC', 2, 1);
    expect(page.total).toBe(2);
    expect(page.data.map((row) => row.employee_code)).toEqual(['EMP-C']);

    const clampedHigh = EmployeeModel.getAll(
      db,
      {},
      'employee_code',
      'ASC',
      1,
      500,
    );
    expect(clampedHigh.data).toHaveLength(2);

    const clampedLow = EmployeeModel.getAll(
      db,
      {},
      'employee_code',
      'ASC',
      0,
      0,
    );
    expect(clampedLow.data).toHaveLength(1);
    db.close();
  });
});

describe('OwnerCapital.getCount', () => {
  it('defaults to posted, supports explicit and all statuses', () => {
    const db = capitalFixture();
    expect(OwnerCapitalModel.getCount(db)).toBe(3);
    expect(OwnerCapitalModel.getCount(db, { status: 'voided' })).toBe(1);
    expect(OwnerCapitalModel.getCount(db, { status: 'all' })).toBe(4);
    db.close();
  });

  it('filters by date and search', () => {
    const db = capitalFixture();
    expect(
      OwnerCapitalModel.getCount(db, {
        from_date: '2026-02-01',
        to_date: '2026-02-28',
      }),
    ).toBe(1);
    expect(OwnerCapitalModel.getCount(db, { search: 'rent' })).toBe(2);
    expect(OwnerCapitalModel.getCount(db, { search: 'Cash' })).toBe(2);
    db.close();
  });
});
