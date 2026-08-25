import { Request, Response } from 'express';
import { AuthRequest } from '../types';
import QuotationModel from '../models/Quotation';
import SalesOrderModel from '../models/SalesOrder';
import InvoiceModel from '../models/Invoice';
import db from '../config/database';
import logger from '../utils/logger';
import { getQueryInteger, getQueryParam } from '../utils/queryUtils';

function parseIdParam(req: Request, res: Response): number | null {
  const id = Number(req.params.id);
  if (isNaN(id) || id <= 0) {
    res.status(400).json({ error: 'Invalid ID parameter' });
    return null;
  }
  return id;
}

// ============ Quotation Controllers ============

function createQuotation(req: AuthRequest, res: Response): void {
  try {
    const {
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
    } = req.body;

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

    const quotation = QuotationModel.create({
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
    }, req.user!.id, db);

    res.status(201).json(quotation);
  } catch (error: any) {
    logger.error('Create quotation error:', error);
    res.status(400).json({ error: error.message || 'Failed to create quotation' });
  }
}

function getQuotations(req: Request, res: Response): void {
  try {
    const page = getQueryInteger(req.query.page, 1);
    const limit = getQueryInteger(req.query.limit, 10);
    const search = getQueryParam(req.query.search);
    const sortBy = getQueryParam(req.query.sortBy);
    const sortOrder = getQueryParam(req.query.sortOrder);

    const filters = {
      status: req.query.status as string | undefined,
      customer_id: req.query.customer_id ? Number(req.query.customer_id) : undefined,
      customer_name: req.query.customer_name as string | undefined,
      search: search || undefined,
      start_date: req.query.start_date as string | undefined,
      end_date: req.query.end_date as string | undefined,
      warehouse_id: req.query.warehouse_id ? Number(req.query.warehouse_id) : undefined,
      sortBy: sortBy || undefined,
      sortOrder: sortOrder || undefined,
      page,
      limit
    };

    const { rows, total, pageNum, limitNum } = QuotationModel.getAll(filters, db);

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
  } catch (error: any) {
    logger.error('Get quotations error:', error);
    res.status(500).json({ error: 'Failed to fetch quotations' });
  }
}

function getQuotation(req: Request, res: Response): void {
  try {
    const id = parseIdParam(req, res);
    if (!id) return;
    const quotation = QuotationModel.getById(id, db);

    if (!quotation) {
      res.status(404).json({ error: 'Quotation not found' });
      return;
    }

    res.json(quotation);
  } catch (error: any) {
    logger.error('Get quotation error:', error);
    res.status(500).json({ error: 'Failed to fetch quotation' });
  }
}

function updateQuotation(req: AuthRequest, res: Response): void {
  try {
    const { id } = req.params;
    const data = req.body;

    const quotation = QuotationModel.update(Number(id), data, req.user!.id, db);
    res.json(quotation);
  } catch (error: any) {
    logger.error('Update quotation error:', error);
    res.status(400).json({ error: error.message || 'Failed to update quotation' });
  }
}

function deleteQuotation(req: AuthRequest, res: Response): void {
  try {
    const id = parseIdParam(req, res);
    if (!id) return;
    QuotationModel.delete(id, req.user!.id, db);
    res.json({ success: true, message: 'Quotation deleted successfully' });
  } catch (error: any) {
    logger.error('Delete quotation error:', error);
    res.status(500).json({ error: error.message || 'Failed to delete quotation' });
  }
}

function convertQuotationToSalesOrder(req: AuthRequest, res: Response): void {
  try {
    const { id } = req.params;

    const result = db.transaction(() => {
      const quotation = QuotationModel.getById(Number(id), db);
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

      return QuotationModel.convertToSalesOrder(Number(id), req.user!.id, db);
    })();

    res.status(201).json({
      success: true,
      message: 'Quotation converted to sales order',
      ...result
    });
  } catch (error: any) {
    logger.error('Convert quotation to SO error:', error);
    res.status(400).json({ error: error.message || 'Failed to convert quotation' });
  }
}

function getQuotationCycleChain(req: Request, res: Response): void {
  try {
    const id = parseIdParam(req, res);
    if (!id) return;
    const chain = QuotationModel.getSalesCycleChain(id, db);
    res.json(chain);
  } catch (error: any) {
    logger.error('Get quotation cycle chain error:', error);
    res.status(500).json({ error: 'Failed to fetch cycle chain' });
  }
}

// ============ Sales Order Controllers ============

function createSalesOrder(req: AuthRequest, res: Response): void {
  try {
    const {
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
    } = req.body;

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

    const salesOrder = SalesOrderModel.create({
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
    }, req.user!.id, db);

    res.status(201).json(salesOrder);
  } catch (error: any) {
    logger.error('Create sales order error:', error);
    res.status(400).json({ error: error.message || 'Failed to create sales order' });
  }
}

function getSalesOrders(req: Request, res: Response): void {
  try {
    const page = getQueryInteger(req.query.page, 1);
    const limit = getQueryInteger(req.query.limit, 10);
    const search = getQueryParam(req.query.search);
    const sortBy = getQueryParam(req.query.sortBy);
    const sortOrder = getQueryParam(req.query.sortOrder);

    const filters = {
      status: req.query.status as string | undefined,
      customer_id: req.query.customer_id ? Number(req.query.customer_id) : undefined,
      customer_name: req.query.customer_name as string | undefined,
      search: search || undefined,
      start_date: req.query.start_date as string | undefined,
      end_date: req.query.end_date as string | undefined,
      warehouse_id: req.query.warehouse_id ? Number(req.query.warehouse_id) : undefined,
      source_type: req.query.source_type as string | undefined,
      sortBy: sortBy || undefined,
      sortOrder: sortOrder || undefined,
      page,
      limit
    };

    const { rows, total, pageNum, limitNum } = SalesOrderModel.getAll(filters, db);

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
  } catch (error: any) {
    logger.error('Get sales orders error:', error);
    res.status(500).json({ error: 'Failed to fetch sales orders' });
  }
}

function getSalesOrder(req: Request, res: Response): void {
  try {
    const id = parseIdParam(req, res);
    if (!id) return;
    const salesOrder = SalesOrderModel.getById(id, db);

    if (!salesOrder) {
      res.status(404).json({ error: 'Sales order not found' });
      return;
    }

    res.json(salesOrder);
  } catch (error: any) {
    logger.error('Get sales order error:', error);
    res.status(500).json({ error: 'Failed to fetch sales order' });
  }
}

function updateSalesOrder(req: AuthRequest, res: Response): void {
  try {
    const { id } = req.params;
    const data = req.body;

    const salesOrder = SalesOrderModel.update(Number(id), data, req.user!.id, db);
    res.json(salesOrder);
  } catch (error: any) {
    logger.error('Update sales order error:', error);
    res.status(400).json({ error: error.message || 'Failed to update sales order' });
  }
}

function deleteSalesOrder(req: AuthRequest, res: Response): void {
  try {
    const id = parseIdParam(req, res);
    if (!id) return;
    SalesOrderModel.delete(id, req.user!.id, db);
    res.json({ success: true, message: 'Sales order deleted successfully' });
  } catch (error: any) {
    logger.error('Delete sales order error:', error);
    res.status(500).json({ error: error.message || 'Failed to delete sales order' });
  }
}

function cancelSalesOrder(req: AuthRequest, res: Response): void {
  try {
    const id = parseIdParam(req, res);
    if (!id) return;
    const result = SalesOrderModel.cancel(id, req.user!.id, db);
    res.json({ success: true, message: 'Sales order cancelled successfully', ...result });
  } catch (error: any) {
    logger.error('Cancel sales order error:', error);
    res.status(500).json({ error: error.message || 'Failed to cancel sales order' });
  }
}

function convertSalesOrderToInvoice(req: AuthRequest, res: Response): void {
  try {
    const { id } = req.params;
    const invoiceData = req.body;

    const result = db.transaction(() => {
      const salesOrder = SalesOrderModel.getById(Number(id), db);
      if (!salesOrder) {
        throw new Error('Sales order not found');
      }

      if (salesOrder.status === 'Cancelled') {
        throw new Error('Cannot convert cancelled sales order');
      }

      if (salesOrder.status === 'Invoiced' || salesOrder.status === 'Completed') {
        throw new Error(`Sales order already ${salesOrder.status}`);
      }

      return SalesOrderModel.convertToInvoice(Number(id), req.user!.id, db, {
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
  } catch (error: any) {
    logger.error('Convert SO to invoice error:', error);
    res.status(400).json({ error: error.message || 'Failed to convert sales order' });
  }
}

function getSalesOrderCycleChain(req: Request, res: Response): void {
  try {
    const id = parseIdParam(req, res);
    if (!id) return;
    const chain = SalesOrderModel.getSalesCycleChain(id, db);
    res.json(chain);
  } catch (error: any) {
    logger.error('Get sales order cycle chain error:', error);
    res.status(500).json({ error: 'Failed to fetch cycle chain' });
  }
}

// ============ Invoice Controllers (for sales cycle) ============

function getInvoicesBySalesOrder(req: Request, res: Response): void {
  try {
    const id = parseIdParam(req, res);
    if (!id) return;
    const invoices = InvoiceModel.getBySalesOrderId(id, db);
    res.json(invoices);
  } catch (error: any) {
    logger.error('Get invoices by SO error:', error);
    res.status(500).json({ error: 'Failed to fetch invoices' });
  }
}

function getInvoicesByQuotation(req: Request, res: Response): void {
  try {
    const id = parseIdParam(req, res);
    if (!id) return;
    const invoices = InvoiceModel.getByQuotationId(id, db);
    res.json(invoices);
  } catch (error: any) {
    logger.error('Get invoices by quotation error:', error);
    res.status(500).json({ error: 'Failed to fetch invoices' });
  }
}

function getSalesDashboard(_req: Request, res: Response): void {
  try {
    const quotations = db.prepare(`
      SELECT
        COUNT(*) as total,
        SUM(CASE WHEN status = 'Draft' THEN 1 ELSE 0 END) as draft,
        SUM(CASE WHEN status = 'Sent' THEN 1 ELSE 0 END) as sent,
        SUM(CASE WHEN status = 'Converted' THEN 1 ELSE 0 END) as converted
      FROM quotations
    `).get() as { total: number; draft: number; sent: number; converted: number };

    const salesOrders = db.prepare(`
      SELECT
        COUNT(*) as total,
        SUM(CASE WHEN status = 'Draft' THEN 1 ELSE 0 END) as draft,
        SUM(CASE WHEN status = 'Confirmed' THEN 1 ELSE 0 END) as confirmed,
        SUM(CASE WHEN status = 'Invoiced' THEN 1 ELSE 0 END) as invoiced
      FROM sales_orders
    `).get() as { total: number; draft: number; confirmed: number; invoiced: number };

    const invoices = db.prepare(`
      SELECT
        COUNT(*) as total,
        SUM(CASE WHEN status = 'Unpaid' THEN 1 ELSE 0 END) as unpaid,
        SUM(CASE WHEN status = 'Paid' THEN 1 ELSE 0 END) as paid,
        SUM(CASE WHEN status = 'Partially Paid' THEN 1 ELSE 0 END) as partially_paid,
        SUM(total_amount) as total_revenue,
        SUM(balance_amount) as outstanding_receivables
      FROM invoices
    `).get() as {
      total: number;
      unpaid: number;
      paid: number;
      partially_paid: number;
      total_revenue: number;
      outstanding_receivables: number;
    };

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
  } catch (error: any) {
    logger.error('Get sales dashboard error:', error);
    res.status(500).json({ error: 'Failed to fetch dashboard' });
  }
}

function getSalesSummaryByDateRange(req: Request, res: Response): void {
  try {
    const { start_date, end_date } = req.query;

    if (!start_date || !end_date) {
      res.status(400).json({ error: 'Start date and end date are required' });
      return;
    }

    const stats = InvoiceModel.getStatsByDateRange(start_date as string, end_date as string, db);
    res.json(stats);
  } catch (error: any) {
    logger.error('Get sales summary by date range error:', error);
    res.status(500).json({ error: 'Failed to get sales summary' });
  }
}

export default {
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
