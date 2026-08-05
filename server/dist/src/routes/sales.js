"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const router = express_1.default.Router();
const auth_1 = require("../middleware/auth");
const requirePermission_1 = require("../middleware/requirePermission");
const salesController_1 = __importDefault(require("../controllers/salesController"));
const rateLimiter_1 = require("../middleware/rateLimiter");
router.use(auth_1.authenticateToken);
// ============ Quotations Routes ============
// POST /api/quotations - Create new quotation
router.post('/quotations', (0, requirePermission_1.requirePermission)('quotations', 'create'), salesController_1.default.createQuotation);
// GET /api/quotations - Get all quotations with filters
router.get('/quotations', (0, requirePermission_1.requirePermission)('quotations', 'read'), salesController_1.default.getQuotations);
// GET /api/quotations/:id - Get single quotation
router.get('/quotations/:id', (0, requirePermission_1.requirePermission)('quotations', 'read'), salesController_1.default.getQuotation);
// PUT /api/quotations/:id - Update quotation
router.put('/quotations/:id', (0, requirePermission_1.requirePermission)('quotations', 'update'), salesController_1.default.updateQuotation);
// DELETE /api/quotations/:id - Delete quotation
router.delete('/quotations/:id', (0, requirePermission_1.requirePermission)('quotations', 'delete'), rateLimiter_1.sensitiveOperationLimiter, salesController_1.default.deleteQuotation);
// POST /api/quotations/:id/convert - Convert quotation to sales order
router.post('/quotations/:id/convert', (0, requirePermission_1.requirePermission)('quotations', 'update'), salesController_1.default.convertQuotationToSalesOrder);
// GET /api/quotations/:id/cycle-chain - Get sales cycle chain for quotation
router.get('/quotations/:id/cycle-chain', (0, requirePermission_1.requirePermission)('quotations', 'read'), salesController_1.default.getQuotationCycleChain);
// ============ Sales Orders Routes ============
// POST /api/sales-orders - Create new sales order
router.post('/sales-orders', (0, requirePermission_1.requirePermission)('sales_orders', 'create'), salesController_1.default.createSalesOrder);
// GET /api/sales-orders - Get all sales orders with filters
router.get('/sales-orders', (0, requirePermission_1.requirePermission)('sales_orders', 'read'), salesController_1.default.getSalesOrders);
// GET /api/sales-orders/:id - Get single sales order
router.get('/sales-orders/:id', (0, requirePermission_1.requirePermission)('sales_orders', 'read'), salesController_1.default.getSalesOrder);
// PUT /api/sales-orders/:id - Update sales order
router.put('/sales-orders/:id', (0, requirePermission_1.requirePermission)('sales_orders', 'update'), salesController_1.default.updateSalesOrder);
// DELETE /api/sales-orders/:id - Delete sales order
router.delete('/sales-orders/:id', (0, requirePermission_1.requirePermission)('sales_orders', 'delete'), rateLimiter_1.sensitiveOperationLimiter, salesController_1.default.deleteSalesOrder);
// POST /api/sales-orders/:id/cancel - Cancel sales order (reverses stock)
router.post('/sales-orders/:id/cancel', (0, requirePermission_1.requirePermission)('sales_orders', 'update'), rateLimiter_1.sensitiveOperationLimiter, salesController_1.default.cancelSalesOrder);
// POST /api/sales-orders/:id/convert - Convert sales order to invoice
router.post('/sales-orders/:id/convert', (0, requirePermission_1.requirePermission)('sales_orders', 'create'), salesController_1.default.convertSalesOrderToInvoice);
// GET /api/sales-orders/:id/cycle-chain - Get sales cycle chain for sales order
router.get('/sales-orders/:id/cycle-chain', (0, requirePermission_1.requirePermission)('sales_orders', 'read'), salesController_1.default.getSalesOrderCycleChain);
// GET /api/sales-orders/:id/invoices - Get invoices for sales order
router.get('/sales-orders/:id/invoices', (0, requirePermission_1.requirePermission)('sales_orders', 'read'), salesController_1.default.getInvoicesBySalesOrder);
// ============ Invoice Links (from sales cycle) ============
// GET /api/quotations/:id/invoices - Get invoices for quotation (via SO or direct)
router.get('/quotations/:id/invoices', (0, requirePermission_1.requirePermission)('quotations', 'read'), salesController_1.default.getInvoicesByQuotation);
// ============ Dashboard ============
// GET /api/sales/dashboard - Get sales dashboard summary
router.get('/dashboard', (0, requirePermission_1.requirePermission)('sales', 'read'), salesController_1.default.getSalesDashboard);
// ============ Legacy Routes (migrated to InvoiceModel) ============
// GET /api/sales/summary/daterange - Sales summary by date range (uses InvoiceModel)
router.get('/sales/summary/daterange', (0, requirePermission_1.requirePermission)('sales', 'read'), salesController_1.default.getSalesSummaryByDateRange);
exports.default = router;
//# sourceMappingURL=sales.js.map