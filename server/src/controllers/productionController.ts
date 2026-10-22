import { listPagination, listPageQuery } from '../utils/controllerPagination';
import { Request, Response } from 'express';
import { getQueryInteger, getQueryParam } from '../utils/queryUtils';
import ProductionModel from '../models/Production';
import { AuthRequest } from '../types';
import { logCRUD, ActionType } from '../services/activityLogger';
import db from '../config/database';
import logger from '../utils/logger';
import { handleBusinessError } from '../utils/businessRuleError';

function validateJointOutputs(lines: Array<{ item_id?: unknown; quantity?: unknown }>, inputs: Array<{ item_id: unknown }>): string | null {
  const seen = new Set<number>();
  const inputIds = new Set(inputs.map(line => Number(line.item_id)));
  for (const line of lines) {
    const itemId = Number(line.item_id);
    const quantity = Number(line.quantity);
    if (!Number.isInteger(itemId) || itemId <= 0) return 'Each output needs a valid item_id';
    if (!Number.isFinite(quantity) || quantity <= 0) return 'Output quantity must be positive';
    if (seen.has(itemId)) return `Output item ${itemId} is listed more than once`;
    if (inputIds.has(itemId)) return 'An item cannot be produced from itself';
    seen.add(itemId);
  }
  return null;
}

function productionBomError(bom_id: number, primaryId: number): string | null {
  const bom = db
    .prepare('SELECT finished_item_id FROM boms WHERE id = ?')
    .get(Number(bom_id)) as { finished_item_id: number } | undefined;
  if (!bom) {
    return `BOM ${bom_id} not found`;
  }
  if (bom.finished_item_id !== primaryId) {
    return `BOM ${bom_id} produces item ${bom.finished_item_id}, but the primary output is item ${primaryId}`;
  }
  return null;
}

interface ProductionRequestBody {
  output_item_id?: unknown;
  output_quantity?: unknown;
  warehouse_id?: unknown;
  raw_materials_warehouse_id?: unknown;
  production_date?: unknown;
  input_items?: unknown;
  overhead_cost?: unknown;
  bom_id?: unknown;
  outputs?: unknown;
}

// D6 guards for joint-product payloads: an output line must be positive,
// unique, and never an input (an item cannot be produced from itself), and
// the BOM must produce the PRIMARY output (the first line). Both reject
// with 400 before the model opens a transaction. The model enforces the
// same rules, but there a BOM mismatch throws into a 500 that hides the
// reason — answering it here gives the client a 400 it can act on (e.g. a
// joint production whose co-product was listed first).
function jointOutputRequestError(
  outputs: unknown,
  inputItems: unknown,
  outputItemId: unknown,
  bomId: unknown
): string | null {
  const hasOutputLines = Array.isArray(outputs) && outputs.length > 0;

  if (hasOutputLines) {
    const lines = outputs as Array<{ item_id?: unknown; quantity?: unknown }>;
    const lineError = validateJointOutputs(lines, inputItems as Array<{ item_id: unknown }>);
    if (lineError) return lineError;
  }

  if (bomId) {
    const primaryId = hasOutputLines
      ? Number((outputs as Array<{ item_id?: unknown }>)[0]?.item_id)
      : Number(outputItemId);
    const bomError = productionBomError(Number(bomId), primaryId);
    if (bomError) return bomError;
  }

  return null;
}

// Every guard below answers 400 with `{ error }`, in this exact precedence.
// Keeping them together preserves that precedence and keeps recordProduction
// readable; the model still enforces the same rules transactionally.
function productionRequestError(body: ProductionRequestBody): string | null {
  const { output_item_id, output_quantity, warehouse_id, production_date, input_items, bom_id } = body;
  const outputs = body.outputs;
  const hasOutputLines = Array.isArray(outputs) && outputs.length > 0;
  const hasSingleOutput = Boolean(output_item_id) && output_quantity !== undefined;

  if (!hasSingleOutput && !hasOutputLines) {
    return 'Provide either outputs[] (D6 joint products) or output_item_id + output_quantity';
  }

  if (!warehouse_id || !production_date || !input_items || !(input_items as unknown[]).length) {
    return 'Warehouse, date, and input items are required';
  }

  if (output_quantity !== undefined && Number(output_quantity) <= 0) {
    return 'Output quantity must be positive';
  }

  return jointOutputRequestError(outputs, input_items, output_item_id, bom_id);
}

function recordProduction(req: AuthRequest, res: Response): void {
  try {
    const requestError = productionRequestError(req.body as ProductionRequestBody);
    if (requestError) {
      res.status(400).json({ error: requestError });
      return;
    }

    const { warehouse_id, raw_materials_warehouse_id, overhead_cost } = req.body as ProductionRequestBody;

    const productionData = {
      ...req.body,
      raw_materials_warehouse_id: (raw_materials_warehouse_id as string | undefined) || (warehouse_id as string),
      overhead_cost: overhead_cost ? parseFloat(String(overhead_cost)) : 0
    };

    const production = ProductionModel.recordProduction(productionData, req.user!.id, db);

    // Log production creation using activity logger
    logCRUD(ActionType.WO_CREATE, 'WorkOrder', production.id, `Created production: ${production.production_no} - ${production.output_item_name} (${production.output_quantity} units)`, req.user!.id);
    req.activityLogged = true;

    res.status(201).json(production);
  } catch (error: unknown) {
    handleBusinessError(res, error, 'Record production', 'Failed to record production');
  }
}

function getProductions(req: Request, res: Response): void {
  try {
    const { page, limit } = listPageQuery(req.query);
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
      pagination: listPagination(total, pageNum, limitNum)
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

    // ProductionModel.delete throws 'Production not found', which the catch
    // below would turn into a 500. A double delete is a missing resource,
    // not a server fault — and checking first also stops the reversal path
    // from starting against a row that is not there.
    if (!production) {
      res.status(404).json({ error: 'Production not found' });
      return;
    }

    ProductionModel.delete(productionId, req.user!.id, db);

    logCRUD(ActionType.WO_DELETE, 'WorkOrder', productionId, `Deleted production: ${production.production_no}`, req.user!.id);
    req.activityLogged = true;

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
