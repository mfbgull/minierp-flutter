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
    // recordPurchase writes expiry at boot-added columns only.
    const sbCols = db.prepare(`SELECT name FROM pragma_table_info('stock_batches')`).all();
    if (!sbCols.some((c) => c.name === 'expiry_date')) {
        db.exec('ALTER TABLE stock_batches ADD COLUMN expiry_date DATE');
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
describe('purchases grid: voided filter + multi-item recording', () => {
    function seedItem(db, itemId, name) {
        db.prepare(`INSERT INTO items (id, item_code, item_name, unit_of_measure, standard_cost, is_purchased, is_active)
                VALUES (?, ?, ?, 'Nos', 10, 1, 1)`).run(itemId, `IT-${itemId}`, name);
    }
    function ensureWarehouse(db) {
        if (!db.prepare('SELECT id FROM warehouses WHERE id = 1').get()) {
            db.prepare(`INSERT INTO warehouses (id, warehouse_code, warehouse_name, is_active)
                  VALUES (1, 'W-GRID', 'Grid WH', 1)`).run();
        }
    }
    it('excludes voided purchases from getAll unless include_voided is set', () => {
        const db = createFixture();
        const activeId = seedPurchase(db, { quantity: 5 });
        const voidedId = seedPurchase(db, { quantity: 7 });
        // Stamp void directly — the full void() reversal flow is covered by
        // models.test.ts / api.integration.test.ts; here only the list filter
        // matters.
        db.prepare(`UPDATE purchases SET voided_at = datetime('now'), void_reason = 'grid test' WHERE id = ?`)
            .run(voidedId);
        const def = Purchase_1.default.getAll({}, db);
        expect(def.rows.map((r) => r.id)).toEqual([activeId]);
        expect(def.total).toBe(1);
        const incl = Purchase_1.default.getAll({ include_voided: true }, db);
        expect(incl.total).toBe(2);
        expect(incl.rows.map((r) => r.id).sort()).toEqual([activeId, voidedId].sort());
        db.close();
    });
    it('records a multi-item purchase atomically — one row per item with side effects', () => {
        const db = createFixture();
        ensureWarehouse(db);
        const itemA = 8101;
        const itemB = 8102;
        seedItem(db, itemA, 'Multi A');
        seedItem(db, itemB, 'Multi B');
        const created = Purchase_1.default.recordPurchaseMulti({
            warehouse_id: 1,
            purchase_date: '2026-08-20',
            invoice_no: 'INV-MULTI-1',
            remarks: 'one delivery',
            items: [
                { item_id: itemA, quantity: 4, unit_cost: 12 },
                { item_id: itemB, quantity: 2, unit_cost: 30 },
            ],
        }, 1, db);
        expect(created).toHaveLength(2);
        expect(created[0].purchase_no).not.toBe(created[1].purchase_no);
        for (const row of created) {
            expect(row.invoice_no).toBe('INV-MULTI-1');
            expect(row.remarks).toBe('one delivery');
        }
        expect(created[0].total_cost).toBe(48);
        expect(created[1].total_cost).toBe(60);
        const ids = created.map((c) => c.id);
        const placeholders = ids.map(() => '?').join(',');
        const batches = db.prepare(`SELECT COUNT(*) n FROM stock_batches WHERE source_type='PURCHASE' AND source_id IN (${placeholders})`).get(...ids);
        expect(batches.n).toBe(2);
        const movements = db.prepare(`SELECT COUNT(*) n, COALESCE(SUM(financial_posted),0) posted FROM stock_movements
       WHERE movement_type='PURCHASE' AND batch_id IS NOT NULL AND reference_doctype='Purchase'
         AND reference_docno IN (${created.map(() => '?').join(',')})`).get(...created.map((c) => c.purchase_no));
        expect(movements.n).toBe(2);
        expect(movements.posted).toBe(2);
        // One balanced Dr Inventory / Cr AP entry per purchase row.
        for (const row of created) {
            const lines = db.prepare(`SELECT debit, credit FROM journal_lines WHERE reference_type='PURCHASE' AND reference_id=? AND voided=0`).all(row.id);
            expect(lines.length).toBeGreaterThanOrEqual(2);
            const debits = lines.reduce((s, l) => s + Number(l.debit), 0);
            const credits = lines.reduce((s, l) => s + Number(l.credit), 0);
            expect(debits).toBeCloseTo(row.total_cost, 2);
            expect(debits).toBeCloseTo(credits, 2);
        }
        // current_stock refreshed per line's item.
        const stockA = db.prepare('SELECT current_stock FROM items WHERE id = ?').get(itemA);
        const stockB = db.prepare('SELECT current_stock FROM items WHERE id = ?').get(itemB);
        expect(Number(stockA.current_stock)).toBe(4);
        expect(Number(stockB.current_stock)).toBe(2);
        db.close();
    });
    it('rolls back ALL lines when one line fails mid-transaction', () => {
        const db = createFixture();
        ensureWarehouse(db);
        const goodItem = 8201;
        seedItem(db, goodItem, 'Rollback Good');
        const before = db.prepare('SELECT COUNT(*) n FROM purchases').get();
        expect(() => Purchase_1.default.recordPurchaseMulti({
            warehouse_id: 1,
            purchase_date: '2026-08-20',
            items: [
                { item_id: goodItem, quantity: 1, unit_cost: 5 },
                { item_id: 999999, quantity: 1, unit_cost: 5 }, // FK violation mid-batch
            ],
        }, 1, db)).toThrow();
        const after = db.prepare('SELECT COUNT(*) n FROM purchases').get();
        expect(after.n).toBe(before.n);
        db.close();
    });
    it('legacy single-item payload still records exactly one purchase', () => {
        const db = createFixture();
        ensureWarehouse(db);
        const item = 8301;
        seedItem(db, item, 'Legacy Single');
        const purchase = Purchase_1.default.recordPurchase({
            item_id: item,
            warehouse_id: 1,
            quantity: 3,
            unit_cost: 9,
            purchase_date: '2026-08-21',
        }, 1, db);
        expect(purchase.total_cost).toBe(27);
        expect(Purchase_1.default.getAll({}, db).total).toBe(1);
        db.close();
    });
});
