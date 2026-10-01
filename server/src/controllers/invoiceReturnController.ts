/**
 * Return settlement endpoints (spec §5.2 / §5.3). The endpoints are thin:
 * all money logic lives in InvoiceReturnService so desktop and mobile
 * cannot diverge (D17).
 */
import { Response } from 'express';
import { AuthRequest } from '../types';
import { InvoiceReturnService, ReturnError, type SettlementInput } from '../services/invoiceReturnService';
import { handleBusinessError } from '../utils/businessRuleError';
import db from '../config/database';
import {
  IDEMPOTENCY_SCOPES,
  claimIdempotencyKey,
  hashRequestPayload,
  startIdempotentRequest,
} from '../utils/idempotency';

function settleReturn(req: AuthRequest, res: Response): Response | void {
  try {
    const returnId = parseInt(req.params.id as string, 10);
    const allocations = (req.body?.allocations as SettlementInput[] | undefined) ?? [];
    if (!Array.isArray(allocations) || allocations.length === 0) {
      return res.status(400).json({ error: 'Invalid request: allocations must be a non-empty array' });
    }
    // audit-3 task 08: settling issues the refund or credit, so a retry must
    // replay rather than pay the customer twice. The claim is keyed on the
    // return being settled, which is the operation's resource identity.
    const hash = hashRequestPayload(req.body);
    const start = startIdempotentRequest(db, req.headers, IDEMPOTENCY_SCOPES.INVOICE_RETURN_SETTLE, hash);
    if (start.kind === 'error') {
      return res.status(start.status).json({ error: start.message });
    }
    if (start.kind === 'replay') {
      res.set('X-Idempotent-Replay', 'true');
      return res.json({ success: true, message: 'Return settled successfully', idempotentReplay: true, data: { returnId: start.resourceId } });
    }

    const result = InvoiceReturnService.settleReturn(returnId, allocations, req.user!.id);
    if (start.key) {
      claimIdempotencyKey(db, IDEMPOTENCY_SCOPES.INVOICE_RETURN_SETTLE, start.key, hash, returnId);
    }
    return res.json({ success: true, message: 'Return settled successfully', data: result });
  } catch (error: unknown) {
    if (error instanceof ReturnError) {
      return res.status(error.status).json({ error: error.message });
    }
    handleBusinessError(res, error, 'Settle return', 'Failed to settle the return');
    return;
  }
}

function voidReturn(req: AuthRequest, res: Response): Response | void {
  try {
    const returnId = parseInt(req.params.id as string, 10);
    const reason = req.body?.reason ? String(req.body.reason) : null;
    InvoiceReturnService.voidReturn(returnId, req.user!.id, reason);
    return res.json({ success: true, message: 'Return voided successfully' });
  } catch (error: unknown) {
    if (error instanceof ReturnError) {
      return res.status(error.status).json({ error: error.message });
    }
    const errorMessage = error instanceof Error ? error.message : String(error);
    if (errorMessage.includes('inside closed accounting period')) {
      return res.status(409).json({ error: errorMessage });
    }
    handleBusinessError(res, error, 'Void return', 'Failed to void the return');
    return;
  }
}

function voidSettlement(req: AuthRequest, res: Response): Response | void {
  try {
    const settlementId = parseInt(req.params.id as string, 10);
    const reason = req.body?.reason ? String(req.body.reason) : null;
    InvoiceReturnService.voidSettlement(settlementId, req.user!.id, reason);
    return res.json({ success: true, message: 'Settlement voided successfully' });
  } catch (error: unknown) {
    if (error instanceof ReturnError) {
      return res.status(error.status).json({ error: error.message });
    }
    const errorMessage = error instanceof Error ? error.message : String(error);
    if (errorMessage.includes('inside closed accounting period')) {
      return res.status(409).json({ error: errorMessage });
    }
    handleBusinessError(res, error, 'Void settlement', 'Failed to void the settlement');
    return;
  }
}

export default { settleReturn, voidReturn, voidSettlement };
