import { Request, Response } from 'express';
import { getQueryInteger, getQueryParam } from '../utils/queryUtils';
import { AuthRequest } from '../types';
import Purchase from '../models/Purchase';
import db from '../config/database';
import logger from '../utils/logger';

function recordPurchase(req: AuthRequest, res: Response): void {
  try {
    // Multi-item payload (Record Purchase form's line items): one
    // transaction creates one purchases row per item. The flat
    // single-item body remains the legacy path.
    const items = req.body?.items;
    if (Array.isArray(items)) {
      if (items.length === 0) {
        res.status(400).json({ error: 'At least one purchase item is required' });
        return;
      }
      if (!req.body.warehouse_id || !req.body.purchase_date) {
        res.status(400).json({ error: 'Warehouse and purchase date are required' });
        return;
      }
      for (const line of items) {
        if (!line?.item_id || !line.quantity || line.unit_cost === undefined) {
          res.status(400).json({
            error: 'Each purchase item needs item_id, quantity, and unit cost'
          });
          return;
        }
        if (Number(line.quantity) <= 0) {
          res.status(400).json({ error: 'Quantity must be positive' });
          return;
        }
        if (Number(line.unit_cost) < 0) {
          res.status(400).json({ error: 'Unit cost cannot be negative' });
          return;
        }
      }

      const created = Purchase.recordPurchaseMulti(req.body, req.user!.id, db);
      res.status(201).json(created);
      return;
    }

    const {
      item_id,
      warehouse_id,
      quantity,
      unit_cost,
      purchase_date,
    } = req.body;

    if (!item_id || !warehouse_id || !quantity || !unit_cost || !purchase_date) {
      res.status(400).json({
        error: 'Item, warehouse, quantity, unit cost, and purchase date are required'
      });
      return;
    }

    if (quantity <= 0) {
      res.status(400).json({ error: 'Quantity must be positive' });
      return;
    }

    if (unit_cost < 0) {
      res.status(400).json({ error: 'Unit cost cannot be negative' });
      return;
    }

    const purchase = Purchase.recordPurchase(req.body, req.user!.id, db);

    res.status(201).json(purchase);
  } catch (error: any) {
    logger.error('Record purchase error:', error);
    res.status(500).json({ error: error.message || 'Failed to record purchase' });
  }
}

function getPurchases(req: Request, res: Response): void {
  try {
    const page = getQueryInteger(req.query.page, 1);
    const limit = getQueryInteger(req.query.limit, 10);
    const startDateParam = getQueryParam(req.query.start_date);
    const endDateParam = getQueryParam(req.query.end_date);
    const itemIdParam = getQueryParam(req.query.item_id);
    const warehouseIdParam = getQueryParam(req.query.warehouse_id);
    const supplierIdParam = getQueryParam(req.query.supplier_id);
    const supplierNameParam = getQueryParam(req.query.supplier_name);
    const search = getQueryParam(req.query.search);
    const sortBy = getQueryParam(req.query.sortBy);
    const sortOrder = getQueryParam(req.query.sortOrder);
    const includeVoidedParam = getQueryParam(req.query.include_voided);

    const filters = {
      start_date: startDateParam as string | undefined,
      end_date: endDateParam as string | undefined,
      item_id: itemIdParam ? Number(itemIdParam) : undefined,
      warehouse_id: warehouseIdParam ? Number(warehouseIdParam) : undefined,
      supplier_id: supplierIdParam ? Number(supplierIdParam) : undefined,
      supplier_name: supplierNameParam as string | undefined,
      search: search || undefined,
      include_voided: includeVoidedParam === '1' || includeVoidedParam === 'true',
      sortBy: sortBy || undefined,
      sortOrder: sortOrder || undefined,
      page,
      limit
    };

    const { rows, total, pageNum, limitNum } = Purchase.getAll(filters, db);

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
  } catch (error) {
    logger.error('Get purchases error:', error);
    res.status(500).json({ error: 'Failed to get purchases' });
  }
}

function getPurchase(req: Request, res: Response): void {
  try {
    const purchase = Purchase.getById(Number(req.params.id), db);

    if (!purchase) {
      res.status(404).json({ error: 'Purchase not found' });
      return;
    }

    res.json(purchase);
  } catch (error) {
    logger.error('Get purchase error:', error);
    res.status(500).json({ error: 'Failed to get purchase' });
  }
}

function getPurchasePayments(req: Request, res: Response): void {
  try {
    const payments = Purchase.getPayments(Number(req.params.id), db);
    res.json({ success: true, data: payments });
  } catch (error) {
    logger.error('Get purchase payments error:', error);
    res.status(500).json({ error: 'Failed to get purchase payments' });
  }
}

function getPurchaseSummaryByItem(req: Request, res: Response): void {
  try {
    const { item_id } = req.params;

    if (!item_id) {
      res.status(400).json({ error: 'Item ID is required' });
      return;
    }

    const summary = Purchase.getSummaryByItem(Number(item_id), db);

    res.json(summary);
  } catch (error) {
    logger.error('Get purchase summary error:', error);
    res.status(500).json({ error: 'Failed to get purchase summary' });
  }
}

function getPurchaseSummaryByDateRange(req: Request, res: Response): void {
  try {
    const { start_date, end_date } = req.query;

    if (!start_date || !end_date) {
      res.status(400).json({ error: 'Start date and end date are required' });
      return;
    }

    const summary = Purchase.getSummaryByDateRange(start_date as string, end_date as string, db);

    res.json(summary);
  } catch (error) {
    logger.error('Get purchase summary error:', error);
    res.status(500).json({ error: 'Failed to get purchase summary' });
  }
}

function getTopSuppliers(req: Request, res: Response): void {
  try {
    const limitParam = getQueryParam(req.query.limit);
    const limit = limitParam ? parseInt(String(limitParam)) : 10;
    const suppliers = Purchase.getTopSuppliers(limit, db);

    res.json(suppliers);
  } catch (error) {
    logger.error('Get top suppliers error:', error);
    res.status(500).json({ error: 'Failed to get top suppliers' });
  }
}

function voidPurchase(req: AuthRequest, res: Response): void {
  try {
    const id = Number(req.params.id);
    const { reason } = req.body as { reason?: string };

    if (!reason || !reason.trim()) {
      res.status(400).json({ success: false, error: 'A void reason is required' });
      return;
    }

    Purchase.void(id, req.user!.id, reason, db);

    res.json({ success: true, message: 'Purchase voided successfully' });
  } catch (error: any) {
    const message = error?.message || 'Failed to void purchase';
    // Guard rejections are client errors — surface the reason.
    const isClientError = /Cannot void|already voided|not found|reason is required/i.test(message);
    logger.error('Void purchase error:', error);
    res.status(isClientError ? 400 : 500).json({ success: false, error: message });
  }
}

export default {
  recordPurchase,
  getPurchases,
  getPurchase,
  getPurchasePayments,
  getPurchaseSummaryByItem,
  getPurchaseSummaryByDateRange,
  getTopSuppliers,
  voidPurchase,
};
