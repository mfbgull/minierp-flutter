import { respondToClosedPeriod } from '../utils/controllerErrors';
import { listPagination, listPageQuery, listRequestQuery } from '../utils/controllerPagination';
import { Response } from 'express';
import type Database from 'better-sqlite3';
import db from '../config/database';
import { AuthRequest, CreateInvoiceDTO, Invoice, InvoiceItemDTO, PaymentDTO, InvoiceStatus, SellableStockUnavailableError } from '../types';
import StockMovementModel from '../models/StockMovement';
import { StockReservationModel, type StockReservation } from '../models/StockReservation';
import InvoiceModel from '../models/Invoice';
import { InvoiceCancellationGuardError, type InvoiceLineRow } from '../models/Invoice';
import PaymentModel from '../models/Payment';
import AccountingService from '../services/accountingService';
import { InvoiceReturnService, ReturnError } from '../services/invoiceReturnService';
import { invoiceReturnOptions } from '../utils/controllerInvoiceReturn';
import ledgerUtils from '../utils/ledgerUtils';
import logger from '../utils/logger';
import { log, logCRUD, ActionType, newCorrelationId } from '../services/activityLogger';
import { getQueryInteger, getQueryParam } from '../utils/queryUtils';
import {
  addCurrency,
  parseCurrency,
  subtractCurrency,
  computeInvoiceGrandTotal,
} from '../utils/currency';
import { isValidPaymentMethod } from '../services/cashService';
import { roundQty } from '../utils/quantity';
import { BusinessRuleError } from '../utils/businessRuleError';
import { handleBusinessError } from '../utils/businessRuleError';
import { assertLegacyInvoiceAllocationsAllowed } from '../services/unappliedPaymentGuard';
import { assertNoPartyAdjustment } from '../utils/partyAdjustmentBalances';
import {
  InvoiceCreationCreditError,
  InvoiceCreationIdempotencyError,
  InvoiceCreationOffsetError,
  InvoiceCreationPaymentMethodError,
  InvoiceCreationService,
  InvoiceCreationTotalMismatchError,
} from '../services/InvoiceCreationService';
import { IDEMPOTENCY_KEY_HEADER, IDEMPOTENCY_SCOPES, INVOICE_CREATE_SCOPE, claimIdempotencyKey, hashRequestPayload, normalizeIdempotencyKey, observeInvoiceIdempotency, respondToIdempotencyReplay, startRequiredIdempotentRequest } from '../utils/idempotency';

/**
 * ACC-18 interim: thrown when a client-supplied invoice total disagrees
 * with the server-computed sum of line items beyond the 0.01 tolerance.
 */
class TotalMismatchError extends Error {
  constructor(clientTotal: number, computedTotal: number) {
    super(`total_amount disagrees with line items (client ${clientTotal.toFixed(2)} vs computed ${computedTotal.toFixed(2)})`);
    this.name = 'TotalMismatchError';
  }
}

/**
 * Inline payment carried a payment_method outside the accepted
 * whitelist — a client error (400), not a server fault.
 */
class InvalidPaymentMethodError extends Error {
  constructor(method?: string | null) {
    super(`Invalid payment_method "${method ?? ''}" — use Cash, Bank, Easypaisa, JazzCash or Upaisa`);
    this.name = 'InvalidPaymentMethodError';
  }
}

/**
 * An edit tried to change an invoice's applied store credit. Changing it
 * means reversing part of an existing GL offset entry, which this path
 * does not do; the client re-sending the unchanged value is a no-op and
 * is accepted so ordinary edits of a credited invoice keep working.
 */
class CreditOffsetChangeNotSupportedError extends Error {
  constructor(applied: number, requested: number) {
    super(
      `Applied credit is ${applied.toFixed(2)} and cannot be changed to ` +
      `${requested.toFixed(2)} by editing the invoice. Settle or refund ` +
      `the difference through the payment or return flow instead.`
    );
    this.name = 'CreditOffsetChangeNotSupportedError';
  }
}

const {
  calculateInvoiceBalance,
  updateInvoiceStatus,
} = ledgerUtils;

// ============ DB Row Types ============

interface InvoiceRow {
  id: number;
  invoice_no: string;
  customer_id: number;
  invoice_date: string;
  due_date: string;
  status: string;
  total_amount: number;
  paid_amount: number;
  balance_amount: number;
  credit_offset?: number;
  discount_scope?: string;
  discount_type?: string;
  discount_value?: number;
  notes?: string;
  terms?: string;
  created_by?: number;
  created_at?: string;
  updated_at?: string;
  customer_name?: string;
  customer_email?: string;
  customer_phone?: string;
  customer_address?: string;
  items?: InvoiceLineRow[];
}

// ============ Controllers ============

/**
 * GET /api/invoices
 * Retrieve all invoices with optional filters.
 */
function getInvoices(req: AuthRequest, res: Response): void {
  try {
    const customerIdParam = getQueryParam(req.query.customer_id) ?? getQueryParam(req.query.customerId);
    const statusParam = getQueryParam(req.query.status);
    const startDate = getQueryParam(req.query.start_date);
    const endDate = getQueryParam(req.query.end_date);

    const filters: Parameters<typeof InvoiceModel.getAll>[0] = {
      statuses: statusParam
        ? statusParam.split(',').map((s) => s.trim())
        : undefined,
      customer_id: customerIdParam ? parseInt(customerIdParam, 10) : undefined,
      start_date: startDate || undefined,
      end_date: endDate || undefined,
      ...listRequestQuery(req.query)
    };

    const { rows, total, pageNum, limitNum } = InvoiceModel.getAll(filters, db);

    // Flat envelope matching the customers/suppliers shape the client's
    // `getPaged` helper expects: `data` is the item list and `pagination`
    // is a sibling of `data` (NOT nested inside it).
    res.json({
      success: true,
      data: rows,
      pagination: listPagination(total, pageNum, limitNum)
    });
  } catch (error: unknown) {
    logger.error('Get invoices error:', { error });
    res.status(500).json({ error: 'Failed to fetch invoices' });
  }
}

function getInvoice(req: AuthRequest, res: Response): Response | void {
  try {
    const id = parseInt(Array.isArray(req.params.id) ? req.params.id[0] : req.params.id, 10);
    const invoice = InvoiceModel.getWithCustomer(id, db) as InvoiceRow | undefined;
    if (!invoice) { return res.status(404).json({ error: 'Invoice not found' }); }
    invoice.items = InvoiceModel.getItems(id, db);

    // The invoice detail screen and the printouts need the full return
    // picture: the returns themselves, the authoritative money position
    // (spec §4.2) and the transaction timeline (spec §6.3).
    const returns = InvoiceReturnService.getReturnDetails(id);
    const position = InvoiceReturnService.getPosition(id);
    const timeline = InvoiceReturnService.getTimeline(id);
    const payments = InvoiceModel.getPayments(id, db);

    res.json({ ...invoice, payments, returns, position, timeline });
  } catch (error: unknown) {
    logger.error('Get invoice error:', { error });
    res.status(500).json({ error: 'Failed to fetch invoice' });
  }
}

/**
 * POST /api/invoices
 * Create a new invoice. Payment recording, ledger entries, stock movements,
 * and customer balance updates all happen inside a single transaction.
 */
function handleCreateInvoiceError(res: Response, error: unknown): Response | void {
  if (error instanceof SellableStockUnavailableError) {
    return res.status(400).json({ error: error.message });
  }
  if (error instanceof InvoiceCreationTotalMismatchError) {
    return res.status(400).json({ error: 'total_amount disagrees with line items' });
  }
  if (error instanceof InvoiceCreationPaymentMethodError) {
    return res.status(400).json({ error: error.message });
  }
  if (error instanceof InvoiceCreationCreditError) {
    return res.status(400).json({ error: error.message });
  }
  if (error instanceof InvoiceCreationOffsetError) {
    return res.status(400).json({ error: error.message });
  }
  if (error instanceof InvoiceCreationIdempotencyError) {
    return res.status(409).json({ error: error.message });
  }
  return handleBusinessError(res, error, 'Create invoice', 'Failed to create invoice');
}

/**
 * ACCT-006: exception report of invoices sold before their stock's purchase
 * receipt. The population carries backdated_before_receipt = 1; historical
 * as-of stock positions for these sales can read negative by design (D19).
 */
function getBackdatedInvoices(_req: AuthRequest, res: Response): Response {
  const rows = db.prepare(`
    SELECT id, invoice_no, invoice_date, customer_id, customer_name,
           total_amount, balance_amount, status, backdated_before_receipt
    FROM invoices
    WHERE backdated_before_receipt = 1
    ORDER BY invoice_date DESC, id DESC
  `).all();
  return res.json({ success: true, data: rows });
}

function createInvoice(req: AuthRequest, res: Response): Response | void {
  if (!req.user) return res.status(401).json({ error: 'Authentication required' });

  try {
    const body = req.body as CreateInvoiceDTO;
    let idemKey: string | null;
    try {
      idemKey = normalizeIdempotencyKey(req.headers[IDEMPOTENCY_KEY_HEADER]);
    } catch (keyError) {
      return res.status(400).json({ error: (keyError as Error).message });
    }
    observeInvoiceIdempotency('POST /api/invoices', idemKey !== null);
    // ACCT-008 / D19: the key is mandatory on this financial write. A
    // keyless submission is a client bug, not a supported posture.
    if (idemKey === null) {
      return res.status(400).json({ error: 'Idempotency-Key header is required for this operation' });
    }

    const service = new InvoiceCreationService(db);
    const result = service.create({
      source: 'DIRECT',
      userId: req.user.id,
      customerId: Number(body.customer_id),
      invoiceDate: body.invoice_date,
      dueDate: body.due_date,
      status: body.status,
      notes: body.notes,
      terms: body.terms,
      items: body.items,
      discountScope: body.discount_scope,
      discountType: body.discount_type,
      discountValue: body.discount_value,
      totalAmount: body.total_amount === undefined ? undefined : parseCurrency(body.total_amount),
      recordPayment: body.record_payment,
      payment: body.payment,
      creditOffset: body.credit_offset,
      idempotency: idemKey
        ? { scope: INVOICE_CREATE_SCOPE, key: idemKey, hash: hashRequestPayload(req.body) }
        : undefined,
    });

    if (result.replayed) res.set('X-Idempotent-Replay', 'true');
    const createdInvoice = InvoiceModel.getWithCustomer(result.invoiceId, db) as InvoiceRow;
    logCRUD(
      ActionType.INVOICE_CREATE,
      'Invoice',
      createdInvoice.id,
      `Invoice ${createdInvoice.invoice_no} created (${createdInvoice.status})`,
      req.user.id,
      { total_amount: createdInvoice.total_amount, customer_id: createdInvoice.customer_id },
      { newValue: createdInvoice, correlationId: newCorrelationId() },
    );
    // ACCT-006: warnings surface backdated-before-receipt acceptance.
    return res.status(201).json({ ...createdInvoice, warnings: result.warnings });
  } catch (error: unknown) {
    return handleCreateInvoiceError(res, error);
  }
}

/**
 * The Flutter form re-sends the invoice's existing credit_offset on every
 * edit, so an unchanged value must stay acceptable. A changed one cannot be
 * honoured here — it would need a partial reversal of the posted offset entry
 * — and silently ignoring it would leave the user believing credit was applied
 * when it was not.
 */
function assertCreditOffsetUnchanged(
    creditOffset: number | string | undefined,
    appliedCreditOnInvoice: number
): void {
    if (creditOffset === undefined || creditOffset === null) return;
    const requestedCredit = parseCurrency(creditOffset);
    if (Math.abs(requestedCredit - appliedCreditOnInvoice) > 0.005) {
        throw new CreditOffsetChangeNotSupportedError(appliedCreditOnInvoice, requestedCredit);
    }
}

/**
 * Auto-compute the invoice status only when the user did NOT explicitly set
 * one. Draft, Sent, Cancelled, and other manual statuses must be preserved
 * on update.
 */
function resolveUpdatedInvoiceStatus(
    requestedStatus: InvoiceStatus | undefined,
    newBalanceAmount: number,
    totalAmountNum: number,
    returnedAmt: number
): InvoiceStatus {
    const fullyReturned = returnedAmt >= totalAmountNum && totalAmountNum > 0;
    if (requestedStatus && requestedStatus !== 'Unpaid') {
        // User explicitly set a non-default status — respect it.
        return requestedStatus;
    }
    if (fullyReturned) return 'Returned';
    if (newBalanceAmount <= 0 && totalAmountNum > 0) return 'Paid';
    if (newBalanceAmount > 0 && newBalanceAmount < totalAmountNum) return 'Partially Paid';
    return requestedStatus || 'Unpaid';
}

/**
 * PAY-01: drop payments the client removed from this invoice. Every
 * deleted_payments id MUST be joined to THIS invoice via an existing
 * payment_allocations row. Anything else is a crafted cross-invoice
 * deletion → 400, delete nothing.
 */
function applyDeletedInvoicePayments(
    db: Database.Database,
    req: AuthRequest,
    invoiceId: number,
    originalInvoice: { customer_id: number },
    deletedPayments: number[] | undefined,
    userId: number
): void {
    if (!deletedPayments || !Array.isArray(deletedPayments) || deletedPayments.length === 0) return;

    for (const deletedPaymentId of deletedPayments) {
        const allocations = PaymentModel.getAllocationsByPaymentId(db, deletedPaymentId);
        const ownsPayment = allocations.some(alloc => alloc.invoice_id === invoiceId);
        if (!ownsPayment) {
            throw new Error(
                `Payment ${deletedPaymentId} is not allocated to invoice ${invoiceId}; ` +
                `refusing to delete`
            );
        }
    }

    for (const deletedPaymentId of deletedPayments) {
        const paymentInfo = PaymentModel.getById(db, deletedPaymentId);
        if (paymentInfo) {
            InvoiceModel.deleteLedgerEntryByReference(db, paymentInfo.payment_no, originalInvoice.customer_id);

            log({
                userId,
                action: ActionType.PAYMENT_DELETE,
                entityType: 'Payment',
                entityId: deletedPaymentId,
                description: `Payment ${paymentInfo.payment_no} (${Number(paymentInfo.amount).toFixed(2)}) removed from invoice ${invoiceId} during invoice update`,
                metadata: {
                    payment_id: deletedPaymentId,
                    payment_no: paymentInfo.payment_no,
                    amount: Number(paymentInfo.amount),
                    invoice_id: invoiceId,
                    actor: userId,
                },
            });
            req.activityLogged = true;
        }

        const allocations = PaymentModel.getAllocationsByPaymentId(db, deletedPaymentId);

        PaymentModel.delete(db, deletedPaymentId, {
            voidedBy: userId,
            voidReason: `Payment removed from invoice ${invoiceId} during update`,
        });

        // Recalculate balance for each affected invoice using
        // the common helper (which accounts for returned_amount)
        for (const alloc of allocations) {
            calculateInvoiceBalance(alloc.invoice_id);
            updateInvoiceStatus(alloc.invoice_id);
        }
    }
}

/**
 * Replace the invoice's items: insert the new rows, consume FIFO batches for
 * each, and record one stock movement per consumed batch. Returns the COGS
 * total the caller posts to the GL.
 */
function consumeInvoiceItemsAndPostCogs(
    db: Database.Database,
    invoiceId: number,
    items: InvoiceItemDTO[],
    invoiceDate: string,
    resolvedInvoiceNo: string,
    userId: number,
    /** MEDIUM-1: reservation per re-created line, keyed by item+warehouse. */
    reservationFor?: (item: InvoiceItemDTO) => StockReservation | undefined,
): number {
    let updatedCogsTotal = 0;
    for (const item of items) {
        const reservation = reservationFor?.(item);
        // Intentionally bypasses InvoiceCreationService (post-create amendment, not invoice creation).
        const invoiceItemId = InvoiceModel.createInvoiceItem(db, invoiceId, {
            item_id: item.item_id,
            quantity: item.quantity,
            unit_price: item.unit_price,
            tax_rate: item.tax_rate,
            discount_type: item.discount_type,
            discount_value: item.discount_value,
            amount: item.amount,
            // MEDIUM-1: keep the reservation link across the edit, so the line
            // is not orphaned from the reservation that backed the sale.
            reservation_id: reservation?.id,
        });

        // FIX #3: Stock validation with warning
        const warehouseId = InvoiceModel.findWarehouseForItem(
            db,
            item.item_id,
            item.quantity,
            item.warehouse_id
        );

        // MEDIUM-1: a linked reservation drains ITS OWN bins; otherwise FIFO.
        // Draining FIFO while the reserve sits on top asks for stock the
        // reservation already holds, which is the 400 this path produced.
        const consumption = reservation
            ? StockMovementModel.consumeAgainstReservation(reservation, item.quantity, db)
            : InvoiceModel.consumeFromOldestBatches(item.item_id, warehouseId, item.quantity, db);
        // Every re-created line records where it drew, for the same reasons as
        // the create path: an edit's reversal and a later return both replay
        // these rows instead of guessing a bin.
        InvoiceModel.recordLineBinDraw(db, invoiceItemId, consumption);
        if (reservation) {
            StockReservationModel.markConsumedPartial(db, reservation, item.quantity);
        }

        // Create one stock movement per consumed batch with actual COGS
        for (const entry of consumption) {
            const batchLabel = entry.batchId ? `(batch ${entry.batchId})` : '(legacy stock)';
            StockMovementModel.recordMovement(
                {
                    item_id: item.item_id,
                    warehouse_id: warehouseId,
                    movement_type: 'SALE',
                    quantity: -entry.consumed,
                    unit_cost: entry.unitCost,
                    reference_doctype: 'INVOICE',
                    reference_docno: resolvedInvoiceNo,
                    remarks: `Sold via Invoice ${resolvedInvoiceNo} (updated) ${batchLabel}`,
                    movement_date: invoiceDate,
                    batch_id: entry.batchId ?? undefined,
                },
                userId,
                db
            );
            updatedCogsTotal += entry.consumed * entry.unitCost;
        }
    }
    return updatedCogsTotal;
}

function handleUpdateInvoiceError(res: Response, error: unknown): Response | void {
  // Expired/blocked stock is a client-recoverable error, not a 500
  if (error instanceof SellableStockUnavailableError) {
    logger.warn('Update invoice rejected:', { error: error.message });
    res.status(400).json({ error: error.message });
    return;
  }
  const errorMessage = error instanceof Error ? error.message : String(error);
  const errorName = error instanceof Error ? error.name : 'Unknown';
  // PAY-01: crafted cross-invoice payment deletion → client error, not 500
  if (errorMessage.includes('refusing to delete')) {
    logger.warn('Update invoice rejected payment deletion:', { error: errorMessage });
    res.status(400).json({ error: 'One or more payments are not allocated to this invoice; nothing was deleted' });
    return;
  }

  // ACC-18 interim: client total disagrees with line items → 400
  if (error instanceof TotalMismatchError) {
    logger.warn('Update invoice rejected:', { error: error.message });
    res.status(400).json({ error: 'total_amount disagrees with line items' });
    return;
  }
  if (error instanceof InvalidPaymentMethodError) {
    logger.warn('Update invoice rejected:', { error: error.message });
    res.status(400).json({ error: error.message });
    return;
  }
  if (error instanceof InvoiceCreationOffsetError) {
    logger.warn('Update invoice rejected:', { error: error.message });
    res.status(400).json({ error: error.message });
    return;
  }
  if (error instanceof CreditOffsetChangeNotSupportedError) {
    logger.warn('Update invoice rejected:', { error: error.message });
    res.status(400).json({ error: error.message });
    return;
  }
  // Closed accounting period: cannot rewrite history.
  if (respondToClosedPeriod(res, errorMessage)) return;

  logger.error('Update invoice error:', { error: errorMessage, name: errorName, stack: error instanceof Error ? error.stack : undefined });
  handleBusinessError(res, error, 'Update invoice', 'Failed to update invoice');
}

function recordUpdatedInvoicePayment(payment: PaymentDTO, context: { invoiceId: number; parsedCustomerId: number; resolvedInvoiceNo: string; originalInvoice: NonNullable<ReturnType<typeof InvoiceModel.getById>>; totalAmountNum: number; userId: number }): void {
  const { invoiceId, parsedCustomerId, resolvedInvoiceNo, originalInvoice, totalAmountNum, userId } = context;
  const newPaymentAmount = parseCurrency(payment.amount);

  if (!isValidPaymentMethod(payment.payment_method)) {
      throw new InvalidPaymentMethodError(payment.payment_method);
  }

  AccountingService.assertPeriodNotClosed(db, payment.payment_date, `Payment for Invoice ${resolvedInvoiceNo}`);

  const paidSoFar = parseCurrency(PaymentModel.getTotalPaidByInvoiceId(db, invoiceId));
  const returnedForGuard = parseCurrency(originalInvoice?.returned_amount || 0);
  if (paidSoFar + newPaymentAmount + returnedForGuard > totalAmountNum + 0.01) {
      throw new InvoiceCreationOffsetError(
          paidSoFar + newPaymentAmount + returnedForGuard,
          totalAmountNum,
      );
  }

  // FIX #5: Atomic payment number generation
  const newPaymentNo = InvoiceModel.generatePaymentNoAtomic(db);

  const newPaymentId = InvoiceModel.createPayment(db, newPaymentNo, parsedCustomerId, payment.payment_date, newPaymentAmount, payment.payment_method, payment.reference_no, payment.notes);

  InvoiceModel.createPaymentAllocation(db, newPaymentId, invoiceId, newPaymentAmount);

  // Ledger entry for payment (credit to reduce AR)
  InvoiceModel.createLedgerEntry(db, parsedCustomerId, 'PAYMENT', newPaymentNo, payment.payment_date, 0, newPaymentAmount, `Payment ${newPaymentNo} for Invoice ${resolvedInvoiceNo}`);

  // GL posting (ACC-09 companion): the create-invoice path posts
  // its recorded payments; the update path must too, else the
  // payment's Dr Cash / Cr AR lines never exist.
  AccountingService.postPaymentEntry(db, {
      paymentId: newPaymentId,
      paymentNo: newPaymentNo,
      amount: newPaymentAmount,
      paymentDate: payment.payment_date,
      paymentMethod: payment.payment_method,
      customerId: parsedCustomerId,
      userId,
  });
}

function updateInvoice(req: AuthRequest, res: Response): Response | void {
  try {
    const { id } = req.params;
    const invoiceId = parseInt(id as string, 10);

    const {
      invoice_no,
      customer_id,
      invoice_date,
      due_date,
      status,
      discount_scope,
      discount_type,
      discount_value,
      items,
      notes,
      terms,
      total_amount,
      deleted_payments,
      record_payment,
      payment,
      credit_offset,
    } = req.body as {
      invoice_no: string;
      customer_id: number | string;
      invoice_date: string;
      due_date: string;
      status?: InvoiceStatus;
      discount_scope?: string;
      discount_type?: string;
      discount_value?: number;
      items: InvoiceItemDTO[];
      notes?: string;
      terms?: string;
      total_amount: number | string;
      deleted_payments?: number[];
      record_payment?: boolean;
      payment?: PaymentDTO;
      credit_offset?: number | string;
    };

    if (!customer_id || !invoice_date || !items || items.length === 0) {
      return res.status(400).json({ error: 'Customer, date, and items are required' });
    }

    const parsedCustomerId = parseInt(String(customer_id), 10);
    const userId = req.user!.id;

    // Fast-fail check outside transaction
    const invoiceExists = InvoiceModel.getById(invoiceId, db);
    if (!invoiceExists) {
      return res.status(404).json({ error: 'Invoice not found' });
    }

    const transaction = db.transaction(() => {
        // Re-read invoice INSIDE transaction for fresh data
        const originalInvoice = InvoiceModel.getById(invoiceId, db);
        if (!originalInvoice) throw new Error('Invoice not found');

        AccountingService.assertPeriodNotClosed(db, originalInvoice.invoice_date, `Invoice ${originalInvoice.invoice_no}`);

        // The Flutter form re-sends the invoice's existing credit_offset on
        // every edit, so an unchanged value must stay acceptable. A changed
        // one cannot be honoured here — it would need a partial reversal of
        // the posted offset entry — and silently ignoring it would leave the
        // user believing credit was applied when it was not.
        const appliedCreditOnInvoice = parseCurrency(originalInvoice.credit_offset || 0);
        assertCreditOffsetUnchanged(credit_offset, appliedCreditOnInvoice);

        // ACC-18 interim: server-authoritative totals on update too.
        const computedTotal = computeInvoiceGrandTotal(items, {
          discount_scope,
          discount_type,
          discount_value,
        });
        const totalAmountNum = computedTotal;

        // SALES-005: void-then-repost below has no floor. `postInvoiceEntry`
        // returns null when the total is non-positive, so editing a paid
        // invoice's lines down to zero voided the original Dr 1100 / Cr 4000,
        // posted nothing back, and left a bare Cr 1100 for a sale that no
        // longer existed — a credit balance on a debit-normal asset, with the
        // trial balance still balanced so nothing alerted.
        //
        // The floor is NON-POSITIVE, not "below what was paid". Reducing a paid
        // invoice's total while leaving the payment intact is legitimate and
        // is covered by moneyPaths 9.3: the balance floors at 0 and the invoice
        // stays 'Paid'. The failure is specifically the case where nothing is
        // posted back at all.
        //
        // The existing over-payment guard below only covers a payment supplied
        // in THIS request; it does not cover editing the lines of an invoice
        // that already carries payments.
        const alreadyPaid = parseCurrency(PaymentModel.getTotalPaidByInvoiceId(db, invoiceId));
        if (alreadyPaid > 0 && totalAmountNum <= 0) {
            throw new InvoiceCreationOffsetError(alreadyPaid, totalAmountNum);
        }

        if (total_amount !== undefined && total_amount !== null) {
            const clientTotal = parseCurrency(total_amount);
            if (Math.abs(clientTotal - computedTotal) > 0.01) {
                throw new TotalMismatchError(clientTotal, computedTotal);
            }
        }

        // Fallback to original invoice_no if not provided in request
        const resolvedInvoiceNo = invoice_no || originalInvoice.invoice_no;

        applyDeletedInvoicePayments(db, req, invoiceId, originalInvoice, deleted_payments, userId);

        // Rebuild running balances after deleting payment ledger entries
        ledgerUtils.rebuildLedgerBalances(parsedCustomerId);

        if (record_payment && payment && parseCurrency(payment.amount) > 0) {
          recordUpdatedInvoicePayment(payment, { invoiceId, parsedCustomerId, resolvedInvoiceNo, originalInvoice, totalAmountNum, userId });
        }

        // === Recalculate paid/balance (accounting for returned_amount) ===
        const paidResult = PaymentModel.getTotalPaidByInvoiceId(db, invoiceId);

        // Applied store credit counts toward paid, exactly as the create
        // path does. Summing payments alone would wipe an applied credit
        // off the invoice on any edit while its GL entry and the
        // customer's decremented credit_balance both survive — AR would
        // silently drift upward by that amount.
        const totalPaid = addCurrency(parseCurrency(paidResult), appliedCreditOnInvoice);
        const returnedAmt = parseCurrency(originalInvoice?.returned_amount || 0);
        const newBalanceAmount = Math.max(0, subtractCurrency(subtractCurrency(totalAmountNum, totalPaid), returnedAmt));

        const newStatus = resolveUpdatedInvoiceStatus(status, newBalanceAmount, totalAmountNum, returnedAmt);

        // Update invoice record
        InvoiceModel.updateInvoice(db, invoiceId, {
            invoice_no: resolvedInvoiceNo,
            customer_id: parsedCustomerId,
            invoice_date,
            due_date,
            status: newStatus,
            total_amount: totalAmountNum,
            paid_amount: totalPaid,
            balance_amount: newBalanceAmount,
            notes,
            discount_scope,
            discount_type,
            discount_value,
            terms
        });

        // === FIX #4: Reverse old stock before inserting new items ===
        const oldItems = InvoiceModel.getInvoiceItemsForStockReverse(db, invoiceId);
        const oldDraws = InvoiceModel.readLineBinDraws(db, oldItems);
        // MEDIUM-1 / NEW-1 / NEW-4: remember which reservation backed each old
        // line BEFORE the rows are deleted. A map keyed by item_id is NOT
        // enough (NEW-1): one invoice may carry two lines of the same item on
        // DIFFERENT reservations. A per-item QUEUE is also not enough (NEW-4):
        // it pairs by ARRAY POSITION, so reordering two same-item lines hands
        // the larger line the smaller reservation - a 400 when the quantities
        // differ, and a silent wrong link when they match. Keep both: an index
        // by reservation id for the explicit case, and the queue as a fallback
        // for a client that does not resend the link.
        const reservationById = new Map<number, StockReservation>();
        const reservationsByItem = new Map<number, StockReservation[]>();
        for (const old of oldItems) {
            if (!old.reservation_id) continue;
            // A released reservation is never handed back to a new line.
            const reservation = StockReservationModel.getById(old.reservation_id, db);
            if (!reservation || reservation.status === 'RELEASED') continue;
            reservationById.set(reservation.id, reservation);
            const queue = reservationsByItem.get(old.item_id) ?? [];
            queue.push(reservation);
            reservationsByItem.set(old.item_id, queue);
        }

        // NEW-2 Option 1: a line whose item CHANGED no longer belongs to the
        // reservation that backed it, so that reservation is RELEASED rather
        // than reopened - reopening would hold the units on a sale that no
        // longer contains the item (the stranded hold Finding 19 pins). Release
        // is terminal: a later change back must reserve again.
        //
        // Identity is the submitted `id` of an existing line. Nothing weaker is
        // safe: an array index shifts on any reorder or deletion (GLM HIGH on
        // e390321a released r1 while the KEPT item-A line stayed unreserved),
        // and comparing quantity or arrival order is the same guess that caused
        // NEW-1 and NEW-4. When identity cannot be established the edit fails
        // closed with 409 instead of pairing something plausible.
        const oldById = new Map<number, (typeof oldItems)[number]>();
        for (const old of oldItems) oldById.set(old.id, old);

        const submittedIds = new Set<number>();
        for (const item of items) {
          if (item.id == null) continue;
          // The id must name a line of THIS invoice - otherwise a client could
          // drive a release on someone else's line.
          if (!oldById.has(item.id)) {
            throw new BusinessRuleError(409,
              `Invoice line ${item.id} does not belong to invoice ${resolvedInvoiceNo}`);
          }
          if (submittedIds.has(item.id)) {
            throw new BusinessRuleError(409,
              `Invoice line ${item.id} is submitted more than once`);
          }
          submittedIds.add(item.id);
        }

        // reservation_id -> the submitted line that claims it. Only meaningful
        // with an explicit link; it names the surviving line for a split.
        const itemByReservation = new Map<number, InvoiceItemDTO>();
        const reservationsPerItem = new Map<number, number>();
        for (const item of items) {
          if (item.reservation_id == null) continue;
          if (!itemByReservation.has(item.reservation_id)) {
            itemByReservation.set(item.reservation_id, item);
          }
          reservationsPerItem.set(item.item_id, (reservationsPerItem.get(item.item_id) ?? 0) + 1);
        }

        // A line is continued when the edit resubmits its id. With no ids at all
        // (an older client) the edit must be unambiguous per item: exactly one
        // old line and one submitted line for that item, both unreserved. Any
        // other shape is refused rather than guessed.
        const legacyMode = !items.some((item) => item.id != null);
        const oldPerItem = new Map<number, number>();
        const newPerItem = new Map<number, number>();
        for (const old of oldItems) oldPerItem.set(old.item_id, (oldPerItem.get(old.item_id) ?? 0) + 1);
        for (const item of items) newPerItem.set(item.item_id, (newPerItem.get(item.item_id) ?? 0) + 1);

        const releasedIds = new Set<number>();
        const linesToReopen: typeof oldItems = [];
        for (const old of oldItems) {
          const explicit = itemByReservation.get(old.reservation_id ?? -1);
          let continued: InvoiceItemDTO | undefined;
          let itemChanged: boolean;

          if (!legacyMode) {
            // The submitted line that carries this old id continues it.
            continued = items.find((item) => item.id === old.id);
            if (!continued) {
              // The old line is gone. Its reservation can only be reopened if
              // the edit did not hand that reservation to another line.
              if (old.reservation_id != null && explicit) {
                throw new BusinessRuleError(409,
                  `Reservation ${old.reservation_id} is still claimed by another line but its own line was removed`);
              }
              linesToReopen.push(old);
              continue;
            }
            itemChanged = continued.item_id !== old.item_id;
          } else {
            // Older client: no ids. Accept only shapes with one obvious answer.
            const ambiguity = old.reservation_id != null
              ? (oldPerItem.get(old.item_id) ?? 0) > 1 || (newPerItem.get(old.item_id) ?? 0) > 1
              : false;
            if (ambiguity) {
              throw new BusinessRuleError(409,
                `Invoice contains more than one line for item ${old.item_id}; resend each line id to edit it`);
            }
            // A line of a different item that is the only submitted line of ITS
            // item is the continuation of this one (an item change); otherwise
            // this line was removed or resized.
            const candidates = items.filter((item) => item.id == null && item.reservation_id == null
              && (newPerItem.get(item.item_id) ?? 0) === 1);
            continued = candidates[0];
            itemChanged = !!continued && continued.item_id !== old.item_id;
          }

          if (itemChanged && old.reservation_id) {
            StockReservationModel.releaseById(db, old.reservation_id);
            releasedIds.add(old.reservation_id);
            continue;
          }
          linesToReopen.push(old);
        }

        InvoiceModel.reverseStockForItems(db, oldItems, originalInvoice.invoice_no, userId, 'INVOICE_UPDATE', undefined, oldDraws);

        // S-1: an edit reverses the sale, so it follows the same reservation
        // rule as a cancel - reopen only when the source order is still
        // active. Runs after the stock reversal, in the same transaction.
        //
        // Decision C: when the reopen is IMPOSSIBLE (a terminal sales order, or
        // a reference that is not a sales order), the edit has taken the hold
        // off a sale that is gone, so it must end the hold instead of leaving
        // it CONSUMED for good. It is released by id - terminal, holding
        // nothing - exactly like an item change (NEW-2 Option 1). Void and
        // cancel keep the CONSUMED rule above: only this edit path releases.
        const reopenable: typeof linesToReopen = [];
        for (const old of linesToReopen) {
          if (old.reservation_id != null && !StockReservationModel.canReopenById(old.reservation_id, db)) {
            StockReservationModel.releaseById(db, old.reservation_id);
            releasedIds.add(old.reservation_id);
            continue;
          }
          reopenable.push(old);
        }
        InvoiceModel.reopenReservationsForLines(db, reopenable, oldDraws);

        // NEW-2 wire contract (PR #42): the edit form resends BOTH the line `id`
        // and its `reservation_id`, and it KEEPS the old link on a line whose
        // item changed - the client has no other way to say "this line still
        // exists". The loop above already RELEASED that hold, so the resent link
        // is void, not a claim on it. Only a line that still sells the
        // reservation's item may budget that hold or be rejected for naming an
        // unknown one. Without this, an ordinary item change sent by the real
        // client 409s with "reservation N holds 0 but the line requests X".
        const claimsReservation = (item: (typeof items)[number]): boolean => {
          if (item.reservation_id == null) return false;
          if (item.id == null) return true;
          const old = oldById.get(item.id);
          return old == null || old.item_id === item.item_id;
        };

        // Line-count rule (audit/DECISIONS.md): one reservation may SPLIT across
        // several resulting lines, but one line must never consume two distinct
        // reservations. Count by durable reservation id, never by position - a
        // line can be reordered, and after a split one reservation legitimately
        // appears on several lines.
        const wantedIds = new Map<number, number>();
        for (const item of items) {
          if (!claimsReservation(item)) continue;
          const reservationId = item.reservation_id as number;
          wantedIds.set(reservationId, (wantedIds.get(reservationId) ?? 0) + 1);
        }
        const unknown = items.find((item) => claimsReservation(item)
          && !reservationById.has(item.reservation_id as number));
        if (unknown) {
          // The line names a reservation this invoice never held - it would have
          // to consume someone else's hold. Reject before any row changes.
          throw new BusinessRuleError(409,
            `Invoice line ${unknown.item_id}: reservation ${unknown.reservation_id} does not belong to this invoice`);
        }

        // Collapse check: the old invoice held N distinct reservations for an
        // item, but the edit keeps fewer LINES for that item. One line cannot
        // honestly consume two reservations, and the surplus is not the user's
        // to lose - refuse rather than silently drop a hold. Reads durable ids
        // only, so a reorder or a resize of lines does not trip this.
        const oldReservedPerItem = new Map<number, number>();
        for (const old of oldItems) {
          if (old.reservation_id == null) continue;
          oldReservedPerItem.set(old.item_id, (oldReservedPerItem.get(old.item_id) ?? 0) + 1);
        }
        const keptLinesPerItem = new Map<number, number>();
        for (const item of items) {
          keptLinesPerItem.set(item.item_id, (keptLinesPerItem.get(item.item_id) ?? 0) + 1);
        }
        for (const [itemId, reserved] of oldReservedPerItem) {
          const kept = keptLinesPerItem.get(itemId) ?? 0;
          // A line that CHANGED item is meant to lose its hold, so it is not a
          // collapse. Count only old lines whose item is still this item.
          const releasedByChange = oldItems.filter((old) => old.item_id === itemId
            && old.reservation_id != null
            && releasedIds.has(old.reservation_id)).length;
          // A line DELETED by the edit also leaves the count, and its
          // reservation correctly reopens - that is a removal, not a collapse.
          // Only a client that sends ids can express a deletion; without them
          // every old line "looks removed", which would fake a collapse.
          const removedLines = legacyMode ? 0 : oldItems.filter((old) => old.item_id === itemId
            && old.reservation_id != null
            && !items.some((item) => item.id === old.id)).length;
          // A removed line is only harmless when nothing absorbs its quantity.
          // If a surviving line of the same item grew past what the kept
          // reservations hold, it is a collapse wearing a deletion's clothes.
          // Compare against the reservations that SURVIVE the edit, so a plain
          // quantity change on a kept line is never mistaken for a collapse.
          const keptIds = new Set(items.map((item) => item.id));
          const keptHeld = oldItems
            .filter((old) => old.item_id === itemId && old.reservation_id != null
              && keptIds.has(old.id))
            .reduce((sum, old) => sum + roundQty(Number(old.quantity)), 0);
          const keptRequested = items
            .filter((item) => item.item_id === itemId)
            .reduce((sum, item) => sum + roundQty(Number(item.quantity)), 0);
          const absorbed = removedLines > 0 && keptRequested > keptHeld;
          if (kept + releasedByChange + removedLines < reserved || absorbed) {
            throw new BusinessRuleError(409,
              `Cannot collapse reservations into one line: item ${itemId} had ${reserved} reserved lines but the edit keeps ${kept}`);
          }
        }

        // Budget per reservation: its remaining held quantity, spent down as each
        // line takes its share. A line asking for more than is left is a
        // collapse that cannot be honoured - it would need a second reservation.
        // Read the LIVE row, not the pre-reopen snapshot: a CONSUMED
        // reservation had quantity_reserved = 0 until reopenReservationsForLines
        // put it back, so a stale read would budget 0 and 409 on a legal edit.
        const budget = new Map<number, number>();
        for (const [id] of wantedIds) {
          const row = StockReservationModel.getById(id, db);
          if (row) budget.set(id, roundQty(Number(row.quantity_reserved)));
        }
        for (const item of items) {
          if (!claimsReservation(item)) continue;
          const reservationId = item.reservation_id as number;
          const left = budget.get(reservationId) ?? 0;
          const want = roundQty(Number(item.quantity));
          if (want > left) {
            // Two reservations collapsed into one line lands here: the line
            // names one reservation and asks for more than it holds.
            throw new BusinessRuleError(409,
              `Cannot collapse reservations into one line: reservation ${reservationId} holds ${left} but the line requests ${want}`);
          }
          budget.set(reservationId, roundQty(left - want));
        }

        // Any reservation quantity no resulting line takes is stranded, so it is
        // released - the same rule as an item change (NEW-2 Option 1), reached
        // by resizing. Done BEFORE the lines are inserted so the consume calls
        // below see the right remaining amounts, and it never releases a
        // reservation that some line still needs.
        for (const [id, left] of budget) {
          if (left <= 0) continue;
          const live = StockReservationModel.getById(id, db);
          if (!live || live.status !== 'ACTIVE') continue;
          // Give back exactly the part no line takes; a line still needs the rest.
          StockReservationModel.releaseById(db, id, left);
        }

        InvoiceModel.deleteInvoiceItems(db, invoiceId);

        // Insert new invoice items and create new stock movements
        const claimed = new Set<number>();
        const updatedCogsTotal = consumeInvoiceItemsAndPostCogs(
            db, invoiceId, items, invoice_date, resolvedInvoiceNo, userId,
            (item) => {
                // NEW-4: an explicit reservation_id from the client is the
                // only durable identity here - never infer it from position.
                // This line must also BE that reservation's item, or the edit
                // is really an item change (see NEW-2 in audit/DECISIONS.md).
                // Line-count rule: one reservation MAY back several lines, so a
                // reservation already taken is not a reason to skip it - the
                // budget and the live bin rows below keep the total exact.
                let captured: StockReservation | undefined;
                if (item.reservation_id != null) {
                    const named = reservationById.get(item.reservation_id);
                    if (named && named.item_id === item.item_id) captured = named;
                }
                if (!captured) {
                    // Fallback for a client that does not resend the link: take
                    // a reservation for the item that still has quantity left.
                    // Never take a reservation this edit just released: it is
                    // terminal, and handing it out would undo the release.
                    captured = reservationsByItem.get(item.item_id)
                        ?.find((r) => !claimed.has(r.id) && !releasedIds.has(r.id));
                }
                if (!captured) return undefined;
                claimed.add(captured.id);
                // Re-read: the reopen above changed the status, and only a
                // reservation it made ACTIVE can be taken again - a closed
                // order stays unreserved by the rule.
                const fresh = StockReservationModel.getById(captured.id, db);
                return fresh?.status === 'ACTIVE' ? fresh : undefined;
            },
        );

        // GL consistency (ACC-08): void the invoice's INVOICE + COGS lines
        // (attributed) and re-post them at the new amounts. The old lines
        // stay in the audit trail; only voided = 0 lines feed the reports.
        AccountingService.voidJournalLinesByReference(db, 'INVOICE', invoiceId, {
            voidedBy: userId,
            voidReason: `Invoice ${resolvedInvoiceNo} updated`,
        });

        // H3: posted tax must equal the STORED invoice tax — read it back
        // from the invoice_items rows just re-inserted above instead of
        // recomputing from gross (which ignored discounts + rounding).
        const updatedTaxAmount = InvoiceModel.getInvoiceTaxTotal(db, invoiceId);

        AccountingService.postInvoiceEntry(db, {
            invoiceId,
            invoiceNo: resolvedInvoiceNo,
            totalAmount: totalAmountNum,
            invoiceDate: invoice_date,
            userId,
            taxAmount: updatedTaxAmount,
        });

        if (updatedCogsTotal > 0) {
            AccountingService.postCOGSEntry(db, {
                invoiceId,
                invoiceNo: resolvedInvoiceNo,
                cogsAmount: parseCurrency(updatedCogsTotal),
                invoiceDate: invoice_date,
                userId,
            });
        }

        // --- FIX #6: Customer balance update inside transaction ---
        if (originalInvoice.customer_id !== parsedCustomerId) {
            ledgerUtils.recalcCustomerBalanceFromLedger(originalInvoice.customer_id);
        }
        ledgerUtils.recalcCustomerBalanceFromLedger(parsedCustomerId);

        // Update invoice status and balance
        updateInvoiceStatus(invoiceId);
    });

    transaction();

    const updatedInvoice = InvoiceModel.getWithCustomer(invoiceId, db) as InvoiceRow;

    logCRUD(ActionType.INVOICE_UPDATE, 'Invoice', updatedInvoice.id,
      `Invoice ${updatedInvoice.invoice_no} updated`, req.user!.id,
      { total_amount: updatedInvoice.total_amount, status: updatedInvoice.status },
      { newValue: updatedInvoice, correlationId: newCorrelationId() });
    res.json(updatedInvoice);
  } catch (error: unknown) {
    return handleUpdateInvoiceError(res, error);
  }
}


/**
 * DELETE /api/invoices/:id
 * Delete an invoice, reversing all stock movements, cleaning up payments,
 * allocations, and ledger entries.
 */
function deleteInvoice(req: AuthRequest, res: Response): Response | void {
  try {
    const { id } = req.params;
    const invoiceId = parseInt(id as string, 10);
    const userId = req.user!.id;

    const invoice = InvoiceModel.getById(invoiceId, db);
    
    if (!invoice) {
        return res.status(404).json({ error: 'Invoice not found' });
    }

    // Block deletion of paid, returned, or cancelled invoices.
    // Only Draft and Unpaid invoices with no payments or returns may be deleted.
    const paidAmount = parseCurrency(invoice.paid_amount);
    const returnedAmount = parseCurrency(invoice.returned_amount);
    const deletableStatuses: string[] = ['Draft', 'Unpaid'];
    if (!deletableStatuses.includes(invoice.status) || paidAmount > 0 || returnedAmount > 0) {
      return res.status(400).json({
        error: 'Cannot delete this invoice. Only unpaid/draft invoices with no payments or returns can be deleted. Use Cancel instead.'
      });
    }

    AccountingService.assertPeriodNotClosed(db, invoice.invoice_date, `Invoice ${invoice.invoice_no}`);

    const transaction = db.transaction(() => {
      // AUD-06 (task 5.2): soft-delete. The invoice row is never removed, so
      // journal lines and customer-ledger rows can never be orphaned.
      const freshInvoice = InvoiceModel.getById(invoiceId, db);
      if (!freshInvoice) throw new Error('Invoice not found');
      assertLegacyInvoiceAllocationsAllowed(db, invoiceId);
      assertNoPartyAdjustment(db, 'invoice', invoiceId);

      const invoiceItems = InvoiceModel.getInvoiceItemsForStockReverse(db, invoiceId);
      const deleteDraws = InvoiceModel.readLineBinDraws(db, invoiceItems);

      // Reverse stock movements
      InvoiceModel.reverseStockForItems(db, invoiceItems, freshInvoice.invoice_no, userId, 'INVOICE_DELETE', undefined, deleteDraws);

      // S-1: a delete reverses the sale, so it follows the same reservation
      // rule as a cancel - reopen only when the source order is still active.
      // The ledger rows are KEPT because a delete is reversible: a restore
      // replays them to take the reservation again.
      InvoiceModel.reopenReservationsForLines(db, invoiceItems, deleteDraws, true);

      // Void ALL related journal lines (invoice + returns). Must affect rows.
      // Return GL groups are keyed to the return document, not the invoice,
      // so void them by return id — see InvoiceModel.voidOwnReturnJournalLines.
      const voided1 = AccountingService.voidJournalLinesByReference(db, 'INVOICE', invoiceId, {
        voidedBy: userId,
        voidReason: `Invoice ${freshInvoice.invoice_no} deleted`,
      });
      const voided2 = InvoiceModel.voidOwnReturnJournalLines(
        db, invoiceId, userId,
        `Invoice ${freshInvoice.invoice_no} deleted`,
      );
      if ((voided1 ?? 0) + (voided2 ?? 0) === 0 && freshInvoice.total_amount > 0) {
        throw new Error(`Refusing to soft-delete invoice ${freshInvoice.invoice_no}: no journal lines were voided — GL state unexpected`);
      }

      // Contra ledger entry neutralizing the original AR debit
      InvoiceModel.deleteLedgerEntryByReference(db, freshInvoice.invoice_no, freshInvoice.customer_id);

      // Void allocations; only remove a payment left with no other allocation
      const allocations = PaymentModel.getAllocationsByInvoiceId(db, invoiceId);
      for (const alloc of allocations) {
        db.prepare('UPDATE payment_allocations SET amount = 0 WHERE payment_id = ? AND invoice_id = ?').run(alloc.payment_id, invoiceId);
        const other = PaymentModel.getAllocationsByPaymentId(db, alloc.payment_id)
          .filter(a => a.invoice_id !== invoiceId);
        if (other.length === 0) {
          AccountingService.voidJournalLinesByReference(db, 'PAYMENT', alloc.payment_id);
          InvoiceModel.deleteLedgerEntryByReference(db,
            (PaymentModel.getById(db, alloc.payment_id))?.payment_no || '', freshInvoice.customer_id);
          PaymentModel.delete(db, alloc.payment_id, {
            voidedBy: userId,
            voidReason: `Payment voided with deleted invoice ${freshInvoice.invoice_no}`,
          });
        }
      }

      // Soft-delete marker + rebuild balances. The pre-delete status is
      // preserved in `deleted_from_status` so the restore endpoint can
      // bring the invoice back exactly as it was (undo pattern).
      db.prepare('UPDATE invoices SET status = ?, payment_status = ?, return_status = ?, deleted_from_status = ?, deleted_from_payment_status = ?, deleted_from_return_status = ?, deleted_at = ?, deleted_by = ? WHERE id = ?')
        .run('Deleted', 'Unpaid', 'None', freshInvoice.status, freshInvoice.payment_status, freshInvoice.return_status, new Date().toISOString(), userId, invoiceId);
      ledgerUtils.rebuildLedgerBalances(freshInvoice.customer_id);
      ledgerUtils.recalcCustomerBalanceFromLedger(freshInvoice.customer_id);
    });

    transaction();

    logCRUD(ActionType.INVOICE_DELETE, 'Invoice', invoiceId,
      `Invoice ${invoice.invoice_no} deleted`, userId,
      { total_amount: invoice.total_amount },
      { oldValue: { invoice_no: invoice.invoice_no, status: invoice.status, total_amount: invoice.total_amount }, reason: 'Manual deletion via API', correlationId: newCorrelationId() });
    res.status(200).json({ message: 'Invoice deleted successfully' });
  } catch (error: unknown) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    // Closed accounting period: cannot rewrite history.
    if (respondToClosedPeriod(res, errorMessage)) return;
    handleBusinessError(res, error, 'Delete invoice', 'Failed to delete invoice');
  }
}

/**
 * POST /api/invoices/:id/restore
 * Revert a soft-deleted invoice (undo pattern, SHORTCOMINGS-FIX 4.2/4.4).
 * Mirrors [deleteInvoice] step-for-step in reverse:
 *   1. Re-consume stock (FIFO/FEFO from oldest batches, new SALE movements)
 *   2. Un-void the invoice's INVOICE + INVOICE_RETURN journal lines
 *   3. Undo the customer-ledger reversal (drop the REVERSAL row, un-void
 *      the original INVOICE row)
 *   4. Restore the pre-delete status + clear deleted_at/deleted_by
 *   5. Rebuild ledger + customer balances
 * Only invoices that are currently soft-deleted (deleted_at set) can be
 * restored; the endpoint refuses otherwise.
 */
function restoreInvoice(req: AuthRequest, res: Response): Response | void {
  try {
    const { id } = req.params;
    const invoiceId = parseInt(id as string, 10);
    const userId = req.user!.id;

    // getById filters deleted rows — a raw lookup is required here.
    const invoice = db.prepare('SELECT * FROM invoices WHERE id = ?').get(invoiceId) as Invoice | undefined;
    if (!invoice) {
      return res.status(404).json({ error: 'Invoice not found' });
    }
    if (!invoice.deleted_at) {
      return res.status(400).json({ error: 'Invoice is not deleted' });
    }

    // Period guard (task 1.3): restoring un-voids GL lines, restores the
    // customer-ledger entry and re-consumes stock. A closed-period invoice
    // must stay deleted; its history is immutable.
    AccountingService.assertPeriodNotClosed(
      db,
      invoice.invoice_date,
      `Invoice ${invoice.invoice_no} restore`
    );

    const transaction = db.transaction(() => {
      // 0. S-1: the restored invoice holds its reservation again BEFORE the
      //    stock re-consume below, from the ledger rows the delete kept. The
      //    re-consume then draws the units it just reserved. Same active-order
      //    rule as the reopen, inside this transaction so stock and reserve
      //    commit together.
      const restoredItems = InvoiceModel.getInvoiceItemsForStockReverse(db, invoiceId);
      InvoiceModel.reconsumeRestoredLines(db, restoredItems, InvoiceModel.readLineBinDraws(db, restoredItems));

      // 1. Re-consume stock — BUG-010: batch-faithful, not today's FIFO.
      //    Re-use the exact batches and unit costs the invoice's original
      //    SALE movements used, so the stock ledger agrees with the COGS
      //    lines that step 2 un-voids. The delete's reverseStockForItems
      //    credited those same batches back, so they are re-available.
      InvoiceModel.reconsumeRestoredInvoiceItems(
        db,
        invoiceId,
        invoice.invoice_no,
        invoice.invoice_date.slice(0, 10),
        userId
      );


      // 2. Un-void the journal lines the delete voided (GL is restored to
      //    its pre-delete state — no new posting, no double counting).
      //    TASK 34: scoped by the accounting service, exactly like the void
      //    side, so no path mutates journal_lines behind the GL authority.
      AccountingService.restoreJournalLinesByReference(db, 'INVOICE', invoiceId);
      AccountingService.restoreJournalLinesByReference(db, 'INVOICE_RETURN', invoiceId, {
        owningInvoiceId: invoiceId,
      });

      // 3. Undo the customer-ledger reversal created by
      //    deleteLedgerEntryByReference: drop the REVERSAL row and
      //    un-void the original INVOICE entry.
      const reversals = db.prepare(`
        SELECT id FROM customer_ledger
        WHERE customer_id = ? AND reference_no = ?
          AND transaction_type = 'REVERSAL:INVOICE' AND voided = 0
      `).all(invoice.customer_id, invoice.invoice_no) as Array<{ id: number }>;
      for (const reversal of reversals) {
        db.prepare('DELETE FROM customer_ledger WHERE id = ?').run(reversal.id);
      }
      db.prepare(`
        UPDATE customer_ledger
        SET voided = 0
        WHERE customer_id = ? AND reference_no = ?
          AND transaction_type = 'INVOICE' AND voided = 1
      `).run(invoice.customer_id, invoice.invoice_no);

      // 4. Restore status + clear the soft-delete markers.
      const restoredStatus =
        invoice.deleted_from_status ||
        (parseCurrency(invoice.total_amount) > 0 ? 'Unpaid' : 'Draft');
      const restoredPaymentStatus = invoice.deleted_from_payment_status || 'Unpaid';
      const restoredReturnStatus = invoice.deleted_from_return_status || 'None';
      db.prepare(`
        UPDATE invoices
        SET status = ?, payment_status = ?, return_status = ?,
            deleted_at = NULL, deleted_by = NULL,
            deleted_from_status = NULL, deleted_from_payment_status = NULL, deleted_from_return_status = NULL,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
      `).run(restoredStatus, restoredPaymentStatus, restoredReturnStatus, invoiceId);

      // 5. Rebuild balances (same as delete — the ledger chain changed).
      ledgerUtils.rebuildLedgerBalances(invoice.customer_id);
      ledgerUtils.recalcCustomerBalanceFromLedger(invoice.customer_id);
    });

    transaction();

    logCRUD(ActionType.INVOICE_UPDATE, 'Invoice', invoiceId,
      `Invoice ${invoice.invoice_no} restored`, userId,
      { total_amount: invoice.total_amount, customer_id: invoice.customer_id },
      {
        oldValue: { status: 'Deleted' },
        newValue: { status: invoice.deleted_from_status || 'Unpaid' },
        reason: 'Undo of soft-delete via API',
      });

    const restored = InvoiceModel.getById(invoiceId, db);
    res.status(200).json({
      success: true,
      data: restored ?? invoice,
      message: 'Invoice restored successfully',
    });
  } catch (error: unknown) {
    logger.error('Restore invoice error:', { error });
    handleBusinessError(res, error, 'Restore invoice', 'Failed to restore invoice');
  }
}

/**
 * PUT /api/invoices/:id/cancel
 * Cancel an invoice. Sets status to 'Cancelled' without reversing stock,
 * payments, or returns. The invoice data is preserved for audit purposes.
 */
function cancelInvoice(req: AuthRequest, res: Response): Response | void {
  try {
    const { id } = req.params;
    const invoiceId = parseInt(id as string, 10);
    const userId = req.user!.id;

    const invoice = InvoiceModel.getById(invoiceId, db);
    if (!invoice) {
      return res.status(404).json({ error: 'Invoice not found' });
    }

    if (invoice.status === 'Cancelled') {
      return res.status(409).json({ error: 'Invoice is already cancelled' });
    }

    AccountingService.assertPeriodNotClosed(db, invoice.invoice_date, `Invoice ${invoice.invoice_no}`);

    const transaction = db.transaction(() => {
      // Reversal-rules C1/C4: one shared primitive for every cancel
      // path (dedicated endpoint + SO.cancel). Guards: payments lock,
      // returns lock. Effects: stock reversal, GL void (INVOICE +
      // INVOICE_RETURN), append-only CANCELLATION ledger credit,
      // balance rebuilds, status stamp. Throws on any inconsistency
      // so the whole transaction rolls back.
      InvoiceModel.cancelInvoiceInternal(db, invoice, userId);

      // (legacy inline body removed — see InvoiceModel.cancelInvoiceInternal)

      const corrCancel = newCorrelationId();
      logCRUD(ActionType.INVOICE_CANCEL, 'Invoice', invoiceId,
        `Invoice ${invoice.invoice_no} cancelled`, userId,
        { total_amount: invoice.total_amount, customer_id: invoice.customer_id },
        {
          oldValue: { status: invoice.status, total_amount: invoice.total_amount, balance_amount: invoice.balance_amount },
          newValue: { status: 'Cancelled' },
          reason: 'Manual cancellation via API',
          correlationId: corrCancel
        });
    });

    transaction();

    const updatedInvoice = InvoiceModel.getWithCustomer(invoiceId, db);
    res.json({ success: true, message: 'Invoice cancelled successfully', data: updatedInvoice });
  } catch (error: unknown) {
    // Guard rejections (payments/returns lock) are state conflicts — 409
    // with the reason, not a 500 server fault.
    if (error instanceof InvoiceCancellationGuardError) {
      return res.status(409).json({ error: error.message });
    }
    const cancelError = error instanceof Error ? error.message : String(error);
    // Closed accounting period: cannot rewrite history.
    if (cancelError.includes('inside closed accounting period')) {
      return res.status(409).json({ error: cancelError });
    }
    handleBusinessError(res, error, 'Cancel invoice', 'Failed to cancel invoice');
  }
}

function getInvoicePayments(req: AuthRequest, res: Response): void {
  try {
    const invoiceId = parseInt(Array.isArray(req.params.id) ? req.params.id[0] : req.params.id, 10);
    const payments = InvoiceModel.getPayments(invoiceId, db);
    res.json({ success: true, data: payments });
  } catch (error: unknown) {
    logger.error('Get invoice payments error:', { error });
    res.status(500).json({ error: 'Failed to fetch invoice payments' });
  }
}

/**
 * POST /api/invoices/:id/return
 *
 * Thin adapter over `InvoiceReturnService.processReturn` (spec §5.1 /
 * §10). Accepts the new payload — `fee_type`/`fee_value`, `return_date`,
 * `warehouse_id`, explicit `settlements[]` — and the legacy shape
 * (`disposition`, `adjust_invoice_ids`, `deduction_type`,
 * `deduction_value`, per-item `reason`) so existing desktop and mobile
 * clients keep working unchanged.
 */
function returnInvoiceItems(req: AuthRequest, res: Response): Response | void {
  try {
    const invoiceId = parseInt(req.params.id as string, 10);
    const userId = req.user!.id;
    const body = req.body as Record<string, unknown>;

    const rawItems = body.items;
    // `location_id` is the user's chosen restock bin, needed for a line whose
    // sale recorded no draw; the service validates it and refuses the line
    // without it. Keep the mapping explicit so no stray body field is honored.
    const items: Array<{ invoice_item_id: number; return_quantity: number; location_id?: number }> =
      Array.isArray(rawItems)
        ? (rawItems as Array<Record<string, unknown>>).map((raw) => ({
            // Kept raw, as before: the service coerces and validates both.
            invoice_item_id: raw.invoice_item_id as number,
            return_quantity: (raw.return_quantity ?? 0) as number,
            ...(raw.location_id == null ? {} : { location_id: Number(raw.location_id) }),
          }))
        : [];
    if (items.length === 0) {
      return res.status(400).json({ error: 'Invalid request: items must be a non-empty array' });
    }

    // Legacy clients send the reason inside the first item. Read it from the
    // RAW body: the mapping above keeps only the fields the service consumes.
    const firstRaw = Array.isArray(rawItems) ? (rawItems[0] as Record<string, unknown> | undefined) : undefined;
    const legacyReason = firstRaw ? String(firstRaw.reason ?? '') : '';
    const reason = body.reason ? String(body.reason) : legacyReason || null;

    // audit-3 task 08: a sales return puts stock back and may refund or
    // credit, so a retry must replay rather than return the goods twice.
    // ACCT-008 / D19: the key is mandatory here.
    const idemHash = hashRequestPayload(req.body);
    const start = startRequiredIdempotentRequest(db, req.headers, IDEMPOTENCY_SCOPES.INVOICE_RETURN, idemHash);
    if (respondToIdempotencyReplay(res, start, {
      buildBody: (resourceId) => ({ success: true, message: 'Return processed successfully', idempotentReplay: true, data: { returnId: resourceId } }),
    })) return;

    const result = InvoiceReturnService.processReturn({
      invoiceId,
      items,
      ...invoiceReturnOptions(body),
      reason,
      userId,
    });

    if (start.kind === 'proceed' && start.key) {
      claimIdempotencyKey(db, IDEMPOTENCY_SCOPES.INVOICE_RETURN, start.key, idemHash, result.returnId);
    }

    return res.json({ success: true, message: 'Return processed successfully', data: result });
  } catch (error: unknown) {
    if (error instanceof ReturnError) {
      return res.status(error.status).json({ error: error.message });
    }
    logger.error('Return invoice items error:', { error });
    handleBusinessError(res, error, 'Return invoice', 'Failed to process the return');
  }
}

/**
 * GET /api/invoices/:id/position
 * The authoritative money position of an invoice (spec §3.2 / §4.2).
 */
function getInvoicePosition(req: AuthRequest, res: Response): Response | void {
  try {
    const invoiceId = parseInt(req.params.id as string, 10);
    const position = InvoiceReturnService.getPosition(invoiceId);
    return res.json({ success: true, data: position });
  } catch (error: unknown) {
    if (error instanceof ReturnError) {
      return res.status(error.status).json({ error: error.message });
    }
    logger.error('Get invoice position error:', { error });
    return res.status(500).json({ error: 'Failed to fetch the invoice position' });
  }
}

/**
 * GET /api/invoices/returns
 * Retrieve invoice return history from stock movements.
 */
function getInvoiceReturnHistory(req: AuthRequest, res: Response): void {
  try {
    const { page, limit } = listPageQuery(req.query);
    const search = getQueryParam(req.query.search);
    const warehouseName = getQueryParam(req.query.warehouse_name);
    const sortBy = getQueryParam(req.query.sortBy);
    const sortOrder = getQueryParam(req.query.sortOrder);
    const startDateParam = getQueryParam(req.query.start_date);
    const endDateParam = getQueryParam(req.query.end_date);
    const itemIdParam = getQueryParam(req.query.item_id);

    const filters = {
      start_date: startDateParam || undefined,
      end_date: endDateParam || undefined,
      item_id: itemIdParam ? Number(itemIdParam) : undefined,
      search: search || undefined,
      warehouse_name: warehouseName || undefined,
      sortBy: sortBy || undefined,
      sortOrder: sortOrder || undefined,
      page,
      limit
    };

    const { rows, total, pageNum, limitNum } = InvoiceModel.getReturnHistory(filters, db);

    // Flat envelope (data = list, pagination a sibling) — the shape the
    // client's `getPaged` helper parses.
    res.json({
      success: true,
      data: rows,
      pagination: listPagination(total, pageNum, limitNum)
    });
  } catch (error: unknown) {
    logger.error('Get invoice return history error:', { error });
    res.status(500).json({ error: 'Failed to get invoice return history' });
  }
}

export {
  getInvoices,
  getInvoice,
  createInvoice,
  updateInvoice,
  deleteInvoice,
  restoreInvoice,
  cancelInvoice,
  getInvoicePayments,
  returnInvoiceItems,
  getInvoiceReturnHistory,
  getInvoicePosition,
  getBackdatedInvoices,
};

export default {
  getInvoices,
  getInvoice,
  createInvoice,
  updateInvoice,
  deleteInvoice,
  restoreInvoice,
  cancelInvoice,
  getInvoicePayments,
  returnInvoiceItems,
  getInvoiceReturnHistory,
  getInvoicePosition,
  getBackdatedInvoices,
};
