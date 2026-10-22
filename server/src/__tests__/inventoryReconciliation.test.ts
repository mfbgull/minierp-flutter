import { afterAll, describe, expect, it } from '@jest/globals';
import Database from 'better-sqlite3';
import { postInventoryReconciliationEntry } from '../utils/inventoryReconciliation';
import { createFixtureDb, cleanupFixtureDbs } from './helpers/productionSchema';

afterAll(() => cleanupFixtureDbs());

const options = (amount: number) => ({
  description: 'Coverage reconciliation: +10 units @ 5 (item 1, warehouse 1)',
  inventoryLineDescription: 'Inventory increase (coverage reconciliation)',
  adjustmentLineDescription: 'Coverage reconciliation adjustment',
  amount,
});

type EntryRow = {
  id: number;
  reference_type: string;
  reference_id: number;
  description: string;
  debit_account: string;
  credit_account: string;
  amount: number;
  voided: number;
};

type LineRow = {
  code: string;
  debit: number;
  credit: number;
  description: string;
};

describe('postInventoryReconciliationEntry', () => {
  it('posts a balanced RECON entry using the inventory and adjustment accounts', () => {
    const db = createFixtureDb({ reference: true });

    db.transaction(() => postInventoryReconciliationEntry(db, options(50)))();

    const entry = db.prepare(
      `SELECT * FROM journal_entries WHERE reference_type = 'RECON'`
    ).get() as EntryRow;
    expect(entry).toMatchObject({
      reference_type: 'RECON',
      reference_id: 0,
      description: 'Coverage reconciliation: +10 units @ 5 (item 1, warehouse 1)',
      debit_account: '1200',
      credit_account: '4999',
      amount: 50,
      voided: 0,
    });

    const lines = db.prepare(`
      SELECT coa.code, jl.debit, jl.credit, jl.description
      FROM journal_lines jl
      JOIN chart_of_accounts coa ON coa.id = jl.account_id
      WHERE jl.journal_entry_id = ?
      ORDER BY jl.id
    `).all(entry.id) as LineRow[];

    expect(lines).toEqual([
      {
        code: '1200',
        debit: 50,
        credit: 0,
        description: 'Inventory increase (coverage reconciliation)',
      },
      {
        code: '4000',
        debit: 0,
        credit: 50,
        description: 'Coverage reconciliation adjustment',
      },
    ]);
    expect(lines.reduce((sum, line) => sum + line.debit - line.credit, 0)).toBe(0);
  });

  it('does nothing when the amount is at or below the posting threshold', () => {
    const db = createFixtureDb({ reference: true });

    postInventoryReconciliationEntry(db, options(0.005));

    expect(db.prepare('SELECT COUNT(*) AS count FROM journal_entries').get()).toEqual({ count: 0 });
    expect(db.prepare('SELECT COUNT(*) AS count FROM journal_lines').get()).toEqual({ count: 0 });
  });

  it('posts the header but no lines when the chart accounts are missing', () => {
    const db = createFixtureDb();

    postInventoryReconciliationEntry(db, options(50));

    expect(db.prepare('SELECT COUNT(*) AS count FROM journal_entries').get()).toEqual({ count: 1 });
    expect(db.prepare('SELECT COUNT(*) AS count FROM journal_lines').get()).toEqual({ count: 0 });
  });

  it('does nothing when the journal_entries table is absent', () => {
    const bare = new Database(':memory:');

    expect(() => postInventoryReconciliationEntry(bare, options(50))).not.toThrow();

    bare.close();
  });

  it('leaves rollback to the caller transaction', () => {
    const db = createFixtureDb({ reference: true });
    db.exec(`
      CREATE TRIGGER fail_line
      BEFORE INSERT ON journal_lines
      BEGIN
        SELECT RAISE(ABORT, 'line failure');
      END
    `);

    expect(() => db.transaction(() => postInventoryReconciliationEntry(db, options(50)))())
      .toThrow(/line failure/);

    expect(db.prepare('SELECT COUNT(*) AS count FROM journal_entries').get()).toEqual({ count: 0 });
  });
});
