import { Request, Response } from 'express';
import db from '../config/database';
import logger from '../utils/logger';
import { AuthRequest } from '../types';
import { SupplierRefundClaimModel, CLAIM_WRITE_OFF_APPROVAL_THRESHOLD } from '../models/SupplierRefundClaim';
import { BusinessRuleError } from '../utils/businessRuleError';
import {
  IDEMPOTENCY_SCOPES,
  claimIdempotencyKey,
  hashRequestPayload,
  respondToIdempotencyReplay,
  startRequiredIdempotentRequest,
} from '../utils/idempotency';

/**
 * Supplier refund claims (PRET-002) — the expected → received lifecycle
 * for money a supplier owes back. Claims post no GL; receipts (supplier
 * refunds) carry the cash movement. Write-offs settle short-paid claims
 * with Dr 7300 / Cr AP and an owner (admin) sign-off above Rs 1,000.
 */

function fail(res: Response, error: unknown): Response {
  if (error instanceof BusinessRuleError) {
    return res.status(error.status).json(error.details !== undefined
      ? { error: error.message, details: error.details }
      : { error: error.message });
  }
  const message = error instanceof Error ? error.message : 'Unknown error';
  logger.error('Supplier refund claim error:', { error: message });
  return res.status(400).json({ error: message });
}

export function getRefundClaims(req: AuthRequest, res: Response): Response {
  try {
    const supplierId = Number(req.query.supplier_id) || undefined;
    const status = typeof req.query.status === 'string' ? req.query.status : undefined;
    const page = Number(req.query.page) || 1;
    const limit = Math.min(Number(req.query.limit) || 50, 200);
    const result = SupplierRefundClaimModel.list({ supplier_id: supplierId, status, page, limit }, db);
    return res.json({ success: true, data: result.rows, pagination: {
      page: result.pageNum, limit: result.limitNum, total: result.total,
    }});
  } catch (error: unknown) {
    return fail(res, error);
  }
}

export function getRefundsDue(_req: AuthRequest, res: Response): Response {
  try {
    const result = SupplierRefundClaimModel.refundsDue(db);
    // Refunds due is a receivable memo, NOT a cash figure — cash and bank
    // move only when a refund receipt posts (REFUND_RECEIPT).
    return res.json({ success: true, data: result.rows, total_due: result.total_due });
  } catch (error: unknown) {
    return fail(res, error);
  }
}

export function getRefundClaim(req: AuthRequest, res: Response): Response {
  try {
    const claim = SupplierRefundClaimModel.getById(Number(req.params.id), db);
    if (!claim) return res.status(404).json({ error: 'Refund claim not found' });
    return res.json({ success: true, data: claim });
  } catch (error: unknown) {
    return fail(res, error);
  }
}

export function createRefundClaim(req: AuthRequest, res: Response): Response | void {
  try {
    const body = req.body as {
      supplier_id?: number;
      claim_date?: string;
      amount?: number | string;
      reason?: string;
    };
    if (!body.supplier_id || body.supplier_id <= 0) {
      return res.status(400).json({ error: 'A valid supplier_id is required' });
    }
    if (!body.claim_date) return res.status(400).json({ error: 'claim_date is required' });
    const amount = Number(body.amount);
    if (!Number.isFinite(amount) || amount <= 0) {
      return res.status(400).json({ error: 'A positive amount is required' });
    }

    const hash = hashRequestPayload(req.body);
    const start = startRequiredIdempotentRequest(db, req.headers, IDEMPOTENCY_SCOPES.SUPPLIER_REFUND_CLAIM_CREATE, hash);
    if (respondToIdempotencyReplay(res, start, {
      status: 201,
      buildBody: (resourceId) => ({ success: true, idempotentReplay: true, data: { id: resourceId } }),
    })) return;

    const created = db.transaction(() => {
      const row = SupplierRefundClaimModel.create({
        supplier_id: body.supplier_id!,
        claim_date: body.claim_date!,
        amount,
        reason: body.reason,
      }, req.user!.id, db);
      if (start.kind === 'proceed' && start.key) {
        claimIdempotencyKey(db, IDEMPOTENCY_SCOPES.SUPPLIER_REFUND_CLAIM_CREATE, start.key, hash, row.id);
      }
      return row;
    })();

    return res.status(201).json({
      success: true,
      message: `Refund claim ${created.claim_no} recorded`,
      data: created,
    });
  } catch (error: unknown) {
    return fail(res, error);
  }
}

export function cancelRefundClaim(req: AuthRequest, res: Response): Response {
  try {
    const id = Number(req.params.id);
    const reason = typeof req.body?.reason === 'string' ? req.body.reason : undefined;
    const cancelled = SupplierRefundClaimModel.cancel(id, req.user!.id, reason || '', db);
    return res.json({
      success: true,
      message: `Refund claim ${cancelled.claim_no} cancelled`,
      data: cancelled,
    });
  } catch (error: unknown) {
    return fail(res, error);
  }
}

export function writeOffRefundClaim(req: AuthRequest, res: Response): Response | void {
  try {
    const id = Number(req.params.id);
    const body = req.body as {
      amount?: number | string;
      reason?: string;
      write_off_date?: string;
    };
    if (!body.reason || !String(body.reason).trim()) {
      return res.status(400).json({ error: 'A write-off reason is required' });
    }

    // Rs 1,000 rule (D19 PRET-002): short-pay write-offs above the
    // threshold need owner/manager sign-off — the admin role in this
    // deployment. At or below it, any user with supplier-refund write
    // permission (enforced by the route) may write the claim off.
    const claim = SupplierRefundClaimModel.getById(id, db);
    if (!claim) return res.status(404).json({ error: 'Refund claim not found' });
    const amount = body.amount === undefined ? undefined : Number(body.amount);
    const effective = amount ?? (claim.amount - claim.received_amount - claim.written_off_amount);
    if (effective > CLAIM_WRITE_OFF_APPROVAL_THRESHOLD + 0.005 && req.user!.role !== 'admin') {
      return res.status(403).json({
        error: `Write-offs above Rs ${CLAIM_WRITE_OFF_APPROVAL_THRESHOLD} require owner (admin) approval`,
      });
    }

    const hash = hashRequestPayload(req.body);
    const start = startRequiredIdempotentRequest(db, req.headers, IDEMPOTENCY_SCOPES.SUPPLIER_REFUND_CLAIM_WRITE_OFF, hash);
    if (respondToIdempotencyReplay(res, start, {
      status: 200,
      buildBody: (resourceId) => ({ success: true, idempotentReplay: true, data: { id: resourceId } }),
    })) return;

    const writtenOff = db.transaction(() => {
      const row = SupplierRefundClaimModel.writeOff(id, req.user!.id, {
        amount,
        reason: String(body.reason),
        write_off_date: body.write_off_date,
      }, db);
      if (start.kind === 'proceed' && start.key) {
        claimIdempotencyKey(db, IDEMPOTENCY_SCOPES.SUPPLIER_REFUND_CLAIM_WRITE_OFF, start.key, hash, row.id);
      }
      return row;
    })();

    return res.json({
      success: true,
      message: `Wrote off refund claim ${writtenOff.claim_no}`,
      data: writtenOff,
    });
  } catch (error: unknown) {
    return fail(res, error);
  }
}
