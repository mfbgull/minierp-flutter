import type { Response } from 'express';
import type { AuthRequest } from '../types';
import db from '../config/database';
import { SupplierBillModel } from '../models/SupplierBill';
import { BusinessRuleError, handleBusinessError } from '../utils/businessRuleError';
import { ActionType, logCRUD } from '../services/activityLogger';

const model = new SupplierBillModel(db);

export function listSupplierBills(req: AuthRequest, res: Response): void {
  try {
    const supplierId = Number(req.query.supplier_id);
    if (!Number.isSafeInteger(supplierId) || supplierId <= 0) throw new BusinessRuleError(400, 'Valid supplier_id is required');
    const page = Number(req.query.page ?? 1);
    const limit = Number(req.query.limit ?? 25);
    if (!Number.isSafeInteger(page) || page < 1 || !Number.isSafeInteger(limit) || limit < 1 || limit > 100) throw new BusinessRuleError(400, 'Invalid bill pagination');
    const total = model.count(supplierId);
    res.json({ success: true, data: model.list(supplierId, page, limit), pagination: {
      currentPage: page, totalPages: Math.max(1, Math.ceil(total / limit)), totalItems: total,
      hasNext: page * limit < total, hasPrev: page > 1,
    } });
  }
  catch (error: unknown) { handleBusinessError(res, error, 'List supplier bills', 'Failed to list supplier bills'); }
}

export function getSupplierBill(req: AuthRequest, res: Response): void {
  try { res.json({ success: true, data: model.get(Number(req.params.id)) }); }
  catch (error: unknown) { handleBusinessError(res, error, 'Get supplier bill', 'Failed to load supplier bill'); }
}

export function createSupplierBill(req: AuthRequest, res: Response): void {
  try {
    const bill = model.create(req.body, req.user!.id, req.headers);
    logCRUD(ActionType.SUPPLIER_BILL_CREATE, 'SupplierBill', bill.id, `Recorded supplier bill ${bill.bill_no}`, req.user!.id);
    req.activityLogged = true;
    res.status(201).json({ success: true, data: bill });
  } catch (error: unknown) { handleBusinessError(res, error, 'Create supplier bill', 'Failed to record supplier bill'); }
}

export function paySupplierBill(req: AuthRequest, res: Response): void {
  try {
    const payment = model.pay(Number(req.params.id), req.body, req.user!.id, req.headers);
    logCRUD(ActionType.PAYMENT_CREATE, 'SupplierBill', Number(req.params.id), 'Supplier bill payment recorded', req.user!.id);
    req.activityLogged = true;
    res.status(201).json({ success: true, data: payment });
  } catch (error: unknown) { handleBusinessError(res, error, 'Pay supplier bill', 'Failed to pay supplier bill'); }
}

export function voidSupplierBill(req: AuthRequest, res: Response): void {
  try {
    const bill = model.void(Number(req.params.id), req.user!.id, req.body.reason);
    logCRUD(ActionType.SUPPLIER_BILL_VOID, 'SupplierBill', bill.id, 'Supplier bill voided', req.user!.id);
    req.activityLogged = true;
    res.json({ success: true, data: bill });
  } catch (error: unknown) { handleBusinessError(res, error, 'Void supplier bill', 'Failed to void supplier bill'); }
}
