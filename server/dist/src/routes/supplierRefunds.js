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
const supplierRefundController_1 = __importDefault(require("../controllers/supplierRefundController"));
router.use(auth_1.authenticateToken);
// Supplier refunds — cash payout against supplier credit notes.
router.get('/', (0, requirePermission_1.requirePermission)('supplier_refunds', 'read'), supplierRefundController_1.default.getSupplierRefunds);
router.get('/:id', (0, requirePermission_1.requirePermission)('supplier_refunds', 'read'), supplierRefundController_1.default.getSupplierRefund);
router.get('/credit-notes/:id/refundable', (0, requirePermission_1.requirePermission)('supplier_refunds', 'read'), supplierRefundController_1.default.getCreditNoteRefundable);
router.post('/', (0, requirePermission_1.requirePermission)('supplier_refunds', 'create'), (0, validation_1.validateZodBody)(validation_1.zodBodySchemas.supplierRefundCreate), rateLimiter_1.sensitiveOperationLimiter, supplierRefundController_1.default.createSupplierRefund);
router.post('/:id/void', (0, requirePermission_1.requirePermission)('supplier_refunds', 'void'), (0, validation_1.validateZodBody)(validation_1.zodBodySchemas.object), rateLimiter_1.sensitiveOperationLimiter, supplierRefundController_1.default.voidSupplierRefund);
exports.default = router;
