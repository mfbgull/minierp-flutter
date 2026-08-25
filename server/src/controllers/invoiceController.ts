import { Response } from 'express';
import db from '../config/database';
import { AuthRequest, InvoiceItemDTO, PaymentDTO, InvoiceStatus } from '../types';
import StockMovementModel from '../models/StockMovement';
import InvoiceModel from '../models/Invoice';
import PaymentModel from '../models/Payment';
import AccountingService from '../services/accountingService';
import ledgerUtils from '../utils/ledgerUtils';
import logger from '../utils/logger';
import { log, logCRUD, ActionType, newCorrelationId } from '../services/activityLogger';
import { getQueryInteger, getQueryParam } from '../utils/queryUtils';
import {
  parseCurrency,
  subtractCurrency,
  computeInvoiceGrandTotal,
} from '../utils/currency';

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
    res.json(invoice);
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
  try {
    const {
      invoice_no,
      customer_id,
      invoice_date,
      due_date,
      status = 'Unpaid' as InvoiceStatus,
      discount_scope,
      discount_type,
      discount_value,
      items,
      notes,
      terms,
      total_amount,
      record_payment,
      payment,
      expired_batch_overrides,
    } = req.body as {
      invoice_no?: string;
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
      record_payment?: boolean;
      payment?: PaymentDTO;
      expired_batch_overrides?: Record<number, string | null>;
    };

    if (!customer_id || !invoice_date || !items || items.length === 0) {
      return res.status(400).json({ error: 'Customer, date, and items are required' });
    }

    const parsedCustomerId = parseInt(String(customer_id), 10);
    const userId = req.user!.id;

    // === ENTIRE operation inside one transaction ===
    const transaction = db.transaction(() => {
      // ACC-18 interim: the server is authoritative over invoice money.
      // Header total = Σ of server-computed line amounts minus an
      // invoice-scope header discount — the same grand total the form
      // displays. A client-supplied total differing by more than 0.01
      // is rejected with nothing written.
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
      const paymentAmountNum = record_payment && payment
        ? parseCurrency(payment.amount)
        : 0;

    // Determine initial paid/balance/status
    const initialPaidAmount = paymentAmountNum;
    const initialBalanceAmount = subtractCurrency(totalAmountNum, paymentAmountNum);

    // Guard: payment cannot exceed the invoice total
    if (record_payment && payment && paymentAmountNum > totalAmountNum) {
      throw new Error(`Payment amount (${paymentAmountNum.toFixed(2)}) exceeds invoice total (${totalAmountNum.toFixed(2)})`);
    }

    let initialStatus: InvoiceStatus;
    if (record_payment && payment && paymentAmountNum > 0) {
      initialStatus = paymentAmountNum >= totalAmountNum ? 'Paid' : 'Partially Paid';
    } else {
      initialStatus = status || 'Unpaid';
    }

    // Insert invoice
    // CRITICAL-1 fix: pass the controller-computed initial paid and
    // balance through to the model so the monetary columns on the
    // invoice header match the payment that is about to be recorded
    // below. Previously these were hard-coded to 0/total, leaving
    // the A/R ledger inconsistent with payment_allocations.
    const invoiceId = InvoiceModel.createInvoice(db, {
      invoice_no,
      customer_id: parsedCustomerId,
      invoice_date,
      due_date,
      status: initialStatus as InvoiceStatus,
      total_amount: totalAmountNum,
      paid_amount: initialPaidAmount,
      balance_amount: initialBalanceAmount,
      notes,
      discount_scope,
      discount_type,
      discount_value,
      terms,
      items,
      override_sale: expired_batch_overrides && Object.keys(expired_batch_overrides).length > 0 ? 1 : 0,
    }, userId);

    // Insert invoice items and deduct stock via FIFO batch consumption
    let cogsTotal = 0;
    const consumptions: Array<{ itemId: number; consumption: Array<{ batchId: number | null; consumed: number }> }> = [];
    for (const item of items) {
      const warehouseId = InvoiceModel.findWarehouseForItem(
        db,
        item.item_id,
        item.quantity,
        item.warehouse_id
      );

      InvoiceModel.createInvoiceItem(db, invoiceId, {
        item_id: item.item_id,
        quantity: item.quantity,
        unit_price: item.unit_price,
        tax_rate: item.tax_rate,
        discount_type: item.discount_type,
        discount_value: item.discount_value,
        amount: item.amount
      });

      // FIFO consumption from oldest batches
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
            reference_docno: invoice_no!,
            remarks: `Sold via Invoice ${invoice_no} ${batchLabel}`,
            movement_date: invoice_date,
            batch_id: entry.batchId ?? undefined,
          },
          userId,
          db
        );
        cogsTotal += entry.consumed * entry.unitCost;
      }

      // Track consumption for expiry denormalization
      consumptions.push({ itemId: item.item_id, consumption });
    }

    // Denormalize expiry info onto invoice items and build expiry_notes.
    // expired_batch_overrides provides original expiry dates for batches
    // whose dates were temporarily cleared to unblock FEFO consumption.
    InvoiceModel.denormalizeExpiryInfo(invoiceId, consumptions, db, expired_batch_overrides);

      // Create customer ledger entry (debit to increase AR)
      createLedgerEntry(
        parsedCustomerId,
        invoice_date,
        'INVOICE',
        invoice_no!,
        totalAmountNum, // debit
        0,              // credit
        `Invoice ${invoice_no}`
      );

      // Post the sales invoice to the GL (Dr AR / Cr Sales Revenue net / Cr Tax Payable).
      // GL Phase-2 wiring: every new invoice auto-posts a journal
      // entry. This brings the new TB and BS into alignment over
      // time as new activity flows through.
      // MAJOR-5 fix: tax is now split out into a separate Tax Payable line
      // when items have tax_rate > 0.
      const computedTaxAmount = items.reduce<number>((sum, item) => {
        const lineAmount = item.quantity * item.unit_price;
        return sum + lineAmount * ((item.tax_rate || 0) / 100);
      }, 0);
      AccountingService.postInvoiceEntry(db, {
        invoiceId,
        invoiceNo: invoice_no!,
        totalAmount: totalAmountNum,
        invoiceDate: invoice_date,
        userId,
        taxAmount: computedTaxAmount,
      });

      // Post COGS: Dr COGS, Cr Inventory Asset at actual FIFO cost
      if (cogsTotal > 0) {
        AccountingService.postCOGSEntry(db, {
          invoiceId,
          invoiceNo: invoice_no!,
          cogsAmount: parseCurrency(cogsTotal),
          invoiceDate: invoice_date,
          userId,
        });
      }

    // --- FIX #2: Payment recording INSIDE transaction ---
    if (record_payment && payment && paymentAmountNum > 0) {
      // FIX #5: Atomic payment number generation
      const newPaymentNo = InvoiceModel.generatePaymentNoAtomic(db);

      const paymentId = InvoiceModel.createPayment(db, newPaymentNo, parsedCustomerId, payment.payment_date, paymentAmountNum, payment.payment_method, payment.reference_no, payment.notes);

      // Payment allocation
      InvoiceModel.createPaymentAllocation(db, paymentId, invoiceId, paymentAmountNum);

      // Ledger entry for payment (credit to reduce AR)
      InvoiceModel.createLedgerEntry(db, parsedCustomerId, 'PAYMENT', newPaymentNo, payment.payment_date, 0, paymentAmountNum, `Payment ${newPaymentNo} for Invoice ${invoice_no}`);

      // Post the payment to the GL (Dr Cash / Cr AR). Cash vs Bank
      // is determined by payment_method.
      AccountingService.postPaymentEntry(db, {
        paymentId,
        paymentNo: newPaymentNo,
        amount: paymentAmountNum,
        paymentDate: payment.payment_date,
        paymentMethod: payment.payment_method,
        customerId: parsedCustomerId,
        userId,
      });
    }

    // --- FIX #6: Customer balance update inside transaction ---
    ledgerUtils.recalcCustomerBalanceFromLedger(parsedCustomerId);

      return invoiceId;
    });

    const invoiceId = transaction();

    const createdInvoice = InvoiceModel.getWithCustomer(invoiceId, db) as InvoiceRow;

    const corrCreate = newCorrelationId();
    logCRUD(ActionType.INVOICE_CREATE, 'Invoice', createdInvoice.id,
      `Invoice ${createdInvoice.invoice_no} created (${createdInvoice.status})`, req.user!.id,
      { total_amount: createdInvoice.total_amount, customer_id: createdInvoice.customer_id },
      { newValue: createdInvoice, correlationId: corrCreate });
    res.status(201).json(createdInvoice);
  } catch (error: unknown) {
    // ACC-18 interim: client total disagrees with line items → 400
    if (error instanceof TotalMismatchError) {
      logger.warn('Create invoice rejected:', { error: error.message });
      res.status(400).json({ error: 'total_amount disagrees with line items' });
      return;
    }
    // FIX #7: Generic error message, log detail server-side
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    const errorCode = (error as { code?: string }).code;
    logger.error('Create invoice error:', { error: errorMessage, code: errorCode, stack: error instanceof Error ? error.stack : undefined });
    res.status(500).json({ error: 'Failed to create invoice' });
  }
}

/**
 * PUT /api/invoices/:id
 * Update an existing invoice. Reverses old stock movements before
 * applying new ones. Payment changes and customer balance updates
 * are all inside the transaction.
 */
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

                PaymentModel.deleteAllocationsByPaymentId(db, deletedPaymentId);
                PaymentModel.delete(db, deletedPaymentId);

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

        // Determine status (considering returned amount)
        let newStatus: InvoiceStatus;
        const fullyReturned = returnedAmt >= totalAmountNum && totalAmountNum > 0;
        if (fullyReturned) {
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

        const updatedTaxAmount = items.reduce<number>((sum, item) => {
            const lineAmount = item.quantity * item.unit_price;
            return sum + lineAmount * ((item.tax_rate || 0) / 100);
        }, 0);

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

    logger.error('Update invoice error:', { error: errorMessage, name: errorName, stack: error instanceof Error ? error.stack : undefined });
    res.status(500).json({ error: 'Failed to update invoice' });
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

    const transaction = db.transaction(() => {
      // AUD-06 (task 5.2): soft-delete. The invoice row is never removed, so
      // journal lines and customer-ledger rows can never be orphaned.
      const freshInvoice = InvoiceModel.getById(invoiceId, db);
      if (!freshInvoice) throw new Error('Invoice not found');

      const invoiceItems = InvoiceModel.getItemsForStockReverse(invoiceId, db);

      // Reverse stock movements
      InvoiceModel.reverseStockForItems(db, invoiceItems, freshInvoice.invoice_no, userId, 'INVOICE_DELETE');

      // Void ALL related journal lines (invoice + returns). Must affect rows.
      const voided1 = AccountingService.voidJournalLinesByReference(db, 'INVOICE', invoiceId);
      const voided2 = AccountingService.voidJournalLinesByReference(db, 'INVOICE_RETURN', invoiceId);
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
          PaymentModel.delete(db, alloc.payment_id);
        }
      }

      // Soft-delete marker + rebuild balances
      db.prepare('UPDATE invoices SET status = ?, deleted_at = ?, deleted_by = ? WHERE id = ?')
        .run('Deleted', new Date().toISOString(), userId, invoiceId);
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
    logger.error('Delete invoice error:', { error });
    res.status(500).json({ error: 'Failed to delete invoice' });
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
      return res.status(400).json({ error: 'Invoice is already cancelled' });
    }

    const transaction = db.transaction(() => {
      // Update status to Cancelled
      db.prepare(`
        UPDATE invoices SET status = 'Cancelled', updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
      `).run(invoiceId);

      // Void the invoice's GL journal_lines (Dr AR / Cr Sales Revenue / Cr Tax Payable).
      // This also covers COGS entries since they use reference_type 'INVOICE'.
      // Do NOT void PAYMENT or INVOICE_RETURN lines — those are still valid
      // adjustments. The CANCELLATION ledger entry below handles the AR offset.
      AccountingService.voidJournalLinesByReference(db, 'INVOICE', invoiceId);

      // Add a CANCELLED ledger entry (credit to offset the original debit)
      // This neutralizes the AR impact without deleting history
      createLedgerEntry(
        invoice.customer_id,
        invoice.invoice_date.slice(0, 10),
        'CANCELLATION',
        invoice.invoice_no,
        0,
        invoice.total_amount,
        `Invoice ${invoice.invoice_no} cancelled`
      );
      // Recalculate customer balance
      ledgerUtils.rebuildLedgerBalances(invoice.customer_id);
      ledgerUtils.recalcCustomerBalanceFromLedger(invoice.customer_id);

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
    logger.error('Cancel invoice error:', { error });
    res.status(500).json({ error: 'Failed to cancel invoice' });
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
 * Process a return for invoice items — reverses stock using FIFO batch restoration
 * and creates ADJUSTMENT movements to add stock back into inventory.
 */
function returnInvoiceItems(req: AuthRequest, res: Response): Response | void {
  try {
    const { id } = req.params;
    const invoiceId = parseInt(id as string, 10);
    const userId = req.user!.id;

    // Normalize payload: support both legacy format (items + reason at top level)
    // and new format from InvoiceReturn.tsx (items with reason inside each item, disposition, adjust_invoice_ids)
    const body = req.body as Record<string, any>;
    const rawItems = body.items;
    const rawDisposition = body.disposition;
    const rawAdjustInvoiceIds = body.adjust_invoice_ids;
    const rawReason = body.reason;
    const rawDeductionType = body.deduction_type;      // 'percentage' | 'flat' | undefined
    const rawDeductionValue = Number(body.deduction_value) || 0;
    // Optional restock warehouse — a customer return is restocked where
    // the user chooses; when omitted the server restocks into the
    // warehouse the sale was dispatched from (backward compatible).
    const rawWarehouseId = body.warehouse_id;
    const warehouseId = rawWarehouseId === undefined || rawWarehouseId === null || rawWarehouseId === ''
      ? undefined
      : Number(rawWarehouseId);
    if (warehouseId !== undefined && (!Number.isInteger(warehouseId) || warehouseId <= 0)) {
      return res.status(400).json({ error: 'A valid warehouse_id is required' });
    }

    const returnItems: Array<{ invoice_item_id: number; return_quantity: number }> = Array.isArray(rawItems) ? rawItems : [];
    const reason: string = rawReason || (returnItems.length > 0 ? (returnItems[0] as any).reason || '' : '');
    const disposition: 'refund' | 'credit' | 'adjust' | undefined = rawDisposition;
    const adjust_invoice_ids: number[] | undefined = rawAdjustInvoiceIds;

    if (returnItems.length === 0) {
      return res.status(400).json({ error: 'Invalid request: items must be a non-empty array' });
    }

    // Fast-fail checks outside transaction
    const invoiceExists = InvoiceModel.getById(invoiceId, db);
    if (!invoiceExists) {
      return res.status(404).json({ error: 'Invoice not found' });
    }

    if (invoiceExists.status === 'Cancelled') {
      return res.status(400).json({ error: 'Cannot return a cancelled invoice' });
    }

    // Default disposition: if invoice was paid, default to refund; otherwise default to credit
    const resolvedDisposition: 'refund' | 'credit' | 'adjust' =
      disposition || (invoiceExists.balance_amount <= 0 ? 'refund' : 'credit');

    const transaction = db.transaction(() => {
      // Re-read invoice INSIDE transaction to get fresh returned_qty values
      // This prevents race conditions on concurrent return requests
      const invoice = InvoiceModel.getById(invoiceId, db);
      if (!invoice) {
        throw new Error('Invoice not found');
      }

      const processedItems: Array<{ item_id: number; quantity: number; unit_price: number; discount_type?: string; discount_value?: number }> = [];
      let returnTotalTaxAmount = 0;

      for (const returnItem of returnItems) {
        // Re-fetch item from DB inside transaction to get fresh returned_qty
        const freshItem = db.prepare(
          'SELECT ii.*, i.item_name FROM invoice_items ii LEFT JOIN items i ON ii.item_id = i.id WHERE ii.id = ? OR ii.item_id = ?'
        ).get(returnItem.invoice_item_id, returnItem.invoice_item_id) as any;

        // Fallback to in-memory item if DB fetch fails
        const invoiceItem = freshItem || invoice.items?.find(
          (ii: any) => ii.id === returnItem.invoice_item_id || ii.item_id === returnItem.invoice_item_id
        );

        if (!invoiceItem) {
          throw new Error(`Invoice item ${returnItem.invoice_item_id} not found`);
        }

        if (returnItem.return_quantity <= 0) {
          throw new Error('Return quantity must be positive');
        }

        const returnedQty = Number(invoiceItem.returned_qty) || 0;
        const availableQty = Number(invoiceItem.quantity) - returnedQty;

        if (returnItem.return_quantity > availableQty) {
          throw new Error(
            `Return quantity (${returnItem.return_quantity}) exceeds available quantity (${availableQty}) for item ${invoiceItem.item_name}. Already returned: ${returnedQty}.`
          );
        }

        processedItems.push({
          item_id: invoiceItem.item_id,
          quantity: returnItem.return_quantity,
          unit_price: invoiceItem.unit_price,
          discount_type: invoiceItem.discount_type || 'percentage',
          discount_value: Number(invoiceItem.discount_value) || 0,
        });

        // Calculate line amount with item discount applied
        const grossLineAmount = Number(returnItem.return_quantity) * Number(invoiceItem.unit_price);
        const itemDiscountType = invoiceItem.discount_type || 'percentage';
        const itemDiscountValue = Number(invoiceItem.discount_value) || 0;
        let lineAmount = grossLineAmount;
        if (itemDiscountType === 'percentage' && itemDiscountValue > 0) {
          lineAmount = grossLineAmount * (1 - itemDiscountValue / 100);
        } else if (itemDiscountType === 'flat' && itemDiscountValue > 0) {
          lineAmount = Math.max(0, grossLineAmount - itemDiscountValue * Number(returnItem.return_quantity));
        }
        returnTotalTaxAmount += lineAmount * ((Number(invoiceItem.tax_rate) || 0) / 100);

        // Update per-item returned quantity tracking
        db.prepare(`UPDATE invoice_items SET returned_qty = returned_qty + ? WHERE id = ?`)
          .run(returnItem.return_quantity, returnItem.invoice_item_id);
      }

      // Reverse stock for the returned items using the same batch-aware logic —
      // restocked into the user-chosen warehouse when provided.
      InvoiceModel.reverseStockForItems(
        db,
        processedItems,
        invoice.invoice_no,
        userId,
        'RETURN',
        warehouseId
      );

      // Calculate the total return amount (with item discounts applied)
      const returnAmount = processedItems.reduce(
        (sum: number, item: { quantity: number; unit_price: number; discount_type?: string; discount_value?: number }) => {
          const grossAmount = Number(item.quantity) * Number(item.unit_price);
          const discountType = item.discount_type || 'percentage';
          const discountValue = Number(item.discount_value) || 0;
          let netAmount = grossAmount;
          if (discountType === 'percentage' && discountValue > 0) {
            netAmount = grossAmount * (1 - discountValue / 100);
          } else if (discountType === 'flat' && discountValue > 0) {
            netAmount = Math.max(0, grossAmount - discountValue * Number(item.quantity));
          }
          return sum + netAmount;
        },
        0
      );

      const todayDate = new Date().toISOString().split('T')[0];

      // Compute deduction (restocking fee) if applicable
      const deductionType: 'percentage' | 'flat' = rawDeductionType === 'percentage' ? 'percentage' : 'flat';
      let deduction = 0;
      if (rawDeductionValue > 0) {
        if (deductionType === 'percentage') {
          deduction = returnAmount * (rawDeductionValue / 100);
        } else {
          deduction = Math.min(rawDeductionValue, returnAmount);
        }
      }
      const netReturn = returnAmount - deduction;

      // Post GL reversal — reverse AR by net, reverse revenue by gross, record fee
      AccountingService.postInvoiceReturnEntry(db, {
        invoiceId,
        invoiceNo: invoice.invoice_no,
        grossReturn: returnAmount,
        netReturn,
        deduction,
        invoiceDate: todayDate,
        userId,
        taxAmount: returnTotalTaxAmount,
      });

      // Post COGS reversal — Dr Inventory Asset, Cr COGS at actual FIFO cost
      let returnCogsTotal = 0;
      for (const item of processedItems) {
        const saleMovements = db.prepare(`
          SELECT quantity, unit_cost, batch_id
          FROM stock_movements
          WHERE item_id = ? AND reference_docno = ? AND movement_type = 'SALE'
          ORDER BY id
        `).all(item.item_id, invoice.invoice_no) as Array<{
          quantity: number; unit_cost: number; batch_id: number | null;
        }>;

        if (saleMovements.length === 0) continue;

        const totalSold = saleMovements.reduce((sum, m) => sum + Math.abs(m.quantity), 0);
        const ratio = totalSold > 0 ? Math.min(Math.abs(item.quantity) / totalSold, 1) : 1;

        for (const movement of saleMovements) {
          returnCogsTotal += Math.abs(movement.quantity) * movement.unit_cost * ratio;
        }
      }

      if (returnCogsTotal > 0) {
        AccountingService.postCOGSReversalEntry(db, {
          invoiceId,
          invoiceNo: invoice.invoice_no,
          cogsAmount: parseCurrency(returnCogsTotal),
          entryDate: todayDate,
          userId,
        });
      }

      // Update returned_amount and return_fee on the invoice
      // Guard: prevent monetary over-return (defense in depth beyond item-level check)
      const currentReturned = Number(invoice.returned_amount || 0);
      const invoiceTotal = Number(invoice.total_amount);
      const newReturnedTotal = currentReturned + returnAmount;
      if (newReturnedTotal > invoiceTotal && (newReturnedTotal - invoiceTotal) > 0.01) {
        throw new Error(
          `Cannot return more than the invoice total. ` +
          `Already returned: ${parseCurrency(currentReturned)}, ` +
          `this return: ${parseCurrency(returnAmount)}, ` +
          `invoice total: ${parseCurrency(invoiceTotal)}.`
        );
      }
      // Update returned_amount (+gross) and return_fee (+deduction)
      db.prepare(
        `UPDATE invoices SET returned_amount = returned_amount + ?, return_fee = return_fee + ? WHERE id = ?`
      ).run(returnAmount.toFixed(2), deduction.toFixed(2), invoiceId);

      // ==================================================================
      // DISPOSITION HANDLING
      // ==================================================================
      //
      // The RETURN ledger entry is created per-disposition so we don't
      // double-count credits: REFUND and CREDIT create one RETURN entry
      // (credit reduces AR). ADJUST skips it because the PAYMENT entries
      // below already handle the AR reduction.

      if (resolvedDisposition === 'refund') {
        // Create customer ledger entry for the return (credit to reduce AR) — net amount
        createLedgerEntry(
          invoice.customer_id,
          todayDate,
          'RETURN',
          invoice.invoice_no,
          0,
          netReturn,
          `Return on Invoice ${invoice.invoice_no}${deduction > 0 ? ` (fee: $${deduction.toFixed(2)})` : ''}`
        );
        // ----------------------------------------------------------------
        // REFUND: Create a refund payment (negative payment record),
        // reverse/fraction the original payment allocation, post GL entry
        // ----------------------------------------------------------------

        const refundPaymentNo = InvoiceModel.generatePaymentNoAtomic(db);

        // Create a refund payment (negative amount) — refund only the net
        const refundPaymentId = InvoiceModel.createPayment(
          db,
          refundPaymentNo,
          invoice.customer_id,
          todayDate,
          -netReturn,  // negative = money going out — only net is refunded
          invoice.paid_amount > 0 ? 'Cash' : 'Cash',
          null,
          `Refund for return on ${invoice.invoice_no}${deduction > 0 ? ` (fee: $${deduction.toFixed(2)})` : ''}`
        );

        // Record a refund allocation (negative allocation = reduction of original payment)
        InvoiceModel.createPaymentAllocation(db, refundPaymentId, invoiceId, -netReturn);
        // Ledger entry: Dr (debit) the refund payment no. to reflect cash out
        createLedgerEntry(
          invoice.customer_id,
          todayDate,
          'REFUND',
          refundPaymentNo,
          netReturn,   // debit = customer owes us more (contra)
          0,
          `Refund ${refundPaymentNo} for return on ${invoice.invoice_no}`
        );

        // Post GL entry for refund: Dr Sales Returns (already done above in postInvoiceReturnEntry),
        // but also need to reverse the cash side: Dr AR (credit the original overpayment) / Cr Cash
        // Since postInvoiceReturnEntry already credited AR, we need an additional entry
        // that reverses the cash impact: Dr AR / Cr Cash (refund paid out)
        AccountingService.postRefundEntry(db, {
          refundPaymentId,
          refundPaymentNo,
          amount: netReturn,
          refundDate: todayDate,
          paymentMethod: invoice.paid_amount > 0 ? 'Cash' : 'Cash',
          customerId: invoice.customer_id,
          userId,
        });
      }

      else if (resolvedDisposition === 'credit') {
        // ----------------------------------------------------------------
        // CREDIT: Add the net returned amount to customer's credit_balance
        // ----------------------------------------------------------------

        // Create customer ledger entry for the return (credit to reduce AR) — net amount
        createLedgerEntry(
          invoice.customer_id,
          todayDate,
          'RETURN',
          invoice.invoice_no,
          0,
          netReturn,
          `Return on Invoice ${invoice.invoice_no}${deduction > 0 ? ` (fee: $${deduction.toFixed(2)})` : ''}`
        );

        // Credit memos remain visible as ledger credits; ACC-13 removes
        // the parallel credit_balance column writer.
      }
      else if (resolvedDisposition === 'adjust') {
        // ----------------------------------------------------------------
        // ADJUST: Apply the return credit to unpaid/partially-paid invoices
        // Creates a PAYMENT entry (not zero-amount) so the credit is
        // clearly visible as a payment against the target invoice.
        // The RETURN entry above serves as the audit trail for the return itself.
        // ----------------------------------------------------------------

        let remainingCredit = netReturn;

        // Determine which invoices to adjust
        let targetInvoiceIds = adjust_invoice_ids;

        if (!targetInvoiceIds || targetInvoiceIds.length === 0) {
          // Auto-fetch oldest unpaid/partially-paid invoices for this customer
          const unpaidInvoices = db.prepare(`
            SELECT id FROM invoices
            WHERE customer_id = ? AND status IN ('Unpaid', 'Partially Paid')
              AND balance_amount > 0
            ORDER BY invoice_date ASC, id ASC
          `).all(invoice.customer_id) as Array<{ id: number }>;

          targetInvoiceIds = unpaidInvoices.map((inv: { id: number }) => inv.id);
        }

        if (!targetInvoiceIds || targetInvoiceIds.length === 0) {
          throw new Error('No unpaid invoices found to adjust against');
        }

        for (const targetInvoiceId of targetInvoiceIds) {
          if (remainingCredit <= 0) break;

          const targetInvoice = db.prepare(
            `SELECT id, invoice_no, total_amount, paid_amount, balance_amount, status FROM invoices WHERE id = ?`
          ).get(targetInvoiceId) as {
            id: number; invoice_no: string; total_amount: number;
            paid_amount: number; balance_amount: number; status: string;
          } | undefined;

          if (!targetInvoice) continue;
          if (targetInvoice.balance_amount <= 0) continue;

          const allocAmount = Math.min(remainingCredit, targetInvoice.balance_amount);

          // Generate a payment number for the return credit
          const adjustPaymentNo = InvoiceModel.generatePaymentNoAtomic(db);

          // Create a payment record with the actual credit amount
          const adjustPaymentId = InvoiceModel.createPayment(
            db,
            adjustPaymentNo,
            invoice.customer_id,
            todayDate,
            allocAmount,
            'Credit',
            null,
            `Return credit from ${invoice.invoice_no} applied to ${targetInvoice.invoice_no}`
          );

          // Allocate the credit to the target invoice
          InvoiceModel.createPaymentAllocation(db, adjustPaymentId, targetInvoiceId, allocAmount);

          // For ADJUST, we create PAYMENT ledger entries (credit reduces AR)
          // but do NOT create a separate RETURN entry above to avoid double-counting.
          createLedgerEntry(
            invoice.customer_id,
            todayDate,
            'PAYMENT',
            adjustPaymentNo,
            0,
            allocAmount,
            `Return credit from ${invoice.invoice_no} applied to ${targetInvoice.invoice_no}`
          );

          // Recalculate target invoice balance and status
          calculateInvoiceBalance(targetInvoiceId);
          updateInvoiceStatus(targetInvoiceId);

          remainingCredit -= allocAmount;
        }

        // Leftover credit stays visible as ledger credits only; ACC-13
        // removed the parallel credit_balance column writer.
      }

      // ==================================================================
      // FINALIZE
      // ==================================================================

      // Recalculate return invoice balance and status
      calculateInvoiceBalance(invoiceId);
      updateInvoiceStatus(invoiceId);

      // Sync the customer's current_balance and credit_balance-aware total
      recalcCustomerBalanceFromLedger(invoice.customer_id);

      // Log the return activity (include disposition info)
      const dispositionLabels: Record<string, string> = {
        refund: 'Refund to customer',
        credit: 'Customer credit',
        adjust: 'Adjusted against unpaid invoice(s)',
      };

      logCRUD('INVOICE_RETURN', 'Invoice', invoiceId,
        `Return processed for ${processedItems.length} item(s) on Invoice ${invoice.invoice_no}` +
        ` — Disposition: ${dispositionLabels[resolvedDisposition] || resolvedDisposition}` +
        `${reason ? '. Reason: ' + reason : ''}`,
        userId,
        { disposition: resolvedDisposition, processedItems: processedItems.length },
        {
          reason: reason || (dispositionLabels[resolvedDisposition] || resolvedDisposition),
          correlationId: newCorrelationId()
        });

      return {
        returnedItems: processedItems,
        totalItems: processedItems.length,
        disposition: resolvedDisposition,
        returnAmount,
        netReturn,
        deduction,
      };
    });

    const result = transaction();
    res.json({ success: true, message: 'Return processed successfully', data: result });
  } catch (error: unknown) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    logger.error('Return invoice items error:', { error: errorMessage });
    res.status(400).json({ error: errorMessage });
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
  cancelInvoice,
  getInvoicePayments,
  returnInvoiceItems,
  getInvoiceReturnHistory,
};

export default {
  getInvoices,
  getInvoice,
  createInvoice,
  updateInvoice,
  deleteInvoice,
  cancelInvoice,
  getInvoicePayments,
  returnInvoiceItems,
  getInvoiceReturnHistory,
};
