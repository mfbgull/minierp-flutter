import Database from 'better-sqlite3';
import { afterEach, beforeEach, describe, expect, it } from '@jest/globals';
import AccountingService from '../accountingService';

const postingCases = [
  {
    name: 'supplier payout',
    accountCode: '2000',
    missingMessage: 'Chart of accounts is missing required account: 2000 (Accounts Payable)',
    cashDebit: 0,
    cashCredit: 25,
    post: (db: Database.Database, paymentMethod: string, amount = 25) =>
      AccountingService.postSupplierPaymentEntry(db, {
        paymentId: 1, paymentNo: 'PAY-1', amount, paymentDate: '2026-10-21', paymentMethod,
      }),
  },
  {
    name: 'owner contribution',
    accountCode: '3200',
    missingMessage: "Chart of accounts is missing required account: 3200 (Owner Capital, text_code 'owner_capital')",
    cashDebit: 25,
    cashCredit: 0,
    post: (db: Database.Database, paymentMethod: string, amount = 25) =>
      AccountingService.postOwnerCapitalEntry(db, {
        capitalId: 1, capitalNo: 'CAP-1', amount, capitalDate: '2026-10-21', paymentMethod,
      }),
  },
  {
    name: 'owner cash withdrawal',
    accountCode: '3300',
    missingMessage: "Chart of accounts is missing required account: 3300 (Owner Drawings, text_code 'owner_drawings')",
    cashDebit: 0,
    cashCredit: 25,
    post: (db: Database.Database, paymentMethod: string, amount = 25) =>
      AccountingService.postOwnerWithdrawalCashEntry(db, {
        withdrawalId: 1, withdrawalNo: 'WD-1', amount, withdrawalDate: '2026-10-21', paymentMethod,
      }),
  },
];

describe.each(postingCases)('cash account resolution: $name', (scenario) => {
  let db: Database.Database;

  beforeEach(() => {
    db = new Database(':memory:');
    db.exec(`
      CREATE TABLE chart_of_accounts (id INTEGER PRIMARY KEY, code TEXT, text_code TEXT, is_active INTEGER);
      CREATE TABLE accounting_periods (id INTEGER PRIMARY KEY, period_name TEXT UNIQUE, start_date TEXT, end_date TEXT, status TEXT);
      CREATE TABLE journal_entries (id INTEGER PRIMARY KEY, reference_type TEXT, reference_id INTEGER,
        entry_date TEXT, description TEXT, debit_account TEXT, credit_account TEXT,
        amount REAL, created_by INTEGER, voided INTEGER);
      CREATE TABLE journal_lines (id INTEGER PRIMARY KEY, journal_entry_id INTEGER, account_id INTEGER,
        debit REAL, credit REAL, description TEXT, line_date TEXT, reference_type TEXT,
        reference_id INTEGER, created_by INTEGER);
    `);
    const insert = db.prepare('INSERT INTO chart_of_accounts (id, code, text_code, is_active) VALUES (?, ?, ?, 1)');
    insert.run(1, '1000', 'cash');
    insert.run(2, '1010', 'bank');
    insert.run(3, '2000', 'accounts_payable');
    insert.run(4, '3200', 'owner_capital');
    insert.run(5, '3300', 'owner_drawings');
    db.prepare('INSERT INTO accounting_periods VALUES (?, ?, ?, ?, ?)')
      .run(1, '2026-10', '2026-10-01', '2026-10-31', 'open');
  });

  afterEach(() => { db?.close(); });

  it.each([['Cash', '1000', 1], ['Bank', '1010', 2]] as const)(
    'posts %s to the existing method account with balanced lines', (method, code, id) => {
      const posted = scenario.post(db, method);
      expect(posted).toMatchObject({ line_count: 2, total_debit: 25, total_credit: 25 });
      expect(db.prepare('SELECT debit, credit FROM journal_lines WHERE account_id = ?').get(id))
        .toEqual({ debit: scenario.cashDebit, credit: scenario.cashCredit });
      expect(db.prepare<[number], { description: string }>('SELECT description FROM journal_entries WHERE id = ?').get(1)?.description)
        .toContain(`(${code})`);
    },
  );

  it.each([['Cash', '1000'], ['Bank', '1010']] as const)(
    'rejects missing %s with the existing account message before writing', (method, code) => {
      db.prepare('DELETE FROM chart_of_accounts WHERE code = ?').run(code);
      expect(() => scenario.post(db, method)).toThrow(`Chart of accounts is missing required account: ${code}`);
      expect(db.prepare('SELECT COUNT(*) AS count FROM journal_entries').get()).toEqual({ count: 0 });
      expect(db.prepare('SELECT COUNT(*) AS count FROM journal_lines').get()).toEqual({ count: 0 });
    },
  );

  it('retains the caller account validation precedence over missing cash', () => {
    db.prepare('DELETE FROM chart_of_accounts WHERE code IN (?, ?)').run(scenario.accountCode, '1000');
    expect(() => scenario.post(db, 'Cash')).toThrow(scenario.missingMessage);
    expect(db.prepare('SELECT COUNT(*) AS count FROM journal_entries').get()).toEqual({ count: 0 });
  });

  it('retains the zero-amount guard before account lookup', () => {
    db.prepare('DELETE FROM chart_of_accounts').run();
    expect(scenario.post(db, 'Cash', 0)).toBeNull();
    expect(db.prepare('SELECT COUNT(*) AS count FROM journal_entries').get()).toEqual({ count: 0 });
  });
});
