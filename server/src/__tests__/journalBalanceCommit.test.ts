import { afterAll, afterEach, beforeEach, describe, expect, it } from '@jest/globals';
import type Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';
import { AccountingService } from '../services/accountingService';
import { cleanupFixtureDbs, createFixtureDb } from './helpers/productionSchema';

let db: Database.Database;
let cash: number;
let equity: number;

beforeEach(() => {
  db = createFixtureDb({ reference: true });
  const accounts = db.prepare<[], { id: number; code: string }>(
    "SELECT id, code FROM chart_of_accounts WHERE code IN ('1000', '3000')"
  ).all();
  const cashAccount = accounts.find(account => account.code === '1000');
  const equityAccount = accounts.find(account => account.code === '3000');
  if (!cashAccount || !equityAccount) throw new Error('Required fixture accounts are missing');
  cash = cashAccount.id;
  equity = equityAccount.id;
});
afterEach(() => { db.close(); });
afterAll(cleanupFixtureDbs);

function line(entry: number, account: number, debit: number, credit: number): void {
  db.prepare(`
    INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, line_date, reference_type, reference_id)
    VALUES (?, ?, ?, ?, '2026-09-01', 'MANUAL_JOURNAL', ?)
  `).run(entry, account, debit, credit, entry);
}

function balanced(): void {
  db.transaction(() => {
    line(1, cash, 100, 0);
    line(1, equity, 0, 100);
  })();
}

describe('DB-002 journal balance at transaction commit', () => {
  it('rejects an unmatched line written without an explicit transaction', () => {
    expect(() => line(1, cash, 100, 0)).toThrow(/FOREIGN KEY constraint failed/);
    expect(db.prepare('SELECT COUNT(*) AS n FROM journal_lines').get()).toEqual({ n: 0 });
  });

  it('rejects an unbalanced transaction and rolls back associated business writes', () => {
    expect(() => db.transaction(() => {
      db.prepare("INSERT INTO settings (key, value) VALUES ('journal-test', 'must roll back')").run();
      line(1, cash, 100, 0);
      line(1, equity, 0, 90);
    })()).toThrow(/FOREIGN KEY constraint failed/);
    expect(db.prepare("SELECT value FROM settings WHERE key = 'journal-test'").get()).toBeUndefined();
    expect(db.prepare('SELECT COUNT(*) AS n FROM journal_lines').get()).toEqual({ n: 0 });
  });

  it('requires every entry to balance even when the global totals cancel', () => {
    expect(() => db.transaction(() => {
      line(1, cash, 100, 0);
      line(2, equity, 0, 100);
    })()).toThrow(/FOREIGN KEY constraint failed/);
  });

  it('allows a balanced multi-line posting with fractional currency amounts', () => {
    db.transaction(() => {
      line(1, cash, 0.3, 0);
      line(1, equity, 0, 0.1);
      line(1, equity, 0, 0.2);
    })();
    expect(db.prepare('SELECT COUNT(*) AS n FROM journal_lines').get()).toEqual({ n: 3 });
    expect(db.pragma('foreign_key_check')).toEqual([]);
  });

  it('lets the legacy stock writer post atomically without a caller transaction', () => {
    const id = AccountingService.postLegacyStockEntry(db, {
      referenceType: 'STOCK_ADJUSTMENT', referenceId: 1, entryDate: '2026-09-01',
      description: 'Commit guard integration', debitTextCode: 'inventory_asset',
      creditTextCode: 'owners_equity', amount: 10,
    });
    expect(db.prepare('SELECT SUM(debit) AS debit, SUM(credit) AS credit FROM journal_lines WHERE journal_entry_id = ?').get(id))
      .toEqual({ debit: 10, credit: 10 });
    expect(db.prepare('SELECT id FROM journal_entries WHERE id = ?').get(id)).toEqual({ id });
    expect(db.pragma('foreign_key_check')).toEqual([]);
  });

  it.each([
    'UPDATE journal_lines SET debit = 101 WHERE debit > 0',
    'UPDATE journal_lines SET voided = 1 WHERE debit > 0',
    'DELETE FROM journal_lines WHERE debit > 0',
    'UPDATE journal_lines SET journal_entry_id = 2 WHERE debit > 0',
  ])('rejects a partial mutation: %s', sql => {
    balanced();
    const before = db.prepare('SELECT * FROM journal_lines ORDER BY id').all();

    expect(() => db.prepare(sql).run()).toThrow(/FOREIGN KEY constraint failed/);

    expect(db.prepare('SELECT * FROM journal_lines ORDER BY id').all()).toEqual(before);
  });

  it.each([
    'UPDATE journal_lines SET voided = 1 WHERE journal_entry_id = 1',
    'DELETE FROM journal_lines WHERE journal_entry_id = 1',
    'UPDATE journal_lines SET journal_entry_id = 2 WHERE journal_entry_id = 1',
  ])('permits a balanced whole-entry mutation: %s', sql => {
    balanced();

    db.prepare(sql).run();

    expect(db.pragma('foreign_key_check')).toEqual([]);
  });

  it('restores a fully voided entry atomically', () => {
    balanced();
    db.prepare('UPDATE journal_lines SET voided = 1').run();

    db.prepare('UPDATE journal_lines SET voided = 0').run();

    expect(db.prepare('SELECT COUNT(*) AS n FROM journal_lines WHERE voided = 0').get()).toEqual({ n: 2 });
    expect(db.pragma('foreign_key_check')).toEqual([]);
  });

  it('allows a balanced correction inside one transaction', () => {
    balanced();

    db.transaction(() => {
      db.prepare('UPDATE journal_lines SET debit = 200 WHERE debit > 0').run();
      db.prepare('UPDATE journal_lines SET credit = 200 WHERE credit > 0').run();
    })();

    expect(db.prepare('SELECT SUM(debit) AS debit, SUM(credit) AS credit FROM journal_lines').get())
      .toEqual({ debit: 200, credit: 200 });
  });

  it('checks the outer transaction even after a nested savepoint is released', () => {
    expect(() => db.transaction(() => {
      db.transaction(() => { line(1, cash, 100, 0); })();
    })()).toThrow(/FOREIGN KEY constraint failed/);
    expect(db.prepare('SELECT COUNT(*) AS n FROM journal_lines').get()).toEqual({ n: 0 });
  });

  it('rejects even a one-cent imbalance', () => {
    expect(() => db.transaction(() => {
      line(1, cash, 100, 0);
      line(1, equity, 0, 99.99);
    })()).toThrow(/FOREIGN KEY constraint failed/);
  });

  it.each([
    `INSERT OR REPLACE INTO journal_lines
      (id, journal_entry_id, account_id, debit, credit, line_date, reference_type, reference_id)
      SELECT id, journal_entry_id, account_id, 200, 0, line_date, reference_type, reference_id
      FROM journal_lines WHERE debit > 0`,
    'UPDATE OR REPLACE journal_lines SET id = (SELECT id FROM journal_lines WHERE credit > 0) WHERE debit > 0',
  ])('rejects replacement that would silently delete a line: %s', sql => {
    balanced();
    const before = db.prepare('SELECT * FROM journal_lines ORDER BY id').all();
    expect(() => db.exec(sql)).toThrow('Journal lines must be updated, not replaced');
    expect(db.prepare('SELECT * FROM journal_lines ORDER BY id').all()).toEqual(before);
  });
});

describe('DB-002 migration from a historical schema', () => {
  const migration = fs.readFileSync(path.join(__dirname, '../migrations/add-journal-balance-commit-guard.sql'), 'utf8');

  beforeEach(() => {
    db.exec(`
      DROP TRIGGER journal_balance_insert;
      DROP TRIGGER journal_balance_update;
      DROP TRIGGER journal_balance_delete;
      DROP TRIGGER journal_balance_no_replace_insert;
      DROP TRIGGER journal_balance_no_replace_update;
      DROP TABLE journal_entry_balances;
      DROP TABLE journal_balance_zero;
    `);
  });

  it('backfills existing balanced journals and then protects their lines', () => {
    balanced();
    db.transaction(() => db.exec(migration))();
    expect(db.prepare('SELECT * FROM journal_entry_balances').all())
      .toEqual([{ journal_entry_id: 1, balance_cents: 0 }]);
    expect(() => db.prepare('DELETE FROM journal_lines WHERE debit > 0').run())
      .toThrow(/FOREIGN KEY constraint failed/);
  });

  it('fails atomically on historical imbalance without changing the old data', () => {
    line(1, cash, 100, 0);
    expect(() => db.transaction(() => db.exec(migration))()).toThrow(/FOREIGN KEY constraint failed/);
    expect(db.prepare("SELECT name FROM sqlite_master WHERE name = 'journal_entry_balances'").get()).toBeUndefined();
    expect(db.prepare('SELECT COUNT(*) AS n FROM journal_lines').get()).toEqual({ n: 1 });
  });

  it('ignores voided historical amounts but guards their restoration', () => {
    line(1, cash, 100, 0);
    db.exec('UPDATE journal_lines SET voided = 1');
    db.transaction(() => db.exec(migration))();
    expect(() => db.exec('UPDATE journal_lines SET voided = 0')).toThrow(/FOREIGN KEY constraint failed/);
  });
});
