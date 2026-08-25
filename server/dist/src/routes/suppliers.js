"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const router = express_1.default.Router();
const suppliersController_1 = __importDefault(require("../controllers/suppliersController"));
const auth_1 = require("../middleware/auth");
const requirePermission_1 = require("../middleware/requirePermission");
// All supplier routes require authentication
router.use(auth_1.authenticateToken);
router.get('/', (0, requirePermission_1.requirePermission)('suppliers', 'read'), suppliersController_1.default.getSuppliers);
router.get('/next-code', (0, requirePermission_1.requirePermission)('suppliers', 'read'), suppliersController_1.default.getNextSupplierCode);
router.get('/:id', (0, requirePermission_1.requirePermission)('suppliers', 'read'), suppliersController_1.default.getSupplierById);
router.get('/:id/ledger', (0, requirePermission_1.requirePermission)('suppliers', 'read'), suppliersController_1.default.getSupplierLedger);
router.get('/:id/statement', (0, requirePermission_1.requirePermission)('suppliers', 'read'), suppliersController_1.default.getSupplierStatement);
router.get('/:id/balance', (0, requirePermission_1.requirePermission)('suppliers', 'read'), suppliersController_1.default.getSupplierBalance);
router.post('/', (0, requirePermission_1.requirePermission)('suppliers', 'create'), suppliersController_1.default.createSupplier);
router.put('/:id', (0, requirePermission_1.requirePermission)('suppliers', 'update'), suppliersController_1.default.updateSupplier);
router.delete('/:id', (0, requirePermission_1.requirePermission)('suppliers', 'delete'), suppliersController_1.default.deleteSupplier);
router.post('/recalculate-balances', (0, requirePermission_1.requirePermission)('suppliers', 'update'), suppliersController_1.default.recalculateAllBalances);
exports.default = router;
