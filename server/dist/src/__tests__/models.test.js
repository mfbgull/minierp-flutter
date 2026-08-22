"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const database_1 = __importDefault(require("../config/database"));
const Item_1 = __importDefault(require("../models/Item"));
const Warehouse_1 = __importDefault(require("../models/Warehouse"));
const StockMovement_1 = __importDefault(require("../models/StockMovement"));
const Purchase_1 = __importDefault(require("../models/Purchase"));
const PurchaseOrder_1 = __importDefault(require("../models/PurchaseOrder"));
const Payment_1 = __importDefault(require("../models/Payment"));
const SupplierLedger_1 = __importDefault(require("../models/SupplierLedger"));
describe('ItemModel', () => {
    let createdItemId;
    describe('create', () => {
        it('creates a new item and returns its ID', () => {
            const id = Item_1.default.create({
                item_code: `MODEL-TEST-${Date.now()}`,
                item_name: 'Model Test Item',
                category: 'Test',
                unit_of_measure: 'Nos',
                standard_cost: 10,
                standard_selling_price: 20,
            }, 1, database_1.default);
            expect(id).toBeGreaterThan(0);
            createdItemId = id;
        });
        it('creates item with default values for optional fields', () => {
            const id = Item_1.default.create({
                item_code: `MINIMAL-${Date.now()}`,
                item_name: 'Minimal Item',
            }, 1, database_1.default);
            expect(id).toBeGreaterThan(0);
        });
    });
    describe('getById', () => {
        it('returns item by ID', () => {
            const item = Item_1.default.getById(createdItemId, database_1.default);
            expect(item).toBeDefined();
            expect(item?.id).toBe(createdItemId);
            expect(item?.item_name).toBe('Model Test Item');
        });
        it('returns undefined for non-existent ID', () => {
            const item = Item_1.default.getById(999999, database_1.default);
            expect(item).toBeUndefined();
        });
    });
    describe('getByCode', () => {
        it('returns item by code', () => {
            const item = Item_1.default.getById(createdItemId, database_1.default);
            expect(item).toBeDefined();
            const byCode = Item_1.default.getByCode(item.item_code, database_1.default);
            expect(byCode).toBeDefined();
            expect(byCode?.id).toBe(createdItemId);
        });
        it('returns undefined for non-existent code', () => {
            const item = Item_1.default.getByCode('NONEXISTENT-CODE-XYZ', database_1.default);
            expect(item).toBeUndefined();
        });
    });
    describe('getAll', () => {
        it('returns all active items paged', () => {
            const { rows, total, pageNum, limitNum } = Item_1.default.getAll({}, database_1.default);
            expect(Array.isArray(rows)).toBe(true);
            expect(rows.length).toBeGreaterThan(0);
            expect(total).toBeGreaterThan(0);
            expect(pageNum).toBe(1);
            expect(limitNum).toBe(10);
            expect(rows.length).toBeLessThanOrEqual(10);
        });
        it('filters by category', () => {
            const { rows } = Item_1.default.getAll({ category: 'Test' }, database_1.default);
            expect(rows.length).toBeGreaterThan(0);
            rows.forEach(item => {
                expect(item.category).toBe('Test');
            });
        });
        it('filters by search term', () => {
            const { rows } = Item_1.default.getAll({ search: 'Model Test' }, database_1.default);
            expect(rows.length).toBeGreaterThan(0);
        });
        it('returns empty array for non-matching search', () => {
            const { rows } = Item_1.default.getAll({ search: 'zzzznonexistent' }, database_1.default);
            expect(rows.length).toBe(0);
        });
        it('excludes inactive items', () => {
            const { rows } = Item_1.default.getAll({}, database_1.default);
            rows.forEach(item => {
                expect(item.is_active).toBe(1);
            });
        });
        it('pages with page/limit', () => {
            const { rows, total, pageNum } = Item_1.default.getAll({ page: 2, limit: 5 }, database_1.default);
            expect(pageNum).toBe(2);
            expect(rows.length).toBeLessThanOrEqual(5);
            expect(total).toBeGreaterThanOrEqual(rows.length);
        });
        it('filters by low stock (current_stock < reorder_level > 0)', () => {
            const { rows } = Item_1.default.getAll({ lowStock: true }, database_1.default);
            rows.forEach(item => {
                expect(item.reorder_level).toBeGreaterThan(0);
                expect(item.current_stock).toBeLessThan(item.reorder_level);
            });
        });
    });
    describe('update', () => {
        it('updates item fields', () => {
            const result = Item_1.default.update(createdItemId, {
                item_name: 'Updated Model Item',
                unit_of_measure: 'Kg',
                description: 'Updated description',
                category: 'Updated',
                reorder_level: 50,
                standard_cost: 15,
                standard_selling_price: 30,
                is_raw_material: true,
                is_finished_good: false,
                is_purchased: true,
                is_manufactured: false,
            }, database_1.default);
            expect(result.changes).toBe(1);
            const updated = Item_1.default.getById(createdItemId, database_1.default);
            expect(updated?.item_name).toBe('Updated Model Item');
            expect(updated?.unit_of_measure).toBe('Kg');
        });
        it('returns 0 changes for non-existent ID', () => {
            const result = Item_1.default.update(999999, {
                item_name: 'Ghost Item',
                unit_of_measure: 'Nos',
                is_raw_material: false,
                is_finished_good: false,
                is_purchased: false,
                is_manufactured: false,
            }, database_1.default);
            expect(result.changes).toBe(0);
        });
    });
    describe('delete', () => {
        it('soft-deletes an item (sets is_active=0)', () => {
            const result = Item_1.default.delete(createdItemId, database_1.default);
            expect(result.changes).toBe(1);
            const deleted = Item_1.default.getById(createdItemId, database_1.default);
            expect(deleted?.is_active).toBe(0);
        });
        it('deleted item does not appear in getAll', () => {
            const { rows } = Item_1.default.getAll({}, database_1.default);
            const found = rows.find(i => i.id === createdItemId);
            expect(found).toBeUndefined();
        });
    });
    describe('getStockByWarehouse', () => {
        it('returns stock distribution across warehouses', () => {
            const stock = Item_1.default.getStockByWarehouse(createdItemId, database_1.default);
            expect(Array.isArray(stock)).toBe(true);
        });
    });
    describe('getCategories', () => {
        it('returns distinct categories', () => {
            const categories = Item_1.default.getCategories(database_1.default);
            expect(Array.isArray(categories)).toBe(true);
        });
    });
    describe('getLowStock', () => {
        it('returns items below reorder level', () => {
            const lowStock = Item_1.default.getLowStock(database_1.default);
            expect(Array.isArray(lowStock)).toBe(true);
        });
    });
});
describe('WarehouseModel', () => {
    let createdWarehouseId;
    describe('create', () => {
        it('creates a new warehouse', () => {
            const id = Warehouse_1.default.create(database_1.default, {
                warehouse_code: `MODEL-WH-${Date.now()}`,
                warehouse_name: 'Model Test Warehouse',
                location: 'Test Location',
            });
            expect(id).toBeGreaterThan(0);
            createdWarehouseId = id;
        });
    });
    describe('getById', () => {
        it('returns warehouse by ID', () => {
            const wh = Warehouse_1.default.getById(database_1.default, createdWarehouseId);
            expect(wh).toBeDefined();
            expect(wh?.warehouse_name).toBe('Model Test Warehouse');
        });
        it('returns undefined for non-existent ID', () => {
            const wh = Warehouse_1.default.getById(database_1.default, 999999);
            expect(wh).toBeUndefined();
        });
    });
    describe('getByCode', () => {
        it('returns warehouse by code', () => {
            const wh = Warehouse_1.default.getById(database_1.default, createdWarehouseId);
            expect(wh).toBeDefined();
            const byCode = Warehouse_1.default.getByCode(database_1.default, wh.warehouse_code);
            expect(byCode).toBeDefined();
            expect(byCode?.id).toBe(createdWarehouseId);
        });
        it('returns undefined for non-existent code', () => {
            const wh = Warehouse_1.default.getByCode(database_1.default, 'NONEXISTENT-WH');
            expect(wh).toBeUndefined();
        });
    });
    describe('getAll', () => {
        it('returns all active warehouses', () => {
            const warehouses = Warehouse_1.default.getAll(database_1.default);
            expect(Array.isArray(warehouses)).toBe(true);
            expect(warehouses.length).toBeGreaterThan(0);
        });
    });
    describe('update', () => {
        it('updates warehouse fields', () => {
            Warehouse_1.default.update(database_1.default, createdWarehouseId, {
                warehouse_code: (Warehouse_1.default.getById(database_1.default, createdWarehouseId)?.warehouse_code),
                warehouse_name: 'Updated Warehouse',
                location: 'Updated Location',
            });
            const updated = Warehouse_1.default.getById(database_1.default, createdWarehouseId);
            expect(updated?.warehouse_name).toBe('Updated Warehouse');
        });
    });
    describe('delete', () => {
        it('soft-deletes a warehouse', () => {
            Warehouse_1.default.delete(database_1.default, createdWarehouseId);
            const deleted = Warehouse_1.default.getById(database_1.default, createdWarehouseId);
            expect(deleted?.is_active).toBe(0);
        });
    });
    describe('getStockSummary', () => {
        it('returns stock summary for a warehouse', () => {
            const summary = Warehouse_1.default.getStockSummary(database_1.default);
            expect(Array.isArray(summary)).toBe(true);
        });
    });
});
describe('StockMovementModel', () => {
    describe('recordMovement', () => {
        it('records a stock-in movement and updates balance', () => {
            const result = StockMovement_1.default.recordMovement({
                item_id: 1,
                warehouse_id: 1,
                movement_type: 'in',
                quantity: 100,
                unit_cost: 10,
                remarks: 'Model test stock-in',
            }, 1, database_1.default);
            expect(result.id).toBeGreaterThan(0);
            expect(result.movement_no).toMatch(/^STK-/);
        });
        it('records a stock-out movement', () => {
            const result = StockMovement_1.default.recordMovement({
                item_id: 1,
                warehouse_id: 1,
                movement_type: 'out',
                quantity: 10,
                remarks: 'Model test stock-out',
            }, 1, database_1.default);
            expect(result.id).toBeGreaterThan(0);
        });
        it('records an adjustment movement', () => {
            const result = StockMovement_1.default.recordMovement({
                item_id: 1,
                warehouse_id: 1,
                movement_type: 'adjustment',
                quantity: -5,
                remarks: 'Model test adjustment',
            }, 1, database_1.default);
            expect(result.id).toBeGreaterThan(0);
        });
    });
    describe('getAll', () => {
        it('returns all movements paged', () => {
            const { rows, total, pageNum, limitNum } = StockMovement_1.default.getAll({}, database_1.default);
            expect(Array.isArray(rows)).toBe(true);
            expect(rows.length).toBeGreaterThan(0);
            expect(total).toBeGreaterThan(0);
            expect(pageNum).toBe(1);
            expect(limitNum).toBe(10);
            expect(rows.length).toBeLessThanOrEqual(10);
        });
        it('filters by item_id', () => {
            const { rows } = StockMovement_1.default.getAll({ item_id: 1 }, database_1.default);
            expect(rows.length).toBeGreaterThan(0);
            rows.forEach(m => {
                expect(m.item_id).toBe(1);
            });
        });
        it('filters by movement_type', () => {
            const { rows } = StockMovement_1.default.getAll({ movement_type: 'in' }, database_1.default);
            expect(rows.length).toBeGreaterThan(0);
            rows.forEach(m => {
                expect(m.movement_type).toBe('in');
            });
        });
        it('respects limit as the page size', () => {
            const { rows } = StockMovement_1.default.getAll({ limit: 5 }, database_1.default);
            expect(rows.length).toBeLessThanOrEqual(5);
        });
        it('pages with page/limit', () => {
            const { rows, total, pageNum } = StockMovement_1.default.getAll({ page: 2, limit: 5 }, database_1.default);
            expect(pageNum).toBe(2);
            expect(rows.length).toBeLessThanOrEqual(5);
            expect(total).toBeGreaterThanOrEqual(rows.length);
        });
        it('filters by search', () => {
            const { rows } = StockMovement_1.default.getAll({ search: 'Model' }, database_1.default);
            expect(rows.length).toBeGreaterThanOrEqual(0);
        });
    });
    describe('getById', () => {
        it('returns movement by ID', () => {
            const { rows } = StockMovement_1.default.getAll({ limit: 1 }, database_1.default);
            if (rows.length > 0) {
                const movement = StockMovement_1.default.getById(rows[0].id, database_1.default);
                expect(movement).toBeDefined();
                expect(movement?.id).toBe(rows[0].id);
            }
        });
        it('returns undefined for non-existent ID', () => {
            const movement = StockMovement_1.default.getById(999999, database_1.default);
            expect(movement).toBeUndefined();
        });
    });
    describe('consumeFromOldestBatches', () => {
        let testItemId;
        let testWhId;
        beforeAll(() => {
            // Create a test item
            testItemId = Item_1.default.create({
                item_code: `BATCH-TEST-${Date.now()}`,
                item_name: 'Batch Test Item',
                category: 'Test',
                unit_of_measure: 'Nos',
                standard_cost: 10,
                standard_selling_price: 25,
            }, 1, database_1.default);
            // Use an existing warehouse (id 1)
            testWhId = 1;
            // Ensure a clean stock_balance entry
            database_1.default.prepare(`DELETE FROM stock_balances WHERE item_id = ? AND warehouse_id = ?`).run(testItemId, testWhId);
            database_1.default.prepare(`DELETE FROM stock_batches WHERE item_id = ? AND warehouse_id = ?`).run(testItemId, testWhId);
            database_1.default.prepare(`INSERT INTO stock_balances (item_id, warehouse_id, quantity) VALUES (?, ?, 0)`).run(testItemId, testWhId);
        });
        afterAll(() => {
            // Clean up - must delete stock_movements first to avoid FK constraints on batch_id
            database_1.default.prepare(`DELETE FROM stock_movements WHERE item_id = ?`).run(testItemId);
            database_1.default.prepare(`DELETE FROM stock_balances WHERE item_id = ?`).run(testItemId);
            database_1.default.prepare(`DELETE FROM stock_batches WHERE item_id = ?`).run(testItemId);
            Item_1.default.delete(testItemId, database_1.default);
        });
        it('consumes from oldest batch first (FIFO)', () => {
            const batch1Result = StockMovement_1.default.recordMovement({
                item_id: testItemId,
                warehouse_id: testWhId,
                movement_type: 'PURCHASE',
                quantity: 100,
                unit_cost: 15,
            }, 1, database_1.default);
            // Manually create batch #1 with older date
            database_1.default.prepare(`INSERT INTO stock_batches (item_id, warehouse_id, batch_no, source_type, source_id, quantity_original, quantity_remaining, unit_cost, received_date)
        VALUES (?, ?, 'BATCH-TEST-1', 'PURCHASE', 0, 50, 50, 15, '2025-01-01')`).run(testItemId, testWhId);
            // Manually create batch #2 with newer date (higher unit cost)
            database_1.default.prepare(`INSERT INTO stock_batches (item_id, warehouse_id, batch_no, source_type, source_id, quantity_original, quantity_remaining, unit_cost, received_date)
        VALUES (?, ?, 'BATCH-TEST-2', 'PURCHASE', 0, 50, 50, 20, '2025-06-01')`).run(testItemId, testWhId);
            // Consume 60 units: should take 50 from batch1, 10 from batch2
            const consumption = StockMovement_1.default.consumeFromOldestBatches(testItemId, testWhId, 60, database_1.default);
            expect(consumption).toHaveLength(2);
            expect(consumption[0].batchId).not.toBeNull();
            expect(consumption[0].consumed).toBe(50);
            expect(consumption[0].unitCost).toBe(15);
            expect(consumption[1].batchId).not.toBeNull();
            expect(consumption[1].consumed).toBe(10);
            expect(consumption[1].unitCost).toBe(20);
            // Verify batch remaining quantities
            const batch1 = database_1.default.prepare(`SELECT quantity_remaining FROM stock_batches WHERE id = ?`).get(consumption[0].batchId);
            expect(batch1.quantity_remaining).toBe(0);
            const batch2 = database_1.default.prepare(`SELECT quantity_remaining FROM stock_batches WHERE id = ?`).get(consumption[1].batchId);
            expect(batch2.quantity_remaining).toBe(40);
        });
        it('throws error when batch stock is insufficient', () => {
            // Clean up old test data
            database_1.default.prepare(`DELETE FROM stock_batches WHERE item_id = ?`).run(testItemId);
            database_1.default.prepare(`UPDATE stock_balances SET quantity = 10 WHERE item_id = ?`).run(testItemId);
            // Create just 1 batch with 10 units
            database_1.default.prepare(`INSERT INTO stock_batches (item_id, warehouse_id, batch_no, source_type, source_id, quantity_original, quantity_remaining, unit_cost, received_date)
        VALUES (?, ?, 'BATCH-TEST-3', 'PURCHASE', 0, 10, 10, 15, '2025-01-01')`).run(testItemId, testWhId);
            // Attempting to consume more than available should throw
            expect(() => {
                StockMovement_1.default.consumeFromOldestBatches(testItemId, testWhId, 15, database_1.default);
            }).toThrow('Insufficient stock');
        });
        it('throws error for zero quantity', () => {
            expect(() => {
                StockMovement_1.default.consumeFromOldestBatches(testItemId, testWhId, 0, database_1.default);
            }).toThrow('consumeFromOldestBatches: quantity must be positive, got 0');
        });
        // ── FEFO edge-case tests ────────────────────────────────────
        it('FEFO: consumes nearest-expiry batch first when has_expiry=1', () => {
            // Clean slate
            database_1.default.prepare('DELETE FROM stock_batches WHERE item_id = ?').run(testItemId);
            // Update item to have expiry tracking
            database_1.default.prepare('UPDATE items SET has_expiry = 1 WHERE id = ?').run(testItemId);
            // Batch A: expires in 60 days, 30 units @ cost 10
            database_1.default.prepare(`INSERT INTO stock_batches (item_id, warehouse_id, batch_no, source_type, source_id, quantity_original, quantity_remaining, unit_cost, received_date, expiry_date)
        VALUES (?, ?, 'FEFO-A', 'PURCHASE', 0, 30, 30, 10, '2026-01-01', date('now', '+60 days'))`).run(testItemId, testWhId);
            // Batch B: expires in 10 days, 30 units @ cost 20
            database_1.default.prepare(`INSERT INTO stock_batches (item_id, warehouse_id, batch_no, source_type, source_id, quantity_original, quantity_remaining, unit_cost, received_date, expiry_date)
        VALUES (?, ?, 'FEFO-B', 'PURCHASE', 0, 30, 30, 20, '2026-06-01', date('now', '+10 days'))`).run(testItemId, testWhId);
            // Set stock_balances to 60
            database_1.default.prepare('UPDATE stock_balances SET quantity = 60 WHERE item_id = ? AND warehouse_id = ?').run(testItemId, testWhId);
            // Consume 40: should take 30 from Batch B (nearest expiry) first, then 10 from A
            const consumption = StockMovement_1.default.consumeFromOldestBatches(testItemId, testWhId, 40, database_1.default);
            expect(consumption).toHaveLength(2);
            expect(consumption[0].unitCost).toBe(20); // Batch B consumed first
            expect(consumption[0].consumed).toBe(30);
            expect(consumption[1].unitCost).toBe(10); // Batch A consumed second
            expect(consumption[1].consumed).toBe(10);
            // Restore item to non-expiry for other tests
            database_1.default.prepare('UPDATE items SET has_expiry = 0 WHERE id = ?').run(testItemId);
        });
        it('FEFO: skips halted batches', () => {
            database_1.default.prepare('DELETE FROM stock_batches WHERE item_id = ?').run(testItemId);
            database_1.default.prepare('UPDATE items SET has_expiry = 1 WHERE id = ?').run(testItemId);
            // Batch A: halted, 30 units
            database_1.default.prepare(`INSERT INTO stock_batches (item_id, warehouse_id, batch_no, source_type, source_id, quantity_original, quantity_remaining, unit_cost, received_date, expiry_date, halted)
        VALUES (?, ?, 'HALT-A', 'PURCHASE', 0, 30, 30, 10, '2026-01-01', date('now', '+30 days'), 1)`).run(testItemId, testWhId);
            // Batch B: not halted, 30 units
            database_1.default.prepare(`INSERT INTO stock_batches (item_id, warehouse_id, batch_no, source_type, source_id, quantity_original, quantity_remaining, unit_cost, received_date, expiry_date, halted)
        VALUES (?, ?, 'HALT-B', 'PURCHASE', 0, 30, 30, 20, '2026-01-01', date('now', '+30 days'), 0)`).run(testItemId, testWhId);
            database_1.default.prepare('UPDATE stock_balances SET quantity = 60 WHERE item_id = ? AND warehouse_id = ?').run(testItemId, testWhId);
            // Consume 20: should only come from Batch B (halted A is skipped)
            const consumption = StockMovement_1.default.consumeFromOldestBatches(testItemId, testWhId, 20, database_1.default);
            expect(consumption).toHaveLength(1);
            expect(consumption[0].unitCost).toBe(20); // Only Batch B
            expect(consumption[0].consumed).toBe(20);
            // Batch A should still have 30 remaining (untouched)
            const batchA = database_1.default.prepare('SELECT quantity_remaining FROM stock_batches WHERE batch_no = ?').get('HALT-A');
            expect(batchA.quantity_remaining).toBe(30);
            database_1.default.prepare('UPDATE items SET has_expiry = 0 WHERE id = ?').run(testItemId);
        });
        it('FEFO: excludes expired batches (expiry_date < today)', () => {
            database_1.default.prepare('DELETE FROM stock_batches WHERE item_id = ?').run(testItemId);
            database_1.default.prepare('UPDATE items SET has_expiry = 1 WHERE id = ?').run(testItemId);
            // Batch A: expired 5 days ago, 30 units
            database_1.default.prepare(`INSERT INTO stock_batches (item_id, warehouse_id, batch_no, source_type, source_id, quantity_original, quantity_remaining, unit_cost, received_date, expiry_date)
        VALUES (?, ?, 'EXP-A', 'PURCHASE', 0, 30, 30, 10, '2026-01-01', date('now', '-5 days'))`).run(testItemId, testWhId);
            // Batch B: not expired, 30 units
            database_1.default.prepare(`INSERT INTO stock_batches (item_id, warehouse_id, batch_no, source_type, source_id, quantity_original, quantity_remaining, unit_cost, received_date, expiry_date)
        VALUES (?, ?, 'EXP-B', 'PURCHASE', 0, 30, 30, 20, '2026-06-01', date('now', '+30 days'))`).run(testItemId, testWhId);
            database_1.default.prepare('UPDATE stock_balances SET quantity = 60 WHERE item_id = ? AND warehouse_id = ?').run(testItemId, testWhId);
            // Consume 20: should only come from Batch B (expired A is excluded)
            const consumption = StockMovement_1.default.consumeFromOldestBatches(testItemId, testWhId, 20, database_1.default);
            expect(consumption).toHaveLength(1);
            expect(consumption[0].unitCost).toBe(20); // Only Batch B
            // Batch A should still have 30 remaining
            const batchA = database_1.default.prepare('SELECT quantity_remaining FROM stock_batches WHERE batch_no = ?').get('EXP-A');
            expect(batchA.quantity_remaining).toBe(30);
            database_1.default.prepare('UPDATE items SET has_expiry = 0 WHERE id = ?').run(testItemId);
        });
        it('FEFO: throws when all batches are halted/expired but stock_balances > 0', () => {
            database_1.default.prepare('DELETE FROM stock_batches WHERE item_id = ?').run(testItemId);
            database_1.default.prepare('UPDATE items SET has_expiry = 1 WHERE id = ?').run(testItemId);
            // Batch A: halted
            database_1.default.prepare(`INSERT INTO stock_batches (item_id, warehouse_id, batch_no, source_type, source_id, quantity_original, quantity_remaining, unit_cost, received_date, halted)
        VALUES (?, ?, 'BLOCKED-A', 'PURCHASE', 0, 30, 30, 10, '2026-01-01', 1)`).run(testItemId, testWhId);
            // Batch B: expired
            database_1.default.prepare(`INSERT INTO stock_batches (item_id, warehouse_id, batch_no, source_type, source_id, quantity_original, quantity_remaining, unit_cost, received_date, expiry_date)
        VALUES (?, ?, 'BLOCKED-B', 'PURCHASE', 0, 30, 30, 20, '2026-06-01', date('now', '-10 days'))`).run(testItemId, testWhId);
            database_1.default.prepare('UPDATE stock_balances SET quantity = 60 WHERE item_id = ? AND warehouse_id = ?').run(testItemId, testWhId);
            // Should throw — stock exists but all batches are blocked
            expect(() => {
                StockMovement_1.default.consumeFromOldestBatches(testItemId, testWhId, 10, database_1.default);
            }).toThrow('All batches for');
            database_1.default.prepare('UPDATE items SET has_expiry = 0 WHERE id = ?').run(testItemId);
        });
        it('FEFO: NULL expiry dates consumed after dated ones', () => {
            database_1.default.prepare('DELETE FROM stock_batches WHERE item_id = ?').run(testItemId);
            database_1.default.prepare('UPDATE items SET has_expiry = 1 WHERE id = ?').run(testItemId);
            // Batch A: no expiry date (NULL), 30 units
            database_1.default.prepare(`INSERT INTO stock_batches (item_id, warehouse_id, batch_no, source_type, source_id, quantity_original, quantity_remaining, unit_cost, received_date, expiry_date)
        VALUES (?, ?, 'NULL-A', 'PURCHASE', 0, 30, 30, 10, '2026-01-01', NULL)`).run(testItemId, testWhId);
            // Batch B: has expiry date (far future), 30 units
            database_1.default.prepare(`INSERT INTO stock_batches (item_id, warehouse_id, batch_no, source_type, source_id, quantity_original, quantity_remaining, unit_cost, received_date, expiry_date)
        VALUES (?, ?, 'NULL-B', 'PURCHASE', 0, 30, 30, 20, '2026-06-01', date('now', '+90 days'))`).run(testItemId, testWhId);
            database_1.default.prepare('UPDATE stock_balances SET quantity = 60 WHERE item_id = ? AND warehouse_id = ?').run(testItemId, testWhId);
            // Consume 40: should take 30 from B (has expiry) first, then 10 from A (NULL expiry)
            const consumption = StockMovement_1.default.consumeFromOldestBatches(testItemId, testWhId, 40, database_1.default);
            expect(consumption).toHaveLength(2);
            expect(consumption[0].unitCost).toBe(20); // Batch B first (dated)
            expect(consumption[0].consumed).toBe(30);
            expect(consumption[1].unitCost).toBe(10); // Batch A second (NULL)
            expect(consumption[1].consumed).toBe(10);
            database_1.default.prepare('UPDATE items SET has_expiry = 0 WHERE id = ?').run(testItemId);
        });
        it('legacy: uses standard_cost when no batch rows exist', () => {
            database_1.default.prepare('DELETE FROM stock_batches WHERE item_id = ?').run(testItemId);
            database_1.default.prepare('UPDATE items SET has_expiry = 0 WHERE id = ?').run(testItemId);
            // Set stock_balances to 50 but no batch rows (legacy stock)
            database_1.default.prepare('UPDATE stock_balances SET quantity = 50 WHERE item_id = ? AND warehouse_id = ?').run(testItemId, testWhId);
            const consumption = StockMovement_1.default.consumeFromOldestBatches(testItemId, testWhId, 20, database_1.default);
            expect(consumption).toHaveLength(1);
            expect(consumption[0].batchId).toBeNull(); // No batch
            expect(consumption[0].consumed).toBe(20);
            expect(consumption[0].unitCost).toBe(10); // Falls back to standard_cost
        });
    });
    describe('Purchase supplier/payment flow', () => {
        let itemId;
        let warehouseId = 1;
        let supplierId;
        let purchaseId;
        let purchaseNo;
        beforeAll(() => {
            itemId = Item_1.default.create({
                item_code: `PURCH-SUP-${Date.now()}`,
                item_name: 'Supplier Payment Test Item',
                category: 'Test',
                unit_of_measure: 'Nos',
                standard_cost: 25,
                standard_selling_price: 40,
            }, 1, database_1.default);
            const result = database_1.default.prepare(`
        INSERT INTO suppliers (supplier_code, supplier_name, is_active)
        VALUES (?, ?, 1)
      `).run(`MODEL-SUP-${Date.now()}`, 'Model Supplier Payment Test');
            supplierId = Number(result.lastInsertRowid);
        });
        afterAll(() => {
            database_1.default.prepare(`DELETE FROM stock_movements WHERE item_id = ?`).run(itemId);
            database_1.default.prepare(`DELETE FROM stock_balances WHERE item_id = ?`).run(itemId);
            database_1.default.prepare(`DELETE FROM stock_batches WHERE item_id = ?`).run(itemId);
            database_1.default.prepare(`DELETE FROM supplier_ledger WHERE supplier_id = ?`).run(supplierId);
            database_1.default.prepare(`DELETE FROM suppliers WHERE id = ?`).run(supplierId);
            Item_1.default.delete(itemId, database_1.default);
        });
        it('records a purchase linked to a supplier and posts the AP ledger entry', () => {
            const purchase = Purchase_1.default.recordPurchase({
                item_id: itemId,
                warehouse_id: warehouseId,
                quantity: 10,
                unit_cost: 25,
                supplier_id: supplierId,
                purchase_date: '2026-08-01',
            }, 1, database_1.default);
            purchaseId = purchase.id;
            purchaseNo = purchase.purchase_no;
            expect(purchase.supplier_id).toBe(supplierId);
            expect(purchase.supplier_name).toBe('Model Supplier Payment Test');
            expect(purchase.total_cost).toBe(250);
            const entry = SupplierLedger_1.default.getTransactions(supplierId, database_1.default).find((e) => e.transaction_type === 'PURCHASE' && e.reference_no === purchaseNo);
            expect(entry).toBeDefined();
            expect(entry?.debit).toBe(250);
            expect(SupplierLedger_1.default.getBalance(supplierId, database_1.default)).toBe(250);
        });
        it('allocates a supplier payment against the purchase and reduces the balance', () => {
            const paymentId = Payment_1.default.createSupplierPayment(database_1.default, {
                supplier_id: supplierId,
                payment_date: '2026-08-02',
                amount: 100,
                payment_method: 'Cash',
                po_allocations: [],
                purchase_allocations: [{ purchase_id: String(purchaseId), amount: 100 }],
                userId: 1,
            });
            expect(paymentId).toBeGreaterThan(0);
            const alloc = database_1.default.prepare('SELECT * FROM purchase_allocations WHERE payment_id = ?').get(paymentId);
            expect(alloc.purchase_id).toBe(purchaseId);
            expect(alloc.amount).toBe(100);
            expect(SupplierLedger_1.default.getBalance(supplierId, database_1.default)).toBe(150);
        });
        it('rejects an allocation exceeding the remaining purchase balance', () => {
            expect(() => Payment_1.default.createSupplierPayment(database_1.default, {
                supplier_id: supplierId,
                payment_date: '2026-08-03',
                amount: 200,
                payment_method: 'Cash',
                po_allocations: [],
                purchase_allocations: [{ purchase_id: String(purchaseId), amount: 200 }],
                userId: 1,
            })).toThrow(/exceeds the remaining balance/);
        });
        it('rejects payments without any PO or purchase allocation', () => {
            expect(() => Payment_1.default.createSupplierPayment(database_1.default, {
                supplier_id: supplierId,
                payment_date: '2026-08-03',
                amount: 50,
                payment_method: 'Cash',
                po_allocations: [],
                userId: 1,
            })).toThrow(/At least one PO or purchase allocation/);
        });
        it('lists the payment history for the purchase', () => {
            const history = Purchase_1.default.getPayments(purchaseId, database_1.default);
            expect(history).toHaveLength(1);
            expect(history[0].amount).toBe(100);
            expect(history[0].payment_no).toMatch(/^PAY/);
        });
        it('exposes paid/balance amounts on the purchase row', () => {
            const row = Purchase_1.default.getById(purchaseId, database_1.default);
            expect(row?.paid_amount).toBe(100);
            expect(row?.balance_amount).toBe(150);
            const { rows } = Purchase_1.default.getAll({}, database_1.default);
            const listed = rows.find((r) => r.id === purchaseId);
            expect(listed?.paid_amount).toBe(100);
            expect(listed?.balance_amount).toBe(150);
        });
        it('blocks deleting a purchase that has recorded payments', () => {
            expect(() => Purchase_1.default.delete(purchaseId, 1, database_1.default)).toThrow(/Cannot delete purchase with recorded payments/);
        });
        it('deleting the payment restores the balance and allows purchase deletion', () => {
            const paymentId = database_1.default.prepare('SELECT payment_id FROM purchase_allocations WHERE purchase_id = ?').get(purchaseId).payment_id;
            Payment_1.default.delete(database_1.default, paymentId);
            // Payment removed → only the purchase entry remains.
            expect(SupplierLedger_1.default.getBalance(supplierId, database_1.default)).toBe(250);
            Purchase_1.default.delete(purchaseId, 1, database_1.default);
            expect(SupplierLedger_1.default.getBalance(supplierId, database_1.default)).toBe(0);
        });
    });
    describe('PO payment history', () => {
        let poSupplierId;
        let poId;
        beforeAll(() => {
            const result = database_1.default.prepare(`
        INSERT INTO suppliers (supplier_code, supplier_name, is_active)
        VALUES (?, ?, 1)
      `).run(`MODEL-PO-SUP-${Date.now()}`, 'Model PO Payment Test');
            poSupplierId = Number(result.lastInsertRowid);
            const po = PurchaseOrder_1.default.create({
                supplier_id: poSupplierId,
                po_date: '2026-08-01',
                status: 'Draft',
                items: [{ item_id: 1, quantity: 5, unit_price: 20 }],
            }, 1, database_1.default);
            poId = po.id;
        });
        afterAll(() => {
            Payment_1.default.delete(database_1.default, database_1.default.prepare('SELECT payment_id FROM po_allocations WHERE po_id = ? LIMIT 1').get(poId).payment_id);
            PurchaseOrder_1.default.delete(poId, 1, database_1.default);
            database_1.default.prepare(`DELETE FROM supplier_ledger WHERE supplier_id = ?`).run(poSupplierId);
            database_1.default.prepare(`DELETE FROM suppliers WHERE id = ?`).run(poSupplierId);
        });
        it('returns the payments allocated to a PO', () => {
            Payment_1.default.createSupplierPayment(database_1.default, {
                supplier_id: poSupplierId,
                payment_date: '2026-08-02',
                amount: 60,
                payment_method: 'Bank Transfer',
                po_allocations: [{ po_id: String(poId), amount: 60 }],
                purchase_allocations: [],
                userId: 1,
            });
            const history = PurchaseOrder_1.default.getPayments(poId, database_1.default);
            expect(history).toHaveLength(1);
            expect(history[0].amount).toBe(60);
            expect(history[0].payment_method).toBe('Bank Transfer');
        });
    });
    describe('supplier payment purchase_order_id linking', () => {
        let supId;
        let poId;
        let poId2;
        let purchaseId;
        beforeAll(() => {
            const r = database_1.default.prepare(`INSERT INTO suppliers (supplier_code, supplier_name, is_active) VALUES (?, ?, 1)`).run(`POID-SUP-${Date.now()}`, 'PO Id Link Test');
            supId = Number(r.lastInsertRowid);
            const po = PurchaseOrder_1.default.create({ supplier_id: supId, po_date: '2026-08-01', status: 'Draft', items: [{ item_id: 1, quantity: 5, unit_price: 20 }] }, 1, database_1.default);
            poId = po.id;
            const po2 = PurchaseOrder_1.default.create({ supplier_id: supId, po_date: '2026-08-01', status: 'Draft', items: [{ item_id: 1, quantity: 3, unit_price: 20 }] }, 1, database_1.default);
            poId2 = po2.id;
            const pr = database_1.default.prepare(`INSERT INTO purchases (purchase_no, item_id, warehouse_id, quantity, unit_cost, total_cost, supplier_id, created_by, purchase_date)
         VALUES (?, ?, 1, 1, 10, 10, ?, ?, '2026-08-01')`).run(`POID-PUR-${Date.now()}`, 1, supId, 1);
            purchaseId = Number(pr.lastInsertRowid);
        });
        afterAll(() => {
            const pids = database_1.default.prepare('SELECT id FROM payments WHERE supplier_id = ?').all(supId);
            for (const p of pids)
                Payment_1.default.delete(database_1.default, p.id);
            if (purchaseId)
                database_1.default.prepare('DELETE FROM purchases WHERE id = ?').run(purchaseId);
            PurchaseOrder_1.default.delete(poId, 1, database_1.default);
            PurchaseOrder_1.default.delete(poId2, 1, database_1.default);
            database_1.default.prepare('DELETE FROM supplier_ledger WHERE supplier_id = ?').run(supId);
            database_1.default.prepare('DELETE FROM suppliers WHERE id = ?').run(supId);
        });
        it('sets purchase_order_id for a single-PO supplier payment', () => {
            const paymentId = Payment_1.default.createSupplierPayment(database_1.default, {
                supplier_id: supId,
                payment_date: '2026-08-02',
                amount: 50,
                po_allocations: [{ po_id: String(poId), amount: 50 }],
                purchase_allocations: [],
                userId: 1,
            });
            const row = database_1.default.prepare('SELECT purchase_order_id FROM payments WHERE id = ?').get(paymentId);
            expect(row.purchase_order_id).toBe(poId);
            const alloc = database_1.default.prepare('SELECT po_id FROM po_allocations WHERE payment_id = ?').get(paymentId);
            expect(alloc.po_id).toBe(poId);
        });
        it('leaves purchase_order_id NULL for a multi-PO supplier payment', () => {
            const paymentId = Payment_1.default.createSupplierPayment(database_1.default, {
                supplier_id: supId,
                payment_date: '2026-08-03',
                amount: 80,
                po_allocations: [
                    { po_id: String(poId), amount: 50 },
                    { po_id: String(poId2), amount: 30 },
                ],
                purchase_allocations: [],
                userId: 1,
            });
            const row = database_1.default.prepare('SELECT purchase_order_id FROM payments WHERE id = ?').get(paymentId);
            expect(row.purchase_order_id).toBeNull();
        });
        it('leaves purchase_order_id NULL for a mixed PO + purchase supplier payment', () => {
            const paymentId = Payment_1.default.createSupplierPayment(database_1.default, {
                supplier_id: supId,
                payment_date: '2026-08-04',
                amount: 35,
                po_allocations: [{ po_id: String(poId2), amount: 30 }],
                purchase_allocations: [{ purchase_id: String(purchaseId), amount: 5 }],
                userId: 1,
            });
            const row = database_1.default.prepare('SELECT purchase_order_id FROM payments WHERE id = ?').get(paymentId);
            expect(row.purchase_order_id).toBeNull();
        });
    });
    describe('recordBatchMovement', () => {
        let testItemId2;
        let testWhId2;
        beforeAll(() => {
            testItemId2 = Item_1.default.create({
                item_code: `BATCH-MOVE-${Date.now()}`,
                item_name: 'Batch Movement Test Item',
                category: 'Test',
                unit_of_measure: 'Nos',
                standard_cost: 12,
                standard_selling_price: 30,
            }, 1, database_1.default);
            testWhId2 = 1;
            database_1.default.prepare(`DELETE FROM stock_balances WHERE item_id = ? AND warehouse_id = ?`).run(testItemId2, testWhId2);
            database_1.default.prepare(`DELETE FROM stock_batches WHERE item_id = ? AND warehouse_id = ?`).run(testItemId2, testWhId2);
            database_1.default.prepare(`INSERT INTO stock_balances (item_id, warehouse_id, quantity) VALUES (?, ?, 0)`).run(testItemId2, testWhId2);
        });
        afterAll(() => {
            database_1.default.prepare(`DELETE FROM stock_movements WHERE item_id = ?`).run(testItemId2);
            database_1.default.prepare(`DELETE FROM stock_balances WHERE item_id = ?`).run(testItemId2);
            database_1.default.prepare(`DELETE FROM stock_batches WHERE item_id = ?`).run(testItemId2);
            Item_1.default.delete(testItemId2, database_1.default);
        });
        it('delegates to recordMovement for incoming movements', () => {
            const results = StockMovement_1.default.recordBatchMovement({
                item_id: testItemId2,
                warehouse_id: testWhId2,
                movement_type: 'PURCHASE',
                quantity: 50,
                unit_cost: 22,
                remarks: 'Test incoming batch movement',
            }, 1, database_1.default);
            expect(results).toHaveLength(1);
            expect(results[0].id).toBeGreaterThan(0);
            expect(results[0].movement_no).toMatch(/^STK-/);
            expect(results[0].quantity).toBe(50);
            // Verify stock_balance updated
            const balance = StockMovement_1.default.getBalance(testItemId2, testWhId2, database_1.default);
            expect(balance.quantity).toBe(50);
        });
        it('consumes from batches for outgoing movements', () => {
            // Manually create two batches
            database_1.default.prepare(`INSERT INTO stock_batches (item_id, warehouse_id, batch_no, source_type, source_id, quantity_original, quantity_remaining, unit_cost, received_date)
        VALUES (?, ?, 'BATCH-MOVE-1', 'PURCHASE', 0, 30, 30, 18, '2025-01-01')`).run(testItemId2, testWhId2);
            database_1.default.prepare(`INSERT INTO stock_batches (item_id, warehouse_id, batch_no, source_type, source_id, quantity_original, quantity_remaining, unit_cost, received_date)
        VALUES (?, ?, 'BATCH-MOVE-2', 'PURCHASE', 0, 20, 20, 25, '2025-06-01')`).run(testItemId2, testWhId2);
            // Update stock_balance to reflect batches
            database_1.default.prepare(`UPDATE stock_balances SET quantity = 100 WHERE item_id = ? AND warehouse_id = ?`).run(testItemId2, testWhId2);
            // Record outgoing TRANSFER of 40 units
            const results = StockMovement_1.default.recordBatchMovement({
                item_id: testItemId2,
                warehouse_id: testWhId2,
                movement_type: 'TRANSFER',
                quantity: -40,
                remarks: 'Test outgoing batch movement',
            }, 1, database_1.default);
            // Should consume 30 from batch1, 10 from batch2 = 2 movements
            expect(results.length).toBeGreaterThanOrEqual(2);
            // First movement: 30 units from batch1 @ 18
            expect(results[0].quantity).toBe(-30);
            expect(results[0].unit_cost).toBe(18);
            expect(results[0].batch_id).not.toBeNull();
            // Second movement: 10 units from batch2 @ 25
            expect(results[1].quantity).toBe(-10);
            expect(results[1].unit_cost).toBe(25);
            expect(results[1].batch_id).not.toBeNull();
            // Verify batch remaining quantities
            const batch1Check = database_1.default.prepare(`SELECT quantity_remaining FROM stock_batches WHERE id = ?`).get(results[0].batch_id);
            expect(batch1Check.quantity_remaining).toBe(0);
            const batch2Check = database_1.default.prepare(`SELECT quantity_remaining FROM stock_batches WHERE id = ?`).get(results[1].batch_id);
            expect(batch2Check.quantity_remaining).toBe(10);
        });
    });
});
//# sourceMappingURL=models.test.js.map