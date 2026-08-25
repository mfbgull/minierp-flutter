"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const router = express_1.default.Router();
const customersController_1 = __importDefault(require("../controllers/customersController"));
const auth_1 = require("../middleware/auth");
const requirePermission_1 = require("../middleware/requirePermission");
const validation_1 = require("../middleware/validation");
const zod_1 = require("zod");
// All customer routes require authentication
router.use(auth_1.authenticateToken);
const customerListQuery = zod_1.z.object({
    ...validation_1.zodSchemas.pagination.shape,
    ...validation_1.zodSchemas.search.shape,
    ...validation_1.zodSchemas.sorting(['customer_name', 'customer_code', 'created_at', 'id', 'current_balance', 'credit_limit']).shape,
    status: zod_1.z.enum(['active', 'inactive', 'all']).optional().default('all'),
});
router.get('/', (0, requirePermission_1.requirePermission)('customers', 'read'), (0, validation_1.validateZodQuery)(customerListQuery), customersController_1.default.getCustomers);
router.get('/:id', (0, requirePermission_1.requirePermission)('customers', 'read'), (0, validation_1.validateZodParams)(validation_1.zodSchemas.id), customersController_1.default.getCustomer);
router.post('/', (0, requirePermission_1.requirePermission)('customers', 'create'), customersController_1.default.createCustomer);
router.put('/:id', (0, requirePermission_1.requirePermission)('customers', 'update'), customersController_1.default.updateCustomer);
router.delete('/:id', (0, requirePermission_1.requirePermission)('customers', 'delete'), customersController_1.default.deleteCustomer);
router.get('/:id/ledger', (0, requirePermission_1.requirePermission)('customers', 'read'), customersController_1.default.getCustomerLedger);
router.get('/:id/statement', (0, requirePermission_1.requirePermission)('customers', 'read'), customersController_1.default.getCustomerStatement);
router.get('/:id/balance', (0, requirePermission_1.requirePermission)('customers', 'read'), customersController_1.default.getCustomerBalance);
router.post('/recalculate-balances', (0, requirePermission_1.requirePermission)('customers', 'update'), customersController_1.default.recalculateAllBalances);
exports.default = router;
