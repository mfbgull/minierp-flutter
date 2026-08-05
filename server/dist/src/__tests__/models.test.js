"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const database_1 = __importDefault(require("../config/database"));
const Item_1 = __importDefault(require("../models/Item"));
const Warehouse_1 = __importDefault(require("../models/Warehouse"));
const StockMovement_1 = __importDefault(require("../models/StockMovement"));
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
        it('returns all active items', () => {
            const items = Item_1.default.getAll({}, database_1.default);
            expect(Array.isArray(items)).toBe(true);
            expect(items.length).toBeGreaterThan(0);
        });
        it('filters by category', () => {
            const items = Item_1.default.getAll({ category: 'Test' }, database_1.default);
            expect(items.length).toBeGreaterThan(0);
            items.forEach(item => {
                expect(item.category).toBe('Test');
            });
        });
        it('filters by search term', () => {
            const items = Item_1.default.getAll({ search: 'Model Test' }, database_1.default);
            expect(items.length).toBeGreaterThan(0);
        });
        it('returns empty array for non-matching search', () => {
            const items = Item_1.default.getAll({ search: 'zzzznonexistent' }, database_1.default);
            expect(items.length).toBe(0);
        });
        it('excludes inactive items', () => {
            const items = Item_1.default.getAll({}, database_1.default);
            items.forEach(item => {
                expect(item.is_active).toBe(1);
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
            const items = Item_1.default.getAll({}, database_1.default);
            const found = items.find(i => i.id === createdItemId);
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
        it('returns all movements', () => {
            const movements = StockMovement_1.default.getAll({}, database_1.default);
            expect(Array.isArray(movements)).toBe(true);
            expect(movements.length).toBeGreaterThan(0);
        });
        it('filters by item_id', () => {
            const movements = StockMovement_1.default.getAll({ item_id: 1 }, database_1.default);
            expect(movements.length).toBeGreaterThan(0);
            movements.forEach(m => {
                expect(m.item_id).toBe(1);
            });
        });
        it('filters by movement_type', () => {
            const movements = StockMovement_1.default.getAll({ movement_type: 'in' }, database_1.default);
            expect(movements.length).toBeGreaterThan(0);
            movements.forEach(m => {
                expect(m.movement_type).toBe('in');
            });
        });
        it('respects limit', () => {
            const movements = StockMovement_1.default.getAll({ limit: 5 }, database_1.default);
            expect(movements.length).toBeLessThanOrEqual(5);
        });
    });
    describe('getById', () => {
        it('returns movement by ID', () => {
            const movements = StockMovement_1.default.getAll({ limit: 1 }, database_1.default);
            if (movements.length > 0) {
                const movement = StockMovement_1.default.getById(movements[0].id, database_1.default);
                expect(movement).toBeDefined();
                expect(movement?.id).toBe(movements[0].id);
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