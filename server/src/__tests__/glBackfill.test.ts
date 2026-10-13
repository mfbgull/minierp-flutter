/**
 * reporting-search-remediation — GL backfill + per-line tax decomposition.
 *
 * Covers tasks 0.6 / 1.4: pre-posting documents (direct purchase, supplier
 * payment, expense, customer payment, opening capital) get balanced
 * journal_lines entries; the migration is idempotent; the table foots;
 * invoice_items amounts decompose into net_amount + tax_amount.
 */
import Database from 'better-sqlite3';
import { runBackfillGlPreposting } from '../migrations/backfillGlPreposting';
import { runBackfillInvoiceItemTax } from '../migrations/backfillInvoiceItemTax';
import { createFixtureDb, cleanupFixtureDbs } from './helpers/productionSchema';

afterAll(() => cleanupFixtureDbs());

/** createFixtureDb() clones schema only, so the accounts add-gl-foundation.sql
 * seeds as DATA are absent. These backfills post against account codes. */
function seedChartOfAccounts(db: Database.Database): void {
  db.exec(`
    INSERT OR IGNORE INTO chart_of_accounts (code, name, type, normal_balance, text_code, description) VALUES
      ('1000', 'Cash', 'asset', 'debit', 'cash', 'On-hand cash'),
      ('1010', 'Bank', 'asset', 'debit', 'bank', 'Bank balances'),
      ('1020', 'Easypaisa / Mobile Wallet', 'asset', 'debit', 'easypaisa', 'Easypaisa / mobile wallet balances'),
      ('1030', 'JazzCash', 'asset', 'debit', 'jazzcash', 'JazzCash wallet balances'),
      ('1040', 'UPaisa', 'asset', 'debit', 'upaisa', 'UPaisa wallet balances'),
      ('1100', 'Accounts Receivable', 'asset', 'debit', 'accounts_receivable', 'Customer balances'),
      ('1110', 'Customer Credit', 'asset', 'credit', 'customer_credit', 'Customer credit balances'),
      ('1200', 'Inventory Asset', 'asset', 'debit', 'inventory_asset', 'On-hand inventory at cost'),
      ('1300', 'Employee Loan Receivable', 'asset', 'debit', 'employee_loan_receivable', 'Loans advanced to employees'),
      ('2000', 'Accounts Payable', 'liability', 'credit', 'accounts_payable', 'Supplier balances'),
      ('2100', 'Tax Payable', 'liability', 'credit', 'tax_payable', 'Sales tax collected'),
      ('3000', 'Owner''s Equity', 'equity', 'credit', 'owners_equity', 'Capital contributions'),
      ('3100', 'Retained Earnings', 'equity', 'credit', 'opening_retained_earnings', 'Cumulative profit/loss carried forward'),
      ('3200', 'Owner Capital', 'equity', 'credit', 'owner_capital', 'Cash contributed by the owner'),
      ('3300', 'Owner Drawings', 'equity', 'debit', 'owner_drawings', 'Cash/goods taken by the owner (contra-equity)'),
      ('4000', 'Sales Revenue', 'revenue', 'credit', 'sales_revenue', 'Revenue from invoices and POS'),
      ('4100', 'Sales Returns', 'revenue', 'debit', 'sales_returns', 'Contra-revenue: returned/credited sales'),
      ('4150', 'Restocking Fee Income', 'revenue', 'credit', 'restocking_fee_income', 'Fees charged on returned items'),
      ('5000', 'Cost of Goods Sold', 'expense', 'debit', 'cogs', 'Cost of items sold'),
      ('6000', 'Operating Expenses', 'expense', 'debit', 'operating_expenses', 'General operating costs'),
      ('6100', 'Wages & Salaries', 'expense', 'debit', 'wages_salaries', 'Payroll'),
      ('6300', 'Loan Write-off', 'expense', 'debit', 'loan_write_off', 'Employee loans written off / forgiven'),
      ('7000', 'Production Clearing', 'expense', 'debit', 'production_clearing', 'Clearing account for production cost flow'),
      ('7100', 'Inventory Correction', 'expense', 'debit', 'inventory_correction', 'Adjustments adding to inventory'),
      ('7200', 'Inventory Shrinkage', 'expense', 'debit', 'inventory_shrinkage', 'Losses / removals from inventory'),
      ('7201', 'Expired Goods Loss', 'expense', 'debit', 'expired_goods_loss', 'Written-off expired stock (write-off endpoint)'),
      ('7202', 'Damaged Goods Loss', 'expense', 'debit', 'damaged_goods_loss', 'Written-off damaged stock'),
      ('7203', 'Stock Shortage Loss', 'expense', 'debit', 'stock_shortage_loss', 'Physical count shortages written off'),
      ('7204', 'Obsolete Stock Loss', 'expense', 'debit', 'obsolete_stock_loss', 'Written-off obsolete stock')
  `);
}

function insertItem(db: Database.Database, code: string): number {
  db.prepare(`INSERT INTO items (item_code,item_name,unit_of_measure,standard_cost,is_purchased,is_active)
              VALUES (?, 'Thing', 'Nos', 50, 1, 1)`).run(code);
  return (db.prepare(`SELECT id FROM items WHERE item_code = ?`).get(code) as { id: number }).id;
}

function createFixture(): Database.Database {
  const db = createFixtureDb();
  seedChartOfAccounts(db);
  db.prepare(`INSERT INTO users (username,email,password_hash,full_name,role,is_active)
              VALUES ('u','e@x.c','h','U','admin',1)`).run();
  db.prepare(`INSERT INTO customers (customer_code,customer_name,is_active)
              VALUES ('C1','Cust',1)`).run();
  return db;
}

function footing(db: Database.Database): { d: number; c: number } {
  return db.prepare(
    `SELECT COALESCE(SUM(debit),0) d, COALESCE(SUM(credit),0) c FROM journal_lines WHERE voided = 0`
  ).get() as { d: number; c: number };
}

describe('GL backfill for pre-posting documents', () => {
  it('posts balanced entries for purchase, payments and expenses plus opening capital', () => {
    const db = createFixture();
    const itemId = insertItem(db, 'IT-X');
    db.prepare(`INSERT INTO suppliers (supplier_code,supplier_name,is_active) VALUES ('S1','Acme',1)`).run();
    db.prepare(`INSERT INTO warehouses (warehouse_code,warehouse_name,is_active) VALUES ('W1','Main',1)`).run();
    const whId = (db.prepare(`SELECT id FROM warehouses WHERE warehouse_code='W1'`).get() as { id: number }).id;

    db.prepare(`INSERT INTO purchases (
        purchase_no, item_id, warehouse_id, quantity, unit_cost, total_cost,
        supplier_id, purchase_date, created_by
      ) VALUES ('PURCH-X', ?, ?, 10, 50, 500, 1, '2026-08-01', 1)`).run(itemId, whId);
    db.prepare(`INSERT INTO payments (payment_no, supplier_id, payment_date, amount, payment_method, created_by)
                VALUES ('PAY-S1', 1, '2026-08-20', 300, 'Cash', 1)`).run();
    db.prepare(`INSERT INTO payments (payment_no, customer_id, payment_date, amount, payment_method, created_by)
                VALUES ('PAY-C1', 1, '2026-08-21', 100, 'Easypaisa', 1)`).run();
    db.prepare(`INSERT INTO expenses (expense_no, expense_category, amount, expense_date, status, payment_method, created_by)
                VALUES ('EXP-X', 'Meals', 40, '2026-08-22', 'Recorded', 'Cash', 1)`).run();
    db.prepare(`INSERT INTO opening_balances (account_key, amount) VALUES ('cash', 5000)
                ON CONFLICT(account_key) DO UPDATE SET amount = 5000`).run();

    runBackfillGlPreposting(db);

    const byRef = (t: string): number =>
      (db.prepare(`SELECT COUNT(*) n FROM journal_lines WHERE reference_type = ? AND voided = 0`).get(t) as { n: number }).n;
    expect(byRef('PURCHASE')).toBe(2);       // Dr 1200 / Cr 2000
    expect(byRef('PAYMENT')).toBe(4);        // supplier + customer entries
    expect(byRef('EXPENSE')).toBe(2);        // Dr 6000 / Cr 1000
    expect(byRef('BACKFILL_OPENING')).toBe(2); // Dr 1000 / Cr 3000

    const f = footing(db);
    expect(Math.abs(f.d - f.c)).toBeLessThan(0.01);

    // Per-method GL balances: customer payment arrived via Easypaisa.
    const balFor = (code: string): number =>
      (db.prepare(`
        SELECT COALESCE(SUM(jl.debit - jl.credit), 0) bal
        FROM journal_lines jl JOIN chart_of_accounts coa ON coa.id = jl.account_id
        WHERE coa.code = ? AND jl.voided = 0
      `).get(code) as { bal: number }).bal;
    expect(balFor('1000')).toBeCloseTo(5000 - 300 - 40, 2); // opening − supplier − expense
    expect(balFor('1020')).toBeCloseTo(100, 2);             // easypaisa receipt
    db.close();
  });

  it('is idempotent — a second run inserts nothing', () => {
    const db = createFixture();
    const itemId2 = insertItem(db, 'IT-Y');
    db.prepare(`INSERT INTO warehouses (warehouse_code,warehouse_name,is_active) VALUES ('W1','Main',1)`).run();
    const whId2 = (db.prepare(`SELECT id FROM warehouses WHERE warehouse_code='W1'`).get() as { id: number }).id;
    db.prepare(`INSERT INTO purchases (
        purchase_no, item_id, warehouse_id, quantity, unit_cost, total_cost,
        supplier_name, purchase_date, created_by
      ) VALUES ('PURCH-Y', ?, ?, 1, 10, 10, 'Cash Vendor', '2026-08-01', 1)`).run(itemId2, whId2);

    runBackfillGlPreposting(db);
    const first = footing(db);
    runBackfillGlPreposting(db);
    expect(footing(db)).toEqual(first);
    db.close();
  });
});

describe('invoice item tax decomposition backfill', () => {
  it('decomposes a tax-inclusive line and leaves zero-rate lines alone', () => {
    const db = createFixture();
    db.prepare(`INSERT INTO invoices (invoice_no, customer_id, invoice_date, total_amount, created_by)
                VALUES ('INV-A', 1, '2026-08-01', 110, 1)`).run();
    const invId = (db.prepare(`SELECT id FROM invoices WHERE invoice_no='INV-A'`).get() as { id: number }).id;
    const itemId3 = insertItem(db, 'IT-Z');

    // qty 1 @ 100 with 10% tax → stored amount 110 (inclusive).
    db.prepare(`INSERT INTO invoice_items (invoice_id, item_id, quantity, unit_price, amount, tax_rate)
                VALUES (?, ?, 1, 100, 110, 10)`).run(invId, itemId3);
    // Zero-tax line stays as-is.
    db.prepare(`INSERT INTO invoice_items (invoice_id, item_id, quantity, unit_price, amount, tax_rate)
                VALUES (?, ?, 2, 50, 100, 0)`).run(invId, itemId3);

    runBackfillInvoiceItemTax(db);

    const rows = db.prepare(`SELECT amount, net_amount, tax_amount FROM invoice_items ORDER BY id`).all() as Array<{
      amount: number; net_amount: number; tax_amount: number;
    }>;
    expect(rows[0].tax_amount).toBe(10);
    expect(rows[0].net_amount).toBe(100);
    expect(rows[0].net_amount + rows[0].tax_amount).toBeCloseTo(rows[0].amount, 2);
    expect(rows[1].tax_amount).toBe(0);
    expect(rows[1].net_amount).toBe(rows[1].amount);
    db.close();
  });
});
