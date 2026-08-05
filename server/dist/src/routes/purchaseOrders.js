"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const router = express_1.default.Router();
const auth_1 = require("../middleware/auth");
const requirePermission_1 = require("../middleware/requirePermission");
const rateLimiter_1 = require("../middleware/rateLimiter");
const purchaseOrderController_1 = __importDefault(require("../controllers/purchaseOrderController"));
router.use(auth_1.authenticateToken);
// CRUD - Purchase Orders
router.post('/purchase-orders', (0, requirePermission_1.requirePermission)('purchase_orders', 'create'), purchaseOrderController_1.default.createPurchaseOrder);
router.get('/purchase-orders', (0, requirePermission_1.requirePermission)('purchase_orders', 'read'), purchaseOrderController_1.default.getPurchaseOrders);
router.get('/purchase-orders/:id', (0, requirePermission_1.requirePermission)('purchase_orders', 'read'), purchaseOrderController_1.default.getPurchaseOrder);
router.put('/purchase-orders/:id', (0, requirePermission_1.requirePermission)('purchase_orders', 'update'), purchaseOrderController_1.default.updatePurchaseOrder);
router.delete('/purchase-orders/:id', (0, requirePermission_1.requirePermission)('purchase_orders', 'delete'), purchaseOrderController_1.default.deletePurchaseOrder);
// Line Items
router.post('/purchase-orders/:id/items', (0, requirePermission_1.requirePermission)('purchase_orders', 'create'), purchaseOrderController_1.default.addLineItem);
router.put('/purchase-orders/:id/items/:itemId', (0, requirePermission_1.requirePermission)('purchase_orders', 'update'), purchaseOrderController_1.default.updateLineItem);
router.delete('/purchase-orders/:id/items/:itemId', (0, requirePermission_1.requirePermission)('purchase_orders', 'delete'), purchaseOrderController_1.default.deleteLineItem);
// Status
router.post('/purchase-orders/:id/status', (0, requirePermission_1.requirePermission)('purchase_orders', 'update'), purchaseOrderController_1.default.updateStatus);
router.get('/purchase-orders/pending', (0, requirePermission_1.requirePermission)('purchase_orders', 'read'), purchaseOrderController_1.default.getPendingOrders);
// Goods Receipts
router.get('/purchase-orders/:id/receipts', (0, requirePermission_1.requirePermission)('purchase_orders', 'read'), purchaseOrderController_1.default.getGoodsReceipts);
router.post('/purchase-orders/:id/receipts', (0, requirePermission_1.requirePermission)('purchase_orders', 'create'), purchaseOrderController_1.default.createGoodsReceipt);
router.post('/purchase-orders/:id/return-receipt', (0, requirePermission_1.requirePermission)('purchase_orders', 'update'), rateLimiter_1.sensitiveOperationLimiter, purchaseOrderController_1.default.returnReceiptItems);
// Summary & Reporting
router.get('/purchase-orders/summary/supplier/:supplierId', (0, requirePermission_1.requirePermission)('purchase_orders', 'read'), purchaseOrderController_1.default.getSummaryBySupplier);
// Supplier Ledger (AP)
router.get('/suppliers/:supplierId/balance', (0, requirePermission_1.requirePermission)('purchase_orders', 'read'), purchaseOrderController_1.default.getSupplierBalance);
router.get('/suppliers/:supplierId/transactions', (0, requirePermission_1.requirePermission)('purchase_orders', 'read'), purchaseOrderController_1.default.getSupplierTransactions);
exports.default = router;
//# sourceMappingURL=purchaseOrders.js.map