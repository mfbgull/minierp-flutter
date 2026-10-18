import type { Response } from 'express';
import { z } from 'zod';
import type { AuthRequest } from '../types';
import db from '../config/database';
import PaymentModel from '../models/Payment';
import { getReceiptReplay, saveReceiptReplay, getCashSummary, getCashActivity } from '../models/UnappliedCash';
import { UnappliedCashService } from '../services/unappliedCashService';
import { UnappliedCashError } from '../services/unappliedCashTypes';
import { receiveCashBody, applyCashBody, refundCashBody, reverseCashBody, cashIdParams, cashSummaryQuery, cashActivityQuery } from '../middleware/unappliedCashValidation';
import { normalizeIdempotencyKey, IDEMPOTENCY_KEY_HEADER, hashRequestPayload, beginIdempotentWrite, claimIdempotencyKey, IdempotencyConflictError } from '../utils/idempotency';
import { sendSuccess, sendInternalError } from '../utils/apiResponse';
import logger from '../utils/logger';

const service = new UnappliedCashService(db);

export function getUnappliedCashCapabilities(_req: AuthRequest, res: Response): void {
  res.setHeader('Cache-Control', 'no-store');
  sendSuccess(res, { receive: 'durable-v1', apply: 'permanent-application-v1', refund: 'permanent-application-v1', reverse: 'guarded-status-v1' });
}

export function getUnappliedCash(req: AuthRequest, res: Response): void {
  try {
    const customerId = Number(cashIdParams.parse(req.params).id);
    const query = cashSummaryQuery.parse(req.query);
    const now = new Date();
    const date = query.operation_date ?? `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
    res.json(getCashSummary(db, customerId, date, query.page, query.limit));
  } catch (error) { respondToError(res, error); }
}

export function getUnappliedCashActivity(req: AuthRequest, res: Response): void {
  try {
    const customerId = Number(cashIdParams.parse(req.params).id);
    const query = cashActivityQuery.parse(req.query);
    res.json(getCashActivity(db, customerId, query.page, query.limit, query.fromDate, query.toDate));
  } catch (error) { respondToError(res, error); }
}

function requiredKey(req: AuthRequest): string {
  let key: string | null;
  try { key = normalizeIdempotencyKey(req.headers[IDEMPOTENCY_KEY_HEADER]); }
  catch { throw new UnappliedCashError('INVALID_IDEMPOTENCY_KEY', 'Idempotency-Key must be 8..200 characters', 400); }
  if (!key) throw new UnappliedCashError('IDEMPOTENCY_KEY_REQUIRED', 'Idempotency-Key is required', 400);
  return key;
}

function respondToError(res: Response, error: unknown): void {
  if (error instanceof UnappliedCashError) {
    res.status(error.status).json({ success: false, error: {
      code: error.code, message: error.message,
      ...(error.blockedBy.length ? { blockedBy: error.blockedBy } : {}),
    } });
    return;
  }
  if (error instanceof IdempotencyConflictError) {
    res.status(409).json({ success: false, error: { code: 'IDEMPOTENCY_CONFLICT', message: 'Idempotency-Key was used for a different request' } });
    return;
  }
  if (error instanceof z.ZodError) {
    res.status(400).json({ success: false, error: { code: 'VALIDATION_ERROR', message: 'Validation failed' } });
    return;
  }
  logger.error('Unapplied cash operation failed', { errorName: error instanceof Error ? error.name : 'UnknownError' });
  sendInternalError(res);
}

export function receiveUnappliedCash(req: AuthRequest, res: Response): void {
  try {
    const customerId = Number(cashIdParams.parse(req.params).id);
    const body = receiveCashBody.parse(req.body);
    const receiptKey = requiredKey(req);
    const key = `${customerId}:${receiptKey}`;
    const hash = hashRequestPayload({ customerId, ...body });
    const result = db.transaction(() => {
      const replay = getReceiptReplay(db, customerId, receiptKey, hash);
      if (replay) return { replayed: true, data: { paymentId: replay.payment_id, applicationId: null, amount: replay.amount } };
      const { replayId } = beginIdempotentWrite(db, 'unapplied_cash.receive', key, hash);
      if (replayId !== null) {
        const receipt = PaymentModel.getById(db, replayId);
        if (!receipt) throw new Error('Idempotent receipt is missing');
        saveReceiptReplay(db, customerId, receiptKey, hash, replayId, receipt.amount);
        return { replayed: true, data: { paymentId: replayId, applicationId: null, amount: receipt.amount } };
      }
      const data = service.receive({ customerId, amount: body.amount, date: body.operation_date, paymentMethod: body.payment_method });
      claimIdempotencyKey(db, 'unapplied_cash.receive', key, hash, data.paymentId);
      saveReceiptReplay(db, customerId, receiptKey, hash, data.paymentId, data.amount);
      return { replayed: false, data };
    }).immediate();
    sendSuccess(res, result.data, result.replayed ? 200 : 201);
  } catch (error) { respondToError(res, error); }
}

export function applyUnappliedCash(req: AuthRequest, res: Response): void {
  try {
    const body = applyCashBody.parse(req.body);
    const data = service.apply({ customerId: body.customer_id, date: body.operation_date, applicationKey: requiredKey(req),
      allocations: body.allocations.map(allocation => ({ invoiceId: allocation.invoice_id, amount: allocation.amount })),
    });
    sendSuccess(res, data);
  } catch (error) { respondToError(res, error); }
}

export function refundUnappliedCash(req: AuthRequest, res: Response): void {
  try {
    const body = refundCashBody.parse(req.body);
    const data = service.refund({ customerId: body.customer_id, amount: body.amount, date: body.operation_date,
      paymentMethod: body.payment_method, applicationKey: requiredKey(req),
    });
    sendSuccess(res, data);
  } catch (error) { respondToError(res, error); }
}

export function reverseUnappliedCash(req: AuthRequest, res: Response): void {
  try {
    const paymentId = Number(cashIdParams.parse(req.params).id);
    const body = reverseCashBody.parse(req.body);
    const key = `${paymentId}:${requiredKey(req)}`;
    const hash = hashRequestPayload({ paymentId, ...body });
    db.transaction(() => {
      const { replayId } = beginIdempotentWrite(db, 'unapplied_cash.reverse', key, hash);
      if (replayId !== null) return;
      service.reverse(paymentId, { voidedBy: req.user?.id ?? null, voidReason: body.reason });
      claimIdempotencyKey(db, 'unapplied_cash.reverse', key, hash, paymentId);
    }).immediate();
    sendSuccess(res, { paymentId, voided: true });
  } catch (error) { respondToError(res, error); }
}
