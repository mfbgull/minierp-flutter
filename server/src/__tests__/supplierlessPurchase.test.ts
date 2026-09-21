/**
 * H12 — Prevent or correct supplier-less credit purchases.
 *
 * A direct purchase with no supplier used to post Dr Inventory /
 * Cr 2000 (Accounts Payable) unconditionally while the supplier-ledger
 * write was gated on a resolved supplier. The AP liability it created
 * had no subledger row and could never be settled — every payment is
 * supplier-keyed and `payments` enforces exactly one counterparty.
 *
 * Intended rule (schema + purchase UI + docs/DESIGN.md): a purchase
 * without a supplier is an *immediate* (counter / walk-in) purchase.
 * It must credit the cash account, never AP. A linked purchase keeps
 * the credit (AP) model and posts the supplier ledger entry.
 */
import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';
import PurchaseModel from '../models/Purchase';
import SupplierLedgerModel from '../models/SupplierLedger';

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
  const cols = db.prepare(`SELECT name FROM pragma_table_info('suppliers')`).all() as Array<{ name: string }>;
  if (!cols.some((c) => c.name === 'current_balance')) {
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
    db.exec('ALTER TABLE stock_movements ADD COLUMN expiry_date DATE');
    db.exec('ALTER TABLE stock_batches ADD COLUMN expiry_date DATE');
  }
  db.pragma('foreign_keys = ON');

  db.prepare(`INSERT INTO users (username,email,password_hash,full_name,role,is_active)
              VALUES ('u','e@x.c','h','U','admin',1)`).run();
  db.prepare(`INSERT INTO suppliers (supplier_code,supplier_name,is_active)
              VALUES ('S1','Acme',1)`).run();
  return db;
}

function ensureWarehouse(db: Database.Database): void {
  const has = db.prepare('SELECT COUNT(*) n FROM warehouses').get() as { n: number };
  if (!has.n) {
    db.prepare(`INSERT INTO warehouses (warehouse_code,warehouse_name,is_active)
                VALUES ('W1','Main',1)`).run();
  }
}

function seedItem(db: Database.Database, id: number, name: string): void {
  db.prepare(`INSERT INTO items (id,item_code,item_name,unit_of_measure,standard_cost,is_purchased,is_active)
              VALUES (?, ?, ?, 'Nos', 0, 1, 1)`).run(id, `C${id}`, name);
}

/** Debit/credit totals for one account code, active lines only. */
function glTotals(db: Database.Database, code: string): { debit: number; credit: number } {
  const row = db.prepare(`
    SELECT COALESCE(SUM(jl.debit),0) debit, COALESCE(SUM(jl.credit),0) credit
    FROM journal_lines jl
    JOIN chart_of_accounts a ON a.id = jl.account_id
    WHERE a.code = ? AND jl.voided = 0
  `).get(code) as { debit: number; credit: number };
  return { debit: Number(row.debit), credit: Number(row.credit) };
}

describe('H12 — supplier-less purchases are immediate (cash), not credit', () => {
  it('a purchase WITHOUT a supplier credits Cash, never Accounts Payable', () => {
    const db = createFixture();
    ensureWarehouse(db);
    seedItem(db, 9001, 'Walk-in Item');

    const purchase = PurchaseModel.recordPurchase({
      item_id: 9001,
      warehouse_id: 1,
      quantity: 5,
      unit_cost: 20,
      purchase_date: '2026-09-01',
    }, 1, db);

    expect(purchase.total_cost).toBe(100);
    // No supplier linked (NULL column → no one to owe).
    expect(purchase.supplier_id).toBeFalsy();

    // No supplier ledger row exists — there is no one to owe.
    const ledgerRows = db.prepare(
      `SELECT COUNT(*) n FROM supplier_ledger WHERE reference_no = ?`
    ).get(purchase.purchase_no) as { n: number };
    expect(ledgerRows.n).toBe(0);

    // GL: Dr 1200 Inventory 100 / Cr 1000 Cash 100. AP untouched.
    const lines = db.prepare(`
      SELECT a.code, jl.debit, jl.credit
      FROM journal_lines jl JOIN chart_of_accounts a ON a.id = jl.account_id
      WHERE jl.reference_type = 'PURCHASE' AND jl.reference_id = ? AND jl.voided = 0
    `).all(purchase.id) as Array<{ code: string; debit: number; credit: number }>;

    const byCode: Record<string, { debit: number; credit: number }> = {};
    for (const l of lines) {
      byCode[l.code] = { debit: Number(l.debit), credit: Number(l.credit) };
    }
    expect(byCode['1200'].debit).toBeCloseTo(100, 2);
    expect(byCode['1000'].credit).toBeCloseTo(100, 2);
    expect(byCode['2000']).toBeUndefined();

    // Whole-ledger check: AP balance stays at zero for this purchase.
    const ap = glTotals(db, '2000');
    expect(ap.credit).toBe(0);
    const cash = glTotals(db, '1000');
    expect(cash.credit).toBeCloseTo(100, 2);
    db.close();
  });

  it('a purchase WITH a supplier keeps the credit model: Cr AP + supplier ledger', () => {
    const db = createFixture();
    ensureWarehouse(db);
    seedItem(db, 9002, 'Supplied Item');

    const purchase = PurchaseModel.recordPurchase({
      item_id: 9002,
      warehouse_id: 1,
      quantity: 4,
      unit_cost: 25,
      purchase_date: '2026-09-01',
      supplier_id: 1,
    }, 1, db);

    expect(purchase.supplier_id).toBe(1);
    expect(purchase.total_cost).toBe(100);

    // Supplier AP subledger row written and balance owing.
    const entry = SupplierLedgerModel.getTransactions(1, db).find(
      (e) => e.transaction_type === 'PURCHASE' && e.reference_no === purchase.purchase_no
    );
    expect(entry).toBeDefined();
    expect(Number(entry?.debit)).toBeCloseTo(100, 2);
    expect(SupplierLedgerModel.getBalance(1, db)).toBeCloseTo(100, 2);

    // GL: Dr 1200 / Cr 2000 AP. Cash untouched.
    const lines = db.prepare(`
      SELECT a.code, jl.debit, jl.credit
      FROM journal_lines jl JOIN chart_of_accounts a ON a.id = jl.account_id
      WHERE jl.reference_type = 'PURCHASE' AND jl.reference_id = ? AND jl.voided = 0
    `).all(purchase.id) as Array<{ code: string; debit: number; credit: number }>;
    const byCode: Record<string, { debit: number; credit: number }> = {};
    for (const l of lines) {
      byCode[l.code] = { debit: Number(l.debit), credit: Number(l.credit) };
    }
    expect(byCode['1200'].debit).toBeCloseTo(100, 2);
    expect(byCode['2000'].credit).toBeCloseTo(100, 2);
    expect(byCode['1000']).toBeUndefined();
    db.close();
  });

  it('a mixed multi-item batch splits correctly: linked lines on AP, supplier-less lines on cash', () => {
    const db = createFixture();
    ensureWarehouse(db);
    seedItem(db, 9101, 'Batch Linked');
    seedItem(db, 9102, 'Batch Walk-in');

    const created = PurchaseModel.recordPurchaseMulti({
      warehouse_id: 1,
      purchase_date: '2026-09-02',
      supplier_id: 1,
      items: [
        { item_id: 9101, quantity: 2, unit_cost: 50 }, // 100 → AP
      ],
    }, 1, db);
    const walkIn = PurchaseModel.recordPurchaseMulti({
      warehouse_id: 1,
      purchase_date: '2026-09-02',
      items: [
        { item_id: 9102, quantity: 1, unit_cost: 30 }, // 30 → cash
      ],
    }, 1, db);

    const linked = created[0];
    expect(linked.supplier_id).toBe(1);
    expect(walkIn[0].supplier_id).toBeFalsy();

    const codeOf = (purchaseId: number, side: 'debit' | 'credit') =>
      (db.prepare(`
        SELECT a.code
        FROM journal_lines jl JOIN chart_of_accounts a ON a.id = jl.account_id
        WHERE jl.reference_type = 'PURCHASE' AND jl.reference_id = ? AND jl.voided = 0
          AND jl.${side} > 0
      `).all(purchaseId) as Array<{ code: string }>).map((r) => r.code);

    expect(codeOf(linked.id, 'credit')).toContain('2000');
    expect(codeOf(linked.id, 'credit')).not.toContain('1000');
    expect(codeOf(walkIn[0].id, 'credit')).toContain('1000');
    expect(codeOf(walkIn[0].id, 'credit')).not.toContain('2000');

    // Ledger totals reconcile: AP owes exactly the linked amount.
    expect(SupplierLedgerModel.getBalance(1, db)).toBeCloseTo(100, 2);
    expect(glTotals(db, '2000').credit).toBeCloseTo(100, 2);
    expect(glTotals(db, '1000').credit).toBeCloseTo(30, 2);
    db.close();
  });

  it('voiding a supplier-less purchase reverses the cash credit and leaves no residue', () => {
    const db = createFixture();
    ensureWarehouse(db);
    seedItem(db, 9201, 'Void Walk-in');

    const purchase = PurchaseModel.recordPurchase({
      item_id: 9201,
      warehouse_id: 1,
      quantity: 3,
      unit_cost: 10,
      purchase_date: '2026-09-03',
    }, 1, db);

    expect(glTotals(db, '1000').credit).toBeCloseTo(30, 2);

    const voided = PurchaseModel.void(purchase.id, 1, 'wrong supplier-less entry', db);
    expect(voided).toBe(true);

    // The GL entry is reversed — cash credit gone, and no AP was ever created.
    expect(glTotals(db, '1000').credit).toBeCloseTo(0, 2);
    expect(glTotals(db, '2000').credit).toBeCloseTo(0, 2);
    expect(glTotals(db, '1200').debit).toBeCloseTo(0, 2);

    // No supplier ledger row to orphan.
    const ledgerRows = db.prepare(
      `SELECT COUNT(*) n FROM supplier_ledger WHERE reference_no = ?`
    ).get(purchase.purchase_no) as { n: number };
    expect(ledgerRows.n).toBe(0);
    db.close();
  });

  it('an immediate purchase still posts stock, batch and movement side effects', () => {
    const db = createFixture();
    ensureWarehouse(db);
    seedItem(db, 9301, 'Cash Stock Item');

    const purchase = PurchaseModel.recordPurchase({
      item_id: 9301,
      warehouse_id: 1,
      quantity: 6,
      unit_cost: 5,
      purchase_date: '2026-09-04',
    }, 1, db);

    // Stock landed, one batch, one financially-posted movement.
    const stock = db.prepare('SELECT current_stock n FROM items WHERE id = 9301').get() as { n: number };
    expect(Number(stock.n)).toBe(6);

    const batch = db.prepare(
      `SELECT quantity_original qo, quantity_remaining qr FROM stock_batches
       WHERE source_type = 'PURCHASE' AND source_id = ?`
    ).get(purchase.id) as { qo: number; qr: number };
    expect(Number(batch.qo)).toBe(6);
    expect(Number(batch.qr)).toBe(6);

    const movement = db.prepare(`
      SELECT COUNT(*) n, COALESCE(SUM(financial_posted),0) posted
      FROM stock_movements WHERE movement_type = 'PURCHASE' AND reference_docno = ?
    `).get(purchase.purchase_no) as { n: number; posted: number };
    expect(movement.n).toBe(1);
    expect(movement.posted).toBe(1);
    db.close();
  });
});
