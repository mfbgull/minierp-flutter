import { Request, Response } from 'express';
import { getQueryInteger } from '../utils/queryUtils';
import { AuthRequest } from '../types';
import SupplierRefundModel, { creditNoteRefundable } from '../models/SupplierRefund';
import db from '../config/database';
import logger from '../utils/logger';
import { isValidPaymentMethod } from '../services/cashService';
import {
  IDEMPOTENCY_SCOPES,
  claimIdempotencyKey,
  hashRequestPayload,
  startIdempotentRequest,
} from '../utils/idempotency';

function getSupplierRefunds(req: Request, res: Response): void {
  try {
    const page = getQueryInteger(req.query.page, 1);
    const limit = getQueryInteger(req.query.limit, 10);
    const supplierId = Number(req.query.supplier_id) || undefined;

    const { rows, total, pageNum, limitNum } = SupplierRefundModel.getAll(
      { supplier_id: supplierId, page, limit },
      db
    );

    res.json({
      success: true,
      data: rows,
      pagination: {
        currentPage: pageNum,
        totalPages: Math.ceil(total / limitNum),
        totalItems: total,
        hasNext: pageNum < Math.ceil(total / limitNum),
        hasPrev: pageNum > 1,
      },
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

/** Refundable balance of a credit note — for the payout dialog. */
function getCreditNoteRefundable(req: Request, res: Response): void {
  try {
    const creditNoteId = Number(req.params.id);
    res.json({ credit_note_id: creditNoteId, refundable: creditNoteRefundable(creditNoteId, db) });
  } catch (error) {
    logger.error('Get refundable balance error:', error);
    res.status(500).json({ error: 'Failed to get refundable balance' });
  }
}

function createSupplierRefund(req: AuthRequest, res: Response): Response | void {
  try {
    const body = req.body as {
      refund_date?: string;
      credit_note_id?: number;
      amount?: number;
      payment_method?: string;
      reference_no?: string;
    };

    if (!body.refund_date) return res.status(400).json({ error: 'refund_date is required' });
    if (!body.credit_note_id || body.credit_note_id <= 0) {
      return res.status(400).json({ error: 'A valid credit_note_id is required' });
    }
    // Validate amount here rather than letting Number(undefined) become NaN
    // and surface as a 500 from the model layer.
    const amount = Number(body.amount);
    if (!Number.isFinite(amount) || amount <= 0) {
      return res.status(400).json({ error: 'A positive amount is required' });
    }
    if (body.payment_method !== undefined && !isValidPaymentMethod(body.payment_method)) {
      return res.status(400).json({
        error: `Invalid payment_method "${body.payment_method}" — use Cash, Bank, Easypaisa, JazzCash or Upaisa`,
      });
    }

    // Bind the validated values: the guards above narrow `body.*`, but that
    // narrowing does not carry into the transaction callback below.
    const refundDate = body.refund_date;
    const creditNoteId = body.credit_note_id;

    // audit-3 task 08: a supplier refund is cash OUT and reduces AP, so a
    // retry after a lost response must replay rather than refund twice.
    const hash = hashRequestPayload(req.body);
    const start = startIdempotentRequest(db, req.headers, IDEMPOTENCY_SCOPES.SUPPLIER_REFUND_CREATE, hash);
    if (start.kind === 'error') {
      return res.status(start.status).json({ error: start.message });
    }
    if (start.kind === 'replay') {
      res.set('X-Idempotent-Replay', 'true');
      return res.status(201).json({ success: true, idempotentReplay: true, data: { id: start.resourceId } });
    }

    const created = db.transaction(() => {
      const row = SupplierRefundModel.create(
        {
          refund_date: refundDate,
          credit_note_id: creditNoteId,
          amount,
          payment_method: body.payment_method,
          reference_no: body.reference_no,
        },
        req.user!.id,
        db
      );
      if (start.key) {
        claimIdempotencyKey(db, IDEMPOTENCY_SCOPES.SUPPLIER_REFUND_CREATE, start.key, hash, row.id);
      }
      return row;
    })();

    res.status(201).json({
      success: true,
      message: `Supplier refund ${created.refund_no} issued successfully`,
      data: created,
    });
  } catch (error: unknown) {
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
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
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
