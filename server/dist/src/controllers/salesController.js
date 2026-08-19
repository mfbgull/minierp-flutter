"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const Quotation_1 = __importDefault(require("../models/Quotation"));
const SalesOrder_1 = __importDefault(require("../models/SalesOrder"));
const Invoice_1 = __importDefault(require("../models/Invoice"));
const database_1 = __importDefault(require("../config/database"));
const logger_1 = __importDefault(require("../utils/logger"));
const queryUtils_1 = require("../utils/queryUtils");
function parseIdParam(req, res) {
    const id = Number(req.params.id);
    if (isNaN(id) || id <= 0) {
        res.status(400).json({ error: 'Invalid ID parameter' });
        return null;
    }
    return id;
}
// ============ Quotation Controllers ============
function createQuotation(req, res) {
    try {
        const { customer_id, customer_name, quotation_date, expiry_date, status, source_type, notes, terms, warehouse_id, items } = req.body;
        if (!customer_id) {
            res.status(400).json({ error: 'Customer is required' });
            return;
        }
        if (!quotation_date) {
            res.status(400).json({ error: 'Quotation date is required' });
            return;
        }
        if (!items || !Array.isArray(items) || items.length === 0) {
            res.status(400).json({ error: 'At least one item is required' });
            return;
        }
        const quotation = Quotation_1.default.create({
            customer_id,
            customer_name,
            quotation_date,
            expiry_date,
            status,
            source_type,
            notes,
            terms,
            warehouse_id,
            items
        }, req.user.id, database_1.default);
        res.status(201).json(quotation);
    }
    catch (error) {
        logger_1.default.error('Create quotation error:', error);
        res.status(400).json({ error: error.message || 'Failed to create quotation' });
    }
}
function getQuotations(req, res) {
    try {
        const page = (0, queryUtils_1.getQueryInteger)(req.query.page, 1);
        const limit = (0, queryUtils_1.getQueryInteger)(req.query.limit, 10);
        const search = (0, queryUtils_1.getQueryParam)(req.query.search);
        const sortBy = (0, queryUtils_1.getQueryParam)(req.query.sortBy);
        const sortOrder = (0, queryUtils_1.getQueryParam)(req.query.sortOrder);
        const filters = {
            status: req.query.status,
            customer_id: req.query.customer_id ? Number(req.query.customer_id) : undefined,
            customer_name: req.query.customer_name,
            search: search || undefined,
            start_date: req.query.start_date,
            end_date: req.query.end_date,
            warehouse_id: req.query.warehouse_id ? Number(req.query.warehouse_id) : undefined,
            sortBy: sortBy || undefined,
            sortOrder: sortOrder || undefined,
            page,
            limit
        };
        const { rows, total, pageNum, limitNum } = Quotation_1.default.getAll(filters, database_1.default);
        // Flat envelope (data = list, pagination a sibling) — the shape the
        // client's `getPaged` helper parses.
        res.json({
            success: true,
            data: rows,
            pagination: {
                currentPage: pageNum,
                totalPages: Math.ceil(total / limitNum),
                totalItems: total,
                hasNext: pageNum < Math.ceil(total / limitNum),
                hasPrev: pageNum > 1
            }
        });
    }
    catch (error) {
        logger_1.default.error('Get quotations error:', error);
        res.status(500).json({ error: 'Failed to fetch quotations' });
    }
}
function getQuotation(req, res) {
    try {
        const id = parseIdParam(req, res);
        if (!id)
            return;
        const quotation = Quotation_1.default.getById(id, database_1.default);
        if (!quotation) {
            res.status(404).json({ error: 'Quotation not found' });
            return;
        }
        res.json(quotation);
    }
    catch (error) {
        logger_1.default.error('Get quotation error:', error);
        res.status(500).json({ error: 'Failed to fetch quotation' });
    }
}
function updateQuotation(req, res) {
    try {
        const { id } = req.params;
        const data = req.body;
        const quotation = Quotation_1.default.update(Number(id), data, req.user.id, database_1.default);
        res.json(quotation);
    }
    catch (error) {
        logger_1.default.error('Update quotation error:', error);
        res.status(400).json({ error: error.message || 'Failed to update quotation' });
    }
}
function deleteQuotation(req, res) {
    try {
        const id = parseIdParam(req, res);
        if (!id)
            return;
        Quotation_1.default.delete(id, req.user.id, database_1.default);
        res.json({ success: true, message: 'Quotation deleted successfully' });
    }
    catch (error) {
        logger_1.default.error('Delete quotation error:', error);
        res.status(500).json({ error: error.message || 'Failed to delete quotation' });
    }
}
function convertQuotationToSalesOrder(req, res) {
    try {
        const { id } = req.params;
        const result = database_1.default.transaction(() => {
            const quotation = Quotation_1.default.getById(Number(id), database_1.default);
            if (!quotation) {
                throw new Error('Quotation not found');
            }
            if (quotation.status === 'Converted') {
                throw new Error('Quotation already converted to sales order');
            }
            if (quotation.expiry_date) {
                const today = new Date().toISOString().split('T')[0];
                if (quotation.expiry_date < today) {
                    throw new Error('Quotation has expired');
                }
            }
            return Quotation_1.default.convertToSalesOrder(Number(id), req.user.id, database_1.default);
        })();
        res.status(201).json({
            success: true,
            message: 'Quotation converted to sales order',
            ...result
        });
    }
    catch (error) {
        logger_1.default.error('Convert quotation to SO error:', error);
        res.status(400).json({ error: error.message || 'Failed to convert quotation' });
    }
}
function getQuotationCycleChain(req, res) {
    try {
        const id = parseIdParam(req, res);
        if (!id)
            return;
        const chain = Quotation_1.default.getSalesCycleChain(id, database_1.default);
        res.json(chain);
    }
    catch (error) {
        logger_1.default.error('Get quotation cycle chain error:', error);
        res.status(500).json({ error: 'Failed to fetch cycle chain' });
    }
}
// ============ Sales Order Controllers ============
function createSalesOrder(req, res) {
    try {
        const { customer_id, customer_name, so_date, delivery_date, status, source_type, source_id, notes, warehouse_id, items } = req.body;
        if (!customer_id) {
            res.status(400).json({ error: 'Customer is required' });
            return;
        }
        if (!so_date) {
            res.status(400).json({ error: 'Sales order date is required' });
            return;
        }
        if (!items || !Array.isArray(items) || items.length === 0) {
            res.status(400).json({ error: 'At least one item is required' });
            return;
        }
        const salesOrder = SalesOrder_1.default.create({
            customer_id,
            customer_name,
            so_date,
            delivery_date,
            status,
            source_type,
            source_id,
            notes,
            warehouse_id,
            items
        }, req.user.id, database_1.default);
        res.status(201).json(salesOrder);
    }
    catch (error) {
        logger_1.default.error('Create sales order error:', error);
        res.status(400).json({ error: error.message || 'Failed to create sales order' });
    }
}
function getSalesOrders(req, res) {
    try {
        const page = (0, queryUtils_1.getQueryInteger)(req.query.page, 1);
        const limit = (0, queryUtils_1.getQueryInteger)(req.query.limit, 10);
        const search = (0, queryUtils_1.getQueryParam)(req.query.search);
        const sortBy = (0, queryUtils_1.getQueryParam)(req.query.sortBy);
        const sortOrder = (0, queryUtils_1.getQueryParam)(req.query.sortOrder);
        const filters = {
            status: req.query.status,
            customer_id: req.query.customer_id ? Number(req.query.customer_id) : undefined,
            customer_name: req.query.customer_name,
            search: search || undefined,
            start_date: req.query.start_date,
            end_date: req.query.end_date,
            warehouse_id: req.query.warehouse_id ? Number(req.query.warehouse_id) : undefined,
            source_type: req.query.source_type,
            sortBy: sortBy || undefined,
            sortOrder: sortOrder || undefined,
            page,
            limit
        };
        const { rows, total, pageNum, limitNum } = SalesOrder_1.default.getAll(filters, database_1.default);
        // Flat envelope (data = list, pagination a sibling) — the shape the
        // client's `getPaged` helper parses.
        res.json({
            success: true,
            data: rows,
            pagination: {
                currentPage: pageNum,
                totalPages: Math.ceil(total / limitNum),
                totalItems: total,
                hasNext: pageNum < Math.ceil(total / limitNum),
                hasPrev: pageNum > 1
            }
        });
    }
    catch (error) {
        logger_1.default.error('Get sales orders error:', error);
        res.status(500).json({ error: 'Failed to fetch sales orders' });
    }
}
function getSalesOrder(req, res) {
    try {
        const id = parseIdParam(req, res);
        if (!id)
            return;
        const salesOrder = SalesOrder_1.default.getById(id, database_1.default);
        if (!salesOrder) {
            res.status(404).json({ error: 'Sales order not found' });
            return;
        }
        res.json(salesOrder);
    }
    catch (error) {
        logger_1.default.error('Get sales order error:', error);
        res.status(500).json({ error: 'Failed to fetch sales order' });
    }
}
function updateSalesOrder(req, res) {
    try {
        const { id } = req.params;
        const data = req.body;
        const salesOrder = SalesOrder_1.default.update(Number(id), data, req.user.id, database_1.default);
        res.json(salesOrder);
    }
    catch (error) {
        logger_1.default.error('Update sales order error:', error);
        res.status(400).json({ error: error.message || 'Failed to update sales order' });
    }
}
function deleteSalesOrder(req, res) {
    try {
        const id = parseIdParam(req, res);
        if (!id)
            return;
        SalesOrder_1.default.delete(id, req.user.id, database_1.default);
        res.json({ success: true, message: 'Sales order deleted successfully' });
    }
    catch (error) {
        logger_1.default.error('Delete sales order error:', error);
        res.status(500).json({ error: error.message || 'Failed to delete sales order' });
    }
}
function cancelSalesOrder(req, res) {
    try {
        const id = parseIdParam(req, res);
        if (!id)
            return;
        const result = SalesOrder_1.default.cancel(id, req.user.id, database_1.default);
        res.json({ success: true, message: 'Sales order cancelled successfully', ...result });
    }
    catch (error) {
        logger_1.default.error('Cancel sales order error:', error);
        res.status(500).json({ error: error.message || 'Failed to cancel sales order' });
    }
}
function convertSalesOrderToInvoice(req, res) {
    try {
        const { id } = req.params;
        const invoiceData = req.body;
        const result = database_1.default.transaction(() => {
            const salesOrder = SalesOrder_1.default.getById(Number(id), database_1.default);
            if (!salesOrder) {
                throw new Error('Sales order not found');
            }
            if (salesOrder.status === 'Cancelled') {
                throw new Error('Cannot convert cancelled sales order');
            }
            if (salesOrder.status === 'Invoiced' || salesOrder.status === 'Completed') {
                throw new Error(`Sales order already ${salesOrder.status}`);
            }
            return SalesOrder_1.default.convertToInvoice(Number(id), req.user.id, database_1.default, {
                invoice_date: invoiceData?.invoice_date,
                due_date: invoiceData?.due_date,
                notes: invoiceData?.notes,
            });
        })();
        res.status(201).json({
            success: true,
            message: 'Sales order converted to invoice',
            ...result
        });
    }
    catch (error) {
        logger_1.default.error('Convert SO to invoice error:', error);
        res.status(400).json({ error: error.message || 'Failed to convert sales order' });
    }
}
function getSalesOrderCycleChain(req, res) {
    try {
        const id = parseIdParam(req, res);
        if (!id)
            return;
        const chain = SalesOrder_1.default.getSalesCycleChain(id, database_1.default);
        res.json(chain);
    }
    catch (error) {
        logger_1.default.error('Get sales order cycle chain error:', error);
        res.status(500).json({ error: 'Failed to fetch cycle chain' });
    }
}
// ============ Invoice Controllers (for sales cycle) ============
function getInvoicesBySalesOrder(req, res) {
    try {
        const id = parseIdParam(req, res);
        if (!id)
            return;
        const invoices = Invoice_1.default.getBySalesOrderId(id, database_1.default);
        res.json(invoices);
    }
    catch (error) {
        logger_1.default.error('Get invoices by SO error:', error);
        res.status(500).json({ error: 'Failed to fetch invoices' });
    }
}
function getInvoicesByQuotation(req, res) {
    try {
        const id = parseIdParam(req, res);
        if (!id)
            return;
        const invoices = Invoice_1.default.getByQuotationId(id, database_1.default);
        res.json(invoices);
    }
    catch (error) {
        logger_1.default.error('Get invoices by quotation error:', error);
        res.status(500).json({ error: 'Failed to fetch invoices' });
    }
}
function getSalesDashboard(_req, res) {
    try {
        const quotations = database_1.default.prepare(`
      SELECT
        COUNT(*) as total,
        SUM(CASE WHEN status = 'Draft' THEN 1 ELSE 0 END) as draft,
        SUM(CASE WHEN status = 'Sent' THEN 1 ELSE 0 END) as sent,
        SUM(CASE WHEN status = 'Converted' THEN 1 ELSE 0 END) as converted
      FROM quotations
    `).get();
        const salesOrders = database_1.default.prepare(`
      SELECT
        COUNT(*) as total,
        SUM(CASE WHEN status = 'Draft' THEN 1 ELSE 0 END) as draft,
        SUM(CASE WHEN status = 'Confirmed' THEN 1 ELSE 0 END) as confirmed,
        SUM(CASE WHEN status = 'Invoiced' THEN 1 ELSE 0 END) as invoiced
      FROM sales_orders
    `).get();
        const invoices = database_1.default.prepare(`
      SELECT
        COUNT(*) as total,
        SUM(CASE WHEN status = 'Unpaid' THEN 1 ELSE 0 END) as unpaid,
        SUM(CASE WHEN status = 'Paid' THEN 1 ELSE 0 END) as paid,
        SUM(CASE WHEN status = 'Partially Paid' THEN 1 ELSE 0 END) as partially_paid,
        SUM(total_amount) as total_revenue,
        SUM(balance_amount) as outstanding_receivables
      FROM invoices
    `).get();
        const dashboard = {
            quotations: {
                total: quotations.total,
                draft: quotations.draft,
                sent: quotations.sent,
                pending_conversion: quotations.total - quotations.converted
            },
            sales_orders: {
                total: salesOrders.total,
                draft: salesOrders.draft,
                confirmed: salesOrders.confirmed,
                pending_invoicing: salesOrders.confirmed
            },
            invoices: {
                total: invoices.total,
                unpaid: invoices.unpaid,
                paid: invoices.paid,
                partially_paid: invoices.partially_paid,
                total_revenue: invoices.total_revenue,
                outstanding_receivables: invoices.outstanding_receivables
            }
        };
        res.json(dashboard);
    }
    catch (error) {
        logger_1.default.error('Get sales dashboard error:', error);
        res.status(500).json({ error: 'Failed to fetch dashboard' });
    }
}
function getSalesSummaryByDateRange(req, res) {
    try {
        const { start_date, end_date } = req.query;
        if (!start_date || !end_date) {
            res.status(400).json({ error: 'Start date and end date are required' });
            return;
        }
        const stats = Invoice_1.default.getStatsByDateRange(start_date, end_date, database_1.default);
        res.json(stats);
    }
    catch (error) {
        logger_1.default.error('Get sales summary by date range error:', error);
        res.status(500).json({ error: 'Failed to get sales summary' });
    }
}
exports.default = {
    createQuotation,
    getQuotations,
    getQuotation,
    updateQuotation,
    deleteQuotation,
    convertQuotationToSalesOrder,
    getQuotationCycleChain,
    createSalesOrder,
    getSalesOrders,
    getSalesOrder,
    updateSalesOrder,
    deleteSalesOrder,
    cancelSalesOrder,
    convertSalesOrderToInvoice,
    getSalesOrderCycleChain,
    getInvoicesBySalesOrder,
    getInvoicesByQuotation,
    getSalesDashboard,
    getSalesSummaryByDateRange
};
//# sourceMappingURL=salesController.js.map