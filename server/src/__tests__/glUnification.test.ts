import Database from 'better-sqlite3';
import { runBackfillGlUnification } from '../migrations/backfillGlUnification';

function setupDb(): Database.Database {
  const db = new Database(':memory:');
  db.exec(`
    CREATE TABLE chart_of_accounts (
      id INTEGER PRIMARY KEY,
      code TEXT NOT NULL,
      text_code TEXT,
      account_name TEXT NOT NULL,
      account_type TEXT NOT NULL
    );
    CREATE TABLE journal_entries (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      reference_type TEXT NOT NULL,
      reference_id INTEGER NOT NULL,
      entry_date TEXT,
      description TEXT,
      debit_account TEXT NOT NULL,
      credit_account TEXT NOT NULL,
      amount REAL,
      created_by INTEGER,
      voided INTEGER DEFAULT 0,
      created_at TEXT DEFAULT CURRENT_TIMESTAMP
    );
    CREATE TABLE journal_lines (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      journal_entry_id INTEGER,
      account_id INTEGER NOT NULL,
      debit REAL DEFAULT 0,
      credit REAL DEFAULT 0,
      description TEXT,
      line_date TEXT,
      reference_type TEXT NOT NULL,
      reference_id INTEGER NOT NULL,
      voided INTEGER DEFAULT 0,
      voided_at TEXT,
      voided_by INTEGER,
      void_reason TEXT
    );
    INSERT INTO chart_of_accounts (id, code, text_code, account_name, account_type) VALUES
      (1, '1000', 'cash', 'Cash', 'asset'),
      (2, '1100', 'accounts_receivable', 'AR', 'asset'),
      (3, '1200', 'inventory_asset', 'Inventory', 'asset'),
      (4, '2000', 'accounts_payable', 'AP', 'liability'),
      (5, '6000', 'inventory_shrinkage', 'Shrinkage', 'expense');
  `);
  return db;
}

function countBroken(db: Database.Database): number {
  return (db.prepare(`
    SELECT COUNT(*) AS n FROM journal_lines jl
    LEFT JOIN journal_entries je ON je.id = jl.journal_entry_id
    WHERE je.id IS NULL OR je.reference_type <> jl.reference_type
  `).get() as { n: number }).n;
}

describe('GL unification migration', () => {
  let db: Database.Database;

  beforeEach(() => {
    db = setupDb();
  });

  afterEach(() => {
    db.close();
  });

  it('re-links orphaned groups to fresh headers', () => {
    db.prepare(`
      INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit,
        description, line_date, reference_type, reference_id)
      VALUES (999, 3, 100, 0, 'purchase 7', '2026-01-01', 'PURCHASE', 7),
            (999, 4, 0, 100, 'purchase 7', '2026-01-01', 'PURCHASE', 7)
    `).run();

    expect(countBroken(db)).toBe(2);

    runBackfillGlUnification(db);

    expect(countBroken(db)).toBe(0);
    const header = db.prepare(`
      SELECT je.id, je.reference_type, je.reference_id, je.debit_account, je.credit_account, je.amount
      FROM journal_entries je WHERE je.reference_type = 'PURCHASE' AND je.reference_id = 7
    `).get() as { id: number; reference_type: string; reference_id: number; debit_account: string; credit_account: string; amount: number };
    expect(header.reference_type).toBe('PURCHASE');
    expect(header.reference_id).toBe(7);
    expect(header.debit_account).toBe('3');
    expect(header.credit_account).toBe('4');
    expect(header.amount).toBe(100);
    const lines = db.prepare(`
      SELECT journal_entry_id FROM journal_lines
      WHERE reference_type = 'PURCHASE' AND reference_id = 7
    `).all() as Array<{ journal_entry_id: number }>;
    expect(lines.every(l => l.journal_entry_id === header.id)).toBe(true);
    expect(lines.some(l => l.journal_entry_id === 999)).toBe(false);
  });

  it('re-links mis-linked groups without touching the wrong header', () => {
    db.prepare(`
      INSERT INTO journal_entries (reference_type, reference_id, entry_date,
        description, debit_account, credit_account, amount) VALUES
        ('stock_adjustment', 50, '2026-01-02', 'stock adj 50', 'inventory_shrinkage', 'inventory_asset', 40)
    `).run();
    const stockHeaderId = (db.prepare(`SELECT id FROM journal_entries`).get() as { id: number }).id;

    db.prepare(`
      INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit,
        description, line_date, reference_type, reference_id)
      VALUES (?, 3, 80, 0, 'production 2', '2026-01-02', 'production', 2),
            (?, 1, 0, 80, 'production 2', '2026-01-02', 'production', 2)
    `).run(stockHeaderId, stockHeaderId);

    expect(countBroken(db)).toBe(2);

    runBackfillGlUnification(db);

    expect(countBroken(db)).toBe(0);
    const prodHeader = db.prepare(`
      SELECT id FROM journal_entries
      WHERE reference_type = 'production' AND reference_id = 2
    `).get() as { id: number };
    expect(prodHeader).toBeDefined();
    const prodLines = db.prepare(`
      SELECT journal_entry_id FROM journal_lines
      WHERE reference_type = 'production' AND reference_id = 2
    `).all() as Array<{ journal_entry_id: number }>;
    expect(prodLines.every(l => l.journal_entry_id === prodHeader.id)).toBe(true);
    const stockLines = db.prepare(`
      SELECT COUNT(*) AS n FROM journal_lines WHERE journal_entry_id = ?
    `).get(stockHeaderId) as { n: number };
    expect(stockLines.n).toBe(2);
  });

  it('migrates line-less legacy entries with balanced lines', () => {
    db.prepare(`
      INSERT INTO journal_entries (reference_type, reference_id, entry_date,
        description, debit_account, credit_account, amount) VALUES
        ('stock_adjustment', 60, '2026-01-03', 'legacy adj', 'inventory_shrinkage', 'inventory_asset', 55)
    `).run();

    runBackfillGlUnification(db);

    const legacyId = (db.prepare(`
      SELECT id FROM journal_entries WHERE reference_id = 60
    `).get() as { id: number }).id;
    const lines = db.prepare(`
      SELECT account_id, debit, credit, voided FROM journal_lines
      WHERE journal_entry_id = ? ORDER BY id
    `).all(legacyId) as Array<{ account_id: number; debit: number; credit: number; voided: number }>;
    expect(lines).toHaveLength(2);
    expect(lines[0].account_id).toBe(5);
    expect(lines[0].debit).toBe(55);
    expect(lines[1].account_id).toBe(3);
    expect(lines[1].credit).toBe(55);
    expect(lines.every(l => l.voided === 0)).toBe(true);
  });

  it('copies the voided flag and is idempotent', () => {
    db.prepare(`
      INSERT INTO journal_entries (reference_type, reference_id, entry_date,
        description, debit_account, credit_account, amount, voided) VALUES
        ('stock_adjustment', 70, '2026-01-04', 'voided legacy', 'inventory_shrinkage', 'inventory_asset', 33, 1)
    `).run();

    runBackfillGlUnification(db);

    const before = db.prepare(`SELECT COUNT(*) AS n FROM journal_lines`).get() as { n: number };
    expect(before.n).toBe(2);
    const voidedLines = db.prepare(`SELECT voided FROM journal_lines`).all() as Array<{ voided: number }>;
    expect(voidedLines.every(l => l.voided === 1)).toBe(true);

    runBackfillGlUnification(db);
    const after = db.prepare(`SELECT COUNT(*) AS n FROM journal_lines`).get() as { n: number };
    expect(after.n).toBe(2);
    expect(countBroken(db)).toBe(0);
  });
});
