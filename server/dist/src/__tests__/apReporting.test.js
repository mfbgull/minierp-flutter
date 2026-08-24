"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
/**
 * financial-audit-p0-remediation task 5.6 — AP reporting (PAY-07) and
 * expense lifecycle (EXP-03/04/05) regressions.
 */
const better_sqlite3_1 = __importDefault(require("better-sqlite3"));
const fs_1 = __importDefault(require("fs"));
const path_1 = __importDefault(require("path"));
const Reports_1 = __importDefault(require("../models/Reports"));
const Expense_1 = __importDefault(require("../models/Expense"));
const MIGRATIONS = [
    'init.sql',
    'add-purchases-table.sql',
    'create-supplier-ledger.sql',
    'create-payment-allocations.sql',
    'add-expenses-table.sql',
    'add-supplier-payment-support.sql',
    'add-purchase-supplier-payment.sql',
    'add-gl-foundation.sql',
    'create-customer-ledger.sql',
    'add-gl-void-attribution.sql',
    'add-salary-payments.sql',
    'add-cash-accounts.sql',
    'add-opening-balances.sql',
    'add-purchase-returns-tables.sql',
];
function createFixture() {
    const db = new better_sqlite3_1.default(':memory:');
    for (const f of MIGRATIONS) {
        db.exec(fs_1.default.readFileSync(path_1.default.join(__dirname, '..', 'migrations', f), 'utf8'));
    }
    // suppliers.current_balance is added programmatically at boot.
    db.exec('ALTER TABLE suppliers ADD COLUMN current_balance DECIMAL(15,2) DEFAULT 0');
    db.prepare(`INSERT INTO users (username,email,password_hash,full_name,role,is_active)
              VALUES ('u','e@x.c','h','U','admin',1)`).run();
    return db;
}
describe('PAY-07: AP reports execute on the live schema', () => {
    it('both reports run without SQL errors and return zero on empty books', () => {
        const db = createFixture();
        const aging = Reports_1.default.getAPAgingReport('2026-08-23', db);
        expect(aging.basis).toBe('supplier_ledger');
        expect(aging.agingBuckets).toEqual([]);
        expect(aging.summary.totalPayables).toBe(0);
        // getAPSummary deleted (reporting-search-remediation): it aggregated
        // raw payments by purchase_order_id and had no route; AP truth lives
        // in supplier_ledger via /reports/ap-aging.
        db.close();
    });
    it('an unpaid direct purchase appears in the current bucket; a paid one does not', () => {
        const db = createFixture();
        db.prepare(`INSERT INTO suppliers (supplier_code,supplier_name,is_active)
                VALUES ('S1','Acme',1)`).run();
        db.prepare(`INSERT INTO items (item_code, item_name, unit_of_measure, standard_cost, is_purchased, is_active)
                VALUES ('IT-X','Thing','Nos',50,1,1)`).run();
        const itemId = db.prepare(`SELECT id FROM items WHERE item_code='IT-X'`).get().id;
        db.prepare(`INSERT INTO warehouses (warehouse_code, warehouse_name, is_active) VALUES ('W1','Main',1)`).run();
        const whId = db.prepare(`SELECT id FROM warehouses WHERE warehouse_code='W1'`).get().id;
        db.prepare(`INSERT INTO purchases (
        purchase_no, item_id, warehouse_id, quantity, unit_cost, total_cost,
        supplier_id, purchase_date, created_by
      ) VALUES ('PURCH-X', ?, ?, 10, 50, 500, 1, '2026-08-01', 1)`).run(itemId, whId);
        // The report reads supplier_ledger (not the purchases table), so post
        // the debit the recordPurchase flow would have written.
        db.prepare(`INSERT INTO supplier_ledger (supplier_id, transaction_date, transaction_type, reference_no, debit, credit, balance)
                VALUES (1, '2026-08-01', 'PURCHASE', 'PURCH-X', 500, 0, 500)`).run();
        let aging = Reports_1.default.getAPAgingReport('2026-08-23', db);
        expect(aging.agingBuckets).toHaveLength(1);
        expect(aging.agingBuckets[0].total_outstanding).toBe(500);
        expect(aging.summary.total_1_30).toBe(500);
        // Settle it fully → drops off aging.
        db.prepare(`INSERT INTO supplier_ledger (supplier_id, transaction_date, transaction_type, reference_no, debit, credit, balance)
                VALUES (1, '2026-08-20', 'PAYMENT', 'PAYX', 0, 500, -500)`).run();
        aging = Reports_1.default.getAPAgingReport('2026-08-23', db);
        expect(aging.agingBuckets).toHaveLength(0);
        db.close();
    });
    it('a back-dated unpaid debit ages into the 31-60 bucket', () => {
        const db = createFixture();
        db.prepare(`INSERT INTO suppliers (supplier_code,supplier_name,is_active)
                VALUES ('S1','Acme',1)`).run();
        db.prepare(`INSERT INTO supplier_ledger (supplier_id, transaction_date, transaction_type, reference_no, debit, credit, balance)
                VALUES (1, '2026-06-01', 'PURCHASE', 'PURCH-Y', 300, 0, 300)`).run();
        const aging = Reports_1.default.getAPAgingReport('2026-08-23', db);
        expect(aging.agingBuckets[0].days_31_60).toBe(0); // Jun 1 → Aug 23 is ~83 days
        expect(aging.agingBuckets[0].days_61_90).toBe(300);
        db.close();
    });
});
describe('EXP-05: atomic numbering from settings counter', () => {
    it('generateExpenseNo continues after seeded counters instead of colliding', () => {
        const db = createFixture();
        db.exec(`INSERT INTO expenses (expense_no, expense_category, amount, expense_date, status, created_by)
             VALUES ('EXP-2608-0007', 'Meals', 5, '2026-08-01', 'Draft', 1)`);
        db.exec(`
      INSERT OR IGNORE INTO settings (key, value)
      SELECT 'EXP_last_no_' || substr(expense_no, 5, 4),
             CAST(CAST(substr(expense_no, 10) AS INTEGER) AS TEXT)
      FROM expenses WHERE expense_no LIKE 'EXP-____-____'
      GROUP BY substr(expense_no, 5, 4)
      HAVING MAX(CAST(substr(expense_no, 10) AS INTEGER))
    `);
        expect(Expense_1.default.generateExpenseNo(db, '2026-08-15')).toBe('EXP-2608-0008');
        expect(Expense_1.default.generateExpenseNo(db, '2026-08-16')).toBe('EXP-2608-0009');
        db.close();
    });
});
//# sourceMappingURL=apReporting.test.js.map