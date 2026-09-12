import { Request, Response } from 'express';
import { getQueryInteger, getQueryParam, getRouteParam } from '../utils/queryUtils';
import ItemModel from '../models/Item';
import WarehouseModel from '../models/Warehouse';
import StockMovementModel from '../models/StockMovement';
import PhysicalCountModel from '../models/PhysicalCount';
import { StockReservationModel } from '../models/StockReservation';
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
      location: req.body.location,
      // D25: accept is_active to allow reactivation after bulk deactivate
      ...(req.body.is_active !== undefined && { is_active: req.body.is_active ? 1 : 0 }),
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

    // FK-delete 400s (reversal-rules Phase 4): many tables reference
    // warehouses(id). Without these checks a hard DELETE surfaces as an
    // opaque 500 FK violation (or, worse, cascades silently).
    const refs: Array<string> = [];
    const count = (sql: string): number =>
      (db.prepare(sql).get(warehouseId) as { c: number }).c;

    const stock = count(
      `SELECT COUNT(*) AS c FROM stock_balances WHERE warehouse_id = ? AND quantity > 0`
    );
    if (stock > 0) refs.push(`${stock} item(s) still in stock`);

    const movements = count(
      `SELECT COUNT(*) AS c FROM stock_movements WHERE warehouse_id = ?`
    );
    if (movements > 0) refs.push(`${movements} stock movement(s)`);

    const batches = count(
      `SELECT COUNT(*) AS c FROM stock_batches WHERE warehouse_id = ? AND quantity_remaining > 0`
    );
    if (batches > 0) refs.push(`${batches} stock batch(es) with remaining units`);

    const purchases = count(
      `SELECT COUNT(*) AS c FROM purchases WHERE warehouse_id = ?`
    );
    if (purchases > 0) refs.push(`${purchases} purchase(s)`);

    const counts = count(
      `SELECT COUNT(*) AS c FROM physical_counts WHERE warehouse_id = ?`
    );
    if (counts > 0) refs.push(`${counts} physical count(s)`);

    const receipts = count(
      `SELECT COUNT(*) AS c FROM goods_receipts WHERE warehouse_id = ?`
    );
    if (receipts > 0) refs.push(`${receipts} goods receipt(s)`);

    const productions = count(
      `SELECT COUNT(*) AS c FROM productions WHERE warehouse_id = ?`
    );
    if (productions > 0) refs.push(`${productions} production(s)`);

    if (refs.length > 0) {
      res.status(400).json({ error: `Cannot delete warehouse with existing references: ${refs.join(', ')}` });
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

/**
 * POST /api/inventory/stock-transfers/:movementNo/void
 * Reversal-rules Phase 4: void a stock transfer. Stock-only reversal
 * (transfers have no GL effect): restores the source batch, draws down
 * the mirrored destination batch, and appends a TRANSFER_VOID reversal
 * pair. Refuses when the transferred units were already consumed from
 * the destination.
 */
function voidStockTransfer(req: AuthRequest, res: Response): void {
  try {
    const movementNo = getRouteParam(req.params.movementNo as string | string[]);
    if (!movementNo) {
      res.status(400).json({ error: 'Transfer movement number is required' });
      return;
    }

    const result = StockMovementModel.voidTransfer(
      { outMovementNo: movementNo },
      req.user!.id,
      db
    );

    res.json({
      success: true,
      message: `Transfer ${movementNo} voided`,
      data: result,
      error: null
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Failed to void transfer';
    const isClientError = /not found|already voided|cannot void|missing|consumed/i.test(message);
    if (isClientError) {
      res.status(400).json({ error: message });
    } else {
      logger.error('Stock transfer void failed:', message);
      res.status(500).json({ error: 'Failed to void transfer' });
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

/**
 * Reversal-rules Phase 4: correct a COMPLETED physical count
 * (POST /physical-counts/:id/correct). POSTED counts are immutable —
 * corrections reverse the original adjustment (stock + GL) and re-apply
 * the recounted quantities in one transaction.
 */
function correctPhysicalCount(req: AuthRequest, res: Response): void {
  try {
    const countId = Number(req.params.id);
    const corrections = req.body?.corrections;

    if (!Array.isArray(corrections) || corrections.length === 0) {
      res.status(400).json({ error: 'corrections array with item_id and counted_quantity is required' });
      return;
    }
    for (const c of corrections) {
      if (typeof c.item_id !== 'number' || typeof c.counted_quantity !== 'number') {
        res.status(400).json({ error: 'Each correction needs numeric item_id and counted_quantity' });
        return;
      }
    }

    PhysicalCountModel.correctCount(
      { countId, corrections },
      req.user!.id,
      db
    );

    logCRUD(ActionType.ITEM_UPDATE, 'PhysicalCount', countId, `Corrected physical count (${corrections.length} item(s) recounted)`, req.user!.id);
    req.activityLogged = true;

    const count = PhysicalCountModel.getById(countId, db);
    res.json(count);
  } catch (error: any) {
    const message = error?.message || String(error);
    if (
      message.includes('not found') ||
      message.includes('Only Completed') ||
      message.includes('already been corrected') ||
      message.includes('Cannot correct') ||
      message.includes('required') ||
      message.includes('snapshot row')
    ) {
      res.status(400).json({ error: message });
      return;
    }
    logger.error('Correct physical count error:', error);
    res.status(500).json({ error: message || 'Failed to correct count' });
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
  voidStockTransfer,
  getStockSummary,
  getItemLedger,
  getStockBalances,
  getPhysicalCounts,
  getPhysicalCount,
  createPhysicalCount,
  recordPhysicalCountItem,
  completePhysicalCount,
  cancelPhysicalCount,
  correctPhysicalCount,
  deletePhysicalCount,
  getBatchReconciliation,
  correctBatchReconciliation,
  updateBatchStatus,
  createReservation,
  releaseReservation,
  getReservations
};

// ============================================
// Batch Location & Reconciliation (new)
// ============================================

export function getBatchReconciliation(req: AuthRequest, res: Response): Response | void {
  try {
    const db = req.app.get('db');
    const { item_id, warehouse_id } = req.query as any;

    let where = 'WHERE 1=1';
    const params: any[] = [];

    if (item_id) {
      where += ' AND sb.item_id = ?';
      params.push(item_id);
    }
    if (warehouse_id) {
      where += ' AND l.warehouse_id = ?';
      params.push(warehouse_id);
    }

    const drifts = db.prepare(`
      SELECT sb.id as batch_id, sb.batch_no, sb.item_id, i.item_code, i.item_name,
             l.warehouse_id, w.warehouse_code, l.id as location_id, l.location_code,
             sb.quantity_remaining as master_qty,
             bsl.quantity_physical, bsl.quantity_reserved, bsl.quantity_available,
             bsl.status_override,
             (sb.quantity_remaining - bsl.quantity_physical) as drift
      FROM stock_batches sb
      JOIN items i ON sb.item_id = i.id
      JOIN batch_stock_by_location bsl ON sb.id = bsl.batch_id
      JOIN locations l ON bsl.location_id = l.id
      JOIN warehouses w ON l.warehouse_id = w.id
      ${where}
      AND ABS(sb.quantity_remaining - bsl.quantity_physical) > 0.001
      ORDER BY sb.id ASC
    `).all(...params);

    return res.json({ drifts });
  } catch (error: any) {
    logger.error('[BatchReconciliation] get failed:', error);
    return res.status(500).json({ error: error.message });
  }
}

export function correctBatchReconciliation(req: AuthRequest, res: Response): Response | void {
  try {
    const db = req.app.get('db');
    const { batch_id, location_id, new_quantity_physical } = req.body as any;
    const userId = req.user!.id;

    if (!batch_id || location_id === undefined || new_quantity_physical === undefined) {
      return res.status(400).json({ error: 'batch_id, location_id, and new_quantity_physical are required' });
    }

    const locRow = db.prepare(`SELECT warehouse_id FROM locations WHERE id = ?`).get(location_id) as { warehouse_id: number } | undefined;
    if (!locRow) {
      return res.status(404).json({ error: 'Location not found' });
    }

    const batch = db.prepare(`SELECT quantity_remaining FROM stock_batches WHERE id = ?`).get(batch_id) as { quantity_remaining: number } | undefined;
    if (!batch) {
      return res.status(404).json({ error: 'Batch not found' });
    }

    const newQty = parseFloat(String(new_quantity_physical));
    if (!Number.isFinite(newQty) || newQty < 0) {
      return res.status(400).json({ error: 'new_quantity_physical must be a non-negative number' });
    }

    const run = db.transaction(() => {
      // Update batch_stock_by_location
      db.prepare(`
        UPDATE batch_stock_by_location
        SET quantity_physical = ?, quantity_available = MAX(0, ? - quantity_reserved), updated_at = CURRENT_TIMESTAMP
        WHERE batch_id = ? AND location_id = ?
      `).run(newQty, newQty, batch_id, location_id);

      // Adjust master batch quantity_remaining to match total across locations
      const totalPhysical = db.prepare(`
        SELECT COALESCE(SUM(quantity_physical), 0) as total
        FROM batch_stock_by_location
        WHERE batch_id = ?
      `).get(batch_id) as { total: number };

      db.prepare(`
        UPDATE stock_batches SET quantity_remaining = ? WHERE id = ?
      `).run(totalPhysical.total, batch_id);

      // Record correction movement
      const diff = newQty - (db.prepare(`SELECT quantity_physical FROM batch_stock_by_location WHERE batch_id = ? AND location_id = ?`).get(batch_id, location_id) as any).quantity_physical;
      // Actually we already updated it, so let's get the old value from a subquery or just use the diff
      const oldRow = db.prepare(`
        SELECT quantity_physical FROM batch_stock_by_location WHERE batch_id = ? AND location_id = ?
      `).get(batch_id, location_id) as { quantity_physical: number };

      // Recalculate diff properly: we need old value. Let's do it before update.
    });

    // Re-implement with proper old value capture
    const oldRow = db.prepare(`
      SELECT quantity_physical FROM batch_stock_by_location WHERE batch_id = ? AND location_id = ?
    `).get(batch_id, location_id) as { quantity_physical: number } | undefined;
    const oldQty = oldRow?.quantity_physical ?? 0;
    const diff = newQty - oldQty;

    db.transaction(() => {
      db.prepare(`
        UPDATE batch_stock_by_location
        SET quantity_physical = ?, quantity_available = MAX(0, ? - quantity_reserved), updated_at = CURRENT_TIMESTAMP
        WHERE batch_id = ? AND location_id = ?
      `).run(newQty, newQty, batch_id, location_id);

      const totalPhysical = db.prepare(`
        SELECT COALESCE(SUM(quantity_physical), 0) as total
        FROM batch_stock_by_location
        WHERE batch_id = ?
      `).get(batch_id) as { total: number };

      db.prepare(`UPDATE stock_batches SET quantity_remaining = ? WHERE id = ?`).run(totalPhysical.total, batch_id);

      const movementNo = StockMovementModel.generateMovementNo(db);
      db.prepare(`
        INSERT INTO stock_movements (
          movement_no, item_id, warehouse_id, movement_type,
          quantity, unit_cost, reference_doctype, reference_docno,
          remarks, movement_date, created_by, batch_id
        ) VALUES (?, ?, ?, 'ADJUSTMENT', ?, 0, 'BATCH_RECONCILIATION', ?, ?, ?, ?)
      `).run(
        movementNo,
        (db.prepare(`SELECT item_id FROM stock_batches WHERE id = ?`).get(batch_id) as any).item_id,
        locRow.warehouse_id,
        diff,
        `RECON-${batch_id}`,
        `Batch reconciliation correction: ${oldQty} -> ${newQty}`,
        new Date().toISOString().split('T')[0],
        userId,
        batch_id
      );
    })();

    return res.json({ success: true, batch_id, location_id, old_quantity: oldQty, new_quantity: newQty, diff });
  } catch (error: any) {
    logger.error('[BatchReconciliation] correct failed:', error);
    return res.status(500).json({ error: error.message });
  }
}

export function updateBatchStatus(req: AuthRequest, res: Response): Response | void {
  try {
    const db = req.app.get('db');
    const { id } = req.params;
    const body = req.body as { location_id?: number; status_override?: string };
    const statusOverride = body.status_override as string;

    const batchId = parseInt(id as string, 10);
    const locationId = Number(body.location_id);
    if (!locationId || !statusOverride) {
      return res.status(400).json({ error: 'location_id and status_override are required' });
    }

    if (!['ACTIVE', 'BLOCKED', 'QUARANTINED', 'DAMAGED', 'REJECTED'].includes(statusOverride)) {
      return res.status(400).json({ error: 'Invalid status_override' });
    }

    db.prepare(`
      UPDATE batch_stock_by_location
      SET status_override = ?
      WHERE batch_id = ? AND location_id = ?
    `).run(statusOverride, batchId, locationId);

    return res.json({ success: true, batch_id: batchId, location_id: locationId, status_override: statusOverride });
  } catch (error: any) {
    logger.error('[BatchStatus] update failed:', error);
    return res.status(500).json({ error: error.message });
  }
}

export function createReservation(req: AuthRequest, res: Response): Response | void {
  try {
    const db = req.app.get('db');
    const { item_id, warehouse_id, location_id, batch_id, quantity_reserved, reference_doctype, reference_docno, reference_line_id } = req.body as any;
    const userId = req.user!.id;

    const reservation = StockReservationModel.create(
      { item_id, warehouse_id, location_id, batch_id, quantity_reserved, reference_doctype, reference_docno, reference_line_id },
      db
    );

    // Decrement quantity_available in batch_stock_by_location
    if (location_id && batch_id) {
      db.prepare(`
        UPDATE batch_stock_by_location
        SET quantity_reserved = quantity_reserved + ?, quantity_available = quantity_physical - (quantity_reserved + ?)
        WHERE batch_id = ? AND location_id = ?
      `).run(quantity_reserved, quantity_reserved, batch_id, location_id);
    }

    return res.status(201).json(reservation);
  } catch (error: any) {
    logger.error('[Reservation] create failed:', error);
    return res.status(500).json({ error: error.message });
  }
}

export function releaseReservation(req: AuthRequest, res: Response): Response | void {
  try {
    const db = req.app.get('db');
    const { id } = req.params;
    const reservationId = parseInt(id as string, 10);

    const reservation = StockReservationModel.getById(reservationId, db);
    if (!reservation) {
      return res.status(404).json({ error: 'Reservation not found' });
    }

    const released = StockReservationModel.release(
      { reference_doctype: reservation.reference_doctype, reference_docno: reservation.reference_docno, reference_line_id: reservation.reference_line_id },
      db
    );

    if (!released) {
      return res.status(400).json({ error: 'Reservation is not active' });
    }

    // Restore quantity_available
    if (reservation.batch_id && reservation.location_id) {
      db.prepare(`
        UPDATE batch_stock_by_location
        SET quantity_reserved = MAX(0, quantity_reserved - ?), quantity_available = quantity_physical - quantity_reserved
        WHERE batch_id = ? AND location_id = ?
      `).run(reservation.quantity_reserved, reservation.batch_id, reservation.location_id);
    }

    return res.json(released);
  } catch (error: any) {
    logger.error('[Reservation] release failed:', error);
    return res.status(500).json({ error: error.message });
  }
}

export function getReservations(req: AuthRequest, res: Response): Response | void {
  try {
    const db = req.app.get('db');
    const { doctype, docno } = req.query as any;

    let reservations: any[];
    if (doctype && docno) {
      reservations = StockReservationModel.getByReference(doctype as string, docno as string, db);
    } else {
      reservations = StockReservationModel.getAll(db);
    }

    return res.json({ reservations });
  } catch (error: any) {
    logger.error('[Reservation] list failed:', error);
    return res.status(500).json({ error: error.message });
  }
}
