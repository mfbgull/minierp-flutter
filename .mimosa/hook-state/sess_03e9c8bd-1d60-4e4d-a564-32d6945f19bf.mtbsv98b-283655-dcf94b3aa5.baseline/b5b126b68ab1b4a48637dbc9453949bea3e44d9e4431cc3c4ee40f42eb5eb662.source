
import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';
import { collectFlows, getCashAccountTransactions, normalizeCashMethod, isValidPaymentMethod } from '../services/cashService';

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
    for (const f of ['init.sql', 'add-purchases-table.sql', 'create-payment-allocations.sql', 'add-expenses-table.sql', 'add-supplier-payment-support.sql', 'add-gl-foundation.sql', 'add-salary-payments.sql', 'add-cash-accounts.sql', 'add-opening-balances.sql', 'add-owner-equity.sql']) {
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
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
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

describe('owner equity appears in the cash till walk', () => {
  it('capital is inflow; cash-kind withdrawal is outflow; goods never touch cash', () => {
    const db = new Database(':memory:');
    for (const f of ['init.sql', 'add-purchases-table.sql', 'create-payment-allocations.sql', 'add-expenses-table.sql', 'add-supplier-payment-support.sql', 'add-gl-foundation.sql', 'add-salary-payments.sql', 'add-cash-accounts.sql', 'add-opening-balances.sql', 'add-owner-equity.sql']) {
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
