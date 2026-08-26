import { Request, Response } from 'express';
import { getQueryInteger, getQueryParam } from '../utils/queryUtils';
import ProductionModel from '../models/Production';
import { AuthRequest } from '../types';
import { logCRUD, ActionType } from '../services/activityLogger';
import db from '../config/database';
import logger from '../utils/logger';

function recordProduction(req: AuthRequest, res: Response): void {
  try {
    const {
      output_item_id,
      output_quantity,
      warehouse_id,
      raw_materials_warehouse_id,
      production_date,
      input_items,
      overhead_cost
    } = req.body;

    if (!output_item_id || !output_quantity || !warehouse_id || !production_date || !input_items || !input_items.length) {
      res.status(400).json({ error: 'Output item, quantity, warehouse, date, and input items are required' });
      return;
    }

    if (output_quantity <= 0) {
      res.status(400).json({ error: 'Output quantity must be positive' });
      return;
    }

    const productionData = {
      ...req.body,
      raw_materials_warehouse_id: raw_materials_warehouse_id || warehouse_id,
      overhead_cost: overhead_cost ? parseFloat(String(overhead_cost)) : 0
    };

    const production = ProductionModel.recordProduction(productionData, req.user!.id, db);

    // Log production creation using activity logger
    logCRUD(ActionType.WO_CREATE, 'WorkOrder', production.id, `Created production: ${production.production_no} - ${production.output_item_name} (${production.output_quantity} units)`, req.user!.id);
    req.activityLogged = true;

    res.status(201).json(production);
  } catch (error: any) {
    logger.error('Record production error:', error);
    res.status(500).json({ error: 'Failed to record production' });
  }
}

function getProductions(req: Request, res: Response): void {
  try {
    const page = getQueryInteger(req.query.page, 1);
    const limit = getQueryInteger(req.query.limit, 10);
    const startDateParam = getQueryParam(req.query.start_date);
    const endDateParam = getQueryParam(req.query.end_date);
    const outputItemIdParam = getQueryParam(req.query.output_item_id);
    const warehouseIdParam = getQueryParam(req.query.warehouse_id);
    const search = getQueryParam(req.query.search);
    const sortBy = getQueryParam(req.query.sortBy);
    const sortOrder = getQueryParam(req.query.sortOrder);

    const filters = {
      start_date: startDateParam as string | undefined,
      end_date: endDateParam as string | undefined,
      output_item_id: outputItemIdParam ? Number(outputItemIdParam) : undefined,
      warehouse_id: warehouseIdParam ? Number(warehouseIdParam) : undefined,
      search: search || undefined,
      sortBy: sortBy || undefined,
      sortOrder: sortOrder || undefined,
      page,
      limit
    };
    const { rows, total, pageNum, limitNum } = ProductionModel.getAll(filters, db);

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
    logger.error('Get productions error:', error);
    res.status(500).json({ error: 'Failed to get productions' });
  }
}

function getProduction(req: Request, res: Response): void {
  try {
    const production = ProductionModel.getById(Number(req.params.id), db);
    if (!production) {
      res.status(404).json({ error: 'Production not found' });
      return;
    }
    res.json(production);
  } catch (error) {
    logger.error('Get production error:', error);
    res.status(500).json({ error: 'Failed to get production' });
  }
}

function getProductionSummaryByItem(req: Request, res: Response): void {
  try {
    const { item_id } = req.params;
    if (!item_id) {
      res.status(400).json({ error: 'Item ID is required' });
      return;
    }
    res.json(ProductionModel.getSummaryByItem(Number(item_id), db));
  } catch (error) {
    logger.error('Get production summary error:', error);
    res.status(500).json({ error: 'Failed to get production summary' });
  }
}

function deleteProduction(req: AuthRequest, res: Response): void {
  try {
    const productionId = Number(req.params.id);
    const production = ProductionModel.getById(productionId, db);

    ProductionModel.delete(productionId, req.user!.id, db);

    // Log production deletion using activity logger
    if (production) {
      logCRUD(ActionType.WO_DELETE, 'WorkOrder', productionId, `Deleted production: ${production.production_no}`, req.user!.id);
      req.activityLogged = true;
    }

    res.json({ success: true, message: 'Production deleted successfully' });
  } catch (error: any) {
    logger.error('Delete production error:', error);
    res.status(500).json({ error: 'Failed to delete production' });
  }
}

export default {
  recordProduction,
  getProductions,
  getProduction,
  getProductionSummaryByItem,
  deleteProduction
};
