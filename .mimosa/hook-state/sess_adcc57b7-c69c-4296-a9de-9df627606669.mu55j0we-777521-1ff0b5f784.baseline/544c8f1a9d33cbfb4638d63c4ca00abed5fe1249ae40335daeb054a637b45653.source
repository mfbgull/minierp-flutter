import express from 'express';
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import salesController from '../controllers/salesController';
import { sensitiveOperationLimiter } from '../middleware/rateLimiter';
import { validateZodBody, zodBodySchemas } from '../middleware/validation';

// SHORTCOMINGS-FIX 2.4: this file was a single router embedding three
// module prefixes (/quotations, /sales-orders, /sales). It is split into
// one router per namespace, each mounted with an explicit `/api/<module>`
// prefix in app.ts. Route paths below are relative to their mount.

const router = express.Router();
router.use(authenticateToken);

// ============ Quotations Routes (mounted at /api/quotations) ============

// POST /api/quotations - Create new quotation
router.post('/', requirePermission('quotations', 'create'), validateZodBody(zodBodySchemas.quotationCreate), salesController.createQuotation);

// GET /api/quotations - Get all quotations with filters
router.get('/', requirePermission('quotations', 'read'), salesController.getQuotations);

// GET /api/quotations/:id - Get single quotation
router.get('/:id', requirePermission('quotations', 'read'), salesController.getQuotation);

// PUT /api/quotations/:id - Update quotation
router.put('/:id', requirePermission('quotations', 'update'), validateZodBody(zodBodySchemas.object), salesController.updateQuotation);

// DELETE /api/quotations/:id - Delete quotation
router.delete('/:id', requirePermission('quotations', 'delete'), sensitiveOperationLimiter, salesController.deleteQuotation);

// POST /api/quotations/:id/convert - Convert quotation to sales order
router.post('/:id/convert', requirePermission('quotations', 'update'), validateZodBody(zodBodySchemas.object), salesController.convertQuotationToSalesOrder);

// GET /api/quotations/:id/cycle-chain - Get sales cycle chain for quotation
router.get('/:id/cycle-chain', requirePermission('quotations', 'read'), salesController.getQuotationCycleChain);

// GET /api/quotations/:id/invoices - Get invoices for quotation (via SO or direct)
router.get('/:id/invoices', requirePermission('quotations', 'read'), salesController.getInvoicesByQuotation);

const quotationRoutes = router;

// ============ Sales Orders Routes (mounted at /api/sales-orders) ============

const salesOrderRouter = express.Router();
salesOrderRouter.use(authenticateToken);

// POST /api/sales-orders - Create new sales order
salesOrderRouter.post('/', requirePermission('sales_orders', 'create'), salesController.createSalesOrder);

// GET /api/sales-orders - Get all sales orders with filters
salesOrderRouter.get('/', requirePermission('sales_orders', 'read'), salesController.getSalesOrders);

// GET /api/sales-orders/:id - Get single sales order
salesOrderRouter.get('/:id', requirePermission('sales_orders', 'read'), salesController.getSalesOrder);

// PUT /api/sales-orders/:id - Update sales order
salesOrderRouter.put('/:id', requirePermission('sales_orders', 'update'), salesController.updateSalesOrder);

// DELETE /api/sales-orders/:id - Delete sales order
salesOrderRouter.delete('/:id', requirePermission('sales_orders', 'delete'), sensitiveOperationLimiter, salesController.deleteSalesOrder);

// POST /api/sales-orders/:id/cancel - Cancel sales order (reverses stock)
salesOrderRouter.post('/:id/cancel', requirePermission('sales_orders', 'update'), sensitiveOperationLimiter, salesController.cancelSalesOrder);

// POST /api/sales-orders/:id/convert - Convert sales order to invoice
salesOrderRouter.post('/:id/convert', requirePermission('sales_orders', 'create'), salesController.convertSalesOrderToInvoice);

// GET /api/sales-orders/:id/cycle-chain - Get sales cycle chain for sales order
salesOrderRouter.get('/:id/cycle-chain', requirePermission('sales_orders', 'read'), salesController.getSalesOrderCycleChain);

// GET /api/sales-orders/:id/invoices - Get invoices for sales order
salesOrderRouter.get('/:id/invoices', requirePermission('sales_orders', 'read'), salesController.getInvoicesBySalesOrder);

// ============ Sales Routes (mounted at /api/sales; legacy dashboard
// also mounted at /api/dashboard — see app.ts) ============

const salesRouter = express.Router();
salesRouter.use(authenticateToken);

// GET /api/dashboard (legacy) / /api/sales - Sales dashboard summary
salesRouter.get('/', requirePermission('sales', 'read'), salesController.getSalesDashboard);

// GET /api/sales/summary/daterange - Sales summary by date range (uses InvoiceModel)
salesRouter.get('/summary/daterange', requirePermission('sales', 'read'), salesController.getSalesSummaryByDateRange);

export default quotationRoutes;
export { salesOrderRouter, salesRouter };