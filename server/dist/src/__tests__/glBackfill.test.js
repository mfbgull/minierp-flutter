"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
/**
 * reporting-search-remediation — GL backfill + per-line tax decomposition.
 *
 * Covers tasks 0.6 / 1.4: pre-posting documents (direct purchase, supplier
 * payment, expense, customer payment, opening capital) get balanced
 * journal_lines entries; the migration is idempotent; the table foots;
 * invoice_items amounts decompose into net_amount + tax_amount.
 */
const better_sqlite3_1 = __importDefault(require("better-sqlite3"));
const fs_1 = __importDefault(require("fs"));
const path_1 = __importDefault(require("path"));
const backfillGlPreposting_1 = require("../migrations/backfillGlPreposting");
const backfillInvoiceItemTax_1 = require("../migrations/backfillInvoiceItemTax");
const MIGRATIONS = [
    'init.sql',
    'add-purchases-table.sql',
    'create-supplier-ledger.sql',
    'create-payment-allocations.sql',
    'add-expenses-table.sql',
    'add-supplier-payment-support.sql',
    'add-purchase-supplier-payment.sql',
    'add-stock-adjustment-financial.sql', // journal_entries table
    'add-gl-foundation.sql',
    'create-customer-ledger.sql',
    'add-gl-void-attribution.sql',
    'add-salary-payments.sql',
    'add-cash-accounts.sql',
    'add-opening-balances.sql',
    'add-invoice-discount-tax-fields.sql',
];
function insertItem(db, code) {
    db.prepare(`INSERT INTO items (item_code,item_name,unit_of_measure,standard_cost,is_purchased,is_active)
              VALUES (?, 'Thing', 'Nos', 50, 1, 1)`).run(code);
    return db.prepare(`SELECT id FROM items WHERE item_code = ?`).get(code).id;
}
function createFixture() {
    const db = new better_sqlite3_1.default(':memory:');
    db.pragma('foreign_keys = ON');
    for (const f of MIGRATIONS) {
        db.exec(fs_1.default.readFileSync(path_1.default.join(__dirname, '..', 'migrations', f), 'utf8'));
    }
    // Columns added programmatically at boot.
    db.exec('ALTER TABLE suppliers ADD COLUMN current_balance DECIMAL(15,2) DEFAULT 0');
    db.prepare(`INSERT INTO users (username,email,password_hash,full_name,role,is_active)
              VALUES ('u','e@x.c','h','U','admin',1)`).run();
    db.prepare(`INSERT INTO customers (customer_code,customer_name,is_active)
              VALUES ('C1','Cust',1)`).run();
    makePaymentsCustomerNullable(db);
    return db;
}
/** Mirror of the boot-time payments rebuild: base init.sql declares
 * customer_id NOT NULL; supplier payments need it nullable. */
function makePaymentsCustomerNullable(db) {
    const cols = db.pragma('table_info(payments)');
    const defs = cols.map((c) => {
        let d = `"${c.name}" ${c.type}`;
        if (c.pk)
            d += ' PRIMARY KEY';
        else {
            if (c.notnull && c.name !== 'customer_id')
                d += ' NOT NULL';
            if (c.dflt_value !== null)
                d += ` DEFAULT ${c.dflt_value}`;
        }
        return d;
    }).join(', ');
    db.exec(`ALTER TABLE payments RENAME TO payments_old;
           CREATE TABLE payments (${defs});
           INSERT INTO payments SELECT * FROM payments_old;
           DROP TABLE payments_old;`);
}
function footing(db) {
    return db.prepare(`SELECT COALESCE(SUM(debit),0) d, COALESCE(SUM(credit),0) c FROM journal_lines WHERE voided = 0`).get();
}
describe('GL backfill for pre-posting documents', () => {
    it('posts balanced entries for purchase, payments and expenses plus opening capital', () => {
        const db = createFixture();
        const itemId = insertItem(db, 'IT-X');
        db.prepare(`INSERT INTO suppliers (supplier_code,supplier_name,is_active) VALUES ('S1','Acme',1)`).run();
        db.prepare(`INSERT INTO warehouses (warehouse_code,warehouse_name,is_active) VALUES ('W1','Main',1)`).run();
        const whId = db.prepare(`SELECT id FROM warehouses WHERE warehouse_code='W1'`).get().id;
        db.prepare(`INSERT INTO purchases (
        purchase_no, item_id, warehouse_id, quantity, unit_cost, total_cost,
        supplier_id, purchase_date, created_by
      ) VALUES ('PURCH-X', ?, ?, 10, 50, 500, 1, '2026-08-01', 1)`).run(itemId, whId);
        db.prepare(`INSERT INTO payments (payment_no, supplier_id, payment_date, amount, payment_method, created_by)
                VALUES ('PAY-S1', 1, '2026-08-20', 300, 'Cash', 1)`).run();
        db.prepare(`INSERT INTO payments (payment_no, customer_id, payment_date, amount, payment_method, created_by)
                VALUES ('PAY-C1', 1, '2026-08-21', 100, 'Easypaisa', 1)`).run();
        db.prepare(`INSERT INTO expenses (expense_no, expense_category, amount, expense_date, status, payment_method, created_by)
                VALUES ('EXP-X', 'Meals', 40, '2026-08-22', 'Approved', 'Cash', 1)`).run();
        db.prepare(`INSERT INTO opening_balances (account_key, amount) VALUES ('cash', 5000)
                ON CONFLICT(account_key) DO UPDATE SET amount = 5000`).run();
        (0, backfillGlPreposting_1.runBackfillGlPreposting)(db);
        const byRef = (t) => db.prepare(`SELECT COUNT(*) n FROM journal_lines WHERE reference_type = ? AND voided = 0`).get(t).n;
        expect(byRef('PURCHASE')).toBe(2); // Dr 1200 / Cr 2000
        expect(byRef('PAYMENT')).toBe(4); // supplier + customer entries
        expect(byRef('EXPENSE')).toBe(2); // Dr 6000 / Cr 1000
        expect(byRef('BACKFILL_OPENING')).toBe(2); // Dr 1000 / Cr 3000
        const f = footing(db);
        expect(Math.abs(f.d - f.c)).toBeLessThan(0.01);
        // Per-method GL balances: customer payment arrived via Easypaisa.
        const balFor = (code) => db.prepare(`
        SELECT COALESCE(SUM(jl.debit - jl.credit), 0) bal
        FROM journal_lines jl JOIN chart_of_accounts coa ON coa.id = jl.account_id
        WHERE coa.code = ? AND jl.voided = 0
      `).get(code).bal;
        expect(balFor('1000')).toBeCloseTo(5000 - 300 - 40, 2); // opening − supplier − expense
        expect(balFor('1020')).toBeCloseTo(100, 2); // easypaisa receipt
        db.close();
    });
    it('is idempotent — a second run inserts nothing', () => {
        const db = createFixture();
        const itemId2 = insertItem(db, 'IT-Y');
        db.prepare(`INSERT INTO warehouses (warehouse_code,warehouse_name,is_active) VALUES ('W1','Main',1)`).run();
        const whId2 = db.prepare(`SELECT id FROM warehouses WHERE warehouse_code='W1'`).get().id;
        db.prepare(`INSERT INTO purchases (
        purchase_no, item_id, warehouse_id, quantity, unit_cost, total_cost,
        supplier_name, purchase_date, created_by
      ) VALUES ('PURCH-Y', ?, ?, 1, 10, 10, 'Cash Vendor', '2026-08-01', 1)`).run(itemId2, whId2);
        (0, backfillGlPreposting_1.runBackfillGlPreposting)(db);
        const first = footing(db);
        (0, backfillGlPreposting_1.runBackfillGlPreposting)(db);
        expect(footing(db)).toEqual(first);
        db.close();
    });
});
describe('invoice item tax decomposition backfill', () => {
    function addTaxColumns(db) {
        db.exec(`ALTER TABLE invoice_items ADD COLUMN net_amount DECIMAL(15,2) NOT NULL DEFAULT 0;
             ALTER TABLE invoice_items ADD COLUMN tax_amount DECIMAL(15,2) NOT NULL DEFAULT 0;`);
    }
    it('decomposes a tax-inclusive line and leaves zero-rate lines alone', () => {
        const db = createFixture();
        addTaxColumns(db);
        db.prepare(`INSERT INTO invoices (invoice_no, customer_id, invoice_date, total_amount, created_by)
                VALUES ('INV-A', 1, '2026-08-01', 110, 1)`).run();
        const invId = db.prepare(`SELECT id FROM invoices WHERE invoice_no='INV-A'`).get().id;
        const itemId3 = insertItem(db, 'IT-Z');
        // qty 1 @ 100 with 10% tax → stored amount 110 (inclusive).
        db.prepare(`INSERT INTO invoice_items (invoice_id, item_id, quantity, unit_price, amount, tax_rate)
                VALUES (?, ?, 1, 100, 110, 10)`).run(invId, itemId3);
        // Zero-tax line stays as-is.
        db.prepare(`INSERT INTO invoice_items (invoice_id, item_id, quantity, unit_price, amount, tax_rate)
                VALUES (?, ?, 2, 50, 100, 0)`).run(invId, itemId3);
        (0, backfillInvoiceItemTax_1.runBackfillInvoiceItemTax)(db);
        const rows = db.prepare(`SELECT amount, net_amount, tax_amount FROM invoice_items ORDER BY id`).all();
        expect(rows[0].tax_amount).toBe(10);
        expect(rows[0].net_amount).toBe(100);
        expect(rows[0].net_amount + rows[0].tax_amount).toBeCloseTo(rows[0].amount, 2);
        expect(rows[1].tax_amount).toBe(0);
        expect(rows[1].net_amount).toBe(rows[1].amount);
        db.close();
    });
});
//# sourceMappingURL=glBackfill.test.js.map