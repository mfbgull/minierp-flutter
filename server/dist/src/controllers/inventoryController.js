"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const queryUtils_1 = require("../utils/queryUtils");
const Item_1 = __importDefault(require("../models/Item"));
const Warehouse_1 = __importDefault(require("../models/Warehouse"));
const StockMovement_1 = __importDefault(require("../models/StockMovement"));
const PhysicalCount_1 = __importDefault(require("../models/PhysicalCount"));
const activityLogger_1 = require("../services/activityLogger");
const database_1 = __importDefault(require("../config/database"));
const logger_1 = __importDefault(require("../utils/logger"));
function getItems(req, res) {
    try {
        const page = (0, queryUtils_1.getQueryInteger)(req.query.page, 1);
        const limit = (0, queryUtils_1.getQueryInteger)(req.query.limit, 10);
        const search = (0, queryUtils_1.getQueryParam)(req.query.search);
        const category = (0, queryUtils_1.getQueryParam)(req.query.category);
        const sortBy = (0, queryUtils_1.getQueryParam)(req.query.sortBy);
        const sortOrder = (0, queryUtils_1.getQueryParam)(req.query.sortOrder);
        const lowStock = (0, queryUtils_1.getQueryParam)(req.query.low_stock);
        const isRawMaterial = (0, queryUtils_1.getQueryParam)(req.query.is_raw_material);
        const isFinishedGood = (0, queryUtils_1.getQueryParam)(req.query.is_finished_good);
        const truthy = (v) => v === '1' || v?.toLowerCase() === 'true';
        const { rows, total, pageNum, limitNum } = Item_1.default.getAll({
            search: search || undefined,
            category: category || undefined,
            lowStock: truthy(lowStock),
            is_raw_material: isRawMaterial === undefined ? undefined : truthy(isRawMaterial),
            is_finished_good: isFinishedGood === undefined ? undefined : truthy(isFinishedGood),
            sortBy: sortBy || undefined,
            sortOrder: sortOrder || undefined,
            page,
            limit
        }, database_1.default);
        res.json({
            success: true,
            data: rows,
            pagination: {
                currentPage: pageNum,
                totalPages: Math.ceil(total / limitNum),
                totalItems: total,
                hasNext: pageNum < Math.ceil(total / limitNum),
                hasPrev: pageNum > 1
            }
        });
    }
    catch (error) {
        logger_1.default.error('Get items error:', error);
        res.status(500).json({ error: 'Failed to fetch items' });
    }
}
function getItem(req, res) {
    try {
        const item = Item_1.default.getById(Number(req.params.id), database_1.default);
        if (!item) {
            res.status(404).json({ error: 'Item not found' });
            return;
        }
        const stockByWarehouse = Item_1.default.getStockByWarehouse(item.id, database_1.default);
        res.json({
            ...item,
            stock_by_warehouse: stockByWarehouse
        });
    }
    catch (error) {
        logger_1.default.error('Get item error:', error);
        res.status(500).json({ error: 'Failed to fetch item' });
    }
}
function createItem(req, res) {
    try {
        const { item_code, item_name } = req.body;
        if (!item_code || !item_name) {
            res.status(400).json({ error: 'Item code and name are required' });
            return;
        }
        const existing = Item_1.default.getByCode(item_code, database_1.default);
        if (existing) {
            res.status(400).json({ error: 'Item code already exists' });
            return;
        }
        const itemId = Item_1.default.create(req.body, req.user.id, database_1.default);
        // Log item creation using activity logger
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.ITEM_CREATE, 'Item', itemId, `Created item: ${item_name}`, req.user.id, {
            item_code,
            item_name,
            category: req.body.category
        });
        req.activityLogged = true;
        const newItem = Item_1.default.getById(itemId, database_1.default);
        res.status(201).json(newItem);
    }
    catch (error) {
        logger_1.default.error('Create item error:', error);
        res.status(500).json({ error: 'Failed to create item' });
    }
}
function updateItem(req, res) {
    try {
        const itemId = Number(req.params.id);
        const existingItem = Item_1.default.getById(itemId, database_1.default);
        if (!existingItem) {
            res.status(404).json({ error: 'Item not found' });
            return;
        }
        Item_1.default.update(itemId, req.body, database_1.default);
        // Log item update using activity logger
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.ITEM_UPDATE, 'Item', itemId, `Updated item: ${req.body.item_name || existingItem.item_name}`, req.user.id, {
            changes: Object.keys(req.body)
        });
        req.activityLogged = true;
        const updatedItem = Item_1.default.getById(itemId, database_1.default);
        res.json(updatedItem);
    }
    catch (error) {
        logger_1.default.error('Update item error:', error);
        res.status(500).json({ error: 'Failed to update item' });
    }
}
function deleteItem(req, res) {
    try {
        const itemId = Number(req.params.id);
        const item = Item_1.default.getById(itemId, database_1.default);
        if (!item) {
            res.status(404).json({ error: 'Item not found' });
            return;
        }
        // Check stock_balances (authoritative stock count) instead of item.current_stock
        const totalStock = database_1.default.prepare(`
      SELECT COALESCE(SUM(quantity), 0) as total FROM stock_balances WHERE item_id = ?
    `).get(itemId);
        if (totalStock && totalStock.total > 0) {
            res.status(400).json({ error: `Cannot delete item with existing stock (${totalStock.total} units)` });
            return;
        }
        Item_1.default.delete(itemId, database_1.default);
        // Log item deletion using activity logger
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.ITEM_DELETE, 'Item', itemId, `Deleted item: ${item.item_name}`, req.user.id, {
            item_code: item.item_code
        });
        req.activityLogged = true;
        res.json({ success: true, message: 'Item deleted successfully' });
    }
    catch (error) {
        logger_1.default.error('Delete item error:', error);
        res.status(500).json({ error: 'Failed to delete item' });
    }
}
function getCategories(req, res) {
    try {
        const categories = Item_1.default.getCategories(database_1.default);
        res.json(categories);
    }
    catch (error) {
        logger_1.default.error('Get categories error:', error);
        res.status(500).json({ error: 'Failed to fetch categories' });
    }
}
function getLowStock(req, res) {
    try {
        const items = Item_1.default.getLowStock(database_1.default);
        res.json(items);
    }
    catch (error) {
        logger_1.default.error('Get low stock error:', error);
        res.status(500).json({ error: 'Failed to fetch low stock items' });
    }
}
function getUnitsOfMeasure(req, res) {
    try {
        const uoms = Item_1.default.getUnitsOfMeasure(database_1.default);
        res.json(uoms);
    }
    catch (error) {
        logger_1.default.error('Get units of measure error:', error);
        res.status(500).json({ error: 'Failed to fetch units of measure' });
    }
}
function getWarehouses(req, res) {
    try {
        const warehouses = Warehouse_1.default.getStockSummary(database_1.default);
        res.json({
            success: true,
            data: warehouses
        });
    }
    catch (error) {
        logger_1.default.error('Get warehouses error:', error);
        res.status(500).json({ error: 'Failed to fetch warehouses' });
    }
}
function getWarehouse(req, res) {
    try {
        const warehouse = Warehouse_1.default.getById(database_1.default, Number(req.params.id));
        if (!warehouse) {
            res.status(404).json({ error: 'Warehouse not found' });
            return;
        }
        const stockSummary = Warehouse_1.default.getStockSummary(database_1.default);
        res.json({
            ...warehouse,
            stock_summary: stockSummary
        });
    }
    catch (error) {
        logger_1.default.error('Get warehouse error:', error);
        res.status(500).json({ error: 'Failed to fetch warehouse' });
    }
}
function createWarehouse(req, res) {
    try {
        const { warehouse_code, warehouse_name } = req.body;
        if (!warehouse_code || !warehouse_name) {
            res.status(400).json({ error: 'Warehouse code and name are required' });
            return;
        }
        const existing = Warehouse_1.default.getByCode(database_1.default, warehouse_code);
        if (existing) {
            res.status(400).json({ error: 'Warehouse code already exists' });
            return;
        }
        const warehouseId = Warehouse_1.default.create(database_1.default, { warehouse_code, warehouse_name, location: req.body.location });
        // Log warehouse creation using activity logger
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.WAREHOUSE_CREATE, 'Warehouse', warehouseId, `Created warehouse: ${warehouse_name}`, req.user.id, {
            warehouse_code,
            warehouse_name,
            location: req.body.location
        });
        req.activityLogged = true;
        const newWarehouse = Warehouse_1.default.getById(database_1.default, warehouseId);
        res.status(201).json(newWarehouse);
    }
    catch (error) {
        logger_1.default.error('Create warehouse error:', error);
        res.status(500).json({ error: 'Failed to create warehouse' });
    }
}
function updateWarehouse(req, res) {
    try {
        const warehouseId = Number(req.params.id);
        const existing = Warehouse_1.default.getById(database_1.default, warehouseId);
        if (!existing) {
            res.status(404).json({ error: 'Warehouse not found' });
            return;
        }
        Warehouse_1.default.update(database_1.default, warehouseId, {
            warehouse_code: req.body.warehouse_code || existing.warehouse_code,
            warehouse_name: req.body.warehouse_name || existing.warehouse_name,
            location: req.body.location
        });
        // Log warehouse update using activity logger
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.WAREHOUSE_UPDATE, 'Warehouse', warehouseId, `Updated warehouse: ${req.body.warehouse_name || existing.warehouse_name}`, req.user.id, {
            changes: Object.keys(req.body)
        });
        req.activityLogged = true;
        const updated = Warehouse_1.default.getById(database_1.default, warehouseId);
        res.json(updated);
    }
    catch (error) {
        logger_1.default.error('Update warehouse error:', error);
        res.status(500).json({ error: 'Failed to update warehouse' });
    }
}
function deleteWarehouse(req, res) {
    try {
        const warehouseId = Number(req.params.id);
        const existing = Warehouse_1.default.getById(database_1.default, warehouseId);
        if (!existing) {
            res.status(404).json({ error: 'Warehouse not found' });
            return;
        }
        Warehouse_1.default.delete(database_1.default, warehouseId);
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.WAREHOUSE_DELETE, 'Warehouse', warehouseId, `Deleted warehouse: ${existing.warehouse_name}`, req.user.id, {
            warehouse_code: existing.warehouse_code
        });
        req.activityLogged = true;
        res.json({ success: true, message: 'Warehouse deleted successfully' });
    }
    catch (error) {
        logger_1.default.error('Delete warehouse error:', error);
        res.status(500).json({ error: 'Failed to delete warehouse' });
    }
}
function getStockMovements(req, res) {
    try {
        const page = (0, queryUtils_1.getQueryInteger)(req.query.page, 1);
        const limit = (0, queryUtils_1.getQueryInteger)(req.query.limit, 10);
        const movementType = (0, queryUtils_1.getQueryParam)(req.query.movement_type);
        const sortBy = (0, queryUtils_1.getQueryParam)(req.query.sortBy);
        const sortOrder = (0, queryUtils_1.getQueryParam)(req.query.sortOrder);
        const search = (0, queryUtils_1.getQueryParam)(req.query.search);
        const { rows, total, pageNum, limitNum } = StockMovement_1.default.getAll({
            movement_type: movementType,
            search,
            sortBy,
            sortOrder,
            page,
            limit
        }, database_1.default);
        // Flat envelope matching the customers/suppliers shape the client's
        // `getPaged` helper expects: `data` is the item list and `pagination`
        // is a sibling of `data` (NOT nested inside it).
        res.json({
            success: true,
            data: rows,
            pagination: {
                currentPage: pageNum,
                totalPages: Math.ceil(total / limitNum),
                totalItems: total,
                hasNext: pageNum < Math.ceil(total / limitNum),
                hasPrev: pageNum > 1
            }
        });
    }
    catch (error) {
        logger_1.default.error('Get stock movements error:', error);
        res.status(500).json({ error: 'Failed to fetch stock movements' });
    }
}
function getStockMovement(req, res) {
    try {
        const movement = StockMovement_1.default.getById(Number(req.params.id), database_1.default);
        if (!movement) {
            res.status(404).json({ error: 'Stock movement not found' });
            return;
        }
        res.json(movement);
    }
    catch (error) {
        logger_1.default.error('Get stock movement error:', error);
        res.status(500).json({ error: 'Failed to fetch stock movement' });
    }
}
function createStockMovement(req, res) {
    try {
        const { item_id, warehouse_id, quantity, movement_type } = req.body;
        if (!item_id || !warehouse_id || !quantity || !movement_type) {
            res.status(400).json({ error: 'Item, warehouse, quantity, and movement type are required' });
            return;
        }
        // Negative Stock Validation for Outgoing Movements
        if (['OUT', 'TRANSFER', 'ADJUSTMENT'].includes(movement_type) && quantity < 0) {
            const currentStock = StockMovement_1.default.getBalance(item_id, warehouse_id, database_1.default);
            const availableQty = currentStock?.quantity || 0;
            if (availableQty < Math.abs(quantity)) {
                res.status(400).json({
                    error: 'Insufficient stock',
                    details: {
                        available: availableQty,
                        requested: Math.abs(quantity)
                    }
                });
                return;
            }
        }
        // Use batch-aware consumption for outgoing transfers and negative adjustments
        const useBatchConsumption = ['SALE', 'TRANSFER', 'ADJUSTMENT'].includes(movement_type) && quantity < 0;
        let results;
        if (useBatchConsumption) {
            results = StockMovement_1.default.recordBatchMovement(req.body, req.user.id, database_1.default);
        }
        else {
            const r = StockMovement_1.default.recordMovement(req.body, req.user.id, database_1.default);
            results = [r];
        }
        const item = Item_1.default.getById(item_id, database_1.default);
        const warehouse = Warehouse_1.default.getById(database_1.default, warehouse_id);
        // Log stock movement using activity logger (log the first/primary movement)
        const primaryResult = results[0];
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.STOCK_MOVEMENT, 'StockMovement', primaryResult.id, `${movement_type}: ${quantity} ${item?.unit_of_measure || 'units'} of ${item?.item_name} at ${warehouse?.warehouse_name}${results.length > 1 ? ` (${results.length} batches)` : ''}`, req.user.id, {
            item_id,
            item_code: item?.item_code,
            warehouse_id,
            warehouse_code: warehouse?.warehouse_code,
            movement_type,
            quantity,
            batch_count: results.length
        });
        req.activityLogged = true;
        // Return the first movement for backward compatibility
        const firstMovement = StockMovement_1.default.getById(primaryResult.id, database_1.default);
        res.status(201).json(firstMovement);
    }
    catch (error) {
        logger_1.default.error('Create stock movement error:', error);
        res.status(500).json({ error: 'Failed to create stock movement' });
    }
}
function getStockSummary(req, res) {
    try {
        const summary = StockMovement_1.default.getStockSummary(database_1.default);
        res.json(summary);
    }
    catch (error) {
        logger_1.default.error('Get stock summary error:', error);
        res.status(500).json({ error: 'Failed to fetch stock summary' });
    }
}
function getItemLedger(req, res) {
    try {
        const itemId = Number(req.params.itemId);
        const warehouseIdParam = (0, queryUtils_1.getQueryParam)(req.query.warehouse_id);
        const warehouseId = warehouseIdParam ? Number(warehouseIdParam) : null;
        const ledger = StockMovement_1.default.getItemLedger(itemId, warehouseId, database_1.default);
        res.json(ledger);
    }
    catch (error) {
        logger_1.default.error('Get item ledger error:', error);
        res.status(500).json({ error: 'Failed to fetch item ledger' });
    }
}
function getStockBalances(req, res) {
    try {
        const page = (0, queryUtils_1.getQueryInteger)(req.query.page, 1);
        const limit = (0, queryUtils_1.getQueryInteger)(req.query.limit, 10);
        const search = (0, queryUtils_1.getQueryParam)(req.query.search);
        const warehouseCode = (0, queryUtils_1.getQueryParam)(req.query.warehouse_code);
        const sortBy = (0, queryUtils_1.getQueryParam)(req.query.sortBy);
        const sortOrder = (0, queryUtils_1.getQueryParam)(req.query.sortOrder);
        const { rows, total, pageNum, limitNum } = StockMovement_1.default.getStockBalances({
            search: search || undefined,
            warehouse_code: warehouseCode || undefined,
            sortBy: sortBy || undefined,
            sortOrder: sortOrder || undefined,
            page,
            limit
        }, database_1.default);
        res.json({
            success: true,
            data: rows,
            pagination: {
                currentPage: pageNum,
                totalPages: Math.ceil(total / limitNum),
                totalItems: total,
                hasNext: pageNum < Math.ceil(total / limitNum),
                hasPrev: pageNum > 1
            }
        });
    }
    catch (error) {
        logger_1.default.error('Get stock balances error:', error);
        res.status(500).json({ error: 'Failed to fetch stock balances' });
    }
}
function getPhysicalCounts(req, res) {
    try {
        const page = (0, queryUtils_1.getQueryInteger)(req.query.page, 1);
        const limit = (0, queryUtils_1.getQueryInteger)(req.query.limit, 10);
        const search = (0, queryUtils_1.getQueryParam)(req.query.search);
        const sortBy = (0, queryUtils_1.getQueryParam)(req.query.sortBy);
        const sortOrder = (0, queryUtils_1.getQueryParam)(req.query.sortOrder);
        const { rows, total, pageNum, limitNum } = PhysicalCount_1.default.getAll({
            search: search || undefined,
            sortBy: sortBy || undefined,
            sortOrder: sortOrder || undefined,
            page,
            limit
        }, database_1.default);
        res.json({
            success: true,
            data: rows,
            pagination: {
                currentPage: pageNum,
                totalPages: Math.ceil(total / limitNum),
                totalItems: total,
                hasNext: pageNum < Math.ceil(total / limitNum),
                hasPrev: pageNum > 1
            }
        });
    }
    catch (error) {
        logger_1.default.error('Get physical counts error:', error);
        res.status(500).json({ error: 'Failed to fetch physical counts' });
    }
}
function getPhysicalCount(req, res) {
    try {
        const count = PhysicalCount_1.default.getById(Number(req.params.id), database_1.default);
        if (!count) {
            res.status(404).json({ error: 'Physical count not found' });
            return;
        }
        const items = PhysicalCount_1.default.getItems(count.id, database_1.default);
        res.json({
            ...count,
            items
        });
    }
    catch (error) {
        logger_1.default.error('Get physical count error:', error);
        res.status(500).json({ error: 'Failed to fetch physical count' });
    }
}
function createPhysicalCount(req, res) {
    try {
        const { warehouse_id, count_date, notes } = req.body;
        if (!warehouse_id) {
            res.status(400).json({ error: 'Warehouse is required' });
            return;
        }
        const warehouse = Warehouse_1.default.getById(database_1.default, warehouse_id);
        if (!warehouse) {
            res.status(400).json({ error: 'Warehouse not found' });
            return;
        }
        const countId = PhysicalCount_1.default.create({ warehouse_id, count_date, notes }, req.user.id, database_1.default);
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.ITEM_CREATE, 'PhysicalCount', countId, `Created physical count for ${warehouse.warehouse_name}`, req.user.id, {
            warehouse_id,
            warehouse_name: warehouse.warehouse_name
        });
        req.activityLogged = true;
        const newCount = PhysicalCount_1.default.getById(countId, database_1.default);
        res.status(201).json(newCount);
    }
    catch (error) {
        logger_1.default.error('Create physical count error:', error);
        res.status(500).json({ error: 'Failed to create physical count' });
    }
}
function recordPhysicalCountItem(req, res) {
    try {
        const countId = Number(req.params.id);
        const { item_id, counted_quantity, notes } = req.body;
        if (item_id === undefined || counted_quantity === undefined) {
            res.status(400).json({ error: 'Item ID and counted quantity are required' });
            return;
        }
        PhysicalCount_1.default.recordCount(countId, item_id, counted_quantity, req.user.id, notes || null, database_1.default);
        const item = PhysicalCount_1.default.getItems(countId, database_1.default).find(i => i.item_id === item_id);
        res.json(item);
    }
    catch (error) {
        logger_1.default.error('Record physical count item error:', error);
        res.status(500).json({ error: error.message || 'Failed to record count' });
    }
}
function completePhysicalCount(req, res) {
    try {
        const countId = Number(req.params.id);
        PhysicalCount_1.default.completeCount(countId, req.user.id, database_1.default);
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.ITEM_UPDATE, 'PhysicalCount', countId, `Completed physical count`, req.user.id);
        req.activityLogged = true;
        const count = PhysicalCount_1.default.getById(countId, database_1.default);
        res.json(count);
    }
    catch (error) {
        logger_1.default.error('Complete physical count error:', error);
        res.status(500).json({ error: error.message || 'Failed to complete count' });
    }
}
function cancelPhysicalCount(req, res) {
    try {
        const countId = Number(req.params.id);
        PhysicalCount_1.default.cancelCount(countId, req.user.id, database_1.default);
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.ITEM_UPDATE, 'PhysicalCount', countId, `Cancelled physical count`, req.user.id);
        req.activityLogged = true;
        const count = PhysicalCount_1.default.getById(countId, database_1.default);
        res.json(count);
    }
    catch (error) {
        logger_1.default.error('Cancel physical count error:', error);
        res.status(500).json({ error: error.message || 'Failed to cancel count' });
    }
}
function deletePhysicalCount(req, res) {
    try {
        const countId = Number(req.params.id);
        PhysicalCount_1.default.deleteCount(countId, database_1.default);
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.ITEM_DELETE, 'PhysicalCount', countId, `Deleted physical count`, req.user.id);
        req.activityLogged = true;
        res.json({ success: true, message: 'Physical count deleted' });
    }
    catch (error) {
        logger_1.default.error('Delete physical count error:', error);
        res.status(500).json({ error: error.message || 'Failed to delete count' });
    }
}
exports.default = {
    getItems,
    getItem,
    createItem,
    updateItem,
    deleteItem,
    getCategories,
    getLowStock,
    getUnitsOfMeasure,
    getWarehouses,
    getWarehouse,
    createWarehouse,
    updateWarehouse,
    deleteWarehouse,
    getStockMovements,
    getStockMovement,
    createStockMovement,
    getStockSummary,
    getItemLedger,
    getStockBalances,
    getPhysicalCounts,
    getPhysicalCount,
    createPhysicalCount,
    recordPhysicalCountItem,
    completePhysicalCount,
    cancelPhysicalCount,
    deletePhysicalCount
};
//# sourceMappingURL=inventoryController.js.map