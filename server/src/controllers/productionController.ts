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
      overhead_cost,
      bom_id
    } = req.body;

    const outputs: unknown = req.body.outputs;
    const hasOutputLines = Array.isArray(outputs) && outputs.length > 0;
    const hasSingleOutput = Boolean(output_item_id) && output_quantity !== undefined;

    if (!hasSingleOutput && !hasOutputLines) {
      res.status(400).json({
        error: 'Provide either outputs[] (D6 joint products) or output_item_id + output_quantity',
      });
      return;
    }

    if (!warehouse_id || !production_date || !input_items || !input_items.length) {
      res.status(400).json({ error: 'Warehouse, date, and input items are required' });
      return;
    }

    if (output_quantity !== undefined && Number(output_quantity) <= 0) {
      res.status(400).json({ error: 'Output quantity must be positive' });
      return;
    }

    // D6 guards: an output line must be positive, unique, and never an input
    // (an item cannot be produced from itself). Reject with 400 before the
    // model opens a transaction.
    if (hasOutputLines) {
      const lines = outputs as Array<{ item_id?: unknown; quantity?: unknown }>;
      const seen = new Set<number>();
      const inputIds = new Set(
        (input_items as Array<{ item_id: unknown }>).map((line) => Number(line.item_id)),
      );
      for (const line of lines) {
        const itemId = Number(line.item_id);
        const quantity = Number(line.quantity);
        if (!Number.isInteger(itemId) || itemId <= 0) {
          res.status(400).json({ error: 'Each output needs a valid item_id' });
          return;
        }
        if (!Number.isFinite(quantity) || quantity <= 0) {
          res.status(400).json({ error: 'Output quantity must be positive' });
          return;
        }
        if (seen.has(itemId)) {
          res.status(400).json({ error: `Output item ${itemId} is listed more than once` });
          return;
        }
        if (inputIds.has(itemId)) {
          res.status(400).json({ error: 'An item cannot be produced from itself' });
          return;
        }
        seen.add(itemId);
      }
    }

    // D6: the BOM must produce the PRIMARY output (the first line). The model
    // enforces the same rule, but there it throws into a 500 that hides the
    // reason — so a mismatched BOM is answered here as a 400 the client can act
    // on (e.g. a joint production whose co-product was listed first).
    if (bom_id) {
      const primaryId = hasOutputLines
        ? Number((outputs as Array<{ item_id?: unknown }>)[0]?.item_id)
        : Number(output_item_id);
      const bom = db
        .prepare('SELECT finished_item_id FROM boms WHERE id = ?')
        .get(Number(bom_id)) as { finished_item_id: number } | undefined;
      if (!bom) {
        res.status(400).json({ error: `BOM ${bom_id} not found` });
        return;
      }
      if (bom.finished_item_id !== primaryId) {
        res.status(400).json({
          error: `BOM ${bom_id} produces item ${bom.finished_item_id}, but the primary output is item ${primaryId}`,
        });
        return;
      }
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
  } catch (error: unknown) {
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
  } catch (error: unknown) {
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
