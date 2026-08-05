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
router.get('/customer-statements', requirePermission('reports', 'read'), sensitiveOperationLimiter, reportsController.getCustomerStatements);
router.get('/top-debtors', requirePermission('reports', 'read'), reportsController.getTopDebtors);
router.get('/dso', requirePermission('reports', 'read'), validateZodQuery(zodSchemas.period), reportsController.getDSOMetric);
router.get('/ar-summary', requirePermission('reports', 'read'), reportsController.getReceivablesSummary);
router.get('/sales-summary', requirePermission('reports', 'read'), reportsController.getSalesSummary);
router.get('/sales-by-customer', requirePermission('reports', 'read'), reportsController.getSalesByCustomer);
router.get('/sales-by-item', requirePermission('reports', 'read'), reportsController.getSalesByItem);
router.get('/stock-level', requirePermission('reports', 'read'), reportsController.getStockLevelReport);
router.get('/low-stock', requirePermission('reports', 'read'), reportsController.getLowStockReport);
router.get('/stock-valuation', requirePermission('reports', 'read'), sensitiveOperationLimiter, reportsController.getStockValuationReport);
router.get('/inventory-movement', requirePermission('reports', 'read'), sensitiveOperationLimiter, reportsController.getInventoryMovementReport);
router.get('/profit-loss', requirePermission('reports', 'read'), sensitiveOperationLimiter, reportsController.getProfitLossReport);
router.get('/cash-flow', requirePermission('reports', 'read'), sensitiveOperationLimiter, reportsController.getCashFlowReport);
router.get('/purchase-summary', requirePermission('reports', 'read'), reportsController.getPurchaseSummary);
router.get('/supplier-analysis', requirePermission('reports', 'read'), reportsController.getSupplierAnalysis);
router.get('/production-summary', requirePermission('reports', 'read'), reportsController.getProductionSummary);
router.get('/bom-usage', requirePermission('reports', 'read'), reportsController.getBOMUsageReport);
router.get('/expenses', requirePermission('reports', 'read'), sensitiveOperationLimiter, reportsController.getExpensesReport);
router.get('/trial-balance', requirePermission('reports', 'read'), sensitiveOperationLimiter, reportsController.getTrialBalanceReport);
router.get('/general-ledger', requirePermission('reports', 'read'), sensitiveOperationLimiter, reportsController.getGeneralLedgerReport);
router.get('/balance-sheet', requirePermission('reports', 'read'), sensitiveOperationLimiter, reportsController.getBalanceSheetReport);
router.get('/income-statement', requirePermission('reports', 'read'), sensitiveOperationLimiter, reportsController.getIncomeStatementReport);
router.get('/tax-summary', requirePermission('reports', 'read'), sensitiveOperationLimiter, reportsController.getTaxSummaryReport);
router.get('/batch-traceability/:itemId', requirePermission('reports', 'read'), reportsController.getBatchTraceabilityReport);

export default router;
