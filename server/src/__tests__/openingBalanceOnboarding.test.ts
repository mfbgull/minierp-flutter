/**
 * TASK 27 — Opening balance / cash guard onboarding.
 *
 * Fresh shops seed opening_balances at 0, so every cash-out failed with
 * a 500 that hid the real message. The guard must stay intact; the fix
 * is (1) classify Insufficient funds as 400 with actionable guidance
 * and (2) the full onboarding path (opening capital → cash payment →
 * supplier payment → expense) must leave cash and owner-equity GL correct.
 */
import Database from 'better-sqlite3';
import { classifyError } from '../utils/businessRuleError';
import ExpenseModel from '../models/Expense';
import PaymentModel from '../models/Payment';
import OwnerCapitalModel, { generateCapitalNo } from '../models/OwnerCapital';
import AccountingService from '../services/accountingService';
import { saveOpeningBalance, syncOpeningBalancesToGl } from '../services/cashService';
import { createFixtureDb, cleanupFixtureDbs } from './helpers/productionSchema';

afterAll(() => cleanupFixtureDbs());

/** createFixtureDb() clones schema only, so the rows add-gl-foundation.sql and
 * add-opening-balances.sql seed as DATA are absent. The onboarding path asserts
 * on account balances resolved by code (1000 cash, 3000 equity, 3200 capital). */
function seedProductionReferenceData(db: Database.Database): void {
  db.exec(`
    INSERT OR IGNORE INTO opening_balances (account_key, amount) VALUES
      ('cash', 0), ('bank', 0), ('easypaisa', 0), ('jazzcash', 0), ('upaisa', 0);
  `);
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

function createFixture(): Database.Database {
  const db = createFixtureDb();
  seedProductionReferenceData(db);
  db.prepare(`INSERT INTO users (username,email,password_hash,full_name,role,is_active)
              VALUES ('u','e@x.c','h','U','admin',1)`).run();
  db.prepare(`INSERT INTO suppliers (supplier_code,supplier_name,is_active,current_balance)
              VALUES ('S1','Acme',1,0)`).run();
  db.prepare(`INSERT INTO customers (customer_code,customer_name,contact_person)
              VALUES ('C1','Walkin','W')`).run();
  db.prepare(`INSERT INTO items (item_code,item_name,unit_of_measure,standard_cost,is_purchased,is_active)
              VALUES ('IT-A','Widget','Nos',20,1,1)`).run();
  db.prepare(`INSERT INTO warehouses (warehouse_code,warehouse_name,is_active)
              VALUES ('W1','Main',1)`).run();
  return db;
}

function seedPurchase(db: Database.Database, totalCost: number): number {
  db.prepare(`
    INSERT INTO purchases (purchase_no, item_id, warehouse_id, quantity, unit_cost, total_cost,
                           purchase_date, supplier_id, created_by)
    VALUES (?, 1, 1, 1, ?, ?, '2026-09-01', 1, 1)
  `).run(`PUR-OB-${Math.floor(Math.random() * 1e6)}`, totalCost, totalCost);
  return (db.prepare('SELECT id FROM purchases ORDER BY id DESC LIMIT 1').get() as { id: number }).id;
}

function seedInvoice(db: Database.Database, total: number): number {
  const res = db.prepare(`
    INSERT INTO invoices (invoice_no, customer_id, invoice_date, due_date, total_amount, balance_amount, status)
    VALUES (?, 1, '2026-09-01', '2026-09-30', ?, ?, 'Unpaid')
  `).run(`INV-OB-${Math.floor(Math.random() * 1e6)}`, total, total);
  return res.lastInsertRowid as number;
}

function accountBalance(db: Database.Database, code: string): number {
  const acct = AccountingService.getAccountByCode(db, code);
  if (!acct) throw new Error(`Account ${code} missing`);
  return AccountingService.getAccountBalance(db, acct.id, '2026-12-31').balance;
}

describe('TASK 27 — classifyError maps Insufficient funds to 400', () => {
  it('returns 400 with the full actionable message', () => {
    const msg =
      'Insufficient funds in Cash: available 0.00, required 50.00 — ' +
      'Record your starting cash (Dashboard → Opening balance) or owner capital first.';
    const r = classifyError(new Error(msg));
    expect(r?.status).toBe(400);
    expect(r?.message).toMatch(/Insufficient funds/i);
    expect(r?.message).toMatch(/Opening balance/);
  });
});

describe('TASK 27 — insufficient-funds protection is not weakened', () => {
  it('fresh database still rejects cash-out before opening capital', () => {
    const db = createFixture();
    const purchaseId = seedPurchase(db, 100);
    expect(() =>
      PaymentModel.createSupplierPayment(db, {
        supplier_id: 1,
        payment_date: '2026-09-05',
        amount: 50,
        payment_method: 'Cash',
        purchase_allocations: [{ purchase_id: String(purchaseId), amount: 50 }],
        userId: 1,
      }),
    ).toThrow(/Insufficient funds/i);

    const expId = ExpenseModel.create(db, {
      expense_no: 'EXP-OB-FAIL',
      expense_category: 'Utilities',
      description: 'should fail',
      amount: 10,
      expense_date: '2026-09-05',
      payment_method: 'Cash',
      status: 'Draft',
      created_by: 1,
    });
    expect(() =>
      ExpenseModel.update(db, expId, { status: 'Recorded' }, { userId: 1 }),
    ).toThrow(/Insufficient funds/i);
    db.close();
  });

  it('guides the user when cash is still at zero', () => {
    const db = createFixture();
    const purchaseId = seedPurchase(db, 100);
    try {
      PaymentModel.createSupplierPayment(db, {
        supplier_id: 1,
        payment_date: '2026-09-05',
        amount: 50,
        payment_method: 'Cash',
        purchase_allocations: [{ purchase_id: String(purchaseId), amount: 50 }],
        userId: 1,
      });
      throw new Error('expected throw');
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      expect(msg).toMatch(/Insufficient funds/i);
      expect(msg).toMatch(/Opening balance|owner capital/i);
      expect(classifyError(e)?.status).toBe(400);
    }
    db.close();
  });
});

describe('TASK 27 regression — fresh DB → opening capital → cash payment → supplier payment → expense', () => {
  it('completes the onboarding path and leaves cash + owner-equity GL correct', () => {
    const db = createFixture();

    const openingCash = 10_000;
    db.transaction(() => {
      saveOpeningBalance(db, 'cash', openingCash);
      syncOpeningBalancesToGl(db, 1);
      OwnerCapitalModel.create(db, {
        capital_no: generateCapitalNo(db, '2026-09-01'),
        capital_date: '2026-09-01',
        amount: 5_000,
        payment_method: 'Cash',
        created_by: 1,
      });
    })();

    const invoiceId = seedInvoice(db, 800);
    const cashPaymentId = PaymentModel.create(db, {
      customer_id: 1,
      amount: 800,
      payment_date: '2026-09-02',
      payment_method: 'Cash',
      invoice_allocations: [{ invoice_id: String(invoiceId), amount: 800 }],
      userId: 1,
    });
    expect(cashPaymentId).toBeGreaterThan(0);

    const purchaseId = seedPurchase(db, 300);
    const supplierPaymentId = PaymentModel.createSupplierPayment(db, {
      supplier_id: 1,
      payment_date: '2026-09-03',
      amount: 300,
      payment_method: 'Cash',
      purchase_allocations: [{ purchase_id: String(purchaseId), amount: 300 }],
      userId: 1,
    });
    expect(supplierPaymentId).toBeGreaterThan(0);

    const expId = ExpenseModel.create(db, {
      expense_no: 'EXP-OB-OK',
      expense_category: 'Utilities',
      description: 'onboarding expense',
      amount: 150,
      expense_date: '2026-09-04',
      payment_method: 'Cash',
      status: 'Draft',
      created_by: 1,
    });
    ExpenseModel.update(db, expId, { status: 'Recorded' }, { userId: 1 });

    const expectedCash = openingCash + 5_000 + 800 - 300 - 150;
    expect(accountBalance(db, '1000')).toBeCloseTo(expectedCash, 2);

    const openingEquity = accountBalance(db, '3000');
    const ownerCapital = accountBalance(db, '3200');
    expect(openingEquity).toBeCloseTo(openingCash, 2);
    expect(ownerCapital).toBeCloseTo(5_000, 2);

    const imbalance = db.prepare(
      'SELECT ABS(COALESCE(SUM(debit),0) - COALESCE(SUM(credit),0)) AS d FROM journal_lines WHERE voided = 0',
    ).get() as { d: number };
    expect(Number(imbalance.d)).toBeLessThan(0.005);

    db.close();
  });
});
