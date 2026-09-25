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
import fs from 'fs';
import path from 'path';
import { classifyError } from '../utils/businessRuleError';
import ExpenseModel from '../models/Expense';
import PaymentModel from '../models/Payment';
import OwnerCapitalModel, { generateCapitalNo } from '../models/OwnerCapital';
import AccountingService from '../services/accountingService';
import { saveOpeningBalance, syncOpeningBalancesToGl } from '../services/cashService';

const MIGRATIONS = [
  'init.sql',
  'add-purchases-table.sql',
  'add-purchase-return-fields.sql',
  'create-supplier-ledger.sql',
  'create-payment-allocations.sql',
  'add-expenses-table.sql',
  'add-supplier-payment-support.sql',
  'add-purchase-supplier-payment.sql',
  'add-gl-foundation.sql',
  'add-stock-adjustment-financial.sql',
  'create-customer-ledger.sql',
  'add-gl-void-attribution.sql',
  'add-salary-payments.sql',
  'add-cash-accounts.sql',
  'add-opening-balances.sql',
  'add-payment-salary-void-columns.sql',
  'add-owner-equity.sql',
  'add-batch-costing.sql',
  'add-purchase-void-columns.sql',
  'add-purchase-return-batches.sql',
  'add-purchase-returns-tables.sql',
  'add-disposition-and-supplier-refunds.sql',
  'add-invoice-returns.sql',
  'add-invoice-return-void-attribution.sql',
  'add-returned-amount.sql',
  'add-invoice-credit-offset.sql',
  'add-invoice-soft-delete.sql',
  'add-idempotency-keys.sql',
  'add-employees-table.sql',
  'add-employee-loans.sql',
  'add-employee-loan-void-columns.sql',
];

function createFixture(): Database.Database {
  const db = new Database(':memory:');
  db.pragma('foreign_keys = OFF');
  for (const f of MIGRATIONS) {
    db.exec(fs.readFileSync(path.join(__dirname, '..', 'migrations', f), 'utf8'));
  }
  db.exec(`
    CREATE TABLE payments_new (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      payment_no VARCHAR(50) UNIQUE NOT NULL,
      customer_id INTEGER REFERENCES customers(id),
      supplier_id INTEGER REFERENCES suppliers(id),
      invoice_id INTEGER,
      payment_date DATE NOT NULL,
      amount DECIMAL(15,2) NOT NULL,
      payment_method VARCHAR(50) NOT NULL DEFAULT 'Cash',
      reference_no VARCHAR(100),
      notes TEXT,
      purchase_order_id INTEGER REFERENCES purchase_orders(id),
      created_by INTEGER,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      voided_at TEXT,
      voided_by INTEGER,
      void_reason TEXT,
      CHECK ((customer_id IS NULL) <> (supplier_id IS NULL)),
      FOREIGN KEY (customer_id) REFERENCES customers(id),
      FOREIGN KEY (supplier_id) REFERENCES suppliers(id),
      FOREIGN KEY (invoice_id) REFERENCES invoices(id)
    );
    DROP TABLE payments;
    ALTER TABLE payments_new RENAME TO payments;
  `);
  db.exec('ALTER TABLE suppliers ADD COLUMN current_balance DECIMAL(15,2) DEFAULT 0');
  db.exec('ALTER TABLE customers ADD COLUMN current_balance DECIMAL(15,2) DEFAULT 0');
  db.exec('ALTER TABLE customers ADD COLUMN credit_balance DECIMAL(15,2) DEFAULT 0');
  db.exec("ALTER TABLE invoices ADD COLUMN return_fee DECIMAL(15,2) NOT NULL DEFAULT 0");
  db.exec("ALTER TABLE invoices ADD COLUMN payment_status TEXT NOT NULL DEFAULT 'Unpaid'");
  db.exec("ALTER TABLE invoices ADD COLUMN return_status TEXT NOT NULL DEFAULT 'None'");
  db.pragma('foreign_keys = ON');

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
