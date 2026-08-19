import { Request, Response } from 'express';
import { getQueryInteger, getQueryParam } from '../utils/queryUtils';
import { AuthRequest } from '../types';
import PurchaseReturnModel from '../models/PurchaseReturn';
import db from '../config/database';
import logger from '../utils/logger';

function getPurchaseReturns(req: Request, res: Response): void {
  try {
    const page = getQueryInteger(req.query.page, 1);
    const limit = getQueryInteger(req.query.limit, 10);
    const search = getQueryParam(req.query.search);
    const startDate = getQueryParam(req.query.start_date);
    const endDate = getQueryParam(req.query.end_date);
    const type = getQueryParam(req.query.type);
    const status = getQueryParam(req.query.status);
    const warehouseIdParam = getQueryParam(req.query.warehouse_id);
    const sortBy = getQueryParam(req.query.sortBy);
    const sortOrder = getQueryParam(req.query.sortOrder);

    const filters = {
      search: search || undefined,
      start_date: startDate || undefined,
      end_date: endDate || undefined,
      type: type || undefined,
      status: status || undefined,
      warehouse_id: warehouseIdParam ? Number(warehouseIdParam) : undefined,
      sortBy: sortBy || undefined,
      sortOrder: sortOrder || undefined,
      page,
      limit
    };

    const { rows, total, pageNum, limitNum } = PurchaseReturnModel.getAll(filters, db);

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
    logger.error('Get purchase returns error:', error);
    res.status(500).json({ error: 'Failed to get purchase returns' });
  }
}

function getPurchaseReturn(req: Request, res: Response): void {
  try {
    const purchaseReturn = PurchaseReturnModel.getById(Number(req.params.id), db);

    if (!purchaseReturn) {
      res.status(404).json({ error: 'Purchase return not found' });
      return;
    }

    res.json(purchaseReturn);
  } catch (error) {
    logger.error('Get purchase return error:', error);
    res.status(500).json({ error: 'Failed to get purchase return' });
  }
}

function createPurchaseReturn(req: AuthRequest, res: Response): Response | void {
  try {
    const body = req.body as {
      return_date?: string;
      source_type?: string;
      source_id?: number;
      warehouse_id?: number;
      reason?: string;
      items?: Array<{ source_item_id: number; quantity: number }>;
    };

    if (!body.return_date) {
      return res.status(400).json({ error: 'return_date is required' });
    }
    if (body.source_type !== 'PURCHASE' && body.source_type !== 'PURCHASE_ORDER') {
      return res.status(400).json({ error: 'source_type must be PURCHASE or PURCHASE_ORDER' });
    }
    if (!body.source_id || body.source_id <= 0) {
      return res.status(400).json({ error: 'A valid source_id is required' });
    }
    if (!body.warehouse_id || body.warehouse_id <= 0) {
      return res.status(400).json({ error: 'A valid warehouse_id is required' });
    }
    if (!body.items || body.items.length === 0) {
      return res.status(400).json({ error: 'At least one return item is required' });
    }

    const created = PurchaseReturnModel.create(
      {
        return_date: body.return_date,
        source_type: body.source_type,
        source_id: body.source_id,
        warehouse_id: body.warehouse_id,
        reason: body.reason,
        items: body.items,
      },
      req.user!.id,
      db
    );

    res.status(201).json({
      success: true,
      message: `Purchase return ${created.return_no} created successfully`,
      data: created,
    });
  } catch (error: unknown) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    logger.error('Create purchase return error:', { error: errorMessage });
    res.status(400).json({ error: errorMessage });
  }
}

function voidPurchaseReturn(req: AuthRequest, res: Response): Response | void {
  try {
    const id = Number(req.params.id);
    const reason = typeof req.body?.reason === 'string' ? req.body.reason : undefined;

    const voided = PurchaseReturnModel.voidReturn(id, req.user!.id, reason || '', db);

    res.json({
      success: true,
      message: `Purchase return ${voided.return_no} voided successfully`,
      data: voided,
    });
  } catch (error: unknown) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    logger.error('Void purchase return error:', { error: errorMessage });
    res.status(400).json({ error: errorMessage });
  }
}

export default {
  getPurchaseReturns,
  getPurchaseReturn,
  createPurchaseReturn,
  voidPurchaseReturn,
};
