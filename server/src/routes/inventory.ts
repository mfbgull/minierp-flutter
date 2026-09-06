import express from 'express';
const router = express.Router();
import inventoryController from '../controllers/inventoryController';
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import { sensitiveOperationLimiter } from '../middleware/rateLimiter';
import { validateZodQuery, validateZodBody, zodSchemas, zodBodySchemas } from '../middleware/validation';

router.use(authenticateToken);

router.get('/items', requirePermission('inventory', 'read'), validateZodQuery(zodSchemas.listQuery), inventoryController.getItems);
router.get('/items/:id', requirePermission('inventory', 'read'), inventoryController.getItem);
router.post('/items', requirePermission('inventory', 'create'), sensitiveOperationLimiter, validateZodBody(zodBodySchemas.itemCreate), inventoryController.createItem);
router.put('/items/:id', requirePermission('inventory', 'update'), sensitiveOperationLimiter, validateZodBody(zodBodySchemas.object), inventoryController.updateItem);
router.delete('/items/:id', requirePermission('inventory', 'delete'), sensitiveOperationLimiter, inventoryController.deleteItem);
router.post('/items/:id/restore', requirePermission('inventory', 'update'), inventoryController.restoreItem);

router.get('/items-categories', requirePermission('inventory', 'read'), inventoryController.getCategories);
router.get('/items-low-stock', requirePermission('inventory', 'read'), inventoryController.getLowStock);
router.get('/items-uom', requirePermission('inventory', 'read'), inventoryController.getUnitsOfMeasure);

router.get('/warehouses', requirePermission('inventory', 'read'), inventoryController.getWarehouses);
router.get('/warehouses/:id', requirePermission('inventory', 'read'), inventoryController.getWarehouse);
router.post('/warehouses', requirePermission('inventory', 'create'), sensitiveOperationLimiter, validateZodBody(zodBodySchemas.object), inventoryController.createWarehouse);
router.put('/warehouses/:id', requirePermission('inventory', 'update'), sensitiveOperationLimiter, validateZodBody(zodBodySchemas.object), inventoryController.updateWarehouse);
router.delete('/warehouses/:id', requirePermission('inventory', 'delete'), sensitiveOperationLimiter, inventoryController.deleteWarehouse);

router.get('/stock-movements', requirePermission('inventory', 'read'), inventoryController.getStockMovements);
router.get('/stock-movements/:id', requirePermission('inventory', 'read'), inventoryController.getStockMovement);
router.post('/stock-movements', requirePermission('inventory', 'create'), sensitiveOperationLimiter, inventoryController.createStockMovement);
router.post('/stock-transfers', requirePermission('inventory', 'create'), sensitiveOperationLimiter, inventoryController.createStockTransfer);

router.get('/stock-summary', requirePermission('inventory', 'read'), inventoryController.getStockSummary);
router.get('/stock-ledger/:itemId', requirePermission('inventory', 'read'), inventoryController.getItemLedger);
router.get('/stock-balances', requirePermission('inventory', 'read'), inventoryController.getStockBalances);

router.get('/physical-counts', requirePermission('inventory', 'read'), inventoryController.getPhysicalCounts);
router.get('/physical-counts/:id', requirePermission('inventory', 'read'), inventoryController.getPhysicalCount);
router.post('/physical-counts', requirePermission('inventory', 'create'), sensitiveOperationLimiter, inventoryController.createPhysicalCount);
router.post('/physical-counts/:id/items', requirePermission('inventory', 'update'), sensitiveOperationLimiter, inventoryController.recordPhysicalCountItem);
router.post('/physical-counts/:id/complete', requirePermission('inventory', 'update'), sensitiveOperationLimiter, inventoryController.completePhysicalCount);
router.post('/physical-counts/:id/cancel', requirePermission('inventory', 'update'), sensitiveOperationLimiter, inventoryController.cancelPhysicalCount);
router.delete('/physical-counts/:id', requirePermission('inventory', 'delete'), sensitiveOperationLimiter, inventoryController.deletePhysicalCount);

export default router;
