"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const router = express_1.default.Router();
const auth_1 = require("../middleware/auth");
const requirePermission_1 = require("../middleware/requirePermission");
const purchaseOrderController_1 = __importDefault(require("../controllers/purchaseOrderController"));
router.use(auth_1.authenticateToken);
// CRUD - Purchase Orders
router.post('/', (0, requirePermission_1.requirePermission)('purchase_orders', 'create'), purchaseOrderController_1.default.createPurchaseOrder);
router.get('/', (0, requirePermission_1.requirePermission)('purchase_orders', 'read'), purchaseOrderController_1.default.getPurchaseOrders);
router.get('/:id', (0, requirePermission_1.requirePermission)('purchase_orders', 'read'), purchaseOrderController_1.default.getPurchaseOrder);
router.put('/:id', (0, requirePermission_1.requirePermission)('purchase_orders', 'update'), purchaseOrderController_1.default.updatePurchaseOrder);
router.delete('/:id', (0, requirePermission_1.requirePermission)('purchase_orders', 'delete'), purchaseOrderController_1.default.deletePurchaseOrder);
// Line Items
router.post('/:id/items', (0, requirePermission_1.requirePermission)('purchase_orders', 'create'), purchaseOrderController_1.default.addLineItem);
router.put('/:id/items/:itemId', (0, requirePermission_1.requirePermission)('purchase_orders', 'update'), purchaseOrderController_1.default.updateLineItem);
router.delete('/:id/items/:itemId', (0, requirePermission_1.requirePermission)('purchase_orders', 'delete'), purchaseOrderController_1.default.deleteLineItem);
// Status
router.post('/:id/status', (0, requirePermission_1.requirePermission)('purchase_orders', 'update'), purchaseOrderController_1.default.updateStatus);
router.get('/pending', (0, requirePermission_1.requirePermission)('purchase_orders', 'read'), purchaseOrderController_1.default.getPendingOrders);
// Payments (history allocated to this PO)
router.get('/:id/payments', (0, requirePermission_1.requirePermission)('purchase_orders', 'read'), purchaseOrderController_1.default.getPurchaseOrderPayments);
// Goods Receipts
router.get('/:id/receipts', (0, requirePermission_1.requirePermission)('purchase_orders', 'read'), purchaseOrderController_1.default.getGoodsReceipts);
router.post('/:id/receipts', (0, requirePermission_1.requirePermission)('purchase_orders', 'create'), purchaseOrderController_1.default.createGoodsReceipt);
// Summary & Reporting
router.get('/summary/supplier/:supplierId', (0, requirePermission_1.requirePermission)('purchase_orders', 'read'), purchaseOrderController_1.default.getSummaryBySupplier);
// Supplier Ledger (AP)
router.get('/suppliers/:supplierId/balance', (0, requirePermission_1.requirePermission)('purchase_orders', 'read'), purchaseOrderController_1.default.getSupplierBalance);
router.get('/suppliers/:supplierId/transactions', (0, requirePermission_1.requirePermission)('purchase_orders', 'read'), purchaseOrderController_1.default.getSupplierTransactions);
exports.default = router;
