/**
 * PUR-001 / C-05 — a reversal voids the original entry; it never posts a second.
 *
 * `Purchase.void` and `invoiceReturnService.voidReturn` both void the document's
 * own GL group and then request a *further* inventory effect through
 * `recordMovement({ movement_type: 'ADJUSTMENT' })`. Every ADJUSTMENT routes to
 * `postFinancialEntryForAdjustment`, which posts `Dr 7200 / Cr 1200` for a
 * removal. So voiding produces a second inventory credit on top of the voided
 * original, plus a shrinkage expense that never happened.
 *
 * The create-side twins get this right — `Invoice.ts` and `PurchaseReturn.ts`
 * both pass `skipAdjustmentFinancialPosting: true`.
 */
import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';

// `ledgerUtils` is bound to the shared global database (config/database), so
// `Purchase.void`'s supplier-ledger reversal cannot run against an in-memory
// fixture. That reversal is covered elsewhere — models.test.ts:793 asserts the
// supplier balance returns to 0 after a successful void. Stubbing it here
// isolates the GL behaviour, which is what PUR-001 is about.
jest.mock('../utils/ledgerUtils', () => ({
  __esModule: true,
  default: {
    reverseLedgerEntry: jest.fn(() => 0),
  },
}));

import PurchaseModel from '../models/Purchase';

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
  'add-expenses-table.sql',
  'add-salary-payments.sql',
  'add-cash-accounts.sql',
  'add-opening-balances.sql',
  'add-purchase-void-columns.sql',
  'add-purchase-return-batches.sql',
  'add-payment-salary-void-columns.sql',
];

function createFixture(): Database.Database {
  const db = new Database(':memory:');
  db.pragma('foreign_keys = ON');
  for (const f of MIGRATIONS) {
    db.exec(fs.readFileSync(path.join(__dirname, '..', 'migrations', f), 'utf8'));
  }
  db.pragma('foreign_keys = OFF');

  const supCols = db.prepare(`SELECT name FROM pragma_table_info('suppliers')`).all() as Array<{ name: string }>;
  if (!supCols.some((c) => c.name === 'current_balance')) {
    db.exec('ALTER TABLE suppliers ADD COLUMN current_balance DECIMAL(15,2) DEFAULT 0');
  }
  const purCols = db.prepare(`SELECT name FROM pragma_table_info('purchases')`).all() as Array<{ name: string }>;
  if (!purCols.some((c) => c.name === 'batch_id')) {
    db.exec('ALTER TABLE purchases ADD COLUMN batch_id INTEGER REFERENCES stock_batches(id)');
    db.exec('ALTER TABLE purchases ADD COLUMN batch_no TEXT');
  }
  const smCols = db.prepare(`SELECT name FROM pragma_table_info('stock_movements')`).all() as Array<{ name: string }>;
  if (!smCols.some((c) => c.name === 'batch_id')) {
    db.exec('ALTER TABLE stock_movements ADD COLUMN batch_id INTEGER REFERENCES stock_batches(id)');
  }
  if (!smCols.some((c) => c.name === 'journal_entry_id')) {
    db.exec('ALTER TABLE stock_movements ADD COLUMN journal_entry_id INTEGER REFERENCES journal_entries(id)');
  }
  const sbCols = db.prepare(`SELECT name FROM pragma_table_info('stock_batches')`).all() as Array<{ name: string }>;
  if (!sbCols.some((c) => c.name === 'expiry_date')) {
    db.exec('ALTER TABLE stock_batches ADD COLUMN expiry_date DATE');
  }
  db.pragma('foreign_keys = ON');

  db.prepare(`INSERT INTO users (username,email,password_hash,full_name,role,is_active)
              VALUES ('u','e@x.c','h','U','admin',1)`).run();
  db.prepare(`INSERT INTO suppliers (supplier_code,supplier_name,is_active)
              VALUES ('S1','Acme',1)`).run();
  db.prepare(`INSERT INTO warehouses (id,warehouse_code,warehouse_name,is_active)
              VALUES (1,'W1','Main',1)`).run();
  db.prepare(`INSERT INTO items (id,item_code,item_name,unit_of_measure,standard_cost,is_purchased,is_active)
              VALUES (1,'IT-1','Widget','Nos',999,1,1)`).run();

  return db;
}

function gl(db: Database.Database, code: string): { debit: number; credit: number } {
  const row = db.prepare(`
    SELECT COALESCE(SUM(jl.debit),0) debit, COALESCE(SUM(jl.credit),0) credit
    FROM journal_lines jl JOIN chart_of_accounts a ON a.id = jl.account_id
    WHERE a.code = ? AND jl.voided = 0
  `).get(code) as { debit: number; credit: number };
  return { debit: Number(row.debit), credit: Number(row.credit) };
}

/** Record a real purchase through the model so the GL and batch are genuine. */
function purchase(db: Database.Database, o: { qty?: number; cost?: number; date?: string } = {}): number {
  const created = PurchaseModel.recordPurchase(
    {
      item_id: 1,
      warehouse_id: 1,
      quantity: o.qty ?? 10,
      unit_cost: o.cost ?? 50,
      purchase_date: o.date ?? '2026-08-01',
      supplier_id: 1,
    },
    1,
    db,
  );
  return created.id;
}

describe('PUR-001 — voiding a purchase reverses inventory exactly once', () => {
  it('after void, GL 1200 is zero on BOTH sides and GL 7200 is untouched', () => {
    const db = createFixture();
    const id = purchase(db, { qty: 10, cost: 50 });

    expect(gl(db, '1200')).toEqual({ debit: 500, credit: 0 });
    expect(gl(db, '2000')).toEqual({ debit: 0, credit: 500 });

    PurchaseModel.void(id, 1, 'wrong purchase', db);

    // The void must remove the original Dr 1200 / Cr 2000 group entirely.
    expect(gl(db, '1200')).toEqual({ debit: 0, credit: 0 });
    expect(gl(db, '2000')).toEqual({ debit: 0, credit: 0 });

    // No shrinkage expense may exist: nothing was lost, it was returned to the
    // supplier. This is the assertion the shipped suite never made.
    expect(gl(db, '7200')).toEqual({ debit: 0, credit: 0 });
    db.close();
  });

  it('reversal is dated with the purchase, not with today', () => {
    const db = createFixture();
    const id = purchase(db, { qty: 10, cost: 50, date: '2026-01-15' });

    PurchaseModel.void(id, 1, 'wrong purchase', db);

    const mv = db.prepare(`
      SELECT movement_date, reference_doctype FROM stock_movements
      WHERE reference_doctype = 'PURCHASE_VOID'
    `).get() as { movement_date: string; reference_doctype: string };

    expect(mv).toBeDefined();
    // A reversal belongs to the period being reversed, not to the day the
    // reversal was typed.
    expect(mv.movement_date).toBe('2026-01-15');
    db.close();
  });

  it('the stock_adjustment pair written by the void carries no financial value', () => {
    const db = createFixture();
    const id = purchase(db, { qty: 10, cost: 50 });

    PurchaseModel.void(id, 1, 'wrong purchase', db);

    const mv = db.prepare(`
      SELECT id, financial_value, financial_posted, journal_entry_id
      FROM stock_movements WHERE reference_doctype = 'PURCHASE_VOID'
    `).get() as { id: number; financial_value: number; financial_posted: number; journal_entry_id: number | null };

    expect(mv).toBeDefined();
    expect(mv.financial_posted).toBeFalsy();
    expect(mv.journal_entry_id).toBeNull();
    expect(Number(mv.financial_value)).toBe(0);
    db.close();
  });

  it('stock and the batch end where a plain reversal would put them', () => {
    const db = createFixture();
    const id = purchase(db, { qty: 10, cost: 50 });

    const balBefore = db.prepare(
      'SELECT quantity FROM stock_balances WHERE item_id = 1 AND warehouse_id = 1',
    ).get() as { quantity: number };
    expect(Number(balBefore.quantity)).toBeCloseTo(10, 3);

    PurchaseModel.void(id, 1, 'wrong purchase', db);

    const balAfter = db.prepare(
      'SELECT quantity FROM stock_balances WHERE item_id = 1 AND warehouse_id = 1',
    ).get() as { quantity: number };
    expect(Number(balAfter.quantity)).toBeCloseTo(0, 3);

    // The batch is retained for FK integrity but must not claim residual value.
    const batch = db.prepare(
      'SELECT quantity_remaining FROM stock_batches WHERE source_type = ? AND source_id = ?',
    ).get('PURCHASE', id) as { quantity_remaining: number };
    expect(Number(batch.quantity_remaining)).toBeCloseTo(0, 3);
    db.close();
  });

  it('invariants still hold after the void — proving the gate can see this path', () => {
    const db = createFixture();
    const id = purchase(db, { qty: 10, cost: 50 });
    PurchaseModel.void(id, 1, 'wrong purchase', db);

    // Invariant A: the ledger is balanced even with a phantom 7200, which is
    // exactly why this defect survived. Asserted so a future change that
    // unbalances the void is caught here.
    const diff = db.prepare(`
      SELECT COALESCE(SUM(jl.debit),0) - COALESCE(SUM(jl.credit),0) AS d
      FROM journal_lines jl WHERE jl.voided = 0
    `).get() as { d: number };
    expect(Number(diff.d)).toBeCloseTo(0, 2);
    db.close();
  });
});

describe('CODE-003 — a GL assertion must check the credit side', () => {
  it('the historical single-sided assertion passes on the defective books', () => {
    const db = createFixture();
    const id = purchase(db, { qty: 10, cost: 50 });
    PurchaseModel.void(id, 1, 'wrong purchase', db);

    const totals = gl(db, '1200');

    // The guard shape that shipped in supplierlessPurchase.test.ts:94.
    expect(totals.debit).toBeCloseTo(0, 2);

    // Which is satisfied while a real credit balance sits on a debit-normal
    // asset. Recorded as an explicit demonstration of the vacuous guard.
    db.close();
  });
});
