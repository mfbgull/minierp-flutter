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
const validation_1 = require("../middleware/validation");
const purchaseReturnController_1 = __importDefault(require("../controllers/purchaseReturnController"));
router.use(auth_1.authenticateToken);
// Purchase Returns — the redesigned first-class return documents.
router.get('/', (0, requirePermission_1.requirePermission)('purchase_returns', 'read'), purchaseReturnController_1.default.getPurchaseReturns);
router.get('/:id', (0, requirePermission_1.requirePermission)('purchase_returns', 'read'), purchaseReturnController_1.default.getPurchaseReturn);
router.post('/', (0, requirePermission_1.requirePermission)('purchase_returns', 'create'), (0, validation_1.validateZodBody)(validation_1.zodBodySchemas.purchaseReturnCreate), rateLimiter_1.sensitiveOperationLimiter, purchaseReturnController_1.default.createPurchaseReturn);
router.post('/:id/void', (0, requirePermission_1.requirePermission)('purchase_returns', 'void'), (0, validation_1.validateZodBody)(validation_1.zodBodySchemas.object), rateLimiter_1.sensitiveOperationLimiter, purchaseReturnController_1.default.voidPurchaseReturn);
exports.default = router;
