import type { Response } from 'express';
import type { AuthRequest } from '../types';
import db from '../config/database';
import { SupplierPrepaymentModel } from '../models/SupplierPrepayment';
import { BusinessRuleError, handleBusinessError } from '../utils/businessRuleError';
import { ActionType, logCRUD } from '../services/activityLogger';

const model = new SupplierPrepaymentModel(db);

export function listSupplierPrepayments(req: AuthRequest, res: Response): void {
  try {
    const supplierId = Number(req.query.supplier_id);
    const page = Number(req.query.page ?? 1);
    const limit = Number(req.query.limit ?? 25);
    if (!Number.isSafeInteger(supplierId) || supplierId <= 0 || !Number.isSafeInteger(page) || page < 1 || !Number.isSafeInteger(limit) || limit < 1 || limit > 100) throw new BusinessRuleError(400, 'Invalid supplier advance query');
    const total = model.count(supplierId);
    res.json({ success: true, data: model.list(supplierId, page, limit), pagination: {
      currentPage: page, totalPages: Math.max(1, Math.ceil(total / limit)), totalItems: total,
      hasNext: page * limit < total, hasPrev: page > 1,
    } });
  } catch (error: unknown) { handleBusinessError(res, error, 'List supplier advances', 'Failed to list supplier advances'); }
}

export function getSupplierPrepayment(req: AuthRequest, res: Response): void {
  try { res.json({ success: true, data: model.get(Number(req.params.id)) }); }
  catch (error: unknown) { handleBusinessError(res, error, 'Get supplier advance', 'Failed to load supplier advance'); }
}

export function getSupplierPrepaymentTargets(req: AuthRequest, res: Response): void {
  try {
    const search = req.query.search === undefined ? '' : req.query.search;
    if (typeof search !== 'string' || search.length > 150) throw new BusinessRuleError(400, 'Invalid document search');
    res.json({ success: true, data: model.targets(Number(req.params.id), search) });
  } catch (error: unknown) { handleBusinessError(res, error, 'Find supplier documents', 'Failed to load supplier documents'); }
}

export function createSupplierPrepayment(req: AuthRequest, res: Response): void {
  try {
    const source = model.create(req.body, req.user!.id, req.headers);
    logCRUD(ActionType.SUPPLIER_ADVANCE_CREATE, 'SupplierAdvance', source.id, 'Supplier advance recorded', req.user!.id);
    req.activityLogged = true;
    res.status(201).json({ success: true, data: source });
  } catch (error: unknown) { handleBusinessError(res, error, 'Create supplier advance', 'Failed to record supplier advance'); }
}

export function applySupplierPrepayment(req: AuthRequest, res: Response): void {
  try {
    const payment = model.apply(Number(req.params.id), req.body, req.user!.id, req.headers);
    logCRUD(ActionType.SUPPLIER_ADVANCE_APPLY, 'SupplierAdvance', Number(req.params.id), 'Supplier advance applied', req.user!.id);
    req.activityLogged = true;
    res.status(201).json({ success: true, data: payment });
  } catch (error: unknown) { handleBusinessError(res, error, 'Apply supplier advance', 'Failed to apply supplier advance'); }
}

export function voidSupplierPrepayment(req: AuthRequest, res: Response): void {
  try {
    const source = model.void(Number(req.params.id), req.user!.id, req.body.reason);
    logCRUD(ActionType.SUPPLIER_ADVANCE_VOID, 'SupplierAdvance', source.id, 'Supplier advance voided', req.user!.id);
    req.activityLogged = true;
    res.json({ success: true, data: source });
  } catch (error: unknown) { handleBusinessError(res, error, 'Void supplier advance', 'Failed to void supplier advance'); }
}
