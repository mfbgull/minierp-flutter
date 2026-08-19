import express from 'express';
const router = express.Router();
import reportsController from '../controllers/reportsController';
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import { sensitiveOperationLimiter } from '../middleware/rateLimiter';
import { validateZodQuery, zodSchemas } from '../middleware/validation';

// All report routes require authentication
router.use(authenticateToken);

router.get('/ar-aging', requirePermission('reports', 'read'), sensitiveOperationLimiter, reportsController.getARAgingReport);
router.get('/ap-aging', requirePermission('reports', 'read'), sensitiveOperationLimiter, reportsController.getAPAgingReport);
router.get('/customer-statements', requirePermission('reports', 'read'), sensitiveOperationLimiter, reportsController.getCustomerStatements);
router.get('/top-debtors', requirePermission('reports', 'read'), reportsController.getTopDebtors);
router.get('/dso', requirePermission('reports', 'read'), validateZodQuery(zodSchemas.period), reportsController.getDSOMetric);
router.get('/ar-summary', requirePermission('reports', 'read'), reportsController.getReceivablesSummary);
router.get('/profit-loss', requirePermission('reports', 'read'), sensitiveOperationLimiter, reportsController.getProfitLossReport);
router.get('/cash-flow', requirePermission('reports', 'read'), sensitiveOperationLimiter, reportsController.getCashFlowReport);
router.get('/cash-reconciliation', requirePermission('reports', 'read'), sensitiveOperationLimiter, reportsController.getCashReconciliation);
router.post('/cash-reconciliation', requirePermission('reports', 'read'), sensitiveOperationLimiter, reportsController.saveCashReconciliation);
router.get('/balance-sheet', requirePermission('reports', 'read'), sensitiveOperationLimiter, reportsController.getBalanceSheetReport);
router.get('/trial-balance', requirePermission('reports', 'read'), sensitiveOperationLimiter, reportsController.getTrialBalanceReport);
router.get('/general-ledger', requirePermission('reports', 'read'), sensitiveOperationLimiter, reportsController.getGeneralLedgerReport);
router.get('/income-statement', requirePermission('reports', 'read'), sensitiveOperationLimiter, reportsController.getIncomeStatementReport);
router.get('/tax-summary', requirePermission('reports', 'read'), sensitiveOperationLimiter, reportsController.getTaxSummaryReport);
router.get('/batch-traceability/:itemId', requirePermission('reports', 'read'), reportsController.getBatchTraceabilityReport);

export default router;
