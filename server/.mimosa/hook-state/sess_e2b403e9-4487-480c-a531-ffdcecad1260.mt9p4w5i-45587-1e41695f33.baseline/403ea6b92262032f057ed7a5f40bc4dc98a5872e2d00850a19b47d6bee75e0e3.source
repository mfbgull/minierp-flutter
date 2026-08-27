import express from 'express';
const router = express.Router();
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import salesController from '../controllers/salesController';
import { sensitiveOperationLimiter } from '../middleware/rateLimiter';

router.use(authenticateToken);

// ============ Quotations Routes ============

// POST /api/quotations - Create new quotation
router.post('/quotations', requirePermission('quotations', 'create'), salesController.createQuotation);

// GET /api/quotations - Get all quotations with filters
router.get('/quotations', requirePermission('quotations', 'read'), salesController.getQuotations);

// GET /api/quotations/:id - Get single quotation
router.get('/quotations/:id', requirePermission('quotations', 'read'), salesController.getQuotation);

// PUT /api/quotations/:id - Update quotation
router.put('/quotations/:id', requirePermission('quotations', 'update'), salesController.updateQuotation);

// DELETE /api/quotations/:id - Delete quotation
router.delete('/quotations/:id', requirePermission('quotations', 'delete'), sensitiveOperationLimiter, salesController.deleteQuotation);

// POST /api/quotations/:id/convert - Convert quotation to sales order
router.post('/quotations/:id/convert', requirePermission('quotations', 'update'), salesController.convertQuotationToSalesOrder);

// GET /api/quotations/:id/cycle-chain - Get sales cycle chain for quotation
router.get('/quotations/:id/cycle-chain', requirePermission('quotations', 'read'), salesController.getQuotationCycleChain);

// ============ Sales Orders Routes ============

// POST /api/sales-orders - Create new sales order
router.post('/sales-orders', requirePermission('sales_orders', 'create'), salesController.createSalesOrder);

// GET /api/sales-orders - Get all sales orders with filters
router.get('/sales-orders', requirePermission('sales_orders', 'read'), salesController.getSalesOrders);

// GET /api/sales-orders/:id - Get single sales order
router.get('/sales-orders/:id', requirePermission('sales_orders', 'read'), salesController.getSalesOrder);

// PUT /api/sales-orders/:id - Update sales order
router.put('/sales-orders/:id', requirePermission('sales_orders', 'update'), salesController.updateSalesOrder);

// DELETE /api/sales-orders/:id - Delete sales order
router.delete('/sales-orders/:id', requirePermission('sales_orders', 'delete'), sensitiveOperationLimiter, salesController.deleteSalesOrder);

// POST /api/sales-orders/:id/cancel - Cancel sales order (reverses stock)
router.post('/sales-orders/:id/cancel', requirePermission('sales_orders', 'update'), sensitiveOperationLimiter, salesController.cancelSalesOrder);

// POST /api/sales-orders/:id/convert - Convert sales order to invoice
router.post('/sales-orders/:id/convert', requirePermission('sales_orders', 'create'), salesController.convertSalesOrderToInvoice);

// GET /api/sales-orders/:id/cycle-chain - Get sales cycle chain for sales order
router.get('/sales-orders/:id/cycle-chain', requirePermission('sales_orders', 'read'), salesController.getSalesOrderCycleChain);

// GET /api/sales-orders/:id/invoices - Get invoices for sales order
router.get('/sales-orders/:id/invoices', requirePermission('sales_orders', 'read'), salesController.getInvoicesBySalesOrder);

// ============ Invoice Links (from sales cycle) ============

// GET /api/quotations/:id/invoices - Get invoices for quotation (via SO or direct)
router.get('/quotations/:id/invoices', requirePermission('quotations', 'read'), salesController.getInvoicesByQuotation);

// ============ Dashboard ============

// GET /api/sales/dashboard - Get sales dashboard summary
router.get('/dashboard', requirePermission('sales', 'read'), salesController.getSalesDashboard);

// ============ Legacy Routes (migrated to InvoiceModel) ============

// GET /api/sales/summary/daterange - Sales summary by date range (uses InvoiceModel)
router.get('/sales/summary/daterange', requirePermission('sales', 'read'), salesController.getSalesSummaryByDateRange);

export default router;
