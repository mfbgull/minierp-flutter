
import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';
import { collectFlows, getCashAccountTransactions, normalizeCashMethod, isValidPaymentMethod, syncOpeningBalancesToGl } from '../services/cashService';
import AccountingService from '../services/accountingService';
import ExpenseModel from '../models/Expense';

/** Task 1.6: cash truth + method normalization (CASH-01/02). */
describe('cash method normalization', () => {
  it('whitelist maps named wallets; bank-like → bank; unknown → unclassified; credit → null', () => {
    expect(normalizeCashMethod('Cash')).toBe('cash');
    expect(normalizeCashMethod('EASYPAISA')).toBe('easypaisa');
    expect(normalizeCashMethod('Jazz')).toBe('jazzcash');
    expect(normalizeCashMethod('upaisa')).toBe('upaisa');
    expect(normalizeCashMethod('Cheque')).toBe('bank');
    expect(normalizeCashMethod('Bank Transfer')).toBe('bank');
    expect(normalizeCashMethod('Credit')).toBeNull();
    expect(normalizeCashMethod('IOU from cousin')).toBe('unclassified');
    expect(normalizeCashMethod(null)).toBe('unclassified');

    expect(isValidPaymentMethod('Cash')).toBe(true);
    expect(isValidPaymentMethod('credit')).toBe(false);
    expect(isValidPaymentMethod('IOU')).toBe(false);
    expect(isValidPaymentMethod(undefined)).toBe(false);
  });
});

describe('unpaid purchase moves no cash (CASH-01)', () => {
  it('collectFlows ignores purchases entirely — supplier payments are the outflow', () => {
    const db = new Database(':memory:');
    db.exec(fs.readFileSync(path.join(__dirname, '..', 'migrations', 'init.sql'), 'utf8'));

    // A purchase with a large cost must contribute NOTHING to cash flows.
    // We assert via normalize: collectFlows reads payments/expenses/salaries
    // only. Simplest observable: the function's source no longer references
    // the purchases table for flow collection.
    const srcPath = path.join(__dirname, '..', 'services', 'cashService.ts');
    const src = fs.readFileSync(srcPath, 'utf8');
    const collectSection = src.slice(src.indexOf('export function collectFlows'), src.indexOf('export interface CashAccountTotals'));
    expect(collectSection.includes('FROM purchases')).toBe(false);
    db.close();
  });
});

describe('supplier payment is the only purchase-side outflow (CASH-01)', () => {
  it('a paid purchase appears once via its supplier payment', () => {
    const db = new Database(':memory:');
    db.pragma('foreign_keys = ON');
    for (const f of ['init.sql', 'add-purchases-table.sql', 'create-payment-allocations.sql', 'add-expenses-table.sql', 'add-supplier-payment-support.sql', 'add-gl-foundation.sql', 'add-salary-payments.sql', 'add-cash-accounts.sql', 'add-opening-balances.sql', 'add-owner-equity.sql', 'add-employees-table.sql', 'add-employee-loans.sql', 'add-purchase-returns-tables.sql', 'add-disposition-and-supplier-refunds.sql', 'add-purchase-supplier-payment.sql', 'add-payment-salary-void-columns.sql', 'add-employee-loan-void-columns.sql']) {
      db.exec(fs.readFileSync(path.join(__dirname, '..', 'migrations', f), 'utf8'));
    }
    db.prepare(`INSERT INTO users (username, email, password_hash, full_name, role, is_active)
                VALUES ('u','e@x.c','h','U','admin',1)`).run();
    db.prepare(`INSERT INTO suppliers (supplier_code, supplier_name) VALUES ('S1','Acme')`).run();
    // The customer_id-nullable rebuild is a programmatic boot migration, so
    // replicate its end state here before inserting the supplier payment.
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
        void_reason TEXT
      );
      DROP TABLE payments;
      ALTER TABLE payments_new RENAME TO payments;
    `);
    db.prepare(`
      INSERT INTO payments (payment_no, supplier_id, payment_date, amount, payment_method)
      VALUES ('PAYX', 1, '2026-08-01', 500, 'Cash')
    `).run();

    const totals = collectFlows(db, '2026-08-31');
    expect(totals.get('cash').outflow).toBe(500); // once — not doubled by a purchases scan
    db.close();
  });
});

describe('unclassified methods surface in reconciliation (CASH-02/03)', () => {
  it('cashService emits a flagged unclassified row; unknowns never map to bank', () => {
    const srcPath = path.join(__dirname, '..', 'services', 'cashService.ts');
    const src = fs.readFileSync(srcPath, 'utf8');
    // The flagged reconciliation row is built in cashService (task 1.3).
    expect(src.includes("key: 'unclassified'")).toBe(true);
    expect(normalizeCashMethod('Cash on delivery')).toBe('unclassified');
    expect(normalizeCashMethod('IOU')).not.toBe('bank');
  });
});

describe('employee loans and supplier refunds appear in the till walk', () => {
  it('loan disbursement is outflow, direct repayment is inflow, salary deduction is not', () => {
    const db = new Database(':memory:');
    for (const f of ['init.sql', 'add-purchases-table.sql', 'create-payment-allocations.sql', 'add-expenses-table.sql', 'add-supplier-payment-support.sql', 'add-gl-foundation.sql', 'add-salary-payments.sql', 'add-cash-accounts.sql', 'add-opening-balances.sql', 'add-owner-equity.sql', 'add-employees-table.sql', 'add-employee-loans.sql', 'add-purchase-returns-tables.sql', 'add-disposition-and-supplier-refunds.sql', 'add-purchase-supplier-payment.sql', 'add-payment-salary-void-columns.sql', 'add-employee-loan-void-columns.sql']) {
      db.exec(fs.readFileSync(path.join(__dirname, '..', 'migrations', f), 'utf8'));
    }
    db.prepare(`INSERT INTO users (username, email, password_hash, full_name, role, is_active)
                VALUES ('u','e@x.c','h','U','admin',1)`).run();
    db.prepare(`INSERT INTO employees (employee_code, first_name, last_name, salary)
                VALUES ('EMP-001','A','B',50000)`).run();
    db.prepare(`INSERT INTO suppliers (supplier_code, supplier_name) VALUES ('S1','Acme')`).run();
    db.prepare(`INSERT INTO credit_notes (credit_no, credit_date, supplier_id, source_type, source_id, amount, status)
                VALUES ('CN-001', '2026-08-01', 1, 'PURCHASE_RETURN', 1, 100, 'POSTED')`).run();

    db.prepare(`INSERT INTO employee_loans (employee_id, amount, balance, disbursement_date, payment_method, status)
                VALUES (1, 1000, 600, '2026-08-01', 'cash', 'active')`).run();
    db.prepare(`INSERT INTO employee_loan_repayments (loan_id, employee_id, amount, payment_date, payment_method, repayment_type)
                VALUES (1, 1, 400, '2026-08-10', 'Cash', 'direct')`).run();
    db.prepare(`INSERT INTO employee_loan_repayments (loan_id, employee_id, amount, payment_date, payment_method, repayment_type)
                VALUES (1, 1, 200, '2026-08-11', 'Cash', 'salary_deduction')`).run();
    db.prepare(`INSERT INTO supplier_refunds (refund_no, refund_date, supplier_id, credit_note_id, amount, payment_method, status)
                VALUES ('SR-001', '2026-08-15', 1, 1, 100, 'bank', 'POSTED')`).run();

    const totals = collectFlows(db, '2026-08-31');
    expect(totals.get('cash').outflow).toBe(1000); // disbursement only
    expect(totals.get('cash').inflow).toBe(400);   // direct repayment only
    expect(totals.get('bank').inflow).toBe(100); // supplier refund (money back in)

    const txns = getCashAccountTransactions(db, 'cash', '2026-08-31');
    expect(txns.some(t => t.type === 'loan_disbursement' && t.amount === -1000)).toBe(true);
    expect(txns.some(t => t.type === 'loan_repayment' && t.amount === 400)).toBe(true);
    expect(txns.some(t => t.type === 'salary_deduction')).toBe(false);
    db.close();
  });
});

describe('opening balances sync to the GL (dashboard seed)', () => {
  it('sync voids stale openings and posts dated at the earliest transaction', () => {
    const db = new Database(':memory:');
    for (const f of ['init.sql', 'add-purchases-table.sql', 'create-payment-allocations.sql', 'add-expenses-table.sql', 'add-supplier-payment-support.sql', 'create-customer-ledger.sql', 'create-supplier-ledger.sql', 'add-gl-foundation.sql', 'add-gl-void-attribution.sql', 'add-salary-payments.sql', 'add-cash-accounts.sql', 'add-opening-balances.sql', 'add-owner-equity.sql', 'add-employees-table.sql', 'add-employee-loans.sql', 'add-purchase-returns-tables.sql', 'add-disposition-and-supplier-refunds.sql', 'add-purchase-supplier-payment.sql', 'add-payment-salary-void-columns.sql', 'add-employee-loan-void-columns.sql']) {
      db.exec(fs.readFileSync(path.join(__dirname, '..', 'migrations', f), 'utf8'));
    }
    // postEntry now writes a journal_entries header first (the legacy
    // table is retained as the header/audit copy) — create it for the
    // header insert this fixture does not already cover.
    db.exec(`
      CREATE TABLE IF NOT EXISTS journal_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        reference_type TEXT NOT NULL,
        reference_id INTEGER NOT NULL,
        entry_date DATE NOT NULL,
        description TEXT,
        debit_account TEXT NOT NULL,
        credit_account TEXT NOT NULL,
        amount DECIMAL(15,4) NOT NULL,
        created_by INTEGER REFERENCES users(id),
        voided BOOLEAN DEFAULT FALSE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `);
    db.prepare(`INSERT INTO users (username, email, password_hash, full_name, role, is_active)
                VALUES ('u','e@x.c','h','U','admin',1)`).run();

    // A stale legacy BACKFILL_OPENING line must get voided by the sync.
    const cashAcct = db.prepare(`SELECT id FROM chart_of_accounts WHERE code = '1000'`).get() as { id: number };
    const equityAcct = db.prepare(`SELECT id FROM chart_of_accounts WHERE code = '3000'`).get() as { id: number };
    db.prepare(`INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, line_date, reference_type, reference_id)
                VALUES (999, ?, 500, 0, '2026-01-01', 'BACKFILL_OPENING', 0)`).run(cashAcct.id);
    db.prepare(`INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, line_date, reference_type, reference_id)
                VALUES (999, ?, 0, 500, '2026-01-01', 'BACKFILL_OPENING', 0)`).run(equityAcct.id);

    db.prepare(`UPDATE opening_balances SET amount = 1000 WHERE account_key = 'cash'`).run();
    db.prepare(`INSERT INTO expenses (expense_no, expense_category, description, amount, expense_date, payment_method, status)
                VALUES ('EXP-001','Utilities','test',100,'2026-03-05','Cash','Submitted')`).run();

    db.transaction(() => syncOpeningBalancesToGl(db, 1))();

    const active = db.prepare(`SELECT reference_type, COUNT(*) as n FROM journal_lines WHERE voided = 0 GROUP BY reference_type`).all() as Array<{ reference_type: string; n: number }>;
    const byRef = new Map(active.map(r => [r.reference_type, r.n]));
    expect(byRef.get('BACKFILL_OPENING')).toBeUndefined(); // voided
    expect(byRef.get('OPENING_BALANCE')).toBe(2);          // fresh Dr cash / Cr equity

    const line = db.prepare(`SELECT line_date, debit FROM journal_lines WHERE reference_type = 'OPENING_BALANCE' AND voided = 0 AND debit > 0`).get() as { line_date: string; debit: number };
    expect(line.line_date).toBe('2026-03-04'); // one day before the earliest transaction
    expect(line.debit).toBe(1000);
    db.close();
  });
});

describe('expense GL lifecycle (draft → submit → cancel)', () => {
  it('draft carries no GL; submit posts; cancel voids; edit while live re-posts', () => {
    const db = new Database(':memory:');
    for (const f of ['init.sql', 'add-purchases-table.sql', 'create-payment-allocations.sql', 'add-expenses-table.sql', 'add-supplier-payment-support.sql', 'create-customer-ledger.sql', 'create-supplier-ledger.sql', 'add-gl-foundation.sql', 'add-gl-void-attribution.sql', 'add-salary-payments.sql', 'add-cash-accounts.sql', 'add-opening-balances.sql', 'add-owner-equity.sql', 'add-employees-table.sql', 'add-employee-loans.sql', 'add-purchase-returns-tables.sql', 'add-disposition-and-supplier-refunds.sql', 'add-purchase-supplier-payment.sql', 'add-payment-salary-void-columns.sql', 'add-employee-loan-void-columns.sql']) {
      db.exec(fs.readFileSync(path.join(__dirname, '..', 'migrations', f), 'utf8'));
    }
    // postEntry now writes a journal_entries header first (the legacy
    // table is retained as the header/audit copy) — create it for the
    // header insert this fixture does not already cover.
    db.exec(`
      CREATE TABLE IF NOT EXISTS journal_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        reference_type TEXT NOT NULL,
        reference_id INTEGER NOT NULL,
        entry_date DATE NOT NULL,
        description TEXT,
        debit_account TEXT NOT NULL,
        credit_account TEXT NOT NULL,
        amount DECIMAL(15,4) NOT NULL,
        created_by INTEGER REFERENCES users(id),
        voided BOOLEAN DEFAULT FALSE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `);
    db.prepare(`INSERT INTO users (username, email, password_hash, full_name, role, is_active)
                VALUES ('u','e@x.c','h','U','admin',1)`).run();
    const id = ExpenseModel.create(db, {
      expense_no: 'EXP-2609-0001', expense_category: 'Utilities', description: 'test',
      amount: 250, expense_date: '2026-09-01', payment_method: 'Cash', status: 'Draft', created_by: 1,
    });
    db.prepare(`UPDATE opening_balances SET amount = 10000 WHERE account_key = 'cash'`).run();
    // Seed the GL so the funds guard sees the opening cash on submit. The
    // Draft expense above is the earliest transaction, so the opening is
    // dated at/before it and the guard's as-of balance includes the seed.
    db.transaction(() => syncOpeningBalancesToGl(db, 1))();
    const activeLines = () => db.prepare(`SELECT COUNT(*) as n FROM journal_lines WHERE reference_type = 'EXPENSE' AND reference_id = ? AND voided = 0`).get(id) as { n: number };
    expect(activeLines().n).toBe(0); // Draft → no GL

    ExpenseModel.update(db, id, { status: 'Submitted' }, { userId: 1 });
    expect(activeLines().n).toBe(2); // submitted → Dr 6000 / Cr 1000

    ExpenseModel.update(db, id, { status: 'Cancelled' }, { userId: 1 });
    expect(activeLines().n).toBe(0); // cancelled → voided

    // Re-open the lifecycle: submit again re-posts, and a money edit while
    // live voids + re-posts using the final values.
    ExpenseModel.update(db, id, { status: 'Submitted' }, { userId: 1 });
    expect(activeLines().n).toBe(2);
    ExpenseModel.update(db, id, { amount: 200, expense_date: '2026-09-02', payment_method: 'Cash' }, { userId: 1 });
    const live = db.prepare(`SELECT debit, credit, line_date FROM journal_lines WHERE reference_type = 'EXPENSE' AND reference_id = ? AND voided = 0`).all(id) as Array<{ debit: number; credit: number; line_date: string }>;
    expect(live.length).toBe(2);
    expect(live.some(l => l.debit === 200)).toBe(true); // expense leg re-posted at the edited amount
    expect(live.every(l => l.line_date === '2026-09-02')).toBe(true);

    db.close();
  });
});

describe('owner equity appears in the cash till walk', () => {
  it('capital is inflow; cash-kind withdrawal is outflow; goods never touch cash', () => {
    const db = new Database(':memory:');
    for (const f of ['init.sql', 'add-purchases-table.sql', 'create-payment-allocations.sql', 'add-expenses-table.sql', 'add-supplier-payment-support.sql', 'add-gl-foundation.sql', 'add-salary-payments.sql', 'add-cash-accounts.sql', 'add-opening-balances.sql', 'add-owner-equity.sql', 'add-employees-table.sql', 'add-employee-loans.sql', 'add-purchase-returns-tables.sql', 'add-disposition-and-supplier-refunds.sql', 'add-purchase-supplier-payment.sql', 'add-payment-salary-void-columns.sql', 'add-employee-loan-void-columns.sql']) {
      db.exec(fs.readFileSync(path.join(__dirname, '..', 'migrations', f), 'utf8'));
    }
    db.prepare(`INSERT INTO users (username, email, password_hash, full_name, role, is_active)
                VALUES ('u','e@x.c','h','U','admin',1)`).run();
    db.prepare(`INSERT INTO items (item_code, item_name) VALUES ('I1','Item')`).run();
    db.prepare(`INSERT INTO warehouses (warehouse_code, warehouse_name) VALUES ('W1','Main')`).run();

    const insertCapital = db.prepare(`
      INSERT INTO owner_capital (capital_no, capital_date, amount, payment_method, status)
      VALUES (?, ?, ?, ?, 'posted')
    `);
    insertCapital.run('CAP1', '2026-08-05', 1000, 'Cash');
    insertCapital.run('CAP2', '2026-08-05', 5000, 'Bank Transfer');

    const insertWithdrawal = db.prepare(`
      INSERT INTO owner_withdrawals (withdrawal_no, withdrawal_date, kind, amount, payment_method, status)
      VALUES (?, ?, ?, ?, ?, 'posted')
    `);
    insertWithdrawal.run('WD1', '2026-08-06', 'cash', 200, 'Cash');
    // Goods withdrawals move no cash — must never appear in the till.
    insertWithdrawal.run('WD2', '2026-08-07', 'goods', 999, null);
    // Voided rows are excluded.
    insertWithdrawal.run('WD3', '2026-08-07', 'cash', 500, 'Cash', );
    db.prepare(`UPDATE owner_withdrawals SET status = 'voided' WHERE withdrawal_no = 'WD3'`).run();

    const totals = collectFlows(db, '2026-08-31');
    expect(totals.get('cash').inflow).toBe(1000);
    expect(totals.get('cash').outflow).toBe(200);
    expect(totals.get('bank').inflow).toBe(5000);

    const txs = getCashAccountTransactions(db, 'cash', '2026-08-31');
    const types = txs.map((t) => t.type);
    expect(types).toContain('owner_capital');
    expect(types).toContain('owner_withdrawal');
    expect(txs.filter((t) => t.type === 'owner_capital')
      .reduce((s, t) => s + t.amount, 0)).toBe(1000);
    expect(txs.filter((t) => t.type === 'owner_withdrawal')
      .reduce((s, t) => s + Math.abs(t.amount), 0)).toBe(200);
    db.close();
  });
});
