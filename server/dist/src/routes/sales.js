"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.salesRouter = exports.salesOrderRouter = void 0;
const express_1 = __importDefault(require("express"));
const auth_1 = require("../middleware/auth");
const requirePermission_1 = require("../middleware/requirePermission");
const salesController_1 = __importDefault(require("../controllers/salesController"));
const rateLimiter_1 = require("../middleware/rateLimiter");
// SHORTCOMINGS-FIX 2.4: this file was a single router embedding three
// module prefixes (/quotations, /sales-orders, /sales). It is split into
// one router per namespace, each mounted with an explicit `/api/<module>`
// prefix in app.ts. Route paths below are relative to their mount.
const router = express_1.default.Router();
router.use(auth_1.authenticateToken);
// ============ Quotations Routes (mounted at /api/quotations) ============
// POST /api/quotations - Create new quotation
router.post('/', (0, requirePermission_1.requirePermission)('quotations', 'create'), salesController_1.default.createQuotation);
// GET /api/quotations - Get all quotations with filters
router.get('/', (0, requirePermission_1.requirePermission)('quotations', 'read'), salesController_1.default.getQuotations);
// GET /api/quotations/:id - Get single quotation
router.get('/:id', (0, requirePermission_1.requirePermission)('quotations', 'read'), salesController_1.default.getQuotation);
// PUT /api/quotations/:id - Update quotation
router.put('/:id', (0, requirePermission_1.requirePermission)('quotations', 'update'), salesController_1.default.updateQuotation);
// DELETE /api/quotations/:id - Delete quotation
router.delete('/:id', (0, requirePermission_1.requirePermission)('quotations', 'delete'), rateLimiter_1.sensitiveOperationLimiter, salesController_1.default.deleteQuotation);
// POST /api/quotations/:id/convert - Convert quotation to sales order
router.post('/:id/convert', (0, requirePermission_1.requirePermission)('quotations', 'update'), salesController_1.default.convertQuotationToSalesOrder);
// GET /api/quotations/:id/cycle-chain - Get sales cycle chain for quotation
router.get('/:id/cycle-chain', (0, requirePermission_1.requirePermission)('quotations', 'read'), salesController_1.default.getQuotationCycleChain);
// GET /api/quotations/:id/invoices - Get invoices for quotation (via SO or direct)
router.get('/:id/invoices', (0, requirePermission_1.requirePermission)('quotations', 'read'), salesController_1.default.getInvoicesByQuotation);
const quotationRoutes = router;
// ============ Sales Orders Routes (mounted at /api/sales-orders) ============
const salesOrderRouter = express_1.default.Router();
exports.salesOrderRouter = salesOrderRouter;
salesOrderRouter.use(auth_1.authenticateToken);
// POST /api/sales-orders - Create new sales order
salesOrderRouter.post('/', (0, requirePermission_1.requirePermission)('sales_orders', 'create'), salesController_1.default.createSalesOrder);
// GET /api/sales-orders - Get all sales orders with filters
salesOrderRouter.get('/', (0, requirePermission_1.requirePermission)('sales_orders', 'read'), salesController_1.default.getSalesOrders);
// GET /api/sales-orders/:id - Get single sales order
salesOrderRouter.get('/:id', (0, requirePermission_1.requirePermission)('sales_orders', 'read'), salesController_1.default.getSalesOrder);
// PUT /api/sales-orders/:id - Update sales order
salesOrderRouter.put('/:id', (0, requirePermission_1.requirePermission)('sales_orders', 'update'), salesController_1.default.updateSalesOrder);
// DELETE /api/sales-orders/:id - Delete sales order
salesOrderRouter.delete('/:id', (0, requirePermission_1.requirePermission)('sales_orders', 'delete'), rateLimiter_1.sensitiveOperationLimiter, salesController_1.default.deleteSalesOrder);
// POST /api/sales-orders/:id/cancel - Cancel sales order (reverses stock)
salesOrderRouter.post('/:id/cancel', (0, requirePermission_1.requirePermission)('sales_orders', 'update'), rateLimiter_1.sensitiveOperationLimiter, salesController_1.default.cancelSalesOrder);
// POST /api/sales-orders/:id/convert - Convert sales order to invoice
salesOrderRouter.post('/:id/convert', (0, requirePermission_1.requirePermission)('sales_orders', 'create'), salesController_1.default.convertSalesOrderToInvoice);
// GET /api/sales-orders/:id/cycle-chain - Get sales cycle chain for sales order
salesOrderRouter.get('/:id/cycle-chain', (0, requirePermission_1.requirePermission)('sales_orders', 'read'), salesController_1.default.getSalesOrderCycleChain);
// GET /api/sales-orders/:id/invoices - Get invoices for sales order
salesOrderRouter.get('/:id/invoices', (0, requirePermission_1.requirePermission)('sales_orders', 'read'), salesController_1.default.getInvoicesBySalesOrder);
// ============ Sales Routes (mounted at /api/sales; legacy dashboard
// also mounted at /api/dashboard — see app.ts) ============
const salesRouter = express_1.default.Router();
exports.salesRouter = salesRouter;
salesRouter.use(auth_1.authenticateToken);
// GET /api/dashboard (legacy) / /api/sales - Sales dashboard summary
salesRouter.get('/', (0, requirePermission_1.requirePermission)('sales', 'read'), salesController_1.default.getSalesDashboard);
// GET /api/sales/summary/daterange - Sales summary by date range (uses InvoiceModel)
salesRouter.get('/summary/daterange', (0, requirePermission_1.requirePermission)('sales', 'read'), salesController_1.default.getSalesSummaryByDateRange);
exports.default = quotationRoutes;
