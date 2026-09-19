/**
 * task 8.1 — expenses pagination envelope + sort whitelist regression.
 */
import Database from 'better-sqlite3';
import ExpenseModel from '../models/Expense';
import { sanitizeSortParams, EXPENSE_SORT_COLUMNS } from '../utils/sqlSanitizer';

function createFixture(): Database.Database {
  const db = new Database(':memory:');
  db.exec(`CREATE TABLE expenses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    expense_no TEXT NOT NULL, expense_category TEXT NOT NULL,
    description TEXT, amount REAL NOT NULL, expense_date TEXT NOT NULL,
    payment_method TEXT, reference_no TEXT, vendor_name TEXT,
    project TEXT, status TEXT NOT NULL DEFAULT 'Draft',
    created_by INTEGER, created_at TEXT, updated_at TEXT
  )`);
  db.exec(`CREATE TABLE users (id INTEGER PRIMARY KEY, full_name TEXT)`);
  db.prepare(
    `INSERT INTO users (id, full_name) VALUES (1, 'Admin')`
  ).run();
  return db;
}

describe('ExpenseModel pagination + sort', () => {
  let db: Database.Database;

  beforeEach(() => {
    db = createFixture();
    db.prepare(
      `INSERT INTO expenses (expense_no, expense_category, description, amount,
                            expense_date, status, created_by, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ).run('E1', 'Fuel', 'Gas', 100, '2026-08-20', 'Paid', 1, '2026-08-20', '2026-08-20');
    db.prepare(
      `INSERT INTO expenses (expense_no, expense_category, description, amount,
                            expense_date, status, created_by, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ).run('E2', 'Food', 'Lunch', 50, '2026-08-22', 'Paid', 1, '2026-08-22', '2026-08-22');
    db.prepare(
      `INSERT INTO expenses (expense_no, expense_category, description, amount,
                            expense_date, status, created_by, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ).run('E3', 'Fuel', 'Diesel', 200, '2026-08-23', 'Draft', 1, '2026-08-23', '2026-08-23');
  });

  afterEach(() => db.close());

  it('getAll returns rows + total for paged envelope', () => {
    const rows = ExpenseModel.getAll(db, { page: 1, limit: 2 });
    expect(rows).toHaveLength(2);
    expect(ExpenseModel.getCount(db, {})).toBe(3);
  });

  it('getCount respects filters', () => {
    expect(ExpenseModel.getCount(db, { category: 'Fuel' })).toBe(2);
    expect(ExpenseModel.getCount(db, { status: 'Draft' })).toBe(1);
    expect(ExpenseModel.getCount(db, { search: 'Lunch' })).toBe(1);
  });

  it('default sort is newest first', () => {
    const rows = ExpenseModel.getAll(db, { page: 1, limit: 10 }) as Array<{ expense_no: string }>;
    expect(rows[0].expense_no).toBe('E3');
    expect(rows[rows.length - 1].expense_no).toBe('E1');
  });

  it('sanitizeSortParams rejects unknown columns', () => {
    const { column, order } = sanitizeSortParams(
      'DROP TABLE expenses;--', 'ASC', EXPENSE_SORT_COLUMNS,
      'e.expense_date', 'ASC'
    );
    expect(EXPENSE_SORT_COLUMNS).not.toContain('DROP TABLE expenses;--');
    expect(column).toBe('e.expense_date');
    expect(order).toBe('ASC');
  });

  it('sanitizeSortParams accepts whitelisted columns', () => {
    const { column } = sanitizeSortParams('e.amount', 'DESC', EXPENSE_SORT_COLUMNS);
    expect(EXPENSE_SORT_COLUMNS).toContain(column);
  });
});
