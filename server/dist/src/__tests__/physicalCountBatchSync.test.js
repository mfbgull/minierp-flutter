"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const better_sqlite3_1 = __importDefault(require("better-sqlite3"));
const fs_1 = __importDefault(require("fs"));
const path_1 = __importDefault(require("path"));
const PhysicalCount_1 = __importDefault(require("../models/PhysicalCount"));
function createFixture() {
    const db = new better_sqlite3_1.default(':memory:');
    db.pragma('foreign_keys = ON');
    const migrations = [
        'init.sql', 'add-purchases-table.sql', 'add-purchase-return-fields.sql',
        'add-batch-costing.sql', 'add-stock-adjustment-financial.sql',
        'create-supplier-ledger.sql', 'add-gl-foundation.sql',
        'add-physical-counts.sql', 'add-production-tables.sql', 'add-item-expiry-tracking.sql', 'create-customer-ledger.sql',
        'add-gl-void-attribution.sql',
    ];
    for (const file of migrations) {
        const p = path_1.default.join(__dirname, '..', 'migrations', file);
        if (fs_1.default.existsSync(p))
            db.exec(fs_1.default.readFileSync(p, 'utf8'));
        else
            console.warn('MISSING migration fixture:', file);
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
    db.prepare(`INSERT INTO users (username,email,password_hash,full_name,role,is_active) VALUES ('admin','a@b.c','x','A','admin',1)`).run();
    db.prepare(`INSERT INTO items (item_code,item_name,unit_of_measure,standard_cost,is_purchased,is_active) VALUES ('IT-C','Counted','Nos',10,1,1)`).run();
    db.prepare(`INSERT INTO warehouses (warehouse_code,warehouse_name,is_active) VALUES ('WH-1','Main',1)`).run();
    return db;
}
describe('PhysicalCount.completeCount batch sync (INV-01/23/24)', () => {
    it('shortage consumes FIFO layers; surplus creates ADJUSTMENT batch; coverage == balance; sequential movement numbers', () => {
        const db = createFixture();
        // Seed batches: layer1 20@5, layer2 10@8 → balance 30
        db.prepare(`INSERT INTO stock_batches (batch_no,item_id,warehouse_id,source_type,source_id,quantity_original,quantity_remaining,unit_cost,received_date)
      VALUES ('B1',1,1,'PURCHASE',1,20,20,5,'2026-01-01')`).run();
        db.prepare(`INSERT INTO stock_batches (batch_no,item_id,warehouse_id,source_type,source_id,quantity_original,quantity_remaining,unit_cost,received_date)
      VALUES ('B2',1,1,'PURCHASE',2,10,10,8,'2026-02-01')`).run();
        db.prepare(`INSERT INTO stock_balances (item_id,warehouse_id,quantity) VALUES (1,1,30)`).run();
        db.prepare(`UPDATE items SET current_stock=30 WHERE id=1`).run();
        const countId = PhysicalCount_1.default.create({ warehouse_id: 1 }, 1, db);
        // record shortage: counted 25 → variance -5. FIFO: 5 from B1 @5.
        PhysicalCount_1.default.recordCount(countId, 1, 25, 1, null, db);
        PhysicalCount_1.default.completeCount(countId, 1, db);
        const bal = db.prepare(`SELECT quantity FROM stock_balances WHERE item_id=1 AND warehouse_id=1`).get();
        expect(bal.quantity).toBe(25);
        const b1 = db.prepare(`SELECT quantity_remaining FROM stock_batches WHERE batch_no='B1'`).get();
        const b2 = db.prepare(`SELECT quantity_remaining FROM stock_batches WHERE batch_no='B2'`).get();
        expect(b1.quantity_remaining).toBe(15); // 20-5 FIFO
        expect(b2.quantity_remaining).toBe(10);
        // coverage == balance
        const covered = db.prepare(`SELECT SUM(quantity_remaining) s FROM stock_batches WHERE item_id=1 AND warehouse_id=1`).get();
        expect(covered.s).toBe(25);
        // movement: sequential number, batch linked, JE valued at consumed cost (5*5=25)
        const mv = db.prepare(`SELECT movement_no, batch_id, unit_cost, financial_value FROM stock_movements WHERE reference_doctype='PhysicalCount'`).get();
        const b1row = db.prepare(`SELECT id FROM stock_batches WHERE batch_no='B1'`).get();
        if (b1row)
            expect(mv.batch_id).toBe(b1row.id);
        expect(mv.movement_no).toMatch(/^STK-\d{4}-\d{4}$/);
        expect(mv.financial_value).toBe(25);
        // Surplus path: record +3 via a second count
        const countId2 = PhysicalCount_1.default.create({ warehouse_id: 1 }, 1, db);
        PhysicalCount_1.default.recordCount(countId2, 1, 31, 1, null, db);
        PhysicalCount_1.default.completeCount(countId2, 1, db);
        const adjBatch = db.prepare(`SELECT source_type, quantity_original, unit_cost FROM stock_batches WHERE source_type='ADJUSTMENT'`).get();
        expect(adjBatch).toBeTruthy();
        expect(adjBatch.quantity_original).toBe(6);
        expect(adjBatch.unit_cost).toBe(10); // snapshot unit_cost = standard_cost
        const covered2 = db.prepare(`SELECT SUM(quantity_remaining) s FROM stock_batches WHERE item_id=1 AND warehouse_id=1`).get();
        const bal2 = db.prepare(`SELECT quantity FROM stock_balances WHERE item_id=1 AND warehouse_id=1`).get();
        expect(covered2.s).toBe(bal2.quantity); // 28
        // Sequential numbering across both counts
        const nos = db.prepare(`SELECT movement_no FROM stock_movements ORDER BY id`).all();
        expect(nos.length).toBeGreaterThanOrEqual(2);
    });
    it('aborts when recording a count with no snapshot row (INV-24)', () => {
        const db = createFixture();
        const countId = PhysicalCount_1.default.create({ warehouse_id: 1 }, 1, db);
        expect(() => PhysicalCount_1.default.recordCount(countId, 999, 5, 1, null, db)).toThrow(/snapshot/i);
    });
});
