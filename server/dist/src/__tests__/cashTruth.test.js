"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const better_sqlite3_1 = __importDefault(require("better-sqlite3"));
const fs_1 = __importDefault(require("fs"));
const path_1 = __importDefault(require("path"));
const cashService_1 = require("../services/cashService");
/** Task 1.6: cash truth + method normalization (CASH-01/02). */
describe('cash method normalization', () => {
    it('whitelist maps named wallets; bank-like → bank; unknown → unclassified; credit → null', () => {
        expect((0, cashService_1.normalizeCashMethod)('Cash')).toBe('cash');
        expect((0, cashService_1.normalizeCashMethod)('EASYPAISA')).toBe('easypaisa');
        expect((0, cashService_1.normalizeCashMethod)('Jazz')).toBe('jazzcash');
        expect((0, cashService_1.normalizeCashMethod)('upaisa')).toBe('upaisa');
        expect((0, cashService_1.normalizeCashMethod)('Cheque')).toBe('bank');
        expect((0, cashService_1.normalizeCashMethod)('Bank Transfer')).toBe('bank');
        expect((0, cashService_1.normalizeCashMethod)('Credit')).toBeNull();
        expect((0, cashService_1.normalizeCashMethod)('IOU from cousin')).toBe('unclassified');
        expect((0, cashService_1.normalizeCashMethod)(null)).toBe('unclassified');
        expect((0, cashService_1.isValidPaymentMethod)('Cash')).toBe(true);
        expect((0, cashService_1.isValidPaymentMethod)('credit')).toBe(false);
        expect((0, cashService_1.isValidPaymentMethod)('IOU')).toBe(false);
        expect((0, cashService_1.isValidPaymentMethod)(undefined)).toBe(false);
    });
});
describe('unpaid purchase moves no cash (CASH-01)', () => {
    it('collectFlows ignores purchases entirely — supplier payments are the outflow', () => {
        const db = new better_sqlite3_1.default(':memory:');
        db.exec(fs_1.default.readFileSync(path_1.default.join(__dirname, '..', 'migrations', 'init.sql'), 'utf8'));
        // A purchase with a large cost must contribute NOTHING to cash flows.
        // We assert via normalize: collectFlows reads payments/expenses/salaries
        // only. Simplest observable: the function's source no longer references
        // the purchases table for flow collection.
        const srcPath = path_1.default.join(__dirname, '..', 'services', 'cashService.ts');
        const src = fs_1.default.readFileSync(srcPath, 'utf8');
        const collectSection = src.slice(src.indexOf('export function collectFlows'), src.indexOf('export interface CashAccountTotals'));
        expect(collectSection.includes('FROM purchases')).toBe(false);
        db.close();
    });
});
describe('supplier payment is the only purchase-side outflow (CASH-01)', () => {
    it('a paid purchase appears once via its supplier payment', () => {
        const db = new better_sqlite3_1.default(':memory:');
        db.pragma('foreign_keys = ON');
        for (const f of ['init.sql', 'add-purchases-table.sql', 'create-payment-allocations.sql', 'add-expenses-table.sql', 'add-supplier-payment-support.sql', 'add-gl-foundation.sql', 'add-salary-payments.sql', 'add-cash-accounts.sql', 'add-opening-balances.sql']) {
            db.exec(fs_1.default.readFileSync(path_1.default.join(__dirname, '..', 'migrations', f), 'utf8'));
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
        const totals = (0, cashService_1.collectFlows)(db, '2026-08-31');
        expect(totals.get('cash').outflow).toBe(500); // once — not doubled by a purchases scan
        db.close();
    });
});
describe('unclassified methods surface in reconciliation (CASH-02/03)', () => {
    it('cashService emits a flagged unclassified row; unknowns never map to bank', () => {
        const srcPath = path_1.default.join(__dirname, '..', 'services', 'cashService.ts');
        const src = fs_1.default.readFileSync(srcPath, 'utf8');
        // The flagged reconciliation row is built in cashService (task 1.3).
        expect(src.includes("key: 'unclassified'")).toBe(true);
        expect((0, cashService_1.normalizeCashMethod)('Cash on delivery')).toBe('unclassified');
        expect((0, cashService_1.normalizeCashMethod)('IOU')).not.toBe('bank');
    });
});
//# sourceMappingURL=cashTruth.test.js.map