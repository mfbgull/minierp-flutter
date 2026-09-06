import { Request, Response } from 'express';
import { getQueryInteger, getQueryParam } from '../utils/queryUtils';
import ItemModel from '../models/Item';
import WarehouseModel from '../models/Warehouse';
import StockMovementModel from '../models/StockMovement';
import PhysicalCountModel from '../models/PhysicalCount';
import { AuthRequest } from '../types';
import { logCRUD, ActionType } from '../services/activityLogger';
import db from '../config/database';
import logger from '../utils/logger';

function getItems(req: Request, res: Response): void {
  try {
    const page = getQueryInteger(req.query.page, 1);
    const limit = getQueryInteger(req.query.limit, 10);
    const search = getQueryParam(req.query.search);
    const category = getQueryParam(req.query.category);
    const sortBy = getQueryParam(req.query.sortBy);
    const sortOrder = getQueryParam(req.query.sortOrder);
    const lowStock = getQueryParam(req.query.low_stock);
    const isRawMaterial = getQueryParam(req.query.is_raw_material);
    const isFinishedGood = getQueryParam(req.query.is_finished_good);

    const truthy = (v: string | undefined) =>
      v === '1' || v?.toLowerCase() === 'true';

    const { rows, total, pageNum, limitNum } = ItemModel.getAll({
      search: search || undefined,
      category: category || undefined,
      lowStock: truthy(lowStock),
      is_raw_material: isRawMaterial === undefined ? undefined : truthy(isRawMaterial),
      is_finished_good: isFinishedGood === undefined ? undefined : truthy(isFinishedGood),
      sortBy: sortBy || undefined,
      sortOrder: sortOrder || undefined,
      page,
      limit
    }, db);

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
  } catch (error) {
    logger.error('Get items error:', error);
    res.status(500).json({ error: 'Failed to fetch items' });
  }
}

function getItem(req: Request, res: Response): void {
  try {
    const item = ItemModel.getById(Number(req.params.id), db);

    if (!item) {
      res.status(404).json({ error: 'Item not found' });
      return;
    }

    const stockByWarehouse = ItemModel.getStockByWarehouse(item.id, db);

    res.json({
      ...item,
      stock_by_warehouse: stockByWarehouse
    });
  } catch (error) {
    logger.error('Get item error:', error);
    res.status(500).json({ error: 'Failed to fetch item' });
  }
}

function createItem(req: AuthRequest, res: Response): void {
  try {
    const { item_code, item_name } = req.body;

    if (!item_code || !item_name) {
      res.status(400).json({ error: 'Item code and name are required' });
      return;
    }

    const existing = ItemModel.getByCode(item_code, db);
    if (existing) {
      res.status(400).json({ error: 'Item code already exists' });
      return;
    }

    const itemId = ItemModel.create(req.body, req.user!.id, db);

    // Log item creation using activity logger
    logCRUD(ActionType.ITEM_CREATE, 'Item', itemId, `Created item: ${item_name}`, req.user!.id, {
      item_code,
      item_name,
      category: req.body.category
    });
    req.activityLogged = true;

    const newItem = ItemModel.getById(itemId, db);
    res.status(201).json(newItem);
  } catch (error) {
    logger.error('Create item error:', error);
    res.status(500).json({ error: 'Failed to create item' });
  }
}

function updateItem(req: AuthRequest, res: Response): void {
  try {
    const itemId = Number(req.params.id);
    const existingItem = ItemModel.getById(itemId, db);

    if (!existingItem) {
      res.status(404).json({ error: 'Item not found' });
      return;
    }

    ItemModel.update(itemId, req.body, db);

    // Log item update using activity logger
    logCRUD(ActionType.ITEM_UPDATE, 'Item', itemId, `Updated item: ${req.body.item_name || existingItem.item_name}`, req.user!.id, {
      changes: Object.keys(req.body)
    });
    req.activityLogged = true;

    const updatedItem = ItemModel.getById(itemId, db);
    res.json(updatedItem);
  } catch (error) {
    logger.error('Update item error:', error);
    res.status(500).json({ error: 'Failed to update item' });
  }
}

function deleteItem(req: AuthRequest, res: Response): void {
  try {
    const itemId = Number(req.params.id);
    const item = ItemModel.getById(itemId, db);

    if (!item) {
      res.status(404).json({ error: 'Item not found' });
      return;
    }

    // Check stock_balances (authoritative stock count) instead of item.current_stock
    const totalStock = db.prepare(`
      SELECT COALESCE(SUM(quantity), 0) as total FROM stock_balances WHERE item_id = ?
    `).get(itemId) as { total: number } | undefined;

    if (totalStock && totalStock.total > 0) {
      res.status(400).json({ error: `Cannot delete item with existing stock (${totalStock.total} units)` });
      return;
    }

    // Soft-delete (SHORTCOMINGS-FIX 4.2): stamp deleted_at + deactivate
    // so the row can be restored instead of being lost forever.
    ItemModel.delete(itemId, req.user!.id, db);

    // Log item deletion using activity logger
    logCRUD(ActionType.ITEM_DELETE, 'Item', itemId, `Deleted item: ${item.item_name}`, req.user!.id, {
      item_code: item.item_code
    });
    req.activityLogged = true;

    res.json({ success: true, message: 'Item deleted successfully' });
  } catch (error) {
    logger.error('Delete item error:', error);
    res.status(500).json({ error: 'Failed to delete item' });
  }
}

function getCategories(req: Request, res: Response): void {
  try {
    const categories = ItemModel.getCategories(db);
    res.json(categories);
  } catch (error) {
    logger.error('Get categories error:', error);
    res.status(500).json({ error: 'Failed to fetch categories' });
  }
}

function getLowStock(req: Request, res: Response): void {
  try {
    const items = ItemModel.getLowStock(db);
    res.json(items);
  } catch (error) {
    logger.error('Get low stock error:', error);
    res.status(500).json({ error: 'Failed to fetch low stock items' });
  }
}

function getUnitsOfMeasure(req: Request, res: Response): void {
  try {
    const uoms = ItemModel.getUnitsOfMeasure(db);
    res.json(uoms);
  } catch (error) {
    logger.error('Get units of measure error:', error);
    res.status(500).json({ error: 'Failed to fetch units of measure' });
  }
}

function getWarehouses(req: Request, res: Response): void {
  try {
    const warehouses = WarehouseModel.getStockSummary(db);
    res.json({
      success: true,
      data: warehouses
    });
  } catch (error) {
    logger.error('Get warehouses error:', error);
    res.status(500).json({ error: 'Failed to fetch warehouses' });
  }
}

function getWarehouse(req: Request, res: Response): void {
  try {
    const warehouse = WarehouseModel.getById(db, Number(req.params.id));

    if (!warehouse) {
      res.status(404).json({ error: 'Warehouse not found' });
      return;
    }

    const stockSummary = WarehouseModel.getStockSummary(db);

    res.json({
      ...warehouse,
      stock_summary: stockSummary
    });
  } catch (error) {
    logger.error('Get warehouse error:', error);
    res.status(500).json({ error: 'Failed to fetch warehouse' });
  }
}

function createWarehouse(req: AuthRequest, res: Response): void {
  try {
    const { warehouse_code, warehouse_name } = req.body;

    if (!warehouse_code || !warehouse_name) {
      res.status(400).json({ error: 'Warehouse code and name are required' });
      return;
    }

    const existing = WarehouseModel.getByCode(db, warehouse_code);
    if (existing) {
      res.status(400).json({ error: 'Warehouse code already exists' });
      return;
    }

    const warehouseId = WarehouseModel.create(db, { warehouse_code, warehouse_name, location: req.body.location });

    // Log warehouse creation using activity logger
    logCRUD(ActionType.WAREHOUSE_CREATE, 'Warehouse', warehouseId, `Created warehouse: ${warehouse_name}`, req.user!.id, {
      warehouse_code,
      warehouse_name,
      location: req.body.location
    });
    req.activityLogged = true;

    const newWarehouse = WarehouseModel.getById(db, warehouseId);
    res.status(201).json(newWarehouse);
  } catch (error) {
    logger.error('Create warehouse error:', error);
    res.status(500).json({ error: 'Failed to create warehouse' });
  }
}

function updateWarehouse(req: AuthRequest, res: Response): void {
  try {
    const warehouseId = Number(req.params.id);
    const existing = WarehouseModel.getById(db, warehouseId);

    if (!existing) {
      res.status(404).json({ error: 'Warehouse not found' });
      return;
    }

    WarehouseModel.update(db, warehouseId, {
      warehouse_code: req.body.warehouse_code || existing.warehouse_code,
      warehouse_name: req.body.warehouse_name || existing.warehouse_name,
      location: req.body.location
    });

    // Log warehouse update using activity logger
    logCRUD(ActionType.WAREHOUSE_UPDATE, 'Warehouse', warehouseId, `Updated warehouse: ${req.body.warehouse_name || existing.warehouse_name}`, req.user!.id, {
      changes: Object.keys(req.body)
    });
    req.activityLogged = true;

    const updated = WarehouseModel.getById(db, warehouseId);
    res.json(updated);
  } catch (error) {
    logger.error('Update warehouse error:', error);
    res.status(500).json({ error: 'Failed to update warehouse' });
  }
}

function restoreItem(req: AuthRequest, res: Response): void {
  try {
    const itemId = Number(req.params.id);
    const item = ItemModel.getById(itemId, db);

    if (!item) {
      res.status(404).json({ error: 'Item not found' });
      return;
    }

    ItemModel.restore(itemId, db);
    const restoredItem = ItemModel.getById(itemId, db);

    logCRUD(ActionType.ITEM_RESTORE, 'Item', itemId, `Restored item: ${item.item_name}`, req.user!.id, {
      item_code: item.item_code
    });
    req.activityLogged = true;

    res.json({ success: true, data: restoredItem, message: 'Item restored successfully' });
  } catch (error) {
    logger.error('Restore item error:', error);
    res.status(500).json({ error: 'Failed to restore item' });
  }
}

function deleteWarehouse(req: AuthRequest, res: Response): void {
  try {
    const warehouseId = Number(req.params.id);
    const existing = WarehouseModel.getById(db, warehouseId);

    if (!existing) {
      res.status(404).json({ error: 'Warehouse not found' });
      return;
    }

    WarehouseModel.delete(db, warehouseId);

    logCRUD(ActionType.WAREHOUSE_DELETE, 'Warehouse', warehouseId, `Deleted warehouse: ${existing.warehouse_name}`, req.user!.id, {
      warehouse_code: existing.warehouse_code
    });
    req.activityLogged = true;

    res.json({ success: true, message: 'Warehouse deleted successfully' });
  } catch (error) {
    logger.error('Delete warehouse error:', error);
    res.status(500).json({ error: 'Failed to delete warehouse' });
  }
}

function getStockMovements(req: Request, res: Response): void {
  try {
    const page = getQueryInteger(req.query.page, 1);
    const limit = getQueryInteger(req.query.limit, 10);
    const movementType = getQueryParam(req.query.movement_type);
    const sortBy = getQueryParam(req.query.sortBy);
    const sortOrder = getQueryParam(req.query.sortOrder);
    const search = getQueryParam(req.query.search);

    const { rows, total, pageNum, limitNum } = StockMovementModel.getAll({
      movement_type: movementType,
      search,
      sortBy,
      sortOrder,
      page,
      limit
    }, db);

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
  } catch (error) {
    logger.error('Get stock movements error:', error);
    res.status(500).json({ error: 'Failed to fetch stock movements' });
  }
}

function getStockMovement(req: Request, res: Response): void {
  try {
    const movement = StockMovementModel.getById(Number(req.params.id), db);
    if (!movement) {
      res.status(404).json({ error: 'Stock movement not found' });
      return;
    }
    res.json(movement);
  } catch (error) {
    logger.error('Get stock movement error:', error);
    res.status(500).json({ error: 'Failed to fetch stock movement' });
  }
}

function createStockMovement(req: AuthRequest, res: Response): void {
  try {
    const { item_id, warehouse_id, quantity, movement_type } = req.body;

    if (!item_id || !warehouse_id || !quantity || !movement_type) {
      res.status(400).json({ error: 'Item, warehouse, quantity, and movement type are required' });
      return;
    }

    // Negative Stock Validation for Outgoing Movements
    if (['OUT', 'TRANSFER', 'ADJUSTMENT'].includes(movement_type) && quantity < 0) {
      const currentStock = StockMovementModel.getBalance(item_id, warehouse_id, db) as { quantity: number } | undefined;
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

    let results: Array<{ id: number; movement_no: string }>;

    if (useBatchConsumption) {
      results = StockMovementModel.recordBatchMovement(req.body, req.user!.id, db);
    } else {
      const r = StockMovementModel.recordMovement(req.body, req.user!.id, db);
      results = [r];
    }

    const item = ItemModel.getById(item_id, db);
    const warehouse = WarehouseModel.getById(db, warehouse_id);

    // Log stock movement using activity logger (log the first/primary movement)
    const primaryResult = results[0];
    logCRUD(ActionType.STOCK_MOVEMENT, 'StockMovement', primaryResult.id, `${movement_type}: ${quantity} ${item?.unit_of_measure || 'units'} of ${item?.item_name} at ${warehouse?.warehouse_name}${results.length > 1 ? ` (${results.length} batches)` : ''}`, req.user!.id, {
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
    const firstMovement = StockMovementModel.getById(primaryResult.id, db);
    res.status(201).json(firstMovement);
  } catch (error) {
    logger.error('Create stock movement error:', error);
    res.status(500).json({ error: 'Failed to create stock movement' });
  }
}


/**
 * POST /api/inventory/stock-transfers (INV-02)
 * Atomic two-warehouse transfer: FIFO consumption at source, mirrored
 * TRANSFER cost layer at destination, both movements written server-side
 * inside one transaction. Replaces the client's two-call orchestration.
 */
function createStockTransfer(req: AuthRequest, res: Response): void {
  try {
    const { item_id, from_warehouse_id, to_warehouse_id, quantity, remarks } = req.body;

    if (!item_id || !from_warehouse_id || !to_warehouse_id) {
      res.status(400).json({ error: 'Item, source warehouse, and destination warehouse are required' });
      return;
    }
    const qty = Number(quantity);
    if (!Number.isFinite(qty) || qty <= 0) {
      res.status(400).json({ error: 'Quantity must be a positive number' });
      return;
    }
    if (from_warehouse_id === to_warehouse_id) {
      res.status(400).json({ error: 'Source and destination warehouses must differ' });
      return;
    }

    const result = StockMovementModel.recordTransfer(
      { item_id, from_warehouse_id, to_warehouse_id, quantity: qty, remarks: remarks || null },
      req.user!.id,
      db
    );

    res.status(201).json({
      success: true,
      data: result,
      error: null
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Failed to record transfer';
    const isClientError = /Insufficient stock|must differ|must be positive/i.test(message);
    if (isClientError) {
      res.status(400).json({ error: message });
    } else {
      logger.error('Stock transfer failed:', message);
      res.status(500).json({ error: 'Failed to record transfer' });
    }
  }
}

function getStockSummary(req: Request, res: Response): void {
  try {
    const summary = StockMovementModel.getStockSummary(db);
    res.json(summary);
  } catch (error) {
    logger.error('Get stock summary error:', error);
    res.status(500).json({ error: 'Failed to fetch stock summary' });
  }
}

function getItemLedger(req: Request, res: Response): void {
  try {
    const itemId = Number(req.params.itemId);
    const warehouseIdParam = getQueryParam(req.query.warehouse_id);
    const warehouseId = warehouseIdParam ? Number(warehouseIdParam) : null;

    const ledger = StockMovementModel.getItemLedger(itemId, warehouseId, db);
    res.json(ledger);
  } catch (error) {
    logger.error('Get item ledger error:', error);
    res.status(500).json({ error: 'Failed to fetch item ledger' });
  }
}

function getStockBalances(req: Request, res: Response): void {
  try {
    const page = getQueryInteger(req.query.page, 1);
    const limit = getQueryInteger(req.query.limit, 10);
    const search = getQueryParam(req.query.search);
    const warehouseCode = getQueryParam(req.query.warehouse_code);
    const sortBy = getQueryParam(req.query.sortBy);
    const sortOrder = getQueryParam(req.query.sortOrder);

    const { rows, total, pageNum, limitNum } = StockMovementModel.getStockBalances({
      search: search || undefined,
      warehouse_code: warehouseCode || undefined,
      sortBy: sortBy || undefined,
      sortOrder: sortOrder || undefined,
      page,
      limit
    }, db);

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
  } catch (error) {
    logger.error('Get stock balances error:', error);
    res.status(500).json({ error: 'Failed to fetch stock balances' });
  }
}

function getPhysicalCounts(req: Request, res: Response): void {
  try {
    const page = getQueryInteger(req.query.page, 1);
    const limit = getQueryInteger(req.query.limit, 10);
    const search = getQueryParam(req.query.search);
    const sortBy = getQueryParam(req.query.sortBy);
    const sortOrder = getQueryParam(req.query.sortOrder);

    const { rows, total, pageNum, limitNum } = PhysicalCountModel.getAll({
      search: search || undefined,
      sortBy: sortBy || undefined,
      sortOrder: sortOrder || undefined,
      page,
      limit
    }, db);

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
  } catch (error) {
    logger.error('Get physical counts error:', error);
    res.status(500).json({ error: 'Failed to fetch physical counts' });
  }
}

function getPhysicalCount(req: Request, res: Response): void {
  try {
    const count = PhysicalCountModel.getById(Number(req.params.id), db);

    if (!count) {
      res.status(404).json({ error: 'Physical count not found' });
      return;
    }

    const items = PhysicalCountModel.getItems(count.id, db);

    res.json({
      ...count,
      items
    });
  } catch (error) {
    logger.error('Get physical count error:', error);
    res.status(500).json({ error: 'Failed to fetch physical count' });
  }
}

function createPhysicalCount(req: AuthRequest, res: Response): void {
  try {
    const { warehouse_id, count_date, notes } = req.body;

    if (!warehouse_id) {
      res.status(400).json({ error: 'Warehouse is required' });
      return;
    }

    const warehouse = WarehouseModel.getById(db, warehouse_id);
    if (!warehouse) {
      res.status(400).json({ error: 'Warehouse not found' });
      return;
    }

    const countId = PhysicalCountModel.create({ warehouse_id, count_date, notes }, req.user!.id, db);

    logCRUD(ActionType.ITEM_CREATE, 'PhysicalCount', countId, `Created physical count for ${warehouse.warehouse_name}`, req.user!.id, {
      warehouse_id,
      warehouse_name: warehouse.warehouse_name
    });
    req.activityLogged = true;

    const newCount = PhysicalCountModel.getById(countId, db);
    res.status(201).json(newCount);
  } catch (error) {
    logger.error('Create physical count error:', error);
    res.status(500).json({ error: 'Failed to create physical count' });
  }
}

function recordPhysicalCountItem(req: AuthRequest, res: Response): void {
  try {
    const countId = Number(req.params.id);
    const { item_id, counted_quantity, notes } = req.body;

    if (item_id === undefined || counted_quantity === undefined) {
      res.status(400).json({ error: 'Item ID and counted quantity are required' });
      return;
    }

    PhysicalCountModel.recordCount(countId, item_id, counted_quantity, req.user!.id, notes || null, db);

    const item = PhysicalCountModel.getItems(countId, db).find(i => i.item_id === item_id);
    res.json(item);
  } catch (error: any) {
    logger.error('Record physical count item error:', error);
    res.status(500).json({ error: error.message || 'Failed to record count' });
  }
}

function completePhysicalCount(req: AuthRequest, res: Response): void {
  try {
    const countId = Number(req.params.id);
    PhysicalCountModel.completeCount(countId, req.user!.id, db);

    logCRUD(ActionType.ITEM_UPDATE, 'PhysicalCount', countId, `Completed physical count`, req.user!.id);
    req.activityLogged = true;

    const count = PhysicalCountModel.getById(countId, db);
    res.json(count);
  } catch (error: any) {
    logger.error('Complete physical count error:', error);
    res.status(500).json({ error: error.message || 'Failed to complete count' });
  }
}

function cancelPhysicalCount(req: AuthRequest, res: Response): void {
  try {
    const countId = Number(req.params.id);
    PhysicalCountModel.cancelCount(countId, req.user!.id, db);

    logCRUD(ActionType.ITEM_UPDATE, 'PhysicalCount', countId, `Cancelled physical count`, req.user!.id);
    req.activityLogged = true;

    const count = PhysicalCountModel.getById(countId, db);
    res.json(count);
  } catch (error: any) {
    logger.error('Cancel physical count error:', error);
    res.status(500).json({ error: error.message || 'Failed to cancel count' });
  }
}

function deletePhysicalCount(req: AuthRequest, res: Response): void {
  try {
    const countId = Number(req.params.id);
    PhysicalCountModel.deleteCount(countId, db);

    logCRUD(ActionType.ITEM_DELETE, 'PhysicalCount', countId, `Deleted physical count`, req.user!.id);
    req.activityLogged = true;

    res.json({ success: true, message: 'Physical count deleted' });
  } catch (error: any) {
    logger.error('Delete physical count error:', error);
    res.status(500).json({ error: error.message || 'Failed to delete count' });
  }
}

export default {
  getItems,
  getItem,
  createItem,
  updateItem,
  deleteItem, restoreItem,
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
  createStockTransfer,
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
