"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const router = express_1.default.Router();
const paymentsController_1 = __importDefault(require("../controllers/paymentsController"));
const auth_1 = require("../middleware/auth");
const requirePermission_1 = require("../middleware/requirePermission");
const validation_1 = require("../middleware/validation");
const rateLimiter_1 = require("../middleware/rateLimiter");
const zod_1 = require("zod");
router.use(auth_1.authenticateToken);
const paymentListQuery = zod_1.z.object({
    ...validation_1.zodSchemas.pagination.shape,
    ...validation_1.zodSchemas.search.shape,
    ...validation_1.zodSchemas.sorting(['payment_date', 'payment_no', 'amount', 'customer_name', 'supplier_name', 'id', 'created_at']).shape,
    ...validation_1.zodSchemas.dateRange.shape,
    customerId: zod_1.z.string().regex(/^\d+$/).optional(),
    supplierId: zod_1.z.string().regex(/^\d+$/).optional(),
});
router.get('/', (0, requirePermission_1.requirePermission)('payments', 'read'), (0, validation_1.validateZodQuery)(paymentListQuery), paymentsController_1.default.getPayments);
router.get('/:id', (0, requirePermission_1.requirePermission)('payments', 'read'), (0, validation_1.validateZodParams)(validation_1.zodSchemas.id), paymentsController_1.default.getPayment);
router.post('/', (0, requirePermission_1.requirePermission)('payments', 'create'), rateLimiter_1.sensitiveOperationLimiter, paymentsController_1.default.createPayment);
router.put('/:id', (0, requirePermission_1.requirePermission)('payments', 'update'), rateLimiter_1.sensitiveOperationLimiter, paymentsController_1.default.updatePayment);
router.delete('/:id', (0, requirePermission_1.requirePermission)('payments', 'delete'), rateLimiter_1.sensitiveOperationLimiter, paymentsController_1.default.deletePayment);
router.get('/:id/receipt', (0, requirePermission_1.requirePermission)('payments', 'read'), (0, validation_1.validateZodParams)(validation_1.zodSchemas.id), paymentsController_1.default.getPaymentReceipt);
router.post('/:id/allocate', (0, requirePermission_1.requirePermission)('payments', 'update'), rateLimiter_1.sensitiveOperationLimiter, paymentsController_1.default.allocatePaymentToInvoice);
exports.default = router;
