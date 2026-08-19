"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const router = express_1.default.Router();
const reportsController_1 = __importDefault(require("../controllers/reportsController"));
const auth_1 = require("../middleware/auth");
const requirePermission_1 = require("../middleware/requirePermission");
const rateLimiter_1 = require("../middleware/rateLimiter");
const validation_1 = require("../middleware/validation");
// All report routes require authentication
router.use(auth_1.authenticateToken);
router.get('/ar-aging', (0, requirePermission_1.requirePermission)('reports', 'read'), rateLimiter_1.sensitiveOperationLimiter, reportsController_1.default.getARAgingReport);
router.get('/ap-aging', (0, requirePermission_1.requirePermission)('reports', 'read'), rateLimiter_1.sensitiveOperationLimiter, reportsController_1.default.getAPAgingReport);
router.get('/customer-statements', (0, requirePermission_1.requirePermission)('reports', 'read'), rateLimiter_1.sensitiveOperationLimiter, reportsController_1.default.getCustomerStatements);
router.get('/top-debtors', (0, requirePermission_1.requirePermission)('reports', 'read'), reportsController_1.default.getTopDebtors);
router.get('/dso', (0, requirePermission_1.requirePermission)('reports', 'read'), (0, validation_1.validateZodQuery)(validation_1.zodSchemas.period), reportsController_1.default.getDSOMetric);
router.get('/ar-summary', (0, requirePermission_1.requirePermission)('reports', 'read'), reportsController_1.default.getReceivablesSummary);
router.get('/profit-loss', (0, requirePermission_1.requirePermission)('reports', 'read'), rateLimiter_1.sensitiveOperationLimiter, reportsController_1.default.getProfitLossReport);
router.get('/cash-flow', (0, requirePermission_1.requirePermission)('reports', 'read'), rateLimiter_1.sensitiveOperationLimiter, reportsController_1.default.getCashFlowReport);
router.get('/cash-reconciliation', (0, requirePermission_1.requirePermission)('reports', 'read'), rateLimiter_1.sensitiveOperationLimiter, reportsController_1.default.getCashReconciliation);
router.post('/cash-reconciliation', (0, requirePermission_1.requirePermission)('reports', 'read'), rateLimiter_1.sensitiveOperationLimiter, reportsController_1.default.saveCashReconciliation);
router.get('/balance-sheet', (0, requirePermission_1.requirePermission)('reports', 'read'), rateLimiter_1.sensitiveOperationLimiter, reportsController_1.default.getBalanceSheetReport);
router.get('/trial-balance', (0, requirePermission_1.requirePermission)('reports', 'read'), rateLimiter_1.sensitiveOperationLimiter, reportsController_1.default.getTrialBalanceReport);
router.get('/general-ledger', (0, requirePermission_1.requirePermission)('reports', 'read'), rateLimiter_1.sensitiveOperationLimiter, reportsController_1.default.getGeneralLedgerReport);
router.get('/income-statement', (0, requirePermission_1.requirePermission)('reports', 'read'), rateLimiter_1.sensitiveOperationLimiter, reportsController_1.default.getIncomeStatementReport);
router.get('/tax-summary', (0, requirePermission_1.requirePermission)('reports', 'read'), rateLimiter_1.sensitiveOperationLimiter, reportsController_1.default.getTaxSummaryReport);
router.get('/batch-traceability/:itemId', (0, requirePermission_1.requirePermission)('reports', 'read'), reportsController_1.default.getBatchTraceabilityReport);
exports.default = router;
//# sourceMappingURL=reports.js.map