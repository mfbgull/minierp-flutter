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
const purchaseController_1 = __importDefault(require("../controllers/purchaseController"));
router.use(auth_1.authenticateToken);
router.post('/purchases', (0, requirePermission_1.requirePermission)('purchases', 'create'), rateLimiter_1.sensitiveOperationLimiter, purchaseController_1.default.recordPurchase);
router.get('/purchases', (0, requirePermission_1.requirePermission)('purchases', 'read'), purchaseController_1.default.getPurchases);
router.get('/purchases/:id', (0, requirePermission_1.requirePermission)('purchases', 'read'), purchaseController_1.default.getPurchase);
router.get('/purchases/:id/payments', (0, requirePermission_1.requirePermission)('purchases', 'read'), purchaseController_1.default.getPurchasePayments);
router.delete('/purchases/:id', (0, requirePermission_1.requirePermission)('purchases', 'delete'), rateLimiter_1.sensitiveOperationLimiter, purchaseController_1.default.deletePurchase);
router.get('/purchases/summary/item/:item_id', (0, requirePermission_1.requirePermission)('purchases', 'read'), purchaseController_1.default.getPurchaseSummaryByItem);
router.get('/purchases/summary/daterange', (0, requirePermission_1.requirePermission)('purchases', 'read'), purchaseController_1.default.getPurchaseSummaryByDateRange);
router.get('/purchases/top-suppliers', (0, requirePermission_1.requirePermission)('purchases', 'read'), purchaseController_1.default.getTopSuppliers);
exports.default = router;
//# sourceMappingURL=purchases.js.map