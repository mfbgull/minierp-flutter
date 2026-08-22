import express from 'express';
const router = express.Router();
import inventoryController from '../controllers/inventoryController';
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import { sensitiveOperationLimiter } from '../middleware/rateLimiter';

router.use(authenticateToken);

router.get('/items', requirePermission('inventory', 'read'), inventoryController.getItems);
router.get('/items/:id', requirePermission('inventory', 'read'), inventoryController.getItem);
router.post('/items', requirePermission('inventory', 'create'), sensitiveOperationLimiter, inventoryController.createItem);
router.put('/items/:id', requirePermission('inventory', 'update'), sensitiveOperationLimiter, inventoryController.updateItem);
router.delete('/items/:id', requirePermission('inventory', 'delete'), sensitiveOperationLimiter, inventoryController.deleteItem);

router.get('/items-categories', requirePermission('inventory', 'read'), inventoryController.getCategories);
router.get('/items-low-stock', requirePermission('inventory', 'read'), inventoryController.getLowStock);
router.get('/items-uom', requirePermission('inventory', 'read'), inventoryController.getUnitsOfMeasure);

router.get('/warehouses', requirePermission('inventory', 'read'), inventoryController.getWarehouses);
router.get('/warehouses/:id', requirePermission('inventory', 'read'), inventoryController.getWarehouse);
router.post('/warehouses', requirePermission('inventory', 'create'), sensitiveOperationLimiter, inventoryController.createWarehouse);
router.put('/warehouses/:id', requirePermission('inventory', 'update'), sensitiveOperationLimiter, inventoryController.updateWarehouse);
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
