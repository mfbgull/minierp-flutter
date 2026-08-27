import { Request, Response } from 'express';
import { getQueryParam, getRouteParam } from '../utils/queryUtils';
import { AuthRequest } from '../types';
import { logCRUD, ActionType } from '../services/activityLogger';
import db from '../config/database';
import logger from '../utils/logger';
import {
  sanitizeSortParams,
  OWNER_CAPITAL_SORT_COLUMNS,
  OWNER_WITHDRAWAL_SORT_COLUMNS,
} from '../utils/sqlSanitizer';
import OwnerCapitalModel, {
  generateCapitalNo,
  type CreateOwnerCapitalDTO,
  type UpdateOwnerCapitalDTO,
} from '../models/OwnerCapital';
import OwnerWithdrawalModel, {
  generateWithdrawalNo,
  type WithdrawalItemInput,
} from '../models/OwnerWithdrawal';
import ExpenseModel from '../models/Expense';

/**
 * Business-rule violations (funds guard, stock guard, closed periods,
 * double-posting, validation) are client errors; anything else is a
 * server fault. Matched on the message prefixes the models/services throw.
 */
function isClientError(message: string): boolean {
  const markers = [
    'Insufficient funds',
    'Insufficient stock',
    'Insufficient stock for',
    'Batch coverage shortfall',
    'All batches for',
    'closed accounting period',
    'already exists for',
    'refusing to double-post',
    'Cannot reverse withdrawal',
    'cannot be edited',
    'already voided',
    'not found',
    'Not found',
    'must be',
    'requires at least one',
    'computed as zero',
    'required account',
    'Unbalanced goods withdrawal',
    'Invalid',
    'Unknown',
    'A journal entry must have',
    'Unbalanced journal entry',
    'No open accounting period',
    'Line amounts',
    'Line must have',
    'Line must be debit',
  ];
  return markers.some((m) => message.includes(m));
}

function fail(res: Response, error: unknown, fallback: string): void {
  const message = error instanceof Error ? error.message : String(error);
  if (isClientError(message)) {
    res.status(400).json({ success: false, error: message });
    return;
  }
  logger.error(`${fallback}:`, error);
  res.status(500).json({ success: false, error: fallback });
}

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

// ---------------------------------------------------------------------
// Owner capital
// ---------------------------------------------------------------------

function createCapital(req: AuthRequest, res: Response): void {
  try {
    const { capital_date, amount, payment_method, note } = req.body;
    const userId = req.user!.id;

    if (!capital_date || !DATE_RE.test(String(capital_date))) {
      res.status(400).json({ success: false, error: 'A valid capital_date (YYYY-MM-DD) is required' });
      return;
    }
    const parsedAmount = Number(amount);
    if (!Number.isFinite(parsedAmount) || parsedAmount <= 0) {
      res.status(400).json({ success: false, error: 'Amount must be a positive number' });
      return;
    }

    let capitalId: number;
    let capitalNo: string;
    db.transaction(() => {
      capitalNo = generateCapitalNo(db, capital_date);
      const dto: CreateOwnerCapitalDTO = {
        capital_no: capitalNo,
        capital_date,
        amount: parsedAmount,
        payment_method: payment_method || undefined,
        note: note || undefined,
        created_by: userId,
      };
      capitalId = OwnerCapitalModel.create(db, dto);
    })();

    logCRUD(ActionType.SETTING_UPDATE, 'OwnerCapital', capitalId!, `Created owner capital ${capitalNo!} (${parsedAmount})`, userId, {
      capital_no: capitalNo!, amount: parsedAmount, payment_method: payment_method ?? null,
    });
    req.activityLogged = true;

    res.status(201).json({
      success: true,
      message: 'Owner capital recorded successfully',
      data: { id: capitalId!, capital_no: capitalNo!, amount: parsedAmount },
    });
  } catch (error) {
    fail(res, error, 'Failed to record owner capital');
  }
}

function getCapitalList(req: Request, res: Response): void {
  try {
    const sortParams = sanitizeSortParams(
      getQueryParam(req.query.sortBy) || 'oc.capital_date',
      getQueryParam(req.query.sortOrder) || 'DESC',
      OWNER_CAPITAL_SORT_COLUMNS,
      'oc.capital_date',
      'DESC'
    );
    const filters = {
      page: parseInt(getQueryParam(req.query.page) as string) || 1,
      limit: parseInt(getQueryParam(req.query.limit) as string) || 10,
      status: getQueryParam(req.query.status) as string | undefined,
      from_date: getQueryParam(req.query.from_date) as string | undefined,
      to_date: getQueryParam(req.query.to_date) as string | undefined,
      search: getQueryParam(req.query.search) as string | undefined,
      sortBy: sortParams.column,
      sortOrder: sortParams.order,
    };

    const rows = OwnerCapitalModel.getAll(db, filters);
    const totalItems = OwnerCapitalModel.getCount(db, filters);
    const totalPages = Math.ceil(totalItems / filters.limit);

    res.json({
      success: true,
      data: rows,
      pagination: {
        currentPage: filters.page,
        totalPages,
        totalItems,
        hasNext: filters.page < totalPages,
        hasPrev: filters.page > 1,
      },
    });
  } catch (error) {
    fail(res, error, 'Failed to fetch owner capital');
  }
}

function updateCapital(req: AuthRequest, res: Response): void {
  try {
    const id = parseInt(getRouteParam(req.params.id), 10);
    const { capital_date, amount, payment_method, note } = req.body;
    const userId = req.user!.id;

    if (capital_date !== undefined && !DATE_RE.test(String(capital_date))) {
      res.status(400).json({ success: false, error: 'capital_date must be YYYY-MM-DD' });
      return;
    }
    if (amount !== undefined && (!Number.isFinite(Number(amount)) || Number(amount) <= 0)) {
      res.status(400).json({ success: false, error: 'Amount must be a positive number' });
      return;
    }
    const existing = OwnerCapitalModel.getById(db, id);
    if (!existing) {
      res.status(404).json({ success: false, error: 'Owner capital entry not found' });
      return;
    }

    const dto: UpdateOwnerCapitalDTO = {
      capital_date,
      amount: amount !== undefined ? Number(amount) : undefined,
      payment_method,
      note,
    };
    OwnerCapitalModel.update(db, id, dto, { userId });

    logCRUD(ActionType.SETTING_UPDATE, 'OwnerCapital', id, `Updated owner capital ${existing.capital_no}`, userId, {
      capital_no: existing.capital_no, changes: dto,
    });
    req.activityLogged = true;

    res.json({ success: true, message: 'Owner capital updated successfully', data: { id } });
  } catch (error) {
    fail(res, error, 'Failed to update owner capital');
  }
}

function voidCapital(req: AuthRequest, res: Response): void {
  try {
    const id = parseInt(getRouteParam(req.params.id), 10);
    const userId = req.user!.id;
    const reason = typeof req.body?.reason === 'string' ? req.body.reason : undefined;

    const existing = OwnerCapitalModel.getById(db, id);
    if (!existing) {
      res.status(404).json({ success: false, error: 'Owner capital entry not found' });
      return;
    }

    OwnerCapitalModel.softVoid(db, id, { userId, reason });

    logCRUD(ActionType.SETTING_UPDATE, 'OwnerCapital', id, `Voided owner capital ${existing.capital_no}`, userId, {
      capital_no: existing.capital_no, reason: reason ?? null,
    });
    req.activityLogged = true;

    res.json({ success: true, message: 'Owner capital voided', data: { id, status: 'voided' } });
  } catch (error) {
    fail(res, error, 'Failed to void owner capital');
  }
}

// ---------------------------------------------------------------------
// Owner withdrawals
// ---------------------------------------------------------------------

function validateItemLines(raw: unknown): { lines?: WithdrawalItemInput[]; error?: string } {
  if (!Array.isArray(raw) || raw.length === 0) {
    return { error: 'A goods withdrawal requires at least one item line' };
  }
  const lines: WithdrawalItemInput[] = [];
  for (const item of raw) {
    // Server-authoritative costing: the client names item/warehouse/qty only.
    if (
      item === null || typeof item !== 'object' ||
      'unit_cost' in item || 'batch_id' in item || 'line_total' in item
    ) {
      return { error: 'Client-supplied costing fields (unit_cost/batch_id/line_total) are not accepted' };
    }
    const itemId = Number((item as Record<string, unknown>).item_id);
    const warehouseId = Number((item as Record<string, unknown>).warehouse_id);
    const quantity = Number((item as Record<string, unknown>).quantity);
    if (!Number.isInteger(itemId) || itemId <= 0) return { error: 'Each line needs a valid item_id' };
    if (!Number.isInteger(warehouseId) || warehouseId <= 0) return { error: 'Each line needs a valid warehouse_id' };
    if (!Number.isFinite(quantity) || quantity <= 0) return { error: 'Line quantities must be positive numbers' };
    lines.push({ item_id: itemId, warehouse_id: warehouseId, quantity });
  }
  return { lines };
}

function createWithdrawal(req: AuthRequest, res: Response): void {
  try {
    const { withdrawal_date, kind, amount, payment_method, note, items } = req.body;
    const userId = req.user!.id;

    if (!withdrawal_date || !DATE_RE.test(String(withdrawal_date))) {
      res.status(400).json({ success: false, error: 'A valid withdrawal_date (YYYY-MM-DD) is required' });
      return;
    }
    if (kind !== 'cash' && kind !== 'goods') {
      res.status(400).json({ success: false, error: "kind must be 'cash' or 'goods'" });
      return;
    }
    if (kind === 'cash') {
      const parsedAmount = Number(amount);
      if (!Number.isFinite(parsedAmount) || parsedAmount <= 0) {
        res.status(400).json({ success: false, error: 'Cash withdrawal amount must be a positive number' });
        return;
      }
    } else if (amount !== undefined) {
      // Goods value is always server-calculated from batch costs.
      res.status(400).json({ success: false, error: 'Goods withdrawal amount is system-calculated and cannot be supplied' });
      return;
    }

    let lines: WithdrawalItemInput[] | undefined;
    if (kind === 'goods') {
      const check = validateItemLines(items);
      if (check.error) {
        res.status(400).json({ success: false, error: check.error });
        return;
      }
      lines = check.lines;
    }

    let withdrawalId: number;
    let withdrawalNo: string;
    let recordedAmount: number;
    db.transaction(() => {
      withdrawalNo = generateWithdrawalNo(db, withdrawal_date);
      const result = OwnerWithdrawalModel.create(db, {
        withdrawal_no: withdrawalNo,
        withdrawal_date,
        kind,
        amount: kind === 'cash' ? Number(amount) : undefined,
        payment_method: kind === 'cash' ? payment_method : undefined,
        note: note || undefined,
        items: lines,
        created_by: userId,
      });
      withdrawalId = result.id;
      recordedAmount = result.amount;
    })();

    logCRUD(ActionType.STOCK_MOVEMENT, 'OwnerWithdrawal', withdrawalId!, `Created owner withdrawal ${withdrawalNo!} (${kind}, ${recordedAmount!.toFixed(2)})`, userId, {
      withdrawal_no: withdrawalNo!, kind, amount: recordedAmount!,
    });
    req.activityLogged = true;

    res.status(201).json({
      success: true,
      message: 'Owner withdrawal recorded successfully',
      data: { id: withdrawalId!, withdrawal_no: withdrawalNo!, amount: recordedAmount! },
    });
  } catch (error) {
    fail(res, error, 'Failed to record owner withdrawal');
  }
}

function quoteWithdrawal(req: Request, res: Response): void {
  try {
    const check = validateItemLines(req.body?.items);
    if (check.error) {
      res.status(400).json({ success: false, error: check.error });
      return;
    }
    const quote = OwnerWithdrawalModel.quote(db, check.lines!);
    res.json({ success: true, data: quote });
  } catch (error) {
    fail(res, error, 'Failed to quote withdrawal cost');
  }
}

function getWithdrawalList(req: Request, res: Response): void {
  try {
    const sortParams = sanitizeSortParams(
      getQueryParam(req.query.sortBy) || 'ow.withdrawal_date',
      getQueryParam(req.query.sortOrder) || 'DESC',
      OWNER_WITHDRAWAL_SORT_COLUMNS,
      'ow.withdrawal_date',
      'DESC'
    );
    const filters = {
      page: parseInt(getQueryParam(req.query.page) as string) || 1,
      limit: parseInt(getQueryParam(req.query.limit) as string) || 10,
      status: getQueryParam(req.query.status) as string | undefined,
      kind: getQueryParam(req.query.kind) as string | undefined,
      from_date: getQueryParam(req.query.from_date) as string | undefined,
      to_date: getQueryParam(req.query.to_date) as string | undefined,
      search: getQueryParam(req.query.search) as string | undefined,
      sortBy: sortParams.column,
      sortOrder: sortParams.order,
    };

    const rows = OwnerWithdrawalModel.getAll(db, filters);
    const totalItems = OwnerWithdrawalModel.getCount(db, filters);
    const totalPages = Math.ceil(totalItems / filters.limit);

    res.json({
      success: true,
      data: rows,
      pagination: {
        currentPage: filters.page,
        totalPages,
        totalItems,
        hasNext: filters.page < totalPages,
        hasPrev: filters.page > 1,
      },
    });
  } catch (error) {
    fail(res, error, 'Failed to fetch owner withdrawals');
  }
}

function getWithdrawalById(req: Request, res: Response): void {
  try {
    const id = parseInt(getRouteParam(req.params.id), 10);
    const withdrawal = OwnerWithdrawalModel.getById(db, id);
    if (!withdrawal) {
      res.status(404).json({ success: false, error: 'Owner withdrawal not found' });
      return;
    }
    const items = OwnerWithdrawalModel.getItems(db, id);
    const movements = OwnerWithdrawalModel.getMovements(db, withdrawal.withdrawal_no);
    res.json({
      success: true,
      data: { ...withdrawal, items, movements },
    });
  } catch (error) {
    fail(res, error, 'Failed to fetch owner withdrawal');
  }
}

function updateWithdrawal(req: AuthRequest, res: Response): void {
  try {
    const id = parseInt(getRouteParam(req.params.id), 10);
    const { withdrawal_date, amount, payment_method, note, items } = req.body;
    const userId = req.user!.id;

    if (withdrawal_date !== undefined && !DATE_RE.test(String(withdrawal_date))) {
      res.status(400).json({ success: false, error: 'withdrawal_date must be YYYY-MM-DD' });
      return;
    }
    const existing = OwnerWithdrawalModel.getById(db, id);
    if (!existing) {
      res.status(404).json({ success: false, error: 'Owner withdrawal not found' });
      return;
    }
    if (existing.kind === 'goods' && amount !== undefined) {
      res.status(400).json({ success: false, error: 'Goods withdrawal amount is system-calculated and cannot be supplied' });
      return;
    }

    let lines: WithdrawalItemInput[] | null | undefined;
    if (existing.kind === 'goods' && items !== undefined) {
      if (items === null) {
        lines = null; // explicit clear rejected below via empty-lines rule
      } else {
        const check = validateItemLines(items);
        if (check.error) {
          res.status(400).json({ success: false, error: check.error });
          return;
        }
        lines = check.lines;
      }
    }

    const result = OwnerWithdrawalModel.update(db, id, {
      withdrawal_date,
      amount: existing.kind === 'cash' && amount !== undefined ? Number(amount) : undefined,
      payment_method,
      note,
      items: lines,
    }, { userId });

    logCRUD(ActionType.STOCK_MOVEMENT, 'OwnerWithdrawal', id, `Updated owner withdrawal ${existing.withdrawal_no}`, userId, {
      withdrawal_no: existing.withdrawal_no, new_amount: result.amount,
    });
    req.activityLogged = true;

    res.json({
      success: true,
      message: 'Owner withdrawal updated successfully',
      data: { id, amount: result.amount },
    });
  } catch (error) {
    fail(res, error, 'Failed to update owner withdrawal');
  }
}

function voidWithdrawal(req: AuthRequest, res: Response): void {
  try {
    const id = parseInt(getRouteParam(req.params.id), 10);
    const userId = req.user!.id;
    const reason = typeof req.body?.reason === 'string' ? req.body.reason : undefined;

    const existing = OwnerWithdrawalModel.getById(db, id);
    if (!existing) {
      res.status(404).json({ success: false, error: 'Owner withdrawal not found' });
      return;
    }

    OwnerWithdrawalModel.softVoid(db, id, { userId, reason });

    logCRUD(ActionType.STOCK_MOVEMENT, 'OwnerWithdrawal', id, `Voided owner withdrawal ${existing.withdrawal_no}`, userId, {
      withdrawal_no: existing.withdrawal_no, reason: reason ?? null,
    });
    req.activityLogged = true;

    res.json({ success: true, message: 'Owner withdrawal voided', data: { id, status: 'voided' } });
  } catch (error) {
    fail(res, error, 'Failed to void owner withdrawal');
  }
}

// ---------------------------------------------------------------------
// Shared
// ---------------------------------------------------------------------

function getSummary(_req: Request, res: Response): void {
  try {
    res.json({ success: true, data: OwnerCapitalModel.getSummaryTotals(db) });
  } catch (error) {
    fail(res, error, 'Failed to fetch owner equity summary');
  }
}

function getPaymentMethodOptions(_req: Request, res: Response): void {
  try {
    res.json({ success: true, data: ExpenseModel.getPaymentMethodOptions() });
  } catch (error) {
    fail(res, error, 'Failed to fetch payment method options');
  }
}

export default {
  createCapital,
  getCapitalList,
  updateCapital,
  voidCapital,
  createWithdrawal,
  quoteWithdrawal,
  getWithdrawalList,
  getWithdrawalById,
  updateWithdrawal,
  voidWithdrawal,
  getSummary,
  getPaymentMethodOptions,
};
