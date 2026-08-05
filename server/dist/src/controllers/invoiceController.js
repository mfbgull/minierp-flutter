"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.getInvoices = getInvoices;
exports.getInvoice = getInvoice;
exports.createInvoice = createInvoice;
exports.updateInvoice = updateInvoice;
exports.deleteInvoice = deleteInvoice;
exports.cancelInvoice = cancelInvoice;
exports.getInvoicePayments = getInvoicePayments;
exports.returnInvoiceItems = returnInvoiceItems;
exports.getInvoiceReturnHistory = getInvoiceReturnHistory;
const database_1 = __importDefault(require("../config/database"));
const StockMovement_1 = __importDefault(require("../models/StockMovement"));
const Invoice_1 = __importDefault(require("../models/Invoice"));
const Payment_1 = __importDefault(require("../models/Payment"));
const accountingService_1 = __importDefault(require("../services/accountingService"));
const ledgerUtils_1 = __importDefault(require("../utils/ledgerUtils"));
const logger_1 = __importDefault(require("../utils/logger"));
const queryUtils_1 = require("../utils/queryUtils");
const currency_1 = require("../utils/currency");
const { createLedgerEntry, updateCustomerBalance, calculateInvoiceBalance, updateInvoiceStatus, } = ledgerUtils_1.default;
// ============ Controllers ============
/**
 * GET /api/invoices
 * Retrieve all invoices with optional filters.
 */
function getInvoices(req, res) {
    try {
        const { customerId, status } = req.query;
        const filters = {};
        if (customerId) {
            filters.customer_id = parseInt(customerId, 10);
        }
        if (status) {
            const statusList = status.split(',').map((s) => s.trim());
            let invoices = Invoice_1.default.getByStatus(statusList, database_1.default);
            if (customerId) {
                const cid = parseInt(customerId, 10);
                invoices = invoices.filter(inv => inv.customer_id === cid);
            }
            res.json({ success: true, data: invoices });
            return;
        }
        const invoices = Invoice_1.default.getAll(filters, database_1.default);
        res.json({ success: true, data: invoices });
    }
    catch (error) {
        logger_1.default.error('Get invoices error:', { error });
        res.status(500).json({ error: 'Failed to fetch invoices' });
    }
}
function getInvoice(req, res) {
    try {
        const id = parseInt(Array.isArray(req.params.id) ? req.params.id[0] : req.params.id, 10);
        const invoice = Invoice_1.default.getWithCustomer(id, database_1.default);
        if (!invoice) {
            return res.status(404).json({ error: 'Invoice not found' });
        }
        invoice.items = Invoice_1.default.getItems(id, database_1.default);
        res.json(invoice);
    }
    catch (error) {
        logger_1.default.error('Get invoice error:', { error });
        res.status(500).json({ error: 'Failed to fetch invoice' });
    }
}
/**
 * POST /api/invoices
 * Create a new invoice. Payment recording, ledger entries, stock movements,
 * and customer balance updates all happen inside a single transaction.
 */
function createInvoice(req, res) {
    try {
        const { invoice_no, customer_id, invoice_date, due_date, status = 'Unpaid', discount_scope, discount_type, discount_value, items, notes, terms, total_amount, record_payment, payment, } = req.body;
        if (!customer_id || !invoice_date || !items || items.length === 0) {
            return res.status(400).json({ error: 'Customer, date, and items are required' });
        }
        const parsedCustomerId = parseInt(String(customer_id), 10);
        const userId = req.user.id;
        // === ENTIRE operation inside one transaction ===
        const transaction = database_1.default.transaction(() => {
            const totalAmountNum = (0, currency_1.parseCurrency)(total_amount);
            const paymentAmountNum = record_payment && payment
                ? (0, currency_1.parseCurrency)(payment.amount)
                : 0;
            // Determine initial paid/balance/status
            const initialPaidAmount = paymentAmountNum;
            const initialBalanceAmount = (0, currency_1.subtractCurrency)(totalAmountNum, paymentAmountNum);
            // Guard: payment cannot exceed the invoice total
            if (record_payment && payment && paymentAmountNum > totalAmountNum) {
                throw new Error(`Payment amount (${paymentAmountNum.toFixed(2)}) exceeds invoice total (${totalAmountNum.toFixed(2)})`);
            }
            let initialStatus;
            if (record_payment && payment && paymentAmountNum > 0) {
                initialStatus = paymentAmountNum >= totalAmountNum ? 'Paid' : 'Partially Paid';
            }
            else {
                initialStatus = status || 'Unpaid';
            }
            // Insert invoice
            // CRITICAL-1 fix: pass the controller-computed initial paid and
            // balance through to the model so the monetary columns on the
            // invoice header match the payment that is about to be recorded
            // below. Previously these were hard-coded to 0/total, leaving
            // the A/R ledger inconsistent with payment_allocations.
            const invoiceId = Invoice_1.default.createInvoice(database_1.default, {
                invoice_no,
                customer_id: parsedCustomerId,
                invoice_date,
                due_date,
                status: initialStatus,
                total_amount: totalAmountNum,
                paid_amount: initialPaidAmount,
                balance_amount: initialBalanceAmount,
                notes,
                discount_scope,
                discount_type,
                discount_value,
                terms,
                items
            }, userId);
            // Insert invoice items and deduct stock via FIFO batch consumption
            let cogsTotal = 0;
            for (const item of items) {
                const warehouseId = Invoice_1.default.findWarehouseForItem(database_1.default, item.item_id, item.quantity, item.warehouse_id);
                Invoice_1.default.createInvoiceItem(database_1.default, invoiceId, {
                    item_id: item.item_id,
                    quantity: item.quantity,
                    unit_price: item.unit_price,
                    tax_rate: item.tax_rate,
                    discount_type: item.discount_type,
                    discount_value: item.discount_value
                });
                // FIFO consumption from oldest batches
                const consumption = Invoice_1.default.consumeFromOldestBatches(item.item_id, warehouseId, item.quantity, database_1.default);
                // Create one stock movement per consumed batch with actual COGS
                for (const entry of consumption) {
                    const batchLabel = entry.batchId ? `(batch ${entry.batchId})` : '(legacy stock)';
                    StockMovement_1.default.recordMovement({
                        item_id: item.item_id,
                        warehouse_id: warehouseId,
                        movement_type: 'SALE',
                        quantity: -entry.consumed,
                        unit_cost: entry.unitCost,
                        reference_doctype: 'INVOICE',
                        reference_docno: invoice_no,
                        remarks: `Sold via Invoice ${invoice_no} ${batchLabel}`,
                        movement_date: invoice_date,
                        batch_id: entry.batchId ?? undefined,
                    }, userId, database_1.default);
                    cogsTotal += entry.consumed * entry.unitCost;
                }
            }
            // Create customer ledger entry (debit to increase AR)
            createLedgerEntry(parsedCustomerId, 'INVOICE', invoice_no, totalAmountNum, // debit
            0, // credit
            `Invoice ${invoice_no}`);
            // Post the sales invoice to the GL (Dr AR / Cr Sales Revenue net / Cr Tax Payable).
            // GL Phase-2 wiring: every new invoice auto-posts a journal
            // entry. This brings the new TB and BS into alignment over
            // time as new activity flows through.
            // MAJOR-5 fix: tax is now split out into a separate Tax Payable line
            // when items have tax_rate > 0.
            const computedTaxAmount = items.reduce((sum, item) => {
                const lineAmount = item.quantity * item.unit_price;
                return sum + lineAmount * ((item.tax_rate || 0) / 100);
            }, 0);
            accountingService_1.default.postInvoiceEntry(database_1.default, {
                invoiceId,
                invoiceNo: invoice_no,
                totalAmount: totalAmountNum,
                invoiceDate: invoice_date,
                userId,
                taxAmount: computedTaxAmount,
            });
            // Post COGS: Dr COGS, Cr Inventory Asset at actual FIFO cost
            if (cogsTotal > 0) {
                accountingService_1.default.postCOGSEntry(database_1.default, {
                    invoiceId,
                    invoiceNo: invoice_no,
                    cogsAmount: (0, currency_1.parseCurrency)(cogsTotal),
                    invoiceDate: invoice_date,
                    userId,
                });
            }
            // --- FIX #2: Payment recording INSIDE transaction ---
            if (record_payment && payment && paymentAmountNum > 0) {
                // FIX #5: Atomic payment number generation
                const newPaymentNo = Invoice_1.default.generatePaymentNoAtomic(database_1.default);
                const paymentId = Invoice_1.default.createPayment(database_1.default, newPaymentNo, parsedCustomerId, payment.payment_date, paymentAmountNum, payment.payment_method, payment.reference_no, payment.notes);
                // Payment allocation
                Invoice_1.default.createPaymentAllocation(database_1.default, paymentId, invoiceId, paymentAmountNum);
                // Ledger entry for payment (credit to reduce AR)
                Invoice_1.default.createLedgerEntry(database_1.default, parsedCustomerId, 'PAYMENT', newPaymentNo, 0, paymentAmountNum, `Payment ${newPaymentNo} for Invoice ${invoice_no}`);
                // Post the payment to the GL (Dr Cash / Cr AR). Cash vs Bank
                // is determined by payment_method.
                accountingService_1.default.postPaymentEntry(database_1.default, {
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
            ledgerUtils_1.default.updateCustomerBalance(parsedCustomerId);
            return invoiceId;
        });
        const invoiceId = transaction();
        const createdInvoice = Invoice_1.default.getWithCustomer(invoiceId, database_1.default);
        res.status(201).json(createdInvoice);
    }
    catch (error) {
        // FIX #7: Generic error message, log detail server-side
        const errorMessage = error instanceof Error ? error.message : 'Unknown error';
        const errorCode = error.code;
        logger_1.default.error('Create invoice error:', { error: errorMessage, code: errorCode, stack: error instanceof Error ? error.stack : undefined });
        res.status(500).json({ error: 'Failed to create invoice' });
    }
}
/**
 * PUT /api/invoices/:id
 * Update an existing invoice. Reverses old stock movements before
 * applying new ones. Payment changes and customer balance updates
 * are all inside the transaction.
 */
function updateInvoice(req, res) {
    try {
        const { id } = req.params;
        const invoiceId = parseInt(id, 10);
        const { invoice_no, customer_id, invoice_date, due_date, status, discount_scope, discount_type, discount_value, items, notes, terms, total_amount, deleted_payments, record_payment, payment, } = req.body;
        if (!customer_id || !invoice_date || !items || items.length === 0) {
            return res.status(400).json({ error: 'Customer, date, and items are required' });
        }
        const parsedCustomerId = parseInt(String(customer_id), 10);
        const userId = req.user.id;
        // Fast-fail check outside transaction
        const invoiceExists = Invoice_1.default.getById(invoiceId, database_1.default);
        if (!invoiceExists) {
            return res.status(404).json({ error: 'Invoice not found' });
        }
        const transaction = database_1.default.transaction(() => {
            // Re-read invoice INSIDE transaction for fresh data
            const originalInvoice = Invoice_1.default.getById(invoiceId, database_1.default);
            if (!originalInvoice)
                throw new Error('Invoice not found');
            // Fallback to original invoice_no if not provided in request
            const resolvedInvoiceNo = invoice_no || originalInvoice.invoice_no;
            // === Handle deleted payments ===
            if (deleted_payments && Array.isArray(deleted_payments) && deleted_payments.length > 0) {
                for (const deletedPaymentId of deleted_payments) {
                    const paymentInfo = Payment_1.default.getById(database_1.default, deletedPaymentId);
                    if (paymentInfo) {
                        Invoice_1.default.deleteLedgerEntryByReference(database_1.default, paymentInfo.payment_no);
                    }
                    const allocations = Payment_1.default.getAllocationsByPaymentId(database_1.default, deletedPaymentId);
                    Payment_1.default.deleteAllocationsByPaymentId(database_1.default, deletedPaymentId);
                    Payment_1.default.delete(database_1.default, deletedPaymentId);
                    // Recalculate balance for each affected invoice using
                    // the common helper (which accounts for returned_amount)
                    for (const alloc of allocations) {
                        calculateInvoiceBalance(alloc.invoice_id);
                        updateInvoiceStatus(alloc.invoice_id);
                    }
                }
            }
            // Rebuild running balances after deleting payment ledger entries
            ledgerUtils_1.default.rebuildLedgerBalances(parsedCustomerId);
            // === Handle new payment recording (FIX #2: inside transaction) ===
            let newPaymentAmount;
            if (record_payment && payment && (0, currency_1.parseCurrency)(payment.amount) > 0) {
                newPaymentAmount = (0, currency_1.parseCurrency)(payment.amount);
                // FIX #5: Atomic payment number generation
                const newPaymentNo = Invoice_1.default.generatePaymentNoAtomic(database_1.default);
                const newPaymentId = Invoice_1.default.createPayment(database_1.default, newPaymentNo, parsedCustomerId, payment.payment_date, newPaymentAmount, payment.payment_method, payment.reference_no, payment.notes);
                Invoice_1.default.createPaymentAllocation(database_1.default, newPaymentId, invoiceId, newPaymentAmount);
                // Ledger entry for payment (credit to reduce AR)
                Invoice_1.default.createLedgerEntry(database_1.default, parsedCustomerId, 'PAYMENT', newPaymentNo, 0, newPaymentAmount, `Payment ${newPaymentNo} for Invoice ${resolvedInvoiceNo}`);
            }
            // === Recalculate paid/balance (accounting for returned_amount) ===
            const paidResult = Payment_1.default.getTotalPaidByInvoiceId(database_1.default, invoiceId);
            const totalPaid = (0, currency_1.parseCurrency)(paidResult);
            const totalAmountNum = (0, currency_1.parseCurrency)(total_amount);
            const returnedAmt = (0, currency_1.parseCurrency)(originalInvoice?.returned_amount || 0);
            const newBalanceAmount = Math.max(0, (0, currency_1.subtractCurrency)((0, currency_1.subtractCurrency)(totalAmountNum, totalPaid), returnedAmt));
            // Determine status (considering returned amount)
            let newStatus;
            const fullyReturned = returnedAmt >= totalAmountNum && totalAmountNum > 0;
            if (fullyReturned) {
                newStatus = 'Returned';
            }
            else if (newBalanceAmount <= 0 && totalAmountNum > 0) {
                newStatus = 'Paid';
            }
            else if (newBalanceAmount > 0 && newBalanceAmount < totalAmountNum) {
                newStatus = 'Partially Paid';
            }
            else {
                newStatus = status || 'Unpaid';
            }
            // Update invoice record
            Invoice_1.default.updateInvoice(database_1.default, invoiceId, {
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
            const oldItems = Invoice_1.default.getInvoiceItemsForStockReverse(database_1.default, invoiceId);
            Invoice_1.default.reverseStockForItems(database_1.default, oldItems, originalInvoice.invoice_no, userId, 'INVOICE_UPDATE');
            Invoice_1.default.deleteInvoiceItems(database_1.default, invoiceId);
            // Insert new invoice items and create new stock movements
            for (const item of items) {
                Invoice_1.default.createInvoiceItem(database_1.default, invoiceId, {
                    item_id: item.item_id,
                    quantity: item.quantity,
                    unit_price: item.unit_price,
                    tax_rate: item.tax_rate,
                    discount_type: item.discount_type,
                    discount_value: item.discount_value
                });
                // FIX #3: Stock validation with warning
                const warehouseId = Invoice_1.default.findWarehouseForItem(database_1.default, item.item_id, item.quantity, item.warehouse_id);
                // FIFO batch consumption for new/updated items
                const consumption = Invoice_1.default.consumeFromOldestBatches(item.item_id, warehouseId, item.quantity, database_1.default);
                // Create one stock movement per consumed batch with actual COGS
                for (const entry of consumption) {
                    const batchLabel = entry.batchId ? `(batch ${entry.batchId})` : '(legacy stock)';
                    StockMovement_1.default.recordMovement({
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
                    }, userId, database_1.default);
                }
            }
            // Update ledger entry for the invoice if total changed
            // Delete old invoice ledger entry and recreate with new amount
            Invoice_1.default.deleteLedgerEntryByReference(database_1.default, resolvedInvoiceNo);
            Invoice_1.default.createLedgerEntry(database_1.default, parsedCustomerId, 'INVOICE', resolvedInvoiceNo, totalAmountNum, 0, `Invoice ${resolvedInvoiceNo} (updated)`);
            // --- FIX #6: Customer balance update inside transaction ---
            if (originalInvoice.customer_id !== parsedCustomerId) {
                ledgerUtils_1.default.updateCustomerBalance(originalInvoice.customer_id);
            }
            ledgerUtils_1.default.updateCustomerBalance(parsedCustomerId);
            // Update invoice status and balance
            updateInvoiceStatus(invoiceId);
        });
        transaction();
        const updatedInvoice = Invoice_1.default.getWithCustomer(invoiceId, database_1.default);
        res.json(updatedInvoice);
    }
    catch (error) {
        const errorMessage = error instanceof Error ? error.message : String(error);
        const errorName = error instanceof Error ? error.name : 'Unknown';
        logger_1.default.error('Update invoice error:', { error: errorMessage, name: errorName, stack: error instanceof Error ? error.stack : undefined });
        res.status(500).json({ error: 'Failed to update invoice' });
    }
}
/**
 * DELETE /api/invoices/:id
 * Delete an invoice, reversing all stock movements, cleaning up payments,
 * allocations, and ledger entries.
 */
function deleteInvoice(req, res) {
    try {
        const { id } = req.params;
        const invoiceId = parseInt(id, 10);
        const userId = req.user.id;
        const invoice = Invoice_1.default.getById(invoiceId, database_1.default);
        if (!invoice) {
            return res.status(404).json({ error: 'Invoice not found' });
        }
        // Block deletion of paid, returned, or cancelled invoices.
        // Only Draft and Unpaid invoices with no payments or returns may be deleted.
        const paidAmount = (0, currency_1.parseCurrency)(invoice.paid_amount);
        const returnedAmount = (0, currency_1.parseCurrency)(invoice.returned_amount);
        const deletableStatuses = ['Draft', 'Unpaid'];
        if (!deletableStatuses.includes(invoice.status) || paidAmount > 0 || returnedAmount > 0) {
            return res.status(400).json({
                error: 'Cannot delete this invoice. Only unpaid/draft invoices with no payments or returns can be deleted. Use Cancel instead.'
            });
        }
        const transaction = database_1.default.transaction(() => {
            // Re-read invoice INSIDE transaction for fresh data
            const freshInvoice = Invoice_1.default.getById(invoiceId, database_1.default);
            if (!freshInvoice)
                throw new Error('Invoice not found');
            const invoiceItems = Invoice_1.default.getItemsForStockReverse(invoiceId, database_1.default);
            // Clean up payment allocations and orphaned payments
            const allocations = Payment_1.default.getAllocationsByInvoiceId(database_1.default, invoiceId);
            for (const alloc of allocations) {
                const otherAllocations = Payment_1.default.getAllocationsByPaymentId(database_1.default, alloc.payment_id);
                if (otherAllocations.length === 0) {
                    const paymentInfo = Payment_1.default.getById(database_1.default, alloc.payment_id);
                    if (paymentInfo) {
                        Invoice_1.default.deleteLedgerEntryByReference(database_1.default, paymentInfo.payment_no);
                        // Void the payment's journal_lines entries (Dr Cash / Cr AR)
                        accountingService_1.default.voidJournalLinesByReference(database_1.default, 'PAYMENT', alloc.payment_id);
                    }
                    Payment_1.default.delete(database_1.default, alloc.payment_id);
                }
            }
            // Reverse stock movements (before deleting invoice items — reversal looks up SALE movements by invoice_no)
            Invoice_1.default.reverseStockForItems(database_1.default, invoiceItems, freshInvoice.invoice_no, userId, 'INVOICE_DELETE');
            // Void the invoice's journal_lines entries (Dr AR / Cr Sales Revenue / Cr Tax Payable)
            accountingService_1.default.voidJournalLinesByReference(database_1.default, 'INVOICE', invoiceId);
            // Also void any return-related journal_lines (Cr AR / Dr Sales Returns / Dr Tax Payable / Dr Inventory / Cr COGS)
            accountingService_1.default.voidJournalLinesByReference(database_1.default, 'INVOICE_RETURN', invoiceId);
            // Delete invoice items after stock reversal is complete
            Invoice_1.default.deleteInvoiceItems(database_1.default, invoiceId);
            // Delete related ledger entries
            Invoice_1.default.deleteLedgerEntryByReference(database_1.default, freshInvoice.invoice_no);
            // Rebuild running balances so remaining ledger rows are consistent
            ledgerUtils_1.default.rebuildLedgerBalances(freshInvoice.customer_id);
            // Delete invoice
            Invoice_1.default.deleteInvoice(database_1.default, invoiceId);
            // Recalculate customer's current_balance now that the invoice is gone
            ledgerUtils_1.default.updateCustomerBalance(freshInvoice.customer_id);
        });
        transaction();
        res.status(200).json({ message: 'Invoice deleted successfully' });
    }
    catch (error) {
        logger_1.default.error('Delete invoice error:', { error });
        res.status(500).json({ error: 'Failed to delete invoice' });
    }
}
/**
 * PUT /api/invoices/:id/cancel
 * Cancel an invoice. Sets status to 'Cancelled' without reversing stock,
 * payments, or returns. The invoice data is preserved for audit purposes.
 */
function cancelInvoice(req, res) {
    try {
        const { id } = req.params;
        const invoiceId = parseInt(id, 10);
        const userId = req.user.id;
        const invoice = Invoice_1.default.getById(invoiceId, database_1.default);
        if (!invoice) {
            return res.status(404).json({ error: 'Invoice not found' });
        }
        if (invoice.status === 'Cancelled') {
            return res.status(400).json({ error: 'Invoice is already cancelled' });
        }
        const transaction = database_1.default.transaction(() => {
            // Update status to Cancelled
            database_1.default.prepare(`
        UPDATE invoices SET status = 'Cancelled', updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
      `).run(invoiceId);
            // Void the invoice's GL journal_lines (Dr AR / Cr Sales Revenue / Cr Tax Payable).
            // This also covers COGS entries since they use reference_type 'INVOICE'.
            // Do NOT void PAYMENT or INVOICE_RETURN lines — those are still valid
            // adjustments. The CANCELLATION ledger entry below handles the AR offset.
            accountingService_1.default.voidJournalLinesByReference(database_1.default, 'INVOICE', invoiceId);
            // Add a CANCELLED ledger entry (credit to offset the original debit)
            // This neutralizes the AR impact without deleting history
            createLedgerEntry(invoice.customer_id, 'CANCELLATION', invoice.invoice_no, 0, invoice.total_amount, `Invoice ${invoice.invoice_no} cancelled`);
            // Recalculate customer balance
            ledgerUtils_1.default.rebuildLedgerBalances(invoice.customer_id);
            ledgerUtils_1.default.updateCustomerBalance(invoice.customer_id);
            // Log the cancellation
            database_1.default.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(userId, 'CANCEL', 'Invoice', invoiceId, `Invoice ${invoice.invoice_no} cancelled`);
        });
        transaction();
        const updatedInvoice = Invoice_1.default.getWithCustomer(invoiceId, database_1.default);
        res.json({ success: true, message: 'Invoice cancelled successfully', data: updatedInvoice });
    }
    catch (error) {
        logger_1.default.error('Cancel invoice error:', { error });
        res.status(500).json({ error: 'Failed to cancel invoice' });
    }
}
function getInvoicePayments(req, res) {
    try {
        const invoiceId = parseInt(Array.isArray(req.params.id) ? req.params.id[0] : req.params.id, 10);
        const payments = Invoice_1.default.getPayments(invoiceId, database_1.default);
        res.json({ success: true, data: payments });
    }
    catch (error) {
        logger_1.default.error('Get invoice payments error:', { error });
        res.status(500).json({ error: 'Failed to fetch invoice payments' });
    }
}
/**
 * POST /api/invoices/:id/return
 * Process a return for invoice items — reverses stock using FIFO batch restoration
 * and creates ADJUSTMENT movements to add stock back into inventory.
 */
function returnInvoiceItems(req, res) {
    try {
        const { id } = req.params;
        const invoiceId = parseInt(id, 10);
        const userId = req.user.id;
        // Normalize payload: support both legacy format (items + reason at top level)
        // and new format from InvoiceReturn.tsx (items with reason inside each item, disposition, adjust_invoice_ids)
        const body = req.body;
        const rawItems = body.items;
        const rawDisposition = body.disposition;
        const rawAdjustInvoiceIds = body.adjust_invoice_ids;
        const rawReason = body.reason;
        const rawDeductionType = body.deduction_type; // 'percentage' | 'flat' | undefined
        const rawDeductionValue = Number(body.deduction_value) || 0;
        const returnItems = Array.isArray(rawItems) ? rawItems : [];
        const reason = rawReason || (returnItems.length > 0 ? returnItems[0].reason || '' : '');
        const disposition = rawDisposition;
        const adjust_invoice_ids = rawAdjustInvoiceIds;
        if (returnItems.length === 0) {
            return res.status(400).json({ error: 'Invalid request: items must be a non-empty array' });
        }
        // Fast-fail checks outside transaction
        const invoiceExists = Invoice_1.default.getById(invoiceId, database_1.default);
        if (!invoiceExists) {
            return res.status(404).json({ error: 'Invoice not found' });
        }
        if (invoiceExists.status === 'Cancelled') {
            return res.status(400).json({ error: 'Cannot return a cancelled invoice' });
        }
        // Default disposition: if invoice was paid, default to refund; otherwise default to credit
        const resolvedDisposition = disposition || (invoiceExists.balance_amount <= 0 ? 'refund' : 'credit');
        const transaction = database_1.default.transaction(() => {
            // Re-read invoice INSIDE transaction to get fresh returned_qty values
            // This prevents race conditions on concurrent return requests
            const invoice = Invoice_1.default.getById(invoiceId, database_1.default);
            if (!invoice) {
                throw new Error('Invoice not found');
            }
            const processedItems = [];
            let returnTotalTaxAmount = 0;
            for (const returnItem of returnItems) {
                // Re-fetch item from DB inside transaction to get fresh returned_qty
                const freshItem = database_1.default.prepare('SELECT ii.*, i.item_name FROM invoice_items ii LEFT JOIN items i ON ii.item_id = i.id WHERE ii.id = ? OR ii.item_id = ?').get(returnItem.invoice_item_id, returnItem.invoice_item_id);
                // Fallback to in-memory item if DB fetch fails
                const invoiceItem = freshItem || invoice.items?.find((ii) => ii.id === returnItem.invoice_item_id || ii.item_id === returnItem.invoice_item_id);
                if (!invoiceItem) {
                    throw new Error(`Invoice item ${returnItem.invoice_item_id} not found`);
                }
                if (returnItem.return_quantity <= 0) {
                    throw new Error('Return quantity must be positive');
                }
                const returnedQty = Number(invoiceItem.returned_qty) || 0;
                const availableQty = Number(invoiceItem.quantity) - returnedQty;
                if (returnItem.return_quantity > availableQty) {
                    throw new Error(`Return quantity (${returnItem.return_quantity}) exceeds available quantity (${availableQty}) for item ${invoiceItem.item_name}. Already returned: ${returnedQty}.`);
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
                }
                else if (itemDiscountType === 'flat' && itemDiscountValue > 0) {
                    lineAmount = Math.max(0, grossLineAmount - itemDiscountValue * Number(returnItem.return_quantity));
                }
                returnTotalTaxAmount += lineAmount * ((Number(invoiceItem.tax_rate) || 0) / 100);
                // Update per-item returned quantity tracking
                database_1.default.prepare(`UPDATE invoice_items SET returned_qty = returned_qty + ? WHERE id = ?`)
                    .run(returnItem.return_quantity, returnItem.invoice_item_id);
            }
            // Reverse stock for the returned items using the same batch-aware logic
            Invoice_1.default.reverseStockForItems(database_1.default, processedItems, invoice.invoice_no, userId, 'RETURN');
            // Calculate the total return amount (with item discounts applied)
            const returnAmount = processedItems.reduce((sum, item) => {
                const grossAmount = Number(item.quantity) * Number(item.unit_price);
                const discountType = item.discount_type || 'percentage';
                const discountValue = Number(item.discount_value) || 0;
                let netAmount = grossAmount;
                if (discountType === 'percentage' && discountValue > 0) {
                    netAmount = grossAmount * (1 - discountValue / 100);
                }
                else if (discountType === 'flat' && discountValue > 0) {
                    netAmount = Math.max(0, grossAmount - discountValue * Number(item.quantity));
                }
                return sum + netAmount;
            }, 0);
            const todayDate = new Date().toISOString().split('T')[0];
            // Compute deduction (restocking fee) if applicable
            const deductionType = rawDeductionType === 'percentage' ? 'percentage' : 'flat';
            let deduction = 0;
            if (rawDeductionValue > 0) {
                if (deductionType === 'percentage') {
                    deduction = returnAmount * (rawDeductionValue / 100);
                }
                else {
                    deduction = Math.min(rawDeductionValue, returnAmount);
                }
            }
            const netReturn = returnAmount - deduction;
            // Post GL reversal — reverse AR by net, reverse revenue by gross, record fee
            accountingService_1.default.postInvoiceReturnEntry(database_1.default, {
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
                const saleMovements = database_1.default.prepare(`
          SELECT quantity, unit_cost, batch_id
          FROM stock_movements
          WHERE item_id = ? AND reference_docno = ? AND movement_type = 'SALE'
          ORDER BY id
        `).all(item.item_id, invoice.invoice_no);
                if (saleMovements.length === 0)
                    continue;
                const totalSold = saleMovements.reduce((sum, m) => sum + Math.abs(m.quantity), 0);
                const ratio = totalSold > 0 ? Math.min(Math.abs(item.quantity) / totalSold, 1) : 1;
                for (const movement of saleMovements) {
                    returnCogsTotal += Math.abs(movement.quantity) * movement.unit_cost * ratio;
                }
            }
            if (returnCogsTotal > 0) {
                accountingService_1.default.postCOGSReversalEntry(database_1.default, {
                    invoiceId,
                    invoiceNo: invoice.invoice_no,
                    cogsAmount: (0, currency_1.parseCurrency)(returnCogsTotal),
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
                throw new Error(`Cannot return more than the invoice total. ` +
                    `Already returned: ${(0, currency_1.parseCurrency)(currentReturned)}, ` +
                    `this return: ${(0, currency_1.parseCurrency)(returnAmount)}, ` +
                    `invoice total: ${(0, currency_1.parseCurrency)(invoiceTotal)}.`);
            }
            // Update returned_amount (+gross) and return_fee (+deduction)
            database_1.default.prepare(`UPDATE invoices SET returned_amount = returned_amount + ?, return_fee = return_fee + ? WHERE id = ?`).run(returnAmount.toFixed(2), deduction.toFixed(2), invoiceId);
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
                createLedgerEntry(invoice.customer_id, 'RETURN', invoice.invoice_no, 0, netReturn, `Return on Invoice ${invoice.invoice_no}${deduction > 0 ? ` (fee: $${deduction.toFixed(2)})` : ''}`);
                // ----------------------------------------------------------------
                // REFUND: Create a refund payment (negative payment record),
                // reverse/fraction the original payment allocation, post GL entry
                // ----------------------------------------------------------------
                const refundPaymentNo = Invoice_1.default.generatePaymentNoAtomic(database_1.default);
                // Create a refund payment (negative amount) — refund only the net
                const refundPaymentId = Invoice_1.default.createPayment(database_1.default, refundPaymentNo, invoice.customer_id, todayDate, -netReturn, // negative = money going out — only net is refunded
                invoice.paid_amount > 0 ? 'Cash' : 'Cash', null, `Refund for return on ${invoice.invoice_no}${deduction > 0 ? ` (fee: $${deduction.toFixed(2)})` : ''}`);
                // Record a refund allocation (negative allocation = reduction of original payment)
                Invoice_1.default.createPaymentAllocation(database_1.default, refundPaymentId, invoiceId, -netReturn);
                // Ledger entry: Dr (debit) the refund payment no. to reflect cash out
                createLedgerEntry(invoice.customer_id, 'REFUND', refundPaymentNo, netReturn, // debit = customer owes us more (contra)
                0, `Refund ${refundPaymentNo} for return on ${invoice.invoice_no}`);
                // Post GL entry for refund: Dr Sales Returns (already done above in postInvoiceReturnEntry),
                // but also need to reverse the cash side: Dr AR (credit the original overpayment) / Cr Cash
                // Since postInvoiceReturnEntry already credited AR, we need an additional entry
                // that reverses the cash impact: Dr AR / Cr Cash (refund paid out)
                accountingService_1.default.postRefundEntry(database_1.default, {
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
                createLedgerEntry(invoice.customer_id, 'RETURN', invoice.invoice_no, 0, netReturn, `Return on Invoice ${invoice.invoice_no}${deduction > 0 ? ` (fee: $${deduction.toFixed(2)})` : ''}`);
                const currentCreditBalance = database_1.default.prepare(`SELECT credit_balance FROM customers WHERE id = ?`).get(invoice.customer_id);
                const newCreditBalance = (currentCreditBalance?.credit_balance || 0) + netReturn;
                database_1.default.prepare(`UPDATE customers SET credit_balance = ? WHERE id = ?`).run(newCreditBalance, invoice.customer_id);
                // Already created a RETURN ledger entry above with the credit
                // No additional GL entry needed — the credit balance is tracked separately
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
                    const unpaidInvoices = database_1.default.prepare(`
            SELECT id FROM invoices
            WHERE customer_id = ? AND status IN ('Unpaid', 'Partially Paid')
              AND balance_amount > 0
            ORDER BY invoice_date ASC, id ASC
          `).all(invoice.customer_id);
                    targetInvoiceIds = unpaidInvoices.map((inv) => inv.id);
                }
                if (!targetInvoiceIds || targetInvoiceIds.length === 0) {
                    throw new Error('No unpaid invoices found to adjust against');
                }
                for (const targetInvoiceId of targetInvoiceIds) {
                    if (remainingCredit <= 0)
                        break;
                    const targetInvoice = database_1.default.prepare(`SELECT id, invoice_no, total_amount, paid_amount, balance_amount, status FROM invoices WHERE id = ?`).get(targetInvoiceId);
                    if (!targetInvoice)
                        continue;
                    if (targetInvoice.balance_amount <= 0)
                        continue;
                    const allocAmount = Math.min(remainingCredit, targetInvoice.balance_amount);
                    // Generate a payment number for the return credit
                    const adjustPaymentNo = Invoice_1.default.generatePaymentNoAtomic(database_1.default);
                    // Create a payment record with the actual credit amount
                    const adjustPaymentId = Invoice_1.default.createPayment(database_1.default, adjustPaymentNo, invoice.customer_id, todayDate, allocAmount, 'Credit', null, `Return credit from ${invoice.invoice_no} applied to ${targetInvoice.invoice_no}`);
                    // Allocate the credit to the target invoice
                    Invoice_1.default.createPaymentAllocation(database_1.default, adjustPaymentId, targetInvoiceId, allocAmount);
                    // For ADJUST, we create PAYMENT ledger entries (credit reduces AR)
                    // but do NOT create a separate RETURN entry above to avoid double-counting.
                    createLedgerEntry(invoice.customer_id, 'PAYMENT', adjustPaymentNo, 0, allocAmount, `Return credit from ${invoice.invoice_no} applied to ${targetInvoice.invoice_no}`);
                    // Recalculate target invoice balance and status
                    calculateInvoiceBalance(targetInvoiceId);
                    updateInvoiceStatus(targetInvoiceId);
                    remainingCredit -= allocAmount;
                }
                if (remainingCredit > 0) {
                    // If there's leftover credit, add it to customer's credit_balance
                    const currentCreditBalance = database_1.default.prepare(`SELECT credit_balance FROM customers WHERE id = ?`).get(invoice.customer_id);
                    const newCreditBalance = (currentCreditBalance?.credit_balance || 0) + remainingCredit;
                    database_1.default.prepare(`UPDATE customers SET credit_balance = ? WHERE id = ?`).run(newCreditBalance, invoice.customer_id);
                }
            }
            // ==================================================================
            // FINALIZE
            // ==================================================================
            // Recalculate return invoice balance and status
            calculateInvoiceBalance(invoiceId);
            updateInvoiceStatus(invoiceId);
            // Sync the customer's current_balance and credit_balance-aware total
            updateCustomerBalance(invoice.customer_id);
            // Log the return activity (include disposition info)
            const dispositionLabels = {
                refund: 'Refund to customer',
                credit: 'Customer credit',
                adjust: 'Adjusted against unpaid invoice(s)',
            };
            database_1.default.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(userId, 'RETURN', 'Invoice', invoiceId, `Return processed for ${processedItems.length} item(s) on Invoice ${invoice.invoice_no}` +
                ` — Disposition: ${dispositionLabels[resolvedDisposition] || resolvedDisposition}` +
                `${reason ? '. Reason: ' + reason : ''}`);
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
    }
    catch (error) {
        const errorMessage = error instanceof Error ? error.message : 'Unknown error';
        logger_1.default.error('Return invoice items error:', { error: errorMessage });
        res.status(400).json({ error: errorMessage });
    }
}
/**
 * GET /api/invoices/returns
 * Retrieve invoice return history from stock movements.
 */
function getInvoiceReturnHistory(req, res) {
    try {
        const startDateParam = (0, queryUtils_1.getQueryParam)(req.query.start_date);
        const endDateParam = (0, queryUtils_1.getQueryParam)(req.query.end_date);
        const itemIdParam = (0, queryUtils_1.getQueryParam)(req.query.item_id);
        const limitParam = (0, queryUtils_1.getQueryParam)(req.query.limit);
        const filters = {
            start_date: startDateParam,
            end_date: endDateParam,
            item_id: itemIdParam ? Number(itemIdParam) : undefined,
            limit: limitParam ? parseInt(String(limitParam)) : undefined
        };
        const returns = Invoice_1.default.getReturnHistory(filters, database_1.default);
        res.json(returns);
    }
    catch (error) {
        logger_1.default.error('Get invoice return history error:', { error });
        res.status(500).json({ error: 'Failed to get invoice return history' });
    }
}
exports.default = {
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
//# sourceMappingURL=invoiceController.js.map