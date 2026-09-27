import { Response } from 'express';
import db from '../config/database';
import { AuthRequest, CreateInvoiceDTO, Invoice, InvoiceItemDTO, PaymentDTO, InvoiceStatus, SellableStockUnavailableError } from '../types';
import StockMovementModel from '../models/StockMovement';
import InvoiceModel from '../models/Invoice';
import { InvoiceCancellationGuardError } from '../models/Invoice';
import PaymentModel from '../models/Payment';
import AccountingService from '../services/accountingService';
import { InvoiceReturnService, ReturnError, type SettlementInput } from '../services/invoiceReturnService';
import type { FeeType } from '../services/returnMath';
import ledgerUtils from '../utils/ledgerUtils';
import logger from '../utils/logger';
import { log, logCRUD, ActionType, newCorrelationId } from '../services/activityLogger';
import { getQueryInteger, getQueryParam } from '../utils/queryUtils';
import {
  parseCurrency,
  subtractCurrency,
  computeInvoiceGrandTotal,
} from '../utils/currency';
import { isValidPaymentMethod } from '../services/cashService';
import { handleBusinessError } from '../utils/businessRuleError';
import { generateDocNo } from '../utils/sequence';
import {
  InvoiceCreationCreditError,
  InvoiceCreationIdempotencyError,
  InvoiceCreationOffsetError,
  InvoiceCreationPaymentMethodError,
  InvoiceCreationService,
  InvoiceCreationTotalMismatchError,
} from '../services/InvoiceCreationService';
import {
  IDEMPOTENCY_KEY_HEADER,
  INVOICE_CREATE_SCOPE,
  normalizeIdempotencyKey,
  hashRequestPayload,
  findIdempotencyRecord,
  claimIdempotencyKey,
} from '../utils/idempotency';

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
 * Credit offset exceeds the customer's available credit balance — a
 * client error (400), not a server fault.
 */
class InsufficientCreditError extends Error {
  constructor(offset: number, available: number) {
    super(`Credit offset (${offset.toFixed(2)}) exceeds available credit balance (${available.toFixed(2)})`);
    this.name = 'InsufficientCreditError';
  }
}

/**
 * H9: payment + credit offset exceeds the invoice total (entitlement) —
 * a client error (400), not a server fault.
 */
class OffsetExceedsTotalError extends Error {
  constructor(applied: number, total: number) {
    super(`Payment + credit offset (${applied.toFixed(2)}) exceeds invoice total (${total.toFixed(2)})`);
    this.name = 'OffsetExceedsTotalError';
  }
}

const {
  createLedgerEntry,
  recalcCustomerBalanceFromLedger,
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
  items?: InvoiceItemRow[];
}

interface InvoiceItemRow {
  item_id: number;
  quantity: number;
  unit_price: number;
  amount: number;
  tax_rate: number;
  discount_type: string;
  discount_value: number;
  item_name?: string;
  item_code?: string;
}

// ============ Controllers ============

/**
 * GET /api/invoices
 * Retrieve all invoices with optional filters.
 */
function getInvoices(req: AuthRequest, res: Response): void {
  try {
    const page = getQueryInteger(req.query.page, 1);
    const limit = getQueryInteger(req.query.limit, 10);
    const search = getQueryParam(req.query.search);
    const sortBy = getQueryParam(req.query.sortBy);
    const sortOrder = getQueryParam(req.query.sortOrder);
    const customerIdParam = getQueryParam(req.query.customer_id) ?? getQueryParam(req.query.customerId);
    const statusParam = getQueryParam(req.query.status);
    const startDate = getQueryParam(req.query.start_date);
    const endDate = getQueryParam(req.query.end_date);

    const filters: Parameters<typeof InvoiceModel.getAll>[0] = {
      statuses: statusParam
        ? statusParam.split(',').map((s) => s.trim())
        : undefined,
      customer_id: customerIdParam ? parseInt(customerIdParam, 10) : undefined,
      search: search || undefined,
      start_date: startDate || undefined,
      end_date: endDate || undefined,
      sortBy: sortBy || undefined,
      sortOrder: sortOrder || undefined,
      page,
      limit
    };

    const { rows, total, pageNum, limitNum } = InvoiceModel.getAll(filters, db);

    // Flat envelope matching the customers/suppliers shape the client's
    // `getPaged` helper expects: `data` is the item list and `pagination`
    // is a sibling of `data` (NOT nested inside it).
    res.json({
      success: true,
      data: rows,
      pagination: {
        currentPage: pageNum,
        totalPages: Math.ceil(total / limitNum),
        totalItems: total,
        hasNext: pageNum < Math.ceil(total / limitNum),
        hasPrev: pageNum > 1
      }
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
    invoice.items = InvoiceModel.getItems(id, db) as InvoiceItemRow[];

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
    return res.status(201).json(createdInvoice);
  } catch (error: unknown) {
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

        // ACC-18 interim: server-authoritative totals on update too.
        const computedTotal = computeInvoiceGrandTotal(items, {
          discount_scope,
          discount_type,
          discount_value,
        });
        const totalAmountNum = computedTotal;
        if (total_amount !== undefined && total_amount !== null) {
            const clientTotal = parseCurrency(total_amount);
            if (Math.abs(clientTotal - computedTotal) > 0.01) {
                throw new TotalMismatchError(clientTotal, computedTotal);
            }
        }

        // Fallback to original invoice_no if not provided in request
        const resolvedInvoiceNo = invoice_no || originalInvoice.invoice_no;

        // === Handle deleted payments (PAY-01) ===
        // Every deleted_payments id MUST be joined to THIS invoice via an
        // existing payment_allocations row. Anything else is a crafted
        // cross-invoice deletion → 400, delete nothing.
        if (deleted_payments && Array.isArray(deleted_payments) && deleted_payments.length > 0) {
            for (const deletedPaymentId of deleted_payments) {
                const allocations = PaymentModel.getAllocationsByPaymentId(db, deletedPaymentId);
                const ownsPayment = allocations.some(alloc => alloc.invoice_id === invoiceId);
                if (!ownsPayment) {
                    throw new Error(
                        `Payment ${deletedPaymentId} is not allocated to invoice ${invoiceId}; ` +
                        `refusing to delete`
                    );
                }
            }

            for (const deletedPaymentId of deleted_payments) {
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

        // Rebuild running balances after deleting payment ledger entries
        ledgerUtils.rebuildLedgerBalances(parsedCustomerId);

        // === Handle new payment recording (FIX #2: inside transaction) ===
        let newPaymentAmount: number;
        if (record_payment && payment && parseCurrency(payment.amount) > 0) {
            newPaymentAmount = parseCurrency(payment.amount);

            if (!isValidPaymentMethod(payment.payment_method)) {
                throw new InvalidPaymentMethodError(payment.payment_method);
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

        // === Recalculate paid/balance (accounting for returned_amount) ===
        const paidResult = PaymentModel.getTotalPaidByInvoiceId(db, invoiceId);

        const totalPaid = parseCurrency(paidResult);
        const returnedAmt = parseCurrency(originalInvoice?.returned_amount || 0);
        const newBalanceAmount = Math.max(0, subtractCurrency(subtractCurrency(totalAmountNum, totalPaid), returnedAmt));

        // Determine status: auto-compute only when the user did NOT
        // explicitly set a status. Draft, Sent, Cancelled, and other
        // manual statuses must be preserved on update.
        let newStatus: InvoiceStatus;
        const fullyReturned = returnedAmt >= totalAmountNum && totalAmountNum > 0;
        if (status && status !== 'Unpaid') {
            // User explicitly set a non-default status — respect it.
            newStatus = status;
        } else if (fullyReturned) {
            newStatus = 'Returned';
        } else if (newBalanceAmount <= 0 && totalAmountNum > 0) {
            newStatus = 'Paid';
        } else if (newBalanceAmount > 0 && newBalanceAmount < totalAmountNum) {
            newStatus = 'Partially Paid';
        } else {
            newStatus = status || 'Unpaid';
        }

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

        InvoiceModel.reverseStockForItems(db, oldItems, originalInvoice.invoice_no, userId, 'INVOICE_UPDATE');

        InvoiceModel.deleteInvoiceItems(db, invoiceId);

        // Insert new invoice items and create new stock movements
        let updatedCogsTotal = 0;
        for (const item of items) {
            InvoiceModel.createInvoiceItem(db, invoiceId, {
                item_id: item.item_id,
                quantity: item.quantity,
                unit_price: item.unit_price,
                tax_rate: item.tax_rate,
                discount_type: item.discount_type,
                discount_value: item.discount_value,
                amount: item.amount
            });

            // FIX #3: Stock validation with warning
            const warehouseId = InvoiceModel.findWarehouseForItem(
                db,
                item.item_id,
                item.quantity,
                item.warehouse_id
            );

            // FIFO batch consumption for new/updated items
            const consumption = InvoiceModel.consumeFromOldestBatches(
                item.item_id,
                warehouseId,
                item.quantity,
                db
            );

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
                        movement_date: invoice_date,
                        batch_id: entry.batchId ?? undefined,
                    },
                    userId,
                    db
                );
                updatedCogsTotal += entry.consumed * entry.unitCost;
            }
        }

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
    // Closed accounting period: cannot rewrite history.
    if (errorMessage.includes('inside closed accounting period')) {
      return res.status(409).json({ error: errorMessage });
    }

    logger.error('Update invoice error:', { error: errorMessage, name: errorName, stack: error instanceof Error ? error.stack : undefined });
    handleBusinessError(res, error, 'Update invoice', 'Failed to update invoice');
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

      const invoiceItems = InvoiceModel.getItemsForStockReverse(invoiceId, db);

      // Reverse stock movements
      InvoiceModel.reverseStockForItems(db, invoiceItems, freshInvoice.invoice_no, userId, 'INVOICE_DELETE');

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
    if (errorMessage.includes('inside closed accounting period')) {
      return res.status(409).json({ error: errorMessage });
    }
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

    const transaction = db.transaction(() => {
      const items = InvoiceModel.getItemsForStockReverse(invoiceId, db);

      // 1. Re-consume stock — mirror the create flow: FIFO/FEFO consumption
      //    from the oldest batches, one SALE movement per consumed batch.
      for (const item of items) {
        // The warehouse the sale was dispatched from (same source the
        // delete's reverseStockForItems reads); fall back to any
        // warehouse with stock.
        const saleMovement = db.prepare(`
          SELECT warehouse_id
          FROM stock_movements
          WHERE item_id = ? AND reference_docno = ? AND movement_type = 'SALE'
          ORDER BY id
          LIMIT 1
        `).get(item.item_id, invoice.invoice_no) as { warehouse_id: number } | undefined;
        const warehouseId = saleMovement?.warehouse_id ??
          InvoiceModel.findWarehouseForItem(db, item.item_id, item.quantity);

        const consumption = InvoiceModel.consumeFromOldestBatches(
          item.item_id,
          warehouseId,
          item.quantity,
          db
        );
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
              reference_docno: invoice.invoice_no,
              remarks: `Sold via Invoice ${invoice.invoice_no} (restored) ${batchLabel}`,
              movement_date: invoice.invoice_date.slice(0, 10),
              batch_id: entry.batchId ?? undefined,
            },
            userId,
            db
          );
        }
      }

      // 2. Un-void the journal lines the delete voided (GL is restored to
      //    its pre-delete state — no new posting, no double counting).
      //    Scoped exactly like the void side (InvoiceModel.voidOwnReturnJournalLines):
      //    return GL groups are keyed to the RETURN document, not the invoice,
      //    so a bare invoice id on INVOICE_RETURN would resurrect lines that
      //    belong to another invoice's return carrying the same numeric id.
      db.prepare(`
        UPDATE journal_lines
        SET voided = 0, voided_by = NULL, void_reason = NULL
        WHERE reference_type = 'INVOICE'
          AND reference_id = ? AND voided = 1
      `).run(invoiceId);
      db.prepare(`
        UPDATE journal_lines
        SET voided = 0, voided_by = NULL, void_reason = NULL
        WHERE reference_type = 'INVOICE_RETURN'
          AND reference_id = ? AND voided = 1
          AND NOT EXISTS (
            SELECT 1 FROM invoice_returns other_returns
            WHERE other_returns.id = journal_lines.reference_id
              AND other_returns.invoice_id <> ?
          )
      `).run(invoiceId, invoiceId);

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
    const items: Array<{ invoice_item_id: number; return_quantity: number }> = Array.isArray(rawItems)
      ? rawItems
      : [];
    if (items.length === 0) {
      return res.status(400).json({ error: 'Invalid request: items must be a non-empty array' });
    }

    // Legacy clients send the reason inside the first item.
    const legacyReason = items.length > 0 ? String((items[0] as Record<string, unknown>)?.reason ?? '') : '';
    const reason = body.reason ? String(body.reason) : legacyReason || null;

    const result = InvoiceReturnService.processReturn({
      invoiceId,
      items,
      feeType: (body.fee_type as FeeType | undefined) ?? undefined,
      feeValue: body.fee_value !== undefined ? Number(body.fee_value) : undefined,
      returnDate: body.return_date ? String(body.return_date) : null,
      warehouseId: body.warehouse_id === undefined || body.warehouse_id === null || body.warehouse_id === ''
        ? null
        : Number(body.warehouse_id),
      reason,
      settlements: Array.isArray(body.settlements) && body.settlements.length > 0
        ? (body.settlements as SettlementInput[])
        : null,
      // Legacy shim (spec §10) — honoured only when `settlements` is absent.
      disposition: (body.disposition as 'refund' | 'credit' | 'adjust' | null) ?? null,
      adjustInvoiceIds: Array.isArray(body.adjust_invoice_ids) ? (body.adjust_invoice_ids as number[]) : null,
      deductionType: (body.deduction_type as 'fixed' | 'percentage' | 'flat' | null) ?? null,
      deductionValue: body.deduction_value !== undefined ? Number(body.deduction_value) : undefined,
      userId,
    });

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
    const page = getQueryInteger(req.query.page, 1);
    const limit = getQueryInteger(req.query.limit, 10);
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
      pagination: {
        currentPage: pageNum,
        totalPages: Math.ceil(total / limitNum),
        totalItems: total,
        hasNext: pageNum < Math.ceil(total / limitNum),
        hasPrev: pageNum > 1
      }
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
};
