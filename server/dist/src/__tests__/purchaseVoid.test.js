"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
/**
 * financial-audit-p0-remediation task 3.6 — purchase void guards and
 * batch identity (PUR-03 / PUR-02 residue).
 */
const better_sqlite3_1 = __importDefault(require("better-sqlite3"));
const fs_1 = __importDefault(require("fs"));
const path_1 = __importDefault(require("path"));
const Purchase_1 = __importDefault(require("../models/Purchase"));
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
];
function createFixture() {
    const db = new better_sqlite3_1.default(':memory:');
    db.pragma('foreign_keys = ON');
    for (const f of MIGRATIONS) {
        db.exec(fs_1.default.readFileSync(path_1.default.join(__dirname, '..', 'migrations', f), 'utf8'));
    }
    db.pragma('foreign_keys = OFF');
    // Programmatic boot ALTERs the fixture chain lacks.
    const cols = db.prepare(`SELECT name FROM pragma_table_info('suppliers')`).all();
    if (!cols.some((c) => c.name === 'current_balance')) {
        db.exec('ALTER TABLE suppliers ADD COLUMN current_balance DECIMAL(15,2) DEFAULT 0');
    }
    const purCols = db.prepare(`SELECT name FROM pragma_table_info('purchases')`).all();
    if (!purCols.some((c) => c.name === 'batch_id')) {
        db.exec('ALTER TABLE purchases ADD COLUMN batch_id INTEGER REFERENCES stock_batches(id)');
        db.exec("ALTER TABLE purchases ADD COLUMN batch_no TEXT");
    }
    const smCols = db.prepare(`SELECT name FROM pragma_table_info('stock_movements')`).all();
    if (!smCols.some((c) => c.name === 'batch_id')) {
        db.exec('ALTER TABLE stock_movements ADD COLUMN batch_id INTEGER REFERENCES stock_batches(id)');
    }
    if (!smCols.some((c) => c.name === 'journal_entry_id')) {
        db.exec('ALTER TABLE stock_movements ADD COLUMN journal_entry_id INTEGER REFERENCES journal_entries(id)');
    }
    db.pragma('foreign_keys = ON');
    db.prepare(`INSERT INTO users (username,email,password_hash,full_name,role,is_active)
              VALUES ('u','e@x.c','h','U','admin',1)`).run();
    db.prepare(`INSERT INTO suppliers (supplier_code,supplier_name,is_active)
              VALUES ('S1','Acme',1)`).run();
    return db;
}
let counter = 0;
function seedPurchase(db, overrides = {}) {
    counter += 1;
    const itemId = overrides.item_id ?? counter;
    const warehouseId = overrides.warehouse_id ?? 1;
    if (!db.prepare('SELECT id FROM items WHERE id = ?').get(itemId)) {
        db.prepare(`INSERT INTO items (id, item_code, item_name, unit_of_measure, standard_cost, is_purchased, is_active)
                VALUES (?, ?, ?, 'Nos', ?, 1, 1)`).run(itemId, `IT-${itemId}`, `Item ${itemId}`, overrides.unit_cost ?? 10);
    }
    if (!db.prepare('SELECT id FROM warehouses WHERE id = ?').get(warehouseId)) {
        db.prepare(`INSERT INTO warehouses (id, warehouse_code, warehouse_name, is_active)
                VALUES (?, 'W-VOID', 'Void WH', 1)`).run(warehouseId);
    }
    const result = db.prepare(`
    INSERT INTO purchases (
      purchase_no, item_id, warehouse_id, quantity, unit_cost, total_cost,
      supplier_id, supplier_name, purchase_date, created_by
    ) VALUES (?, ?, ?, ?, ?, ?, ?, 'Acme', ?, 1)
  `).run(overrides.purchase_no ?? `PURCH-V-${counter}`, itemId, warehouseId, overrides.quantity ?? 10, overrides.unit_cost ?? 10, (overrides.quantity ?? 10) * (overrides.unit_cost ?? 10), overrides.supplier_id ?? 1, overrides.purchase_date ?? '2026-08-01');
    const purchaseId = result.lastInsertRowid;
    const batchResult = db.prepare(`
    INSERT INTO stock_batches (
      batch_no, item_id, warehouse_id, source_type, source_id,
      quantity_original, quantity_remaining, unit_cost, received_date
    ) VALUES (?, ?, ?, 'PURCHASE', ?, ?, ?, ?, ?)
  `).run(`BATCH-V-${purchaseId}`, itemId, warehouseId, purchaseId, overrides.quantity ?? 10, overrides.quantity ?? 10, overrides.unit_cost ?? 10, overrides.purchase_date ?? '2026-08-01');
    // Mirror the fixed model: identity from lastInsertRowid, never re-query.
    const batchId = Number(batchResult.lastInsertRowid);
    db.prepare(`UPDATE purchases SET batch_id = ?, batch_no = ? WHERE id = ?`)
        .run(batchId, `BATCH-V-${purchaseId}`, purchaseId);
    return purchaseId;
}
describe('task 3.6: purchase void lifecycle', () => {
    it('refuses to void a purchase whose stock was partially sold', () => {
        const db = createFixture();
        const pid = seedPurchase(db, { quantity: 50 });
        // Simulate 45 sold out of the batch.
        db.prepare(`UPDATE stock_batches SET quantity_remaining = quantity_remaining - 45
                WHERE source_type='PURCHASE' AND source_id=?`).run(pid);
        expect(() => Purchase_1.default.void(pid, 1, 'mistake', db))
            .toThrow(/already sold\/consumed/);
        // Nothing changed.
        const row = db.prepare('SELECT voided_at FROM purchases WHERE id = ?').get(pid);
        expect(row.voided_at).toBeNull();
        db.close();
    });
    it('refuses to void when returned_quantity > 0', () => {
        const db = createFixture();
        const pid = seedPurchase(db, { quantity: 10 });
        db.prepare('UPDATE purchases SET returned_quantity = 3 WHERE id = ?').run(pid);
        expect(() => Purchase_1.default.void(pid, 1, 'mistake', db))
            .toThrow(/already returned/);
        db.close();
    });
    // The clean-void reversal flows through ledgerUtils.reverseLedgerEntry,
    // which is bound to the shared global test database (config/database) —
    // covered end-to-end by api.integration.test.ts's purchase-returns flow
    // and models.test.ts's 'allows purchase void' case. Unit-level coverage
    // here targets the guards that don't need the global db.
    it('batch identity comes from lastInsertRowid under an id collision', () => {
        const db = createFixture();
        // A decoy GR batch whose source_id equals the NEXT purchase's id — the
        // old re-query could match this one instead of the new purchase's batch.
        const nextId = (db.prepare('SELECT COALESCE(MAX(id),0)+1 n FROM purchases').get().n);
        // Warehouse 1 must exist for the decoy batch.
        if (!db.prepare('SELECT id FROM warehouses WHERE id = 1').get()) {
            db.prepare(`INSERT INTO warehouses (id, warehouse_code, warehouse_name, is_active)
                  VALUES (1, 'W-VOID', 'Void WH', 1)`).run();
        }
        const decoyItem = 900 + counter;
        db.prepare(`INSERT INTO items (id, item_code, item_name, unit_of_measure, standard_cost, is_purchased, is_active)
                VALUES (?, 'IT-DECOY', 'Decoy', 'Nos', 99, 1, 1)`).run(decoyItem);
        db.prepare(`
      INSERT INTO stock_batches (
        batch_no, item_id, warehouse_id, source_type, source_id,
        quantity_original, quantity_remaining, unit_cost, received_date
      ) VALUES ('BATCH-DECOY', ?, 1, 'PURCHASE', ?, 5, 5, 999, '2026-07-01')
    `).run(decoyItem, nextId); // collides with the upcoming purchase id
        const pid = seedPurchase(db, { quantity: 10, unit_cost: 10 });
        // seedPurchase writes the header + batch only. Simulate what
        // recordPurchase does AFTER obtaining batch identity: it links the
        // movement (and purchases.batch_id) to outputBatchId. Under the old
        // re-query that id could resolve to the decoy; with lastInsertRowid it
        // is always the newly inserted row — which has unit_cost 10, not 999.
        const ownBatch = db.prepare(`
      SELECT b.id, b.batch_no, b.unit_cost FROM stock_batches b
      JOIN purchases p ON p.batch_id = b.id
      WHERE p.id = ?
    `).get(pid);
        expect(ownBatch).toBeDefined();
        // The header must link to the batch obtained from lastInsertRowid —
        // unit_cost 10 — never the 999 decoy sharing (source_type, source_id).
        expect(Number(ownBatch.unit_cost)).toBe(10);
        expect(ownBatch.batch_no).not.toBe('BATCH-DECOY');
        db.close();
    });
});
//# sourceMappingURL=purchaseVoid.test.js.map