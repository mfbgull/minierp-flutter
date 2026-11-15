import { listPagination, listPageQuery } from '../utils/controllerPagination';
import { Request, Response } from 'express';
import { getQueryInteger } from '../utils/queryUtils';
import { AuthRequest } from '../types';
import SupplierRefundModel, { creditNoteRefundable } from '../models/SupplierRefund';
import db from '../config/database';
import logger from '../utils/logger';
import { isValidPaymentMethod } from '../services/cashService';
import { SupplierRefundClaimModel, claimRemaining } from '../models/SupplierRefundClaim';
import { BusinessRuleError } from '../utils/businessRuleError';
import { IDEMPOTENCY_SCOPES, claimIdempotencyKey, hashRequestPayload, respondToIdempotencyReplay, startIdempotentRequest, startRequiredIdempotentRequest } from '../utils/idempotency';

function getSupplierRefunds(req: Request, res: Response): void {
  try {
    const { page, limit } = listPageQuery(req.query);
    const supplierId = Number(req.query.supplier_id) || undefined;
    const claimId = Number(req.query.claim_id) || undefined;

    const { rows, total, pageNum, limitNum } = SupplierRefundModel.getAll(
      { supplier_id: supplierId, claim_id: claimId, page, limit },
      db
    );

    res.json({
      success: true,
      data: rows,
      pagination: listPagination(total, pageNum, limitNum),
    });
  } catch (error) {
    logger.error('Get supplier refunds error:', error);
    res.status(500).json({ error: 'Failed to get supplier refunds' });
  }
}

function getSupplierRefund(req: Request, res: Response): void {
  try {
    const refund = SupplierRefundModel.getById(Number(req.params.id), db);
    if (!refund) {
      res.status(404).json({ error: 'Supplier refund not found' });
      return;
    }
    res.json(refund);
  } catch (error) {
    logger.error('Get supplier refund error:', error);
    res.status(500).json({ error: 'Failed to get supplier refund' });
  }
}

/** Refundable balance of a credit note — for the payout dialog. When the
 * note carries a live refund claim (PRET-002), its remaining balance is
 * included: the receipt must fit both caps. */
function getCreditNoteRefundable(req: Request, res: Response): void {
  try {
    const creditNoteId = Number(req.params.id);
    const refundable = creditNoteRefundable(creditNoteId, db);
    const claim = SupplierRefundClaimModel.getByCreditNoteId(creditNoteId, db);
    res.json({
      credit_note_id: creditNoteId,
      refundable,
      claim: claim ? {
        id: claim.id,
        claim_no: claim.claim_no,
        status: claim.status,
        amount: claim.amount,
        received_amount: claim.received_amount,
        remaining: claimRemaining(claim),
      } : null,
    });
  } catch (error) {
    logger.error('Get refundable balance error:', error);
    res.status(500).json({ error: 'Failed to get refundable balance' });
  }
}

/** Controller-level request guards for create; returns the first error message. */
function refundRequestError(body: {
  refund_date?: string; credit_note_id?: number; claim_id?: number;
  amount?: number; payment_method?: string;
}): string | undefined {
  if (!body.refund_date) return 'refund_date is required';
  const amount = Number(body.amount);
  if (!Number.isFinite(amount) || amount <= 0) return 'A positive amount is required';
  if (!body.credit_note_id && !body.claim_id) return 'A credit_note_id or claim_id is required';
  if (body.payment_method !== undefined && !isValidPaymentMethod(body.payment_method)) {
    return `Invalid payment_method "${body.payment_method}" — use Cash or Bank transfer`;
  }
  return undefined;
}

function createSupplierRefund(req: AuthRequest, res: Response): Response | void {
  try {
    const body = req.body as {
      refund_date?: string;
      credit_note_id?: number;
      claim_id?: number;
      amount?: number;
      payment_method?: string;
      reference_no?: string;
      treat_excess_as_advance?: boolean;
    };

    const validationError = refundRequestError(body);
    if (validationError) return res.status(400).json({ error: validationError });

    // Bind the validated values: the guards above narrow `body.*`, but that
    // narrowing does not carry into the transaction callback below.
    const refundDate = body.refund_date as string;
    const creditNoteId = body.credit_note_id ? Number(body.credit_note_id) : undefined;
    const claimId = body.claim_id ? Number(body.claim_id) : undefined;
    const amount = Number(body.amount);

    // ACCT-013 + PRET-002: a refund receipt is cash IN — a retry after a
    // lost response must replay rather than post twice. The key is now
    // mandatory (new-surface ACCT-008 contract).
    const hash = hashRequestPayload(req.body);
    const start = startRequiredIdempotentRequest(db, req.headers, IDEMPOTENCY_SCOPES.SUPPLIER_REFUND_CREATE, hash);
    if (respondToIdempotencyReplay(res, start, {
      status: 201,
      buildBody: (resourceId) => ({ success: true, idempotentReplay: true, data: { id: resourceId } }),
    })) return;

    const created = db.transaction(() => {
      const row = SupplierRefundModel.create(
        {
          refund_date: refundDate,
          credit_note_id: creditNoteId,
          claim_id: claimId,
          amount,
          payment_method: body.payment_method,
          reference_no: body.reference_no,
          treat_excess_as_advance: body.treat_excess_as_advance === true,
        },
        req.user!.id,
        db
      );
      if (start.kind === 'proceed' && start.key) {
        claimIdempotencyKey(db, IDEMPOTENCY_SCOPES.SUPPLIER_REFUND_CREATE, start.key, hash, row.id);
      }
      return row;
    })();

    res.status(201).json({
      success: true,
      message: created.excess > 0
        ? `Refund receipt ${created.refund_no} recorded; excess ${created.excess.toFixed(2)} held as supplier credit on account`
        : `Supplier refund ${created.refund_no} issued successfully`,
      data: created,
    });
  } catch (error: unknown) {
    if (error instanceof BusinessRuleError) {
      res.status(error.status).json(error.details !== undefined
        ? { error: error.message, details: error.details }
        : { error: error.message });
      return;
    }
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    logger.error('Create supplier refund error:', { error: errorMessage });
    res.status(400).json({ error: errorMessage });
  }
}

function voidSupplierRefund(req: AuthRequest, res: Response): Response | void {
  try {
    const id = Number(req.params.id);
    const reason = typeof req.body?.reason === 'string' ? req.body.reason : undefined;

    const voided = SupplierRefundModel.void(id, req.user!.id, reason || '', db);

    res.json({
      success: true,
      message: `Supplier refund ${voided.refund_no} voided successfully`,
      data: voided,
    });
  } catch (error: unknown) {
    // ACCT-013: BusinessRuleError carries its own status (409 for cash-timeline
    // and closed-period refusals) plus structured blockers when present.
    if (error instanceof BusinessRuleError) {
      res.status(error.status).json(error.details !== undefined
        ? { error: error.message, details: error.details }
        : { error: error.message });
      return;
    }
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    if (errorMessage.includes('inside closed accounting period')) {
      res.status(409).json({ error: errorMessage });
      return;
    }
    logger.error('Void supplier refund error:', { error: errorMessage });
    res.status(400).json({ error: errorMessage });
  }
}

export default {
  getSupplierRefunds,
  getSupplierRefund,
  getCreditNoteRefundable,
  createSupplierRefund,
  voidSupplierRefund,
};
