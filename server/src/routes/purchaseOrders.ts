import express from 'express';
const router = express.Router();
import { authenticateToken } from '../middleware/auth';
import { validateZodBody, zodBodySchemas } from '../middleware/validation';
import { requirePermission } from '../middleware/requirePermission';
import purchaseOrderController from '../controllers/purchaseOrderController';

router.use(authenticateToken);

// CRUD - Purchase Orders
router.post('/', requirePermission('purchase_orders', 'create'), validateZodBody(zodBodySchemas.poCreate), purchaseOrderController.createPurchaseOrder);
router.get('/', requirePermission('purchase_orders', 'read'), purchaseOrderController.getPurchaseOrders);
router.get('/:id', requirePermission('purchase_orders', 'read'), purchaseOrderController.getPurchaseOrder);
router.put('/:id', requirePermission('purchase_orders', 'update'), validateZodBody(zodBodySchemas.object), purchaseOrderController.updatePurchaseOrder);
router.delete('/:id', requirePermission('purchase_orders', 'delete'), purchaseOrderController.deletePurchaseOrder);

// Line Items
router.post('/:id/items', requirePermission('purchase_orders', 'create'), validateZodBody(zodBodySchemas.object), purchaseOrderController.addLineItem);
router.put('/:id/items/:itemId', requirePermission('purchase_orders', 'update'), validateZodBody(zodBodySchemas.object), purchaseOrderController.updateLineItem);
router.delete('/:id/items/:itemId', requirePermission('purchase_orders', 'delete'), purchaseOrderController.deleteLineItem);

// Status
router.post('/:id/status', requirePermission('purchase_orders', 'update'), validateZodBody(zodBodySchemas.poStatus), purchaseOrderController.updateStatus);
router.get('/pending', requirePermission('purchase_orders', 'read'), purchaseOrderController.getPendingOrders);

// Payments (history allocated to this PO)
router.get('/:id/payments', requirePermission('purchase_orders', 'read'), purchaseOrderController.getPurchaseOrderPayments);

// Goods Receipts
router.get('/:id/receipts', requirePermission('purchase_orders', 'read'), purchaseOrderController.getGoodsReceipts);
router.post('/:id/receipts', requirePermission('purchase_orders', 'create'), validateZodBody(zodBodySchemas.goodsReceipt), purchaseOrderController.createGoodsReceipt);
// Summary & Reporting
router.get('/summary/supplier/:supplierId', requirePermission('purchase_orders', 'read'), purchaseOrderController.getSummaryBySupplier);

// Supplier Ledger (AP)
router.get('/suppliers/:supplierId/balance', requirePermission('purchase_orders', 'read'), purchaseOrderController.getSupplierBalance);
router.get('/suppliers/:supplierId/transactions', requirePermission('purchase_orders', 'read'), purchaseOrderController.getSupplierTransactions);

export default router;
