import { describe, expect, it } from '@jest/globals';
import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';

describe('Accounting extension account reservations', () => {
  for (const [file, code, name, type, normal] of [
    ['112_expense_payables.sql', '2115', 'Expense Payables', 'liability', 'credit'],
    ['113_supplier_bills.sql', '1320', 'Recoverable Input Tax', 'asset', 'debit'],
    ['114_supplier_prepayments.sql', '1330', 'Supplier Prepayments', 'asset', 'debit'],
  ]) {
    it(`${file} rejects an existing unrelated account`, () => {
      const fixture = new Database(':memory:');
      try {
        fixture.exec(`CREATE TABLE chart_of_accounts (code TEXT UNIQUE, name TEXT, type TEXT, normal_balance TEXT, text_code TEXT, is_active INTEGER DEFAULT 1)`);
        fixture.prepare('INSERT INTO chart_of_accounts (code, name, type, normal_balance) VALUES (?, ?, ?, ?)').run(code, 'Unrelated account', 'equity', 'credit');
        expect(() => fixture.exec(fs.readFileSync(path.join(__dirname, '../migrations', file), 'utf8'))).toThrow();
        expect(fixture.prepare('SELECT name FROM chart_of_accounts WHERE code = ?').get(code)).toEqual({ name: 'Unrelated account' });
      } finally { fixture.close(); }
    });

    it(`${file} creates the intended account on clean books`, () => {
      const fixture = new Database(':memory:');
      try {
        fixture.exec(`CREATE TABLE chart_of_accounts (code TEXT UNIQUE, name TEXT, type TEXT, normal_balance TEXT, text_code TEXT, is_active INTEGER DEFAULT 1)`);
        fixture.exec(fs.readFileSync(path.join(__dirname, '../migrations', file), 'utf8'));
        expect(fixture.prepare('SELECT name, type, normal_balance FROM chart_of_accounts WHERE code = ?').get(code)).toEqual({ name, type, normal_balance: normal });
      } finally { fixture.close(); }
    });
  }
});
