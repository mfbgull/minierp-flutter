/**
 * Return settlement endpoints (spec §5.2 / §5.3). The endpoints are thin:
 * all money logic lives in InvoiceReturnService so desktop and mobile
 * cannot diverge (D17).
 */
import { Response } from 'express';
import { AuthRequest } from '../types';
import { InvoiceReturnService, ReturnError, type SettlementInput } from '../services/invoiceReturnService';
import { handleBusinessError } from '../utils/businessRuleError';

function settleReturn(req: AuthRequest, res: Response): Response | void {
  try {
    const returnId = parseInt(req.params.id as string, 10);
    const allocations = (req.body?.allocations as SettlementInput[] | undefined) ?? [];
    if (!Array.isArray(allocations) || allocations.length === 0) {
      return res.status(400).json({ error: 'Invalid request: allocations must be a non-empty array' });
    }
    const result = InvoiceReturnService.settleReturn(returnId, allocations, req.user!.id);
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
