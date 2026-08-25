"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const dashboardController_1 = __importDefault(require("../controllers/dashboardController"));
const dashboardLayoutController_1 = __importDefault(require("../controllers/dashboardLayoutController"));
const auth_1 = require("../middleware/auth");
const requirePermission_1 = require("../middleware/requirePermission");
const router = express_1.default.Router();
router.use(auth_1.authenticateToken);
// Existing summary endpoint
router.get('/summary', (0, requirePermission_1.requirePermission)('dashboard', 'read'), dashboardController_1.default.getSummary);
// ============ Dashboard Data Endpoints ============
router.get('/top-customers', (0, requirePermission_1.requirePermission)('dashboard', 'read'), dashboardController_1.default.getTopCustomers);
router.get('/sales-summary', (0, requirePermission_1.requirePermission)('dashboard', 'read'), dashboardController_1.default.getSalesSummary);
router.get('/expense-summary', (0, requirePermission_1.requirePermission)('dashboard', 'read'), dashboardController_1.default.getExpenseSummary);
router.get('/production-status', (0, requirePermission_1.requirePermission)('dashboard', 'read'), dashboardController_1.default.getProductionStatus);
router.get('/stock-movement-summary', (0, requirePermission_1.requirePermission)('dashboard', 'read'), dashboardController_1.default.getStockMovementSummary);
router.get('/kpi', (0, requirePermission_1.requirePermission)('dashboard', 'read'), dashboardController_1.default.getKPI);
router.get('/kpi-batch', (0, requirePermission_1.requirePermission)('dashboard', 'read'), dashboardController_1.default.getKPIBatch);
router.get('/ar-summary', (0, requirePermission_1.requirePermission)('dashboard', 'read'), dashboardController_1.default.getARSummary);
router.get('/cash-position', (0, requirePermission_1.requirePermission)('dashboard', 'read'), dashboardController_1.default.getCashPosition);
router.get('/expiry-alerts', (0, requirePermission_1.requirePermission)('dashboard', 'read'), dashboardController_1.default.getExpiryAlerts);
router.get('/cash-opening-balances', (0, requirePermission_1.requirePermission)('dashboard', 'read'), dashboardController_1.default.getCashOpeningBalances);
router.put('/cash-opening-balances', (0, requirePermission_1.requirePermission)('dashboard', 'update'), dashboardController_1.default.saveCashOpeningBalances);
// ============ Layout CRUD ============
router.get('/layout/active', (0, requirePermission_1.requirePermission)('dashboard', 'read'), dashboardLayoutController_1.default.getActiveLayout);
router.post('/layout', (0, requirePermission_1.requirePermission)('dashboard', 'create'), dashboardLayoutController_1.default.createLayout);
router.put('/layout/:id', (0, requirePermission_1.requirePermission)('dashboard', 'update'), dashboardLayoutController_1.default.updateLayout);
router.patch('/layout/:id/rename', (0, requirePermission_1.requirePermission)('dashboard', 'update'), dashboardLayoutController_1.default.renameLayout);
router.delete('/layout/:id', (0, requirePermission_1.requirePermission)('dashboard', 'delete'), dashboardLayoutController_1.default.deleteLayout);
router.get('/layouts', (0, requirePermission_1.requirePermission)('dashboard', 'read'), dashboardLayoutController_1.default.listLayouts);
router.put('/layout/:id/activate', (0, requirePermission_1.requirePermission)('dashboard', 'update'), dashboardLayoutController_1.default.setActiveLayout);
router.post('/layout/duplicate', (0, requirePermission_1.requirePermission)('dashboard', 'create'), dashboardLayoutController_1.default.duplicateLayout);
exports.default = router;
