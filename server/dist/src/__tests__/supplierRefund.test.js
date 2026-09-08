"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
/**
 * SupplierRefundModel — cash payout against a supplier credit note.
 * Covers: create (ledger + GL + funds guard), refundable cap, void reversal.
 */
const fs_1 = __importDefault(require("fs"));
const path_1 = __importDefault(require("path"));
const better_sqlite3_1 = __importDefault(require("better-sqlite3"));
const SupplierRefund_1 = __importStar(require("../models/SupplierRefund"));
const PurchaseReturn_1 = __importDefault(require("../models/PurchaseReturn"));
const accountingService_1 = __importDefault(require("../services/accountingService"));
const MIGRATIONS = [
    'init.sql',
    'add-purchases-table.sql',
    'add-supplier-payment-support.sql',
    'add-purchase-supplier-payment.sql',
    'add-purchase-return-fields.sql',
    'add-batch-costing.sql',
    'add-stock-adjustment-financial.sql',
    'create-supplier-ledger.sql',
    'add-gl-foundation.sql',
    'create-payment-allocations.sql',
    'add-payments-purchase-order-id.sql',
    'add-purchase-returns-tables.sql',
    'add-purchase-return-batches.sql',
    'add-disposition-and-supplier-refunds.sql',
    'create-customer-ledger.sql',
    'add-gl-void-attribution.sql',
];
function setupDb() {
    const db = new better_sqlite3_1.default(':memory:');
    db.pragma('foreign_keys = ON');
    for (const file of MIGRATIONS) {
        const sql = fs_1.default.readFileSync(path_1.default.join(__dirname, '..', 'migrations', file), 'utf8');
        db.exec(sql);
    }
    // Boot-time rebuild: make payments.customer_id nullable (supplier payouts).
    const notNull = db.prepare(`
    SELECT COUNT(*) as count FROM pragma_table_info('payments')
    WHERE name='customer_id' AND "notnull"=1
  `).get();
    if (notNull.count > 0) {
        db.pragma('foreign_keys = OFF');
        try {
            db.exec(`
        CREATE TABLE payments_new (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            payment_no VARCHAR(50) UNIQUE NOT NULL,
            customer_id INTEGER,
            supplier_id INTEGER REFERENCES suppliers(id),
            invoice_id INTEGER,
            payment_date DATE NOT NULL,
            amount DECIMAL(15,2) NOT NULL,
            payment_method VARCHAR(50),
            reference_no VARCHAR(100),
            notes TEXT,
            purchase_order_id INTEGER REFERENCES purchase_orders(id),
            created_by INTEGER,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (customer_id) REFERENCES customers(id),
            FOREIGN KEY (supplier_id) REFERENCES suppliers(id),
            FOREIGN KEY (invoice_id) REFERENCES invoices(id),
            FOREIGN KEY (purchase_order_id) REFERENCES purchase_orders(id),
            FOREIGN KEY (created_by) REFERENCES users(id)
        );
        INSERT INTO payments_new (id, payment_no, customer_id, supplier_id, invoice_id, payment_date, amount, payment_method, reference_no, notes, purchase_order_id, created_by, created_at)
          SELECT id, payment_no, customer_id, supplier_id, invoice_id, payment_date, amount, payment_method, reference_no, notes, purchase_order_id, created_by, created_at FROM payments;
        DROP TABLE payments;
        ALTER TABLE payments_new RENAME TO payments;
      `);
        }
        finally {
            db.pragma('foreign_keys = ON');
        }
    }
    const supCols = db.prepare(`SELECT name FROM pragma_table_info('suppliers')`).all();
    if (!supCols.some((c) => c.name === 'current_balance')) {
        db.exec('ALTER TABLE suppliers ADD COLUMN current_balance DECIMAL(15,2) DEFAULT 0');
    }
    const cols = db.prepare(`SELECT name FROM pragma_table_info('stock_movements')`).all();
    const has = (n) => cols.some((c) => c.name === n);
    if (!has('batch_id'))
        db.exec('ALTER TABLE stock_movements ADD COLUMN batch_id INTEGER REFERENCES stock_batches(id)');
    if (!has('financial_value'))
        db.exec('ALTER TABLE stock_movements ADD COLUMN financial_value DECIMAL(15,4) DEFAULT 0');
    if (!has('financial_posted'))
        db.exec('ALTER TABLE stock_movements ADD COLUMN financial_posted BOOLEAN DEFAULT FALSE');
    if (!has('journal_entry_id'))
        db.exec('ALTER TABLE stock_movements ADD COLUMN journal_entry_id INTEGER REFERENCES journal_entries(id)');
    db.prepare(`
    INSERT INTO users (username, email, password_hash, full_name, role, is_active)
    VALUES ('admin', 'a@b.c', 'x', 'Admin', 'admin', 1)
  `).run();
    db.prepare(`
    INSERT INTO items (item_code, item_name, unit_of_measure, standard_cost, is_purchased, is_active)
    VALUES ('IT-1', 'Widget', 'Nos', 10, 1, 1)
  `).run();
    db.prepare(`
    INSERT INTO warehouses (warehouse_code, warehouse_name, is_active)
    VALUES ('WH-1', 'Main', 1)
  `).run();
    db.prepare(`
    INSERT INTO suppliers (supplier_code, supplier_name, is_active)
    VALUES ('SUP-1', 'Acme Supplies', 1)
  `).run();
    return db;
}
let seedCounter = 0;
/** Seed a fully-paid purchase + the return against it (disposition stamped). */
function seedReturn(db, opts = {}) {
    seedCounter += 1;
    const qty = 10;
    const unitCost = 10;
    const total = qty * unitCost;
    const itemResult = db.prepare(`
    INSERT INTO purchases (
      purchase_no, item_id, warehouse_id, quantity, unit_cost, total_cost,
      supplier_id, supplier_name, purchase_date, created_by
    ) VALUES (?, 1, 1, ?, ?, ?, 1, 'Acme Supplies', '2026-07-01', 1)
  `).run(`PURCH-SR-${seedCounter}`, qty, unitCost, total);
    const purchaseId = itemResult.lastInsertRowid;
    db.prepare(`
    INSERT INTO stock_batches (
      batch_no, item_id, warehouse_id, source_type, source_id,
      quantity_original, quantity_remaining, unit_cost, received_date
    ) VALUES (?, 1, 1, 'PURCHASE', ?, ?, ?, ?, '2026-07-01')
  `).run(`BATCH-SR-${seedCounter}`, purchaseId, qty, qty, unitCost);
    db.prepare(`
    INSERT INTO stock_balances (item_id, warehouse_id, quantity) VALUES (1, 1, ?)
  `).run(qty);
    db.prepare('UPDATE items SET current_stock = ? WHERE id = 1').run(qty);
    // Fully paid → the return must declare a disposition (PRET-06 path).
    const payResult = db.prepare(`
    INSERT INTO payments (payment_no, supplier_id, payment_date, amount, payment_method)
    VALUES (?, 1, '2026-07-01', ?, 'Cash')
  `).run(`PAY-SR-${seedCounter}`, total);
    db.prepare(`
    INSERT INTO purchase_allocations (payment_id, purchase_id, amount)
    VALUES (?, ?, ?)
  `).run(payResult.lastInsertRowid, purchaseId, total);
    if (opts.cash !== undefined && opts.cash > 0) {
        // Seed cash so the funds guard passes: Dr cash against opening equity.
        const cash = db.prepare(`SELECT id FROM chart_of_accounts WHERE code = '1000'`).get();
        const equity = db.prepare(`SELECT id FROM chart_of_accounts WHERE code = '3000'`).get();
        if (equity) {
            accountingService_1.default.postEntry(db, {
                entry_date: '2026-07-01',
                description: 'opening cash',
                lines: [
                    { account_id: cash.id, debit: opts.cash, description: 'opening' },
                    { account_id: equity.id, credit: opts.cash, description: 'opening' },
                ],
            });
        }
    }
    const created = PurchaseReturn_1.default.create({
        return_date: '2026-07-02',
        source_type: 'PURCHASE',
        source_id: purchaseId,
        warehouse_id: 1,
        disposition: 'refund_expected',
        items: [{ source_item_id: purchaseId, quantity: qty }],
    }, 1, db);
    const note = db.prepare(`SELECT id FROM credit_notes WHERE source_id = ?`)
        .get(created.id);
    return { returnId: created.id, creditNoteId: note.id, total };
}
describe('SupplierRefundModel', () => {
    test('create pays out a credit note: ledger debit, GL posting, refundable drops', () => {
        const db = setupDb();
        const { creditNoteId, total } = seedReturn(db, { cash: 1000 });
        expect((0, SupplierRefund_1.creditNoteRefundable)(creditNoteId, db)).toBe(total);
        const refund = SupplierRefund_1.default.create({
            refund_date: '2026-07-03',
            credit_note_id: creditNoteId,
            amount: total,
            payment_method: 'cash',
        }, 1, db);
        expect(refund.status).toBe('POSTED');
        expect(refund.amount).toBe(total);
        expect(refund.refund_no).toMatch(/^SR-\d{4}-\d{4}$/);
        // Ledger: SUPPLIER_REFUND debit restores the supplier balance to ~0.
        const balance = db.prepare(`SELECT balance FROM supplier_ledger WHERE supplier_id = 1 ORDER BY id DESC LIMIT 1`).get();
        expect(Math.abs(balance.balance)).toBeLessThan(0.01);
        // GL: Dr AP / Cr Cash posted by reference.
        const gl = db.prepare(`
      SELECT SUM(jl.debit) AS dr, SUM(jl.credit) AS cr
      FROM journal_lines jl
      WHERE jl.reference_type = 'SUPPLIER_REFUND' AND jl.reference_id = ? AND jl.voided = 0
      GROUP BY jl.journal_entry_id
    `).all(refund.id);
        expect(gl).toHaveLength(1);
        expect(gl[0].dr).toBeCloseTo(total);
        expect(gl[0].cr).toBeCloseTo(total);
        expect((0, SupplierRefund_1.creditNoteRefundable)(creditNoteId, db)).toBe(0);
    });
    test('rejects a refund exceeding the refundable balance', () => {
        const db = setupDb();
        const { creditNoteId, total } = seedReturn(db, { cash: 1000 });
        expect(() => SupplierRefund_1.default.create({ refund_date: '2026-07-03', credit_note_id: creditNoteId, amount: total + 1 }, 1, db)).toThrow(/exceeds the refundable/);
    });
    test('funds guard: insufficient cash rejects the payout', () => {
        const db = setupDb();
        const { creditNoteId, total } = seedReturn(db, { cash: 0 });
        expect(() => SupplierRefund_1.default.create({ refund_date: '2026-07-03', credit_note_id: creditNoteId, amount: total }, 1, db)).toThrow(/Insufficient funds/);
    });
    test('void reverses ledger + GL and restores the refundable balance', () => {
        const db = setupDb();
        const { creditNoteId, total } = seedReturn(db, { cash: 1000 });
        const refund = SupplierRefund_1.default.create({ refund_date: '2026-07-03', credit_note_id: creditNoteId, amount: total }, 1, db);
        const voided = SupplierRefund_1.default.void(refund.id, 1, 'wrong amount', db);
        expect(voided.status).toBe('VOIDED');
        expect((0, SupplierRefund_1.creditNoteRefundable)(creditNoteId, db)).toBe(total);
        // GL reversed (all lines voided by reference).
        const gl = db.prepare(`
      SELECT COUNT(*) AS n FROM journal_lines jl
      WHERE jl.reference_type = 'SUPPLIER_REFUND' AND jl.reference_id = ? AND jl.voided = 0
    `).get(refund.id);
        expect(gl.n).toBe(0);
        // Voiding an already-voided refund fails.
        expect(() => SupplierRefund_1.default.void(refund.id, 1, '', db))
            .toThrow(/Only POSTED/);
    });
});
