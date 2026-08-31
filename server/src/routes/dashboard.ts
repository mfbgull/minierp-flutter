import express from 'express';
import dashboardController from '../controllers/dashboardController';
import dashboardLayoutController from '../controllers/dashboardLayoutController';
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';

const router = express.Router();

router.use(authenticateToken);

// Existing summary endpoint
router.get('/summary', requirePermission('dashboard', 'read'), dashboardController.getSummary);

// ============ Dashboard Data Endpoints ============

router.get('/top-customers', requirePermission('dashboard', 'read'), dashboardController.getTopCustomers);
router.get('/sales-summary', requirePermission('dashboard', 'read'), dashboardController.getSalesSummary);
router.get('/expense-summary', requirePermission('dashboard', 'read'), dashboardController.getExpenseSummary);
router.get('/production-status', requirePermission('dashboard', 'read'), dashboardController.getProductionStatus);
router.get('/stock-movement-summary', requirePermission('dashboard', 'read'), dashboardController.getStockMovementSummary);
router.get('/kpi', requirePermission('dashboard', 'read'), dashboardController.getKPI);
router.get('/kpi-batch', requirePermission('dashboard', 'read'), dashboardController.getKPIBatch);
router.get('/ar-summary', requirePermission('dashboard', 'read'), dashboardController.getARSummary);
router.get('/cash-position', requirePermission('dashboard', 'read'), dashboardController.getCashPosition);
router.get('/expiry-alerts', requirePermission('dashboard', 'read'), dashboardController.getExpiryAlerts);
router.get('/cash-opening-balances', requirePermission('dashboard', 'read'), dashboardController.getCashOpeningBalances);
router.put('/cash-opening-balances', requirePermission('dashboard', 'update'), dashboardController.saveCashOpeningBalances);
router.get('/active-loans', requirePermission('dashboard', 'read'), dashboardController.getActiveLoans);

// ============ Layout CRUD ============

router.get('/layout/active', requirePermission('dashboard', 'read'), dashboardLayoutController.getActiveLayout);
router.post('/layout', requirePermission('dashboard', 'create'), dashboardLayoutController.createLayout);
router.put('/layout/:id', requirePermission('dashboard', 'update'), dashboardLayoutController.updateLayout);
router.patch('/layout/:id/rename', requirePermission('dashboard', 'update'), dashboardLayoutController.renameLayout);
router.delete('/layout/:id', requirePermission('dashboard', 'delete'), dashboardLayoutController.deleteLayout);
router.get('/layouts', requirePermission('dashboard', 'read'), dashboardLayoutController.listLayouts);
router.put('/layout/:id/activate', requirePermission('dashboard', 'update'), dashboardLayoutController.setActiveLayout);
router.post('/layout/duplicate', requirePermission('dashboard', 'create'), dashboardLayoutController.duplicateLayout);

export default router;
