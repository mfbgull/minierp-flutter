import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';
import ReportsModel from '../models/Reports';

const MIGRATIONS = [
  'init.sql',
  'add-purchases-table.sql',
  'add-purchase-return-fields.sql',
  'add-batch-costing.sql',
  'add-stock-adjustment-financial.sql',
  'create-supplier-ledger.sql',
  'add-gl-foundation.sql',
  'create-customer-ledger.sql',
  'add-gl-void-attribution.sql',
  'add-purchase-returns-tables.sql',
  'create-payment-allocations.sql',
  'add-supplier-payment-support.sql',
  'add-purchase-supplier-payment.sql',
  'add-salary-payments.sql',
  'add-cash-accounts.sql',
  'add-payment-salary-void-columns.sql',
];

function createFixture(): Database.Database {
  const db = new Database(':memory:');
  db.pragma('foreign_keys = ON');
  for (const f of MIGRATIONS) {
    db.exec(fs.readFileSync(path.join(__dirname, '..', 'migrations', f), 'utf8'));
  }

  const supCols = db.prepare(`SELECT name FROM pragma_table_info('suppliers')`).all() as { name: string }[];
  if (!supCols.some((c) => c.name === 'current_balance')) {
    db.exec('ALTER TABLE suppliers ADD COLUMN current_balance DECIMAL(15,2) DEFAULT 0');
  }

  db.prepare(`INSERT INTO users (username,email,password_hash,full_name,role,is_active)
              VALUES ('u','e@x.c','h','U','admin',1)`).run();
  db.prepare(`INSERT INTO suppliers (supplier_code,supplier_name,is_active,current_balance)
              VALUES ('S1','Acme',1,0)`).run();
  return db;
}

type LedgerRow = {
  supplier_id: number; transaction_date: string; transaction_type: string;
  reference_no: string; debit: number; credit: number; description: string;
};

let seq = 0;
function post(db: Database.Database, r: Omit<LedgerRow, 'supplier_id'>): number {
  seq += 1;
  return db.prepare(`
    INSERT INTO supplier_ledger (supplier_id, transaction_date, transaction_type, reference_no,
      debit, credit, balance, description)
    VALUES (1, ?, ?, ?, ?, ?, 0, ?)
  `).run(r.transaction_date, r.transaction_type, r.reference_no, r.debit, r.credit, r.description)
    .lastInsertRowid as number;
}

/** The authoritative AP position: invariant D's own expression. */
function trueAp(db: Database.Database): number {
  const row = db.prepare(`
    SELECT COALESCE(SUM(debit) - SUM(credit), 0) AS net FROM supplier_ledger
    WHERE voided = 0 AND reversed_by IS NULL
  `).get() as { net: number };
  return Number(row.net);
}

const setBalance = (db: Database.Database, v: number) =>
  db.prepare('UPDATE suppliers SET current_balance = ? WHERE id = 1').run(v);

const aging = (db: Database.Database, asOf = '2026-12-31') =>
  ReportsModel.getAPAgingReport(asOf, db);

const totalPayables = (db: Database.Database, asOf = '2026-12-31'): number => {
  const r = aging(db, asOf) as unknown as { summary: { totalPayables: number } };
  return r.summary.totalPayables;
};

describe('PUR-002 — AP aging must not double-count reversal credits', () => {
  it('a voided purchase leaves the correct AP', () => {
    const db = createFixture();
    post(db, { transaction_date: '2026-01-05', transaction_type: 'PURCHASE', reference_no: 'P1', debit: 100, credit: 0, description: 'p1' });
    post(db, { transaction_date: '2026-01-06', transaction_type: 'PURCHASE', reference_no: 'P2', debit: 200, credit: 0, description: 'p2' });

    // Void P1 the way ledgerUtils does: the original is marked voided, and an
    // equal-and-opposite REVERSAL row is appended referencing it.
    const original = db.prepare(
      `SELECT id FROM supplier_ledger WHERE reference_no = 'P1' AND voided = 0`,
    ).get() as { id: number };
    db.prepare('UPDATE supplier_ledger SET voided = 1 WHERE id = ?').run(original.id);
    const reversalId = post(db, {
      transaction_date: '2026-01-05', transaction_type: 'REVERSAL:PURCHASE',
      reference_no: 'P1', debit: 0, credit: 100, description: 'reversal',
    });
    db.prepare('UPDATE supplier_ledger SET reversed_by = ? WHERE id = ?').run(original.id, reversalId);

    // True position: only P2 remains.
    setBalance(db, trueAp(db));
    expect(trueAp(db)).toBe(200);

    expect(totalPayables(db)).toBe(200);
    db.close();
  });

  it('voiding the only purchase reports zero, not a credit', () => {
    const db = createFixture();
    post(db, { transaction_date: '2026-01-05', transaction_type: 'PURCHASE', reference_no: 'P1', debit: 300, credit: 0, description: 'p1' });

    const original = db.prepare(`SELECT id FROM supplier_ledger WHERE reference_no = 'P1' AND voided = 0`).get() as { id: number };
    db.prepare('UPDATE supplier_ledger SET voided = 1 WHERE id = ?').run(original.id);
    const revId = post(db, {
      transaction_date: '2026-01-05', transaction_type: 'REVERSAL:PURCHASE',
      reference_no: 'P1', debit: 0, credit: 300, description: 'reversal',
    });
    db.prepare('UPDATE supplier_ledger SET reversed_by = ? WHERE id = ?').run(original.id, revId);

    setBalance(db, trueAp(db));
    expect(trueAp(db)).toBe(0);
    expect(totalPayables(db)).toBe(0);
    db.close();
  });

  it('a real credit note is still counted', () => {
    const db = createFixture();
    post(db, { transaction_date: '2026-01-05', transaction_type: 'PURCHASE', reference_no: 'P1', debit: 500, credit: 0, description: 'p1' });
    post(db, { transaction_date: '2026-02-01', transaction_type: 'PURCHASE_RETURN', reference_no: 'R1', debit: 0, credit: 200, description: 'credit note' });

    setBalance(db, trueAp(db));
    expect(trueAp(db)).toBe(300);
    expect(totalPayables(db)).toBe(300);
    db.close();
  });

  it('reported AP ties to suppliers.current_balance after several voids', () => {
    const db = createFixture();
    post(db, { transaction_date: '2026-01-05', transaction_type: 'PURCHASE', reference_no: 'P1', debit: 100, credit: 0, description: 'p1' });
    post(db, { transaction_date: '2026-01-06', transaction_type: 'PURCHASE', reference_no: 'P2', debit: 200, credit: 0, description: 'p2' });
    post(db, { transaction_date: '2026-01-07', transaction_type: 'PURCHASE', reference_no: 'P3', debit: 300, credit: 0, description: 'p3' });

    for (const ref of ['P1', 'P3']) {
      const original = db.prepare(`SELECT id FROM supplier_ledger WHERE reference_no = ? AND voided = 0`).get(ref) as { id: number };
      db.prepare('UPDATE supplier_ledger SET voided = 1 WHERE id = ?').run(original.id);
      const revId = post(db, {
        transaction_date: '2026-01-06', transaction_type: `REVERSAL:${ref}`,
        reference_no: ref, debit: 0, credit: original.id === 1 ? 100 : 300, description: 'rev',
      });
      db.prepare('UPDATE supplier_ledger SET reversed_by = ? WHERE id = ?').run(original.id, revId);
    }

    setBalance(db, trueAp(db));
    expect(trueAp(db)).toBe(200);
    expect(totalPayables(db)).toBe(200);
    db.close();
  });
});

describe('PUR-006 — AP aging honours the as-of date on both sides', () => {
  it('a purchase dated after the as-of date is excluded', () => {
    const db = createFixture();
    post(db, { transaction_date: '2026-01-05', transaction_type: 'PURCHASE', reference_no: 'P1', debit: 500, credit: 0, description: 'p1' });
    post(db, { transaction_date: '2031-01-01', transaction_type: 'PURCHASE', reference_no: 'P2', debit: 500, credit: 0, description: 'future' });

    setBalance(db, trueAp(db));

    // As of end of 2026 the future purchase must not appear.
    expect(totalPayables(db, '2026-12-31')).toBe(500);
    // As of 2031 it does.
    expect(totalPayables(db, '2031-12-31')).toBe(1000);
    db.close();
  });

  it('a credit dated after the as-of date does not reduce an earlier figure', () => {
    const db = createFixture();
    post(db, { transaction_date: '2026-01-05', transaction_type: 'PURCHASE', reference_no: 'P1', debit: 500, credit: 0, description: 'p1' });
    post(db, { transaction_date: '2027-06-01', transaction_type: 'PURCHASE_RETURN', reference_no: 'R1', debit: 0, credit: 200, description: 'later credit' });

    setBalance(db, trueAp(db));

    // Both sides must be filtered, or the future credit silently shrinks 2026.
    expect(totalPayables(db, '2026-12-31')).toBe(500);
    db.close();
  });
});