import express from 'express';
const router = express.Router();
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import { sensitiveOperationLimiter } from '../middleware/rateLimiter';
import purchaseOrderController from '../controllers/purchaseOrderController';

router.use(authenticateToken);

// CRUD - Purchase Orders
router.post('/purchase-orders', requirePermission('purchase_orders', 'create'), purchaseOrderController.createPurchaseOrder);
router.get('/purchase-orders', requirePermission('purchase_orders', 'read'), purchaseOrderController.getPurchaseOrders);
router.get('/purchase-orders/:id', requirePermission('purchase_orders', 'read'), purchaseOrderController.getPurchaseOrder);
router.put('/purchase-orders/:id', requirePermission('purchase_orders', 'update'), purchaseOrderController.updatePurchaseOrder);
router.delete('/purchase-orders/:id', requirePermission('purchase_orders', 'delete'), purchaseOrderController.deletePurchaseOrder);

// Line Items
router.post('/purchase-orders/:id/items', requirePermission('purchase_orders', 'create'), purchaseOrderController.addLineItem);
router.put('/purchase-orders/:id/items/:itemId', requirePermission('purchase_orders', 'update'), purchaseOrderController.updateLineItem);
router.delete('/purchase-orders/:id/items/:itemId', requirePermission('purchase_orders', 'delete'), purchaseOrderController.deleteLineItem);

// Status
router.post('/purchase-orders/:id/status', requirePermission('purchase_orders', 'update'), purchaseOrderController.updateStatus);
router.get('/purchase-orders/pending', requirePermission('purchase_orders', 'read'), purchaseOrderController.getPendingOrders);

// Goods Receipts
router.get('/purchase-orders/:id/receipts', requirePermission('purchase_orders', 'read'), purchaseOrderController.getGoodsReceipts);
router.post('/purchase-orders/:id/receipts', requirePermission('purchase_orders', 'create'), purchaseOrderController.createGoodsReceipt);
router.post('/purchase-orders/:id/return-receipt', requirePermission('purchase_orders', 'update'), sensitiveOperationLimiter, purchaseOrderController.returnReceiptItems);

// Summary & Reporting
router.get('/purchase-orders/summary/supplier/:supplierId', requirePermission('purchase_orders', 'read'), purchaseOrderController.getSummaryBySupplier);

// Supplier Ledger (AP)
router.get('/suppliers/:supplierId/balance', requirePermission('purchase_orders', 'read'), purchaseOrderController.getSupplierBalance);
router.get('/suppliers/:supplierId/transactions', requirePermission('purchase_orders', 'read'), purchaseOrderController.getSupplierTransactions);

export default router;
