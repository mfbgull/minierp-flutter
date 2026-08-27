"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const queryUtils_1 = require("../utils/queryUtils");
const activityLogger_1 = require("../services/activityLogger");
const database_1 = __importDefault(require("../config/database"));
const queryUtils_2 = require("../utils/queryUtils");
const sqlSanitizer_1 = require("../utils/sqlSanitizer");
const logger_1 = __importDefault(require("../utils/logger"));
const currency_1 = require("../utils/currency");
const Payment_1 = __importDefault(require("../models/Payment"));
const Customer_1 = __importDefault(require("../models/Customer"));
const ledgerUtils_1 = __importDefault(require("../utils/ledgerUtils"));
const Invoice_1 = __importDefault(require("../models/Invoice"));
const Supplier_1 = __importDefault(require("../models/Supplier"));
function getPayments(req, res) {
    try {
        const pageParam = (0, queryUtils_1.getQueryParam)(req.query.page);
        const limitParam = (0, queryUtils_1.getQueryParam)(req.query.limit);
        const searchParam = (0, queryUtils_1.getQueryParam)(req.query.search);
        const customerIdParam = (0, queryUtils_1.getQueryParam)(req.query.customerId);
        const supplierIdParam = (0, queryUtils_1.getQueryParam)(req.query.supplierId);
        const fromDateParam = (0, queryUtils_1.getQueryParam)(req.query.fromDate);
        const toDateParam = (0, queryUtils_1.getQueryParam)(req.query.toDate);
        const sortByParam = (0, queryUtils_1.getQueryParam)(req.query.sortBy);
        const sortOrderParam = (0, queryUtils_1.getQueryParam)(req.query.sortOrder);
        const filters = {
            page: parseInt(pageParam) || 1,
            limit: parseInt(limitParam) || 10,
            search: searchParam,
            customerId: customerIdParam,
            supplierId: supplierIdParam,
            fromDate: fromDateParam,
            toDate: toDateParam,
            sortBy: sortByParam,
            sortOrder: sortOrderParam,
        };
        const { payments, total, pageNum, limitNum } = Payment_1.default.getAll(database_1.default, filters, [...sqlSanitizer_1.PAYMENT_SORT_COLUMNS], 'payment_date', 'DESC');
        res.json({
            success: true, data: payments,
            pagination: { currentPage: pageNum, totalPages: Math.ceil(total / limitNum), totalItems: total, hasNext: pageNum < Math.ceil(total / limitNum), hasPrev: pageNum > 1 }
        });
    }
    catch (error) {
        logger_1.default.error('Error fetching payments:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch payments' });
    }
}
function getUnifiedPayments(req, res) {
    try {
        const filters = {
            page: parseInt((0, queryUtils_1.getQueryParam)(req.query.page)) || 1,
            limit: parseInt((0, queryUtils_1.getQueryParam)(req.query.limit)) || 10,
            search: (0, queryUtils_1.getQueryParam)(req.query.search),
            type: (0, queryUtils_1.getQueryParam)(req.query.type),
            fromDate: (0, queryUtils_1.getQueryParam)(req.query.fromDate),
            toDate: (0, queryUtils_1.getQueryParam)(req.query.toDate),
            sortBy: (0, queryUtils_1.getQueryParam)(req.query.sortBy),
            sortOrder: (0, queryUtils_1.getQueryParam)(req.query.sortOrder),
        };
        const { payments, total, pageNum, limitNum } = Payment_1.default.getUnifiedPayments(database_1.default, filters);
        res.json({
            success: true, data: payments,
            pagination: { currentPage: pageNum, totalPages: Math.ceil(total / limitNum), totalItems: total, hasNext: pageNum < Math.ceil(total / limitNum), hasPrev: pageNum > 1 }
        });
    }
    catch (error) {
        logger_1.default.error('Error fetching unified payments:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch unified payments' });
    }
}
function getPayment(req, res) {
    try {
        const id = parseInt(Array.isArray(req.params.id) ? req.params.id[0] : req.params.id, 10);
        const payment = Payment_1.default.getById(database_1.default, id);
        if (!payment) {
            res.status(404).json({ success: false, error: 'Payment not found' });
            return;
        }
        res.json({ success: true, data: payment });
    }
    catch (error) {
        logger_1.default.error('Error fetching payment:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch payment' });
    }
}
function createPayment(req, res) {
    try {
        const { customer_id, supplier_id, payment_date, amount, payment_method, reference_no, notes, invoice_allocations, po_allocations, purchase_allocations } = req.body;
        // PAY-09 (task 2.2): XOR — exactly one counterparty. The old `||` guard
        // admitted both ids and then silently discarded the supplier.
        if (!!customer_id === !!supplier_id) {
            res.status(400).json({ success: false, error: 'Exactly one of customer_id or supplier_id is required' });
            return;
        }
        if (!payment_date || !amount || amount <= 0) {
            res.status(400).json({ success: false, error: 'Payment date and a positive amount are required' });
            return;
        }
        const parsedAmount = (0, currency_1.parseCurrency)(amount);
        if (customer_id) {
            const parsedCustomerId = parseInt(customer_id, 10);
            if (!invoice_allocations || !Array.isArray(invoice_allocations) || invoice_allocations.length === 0) {
                res.status(400).json({ success: false, error: 'At least one invoice allocation is required for customer payments' });
                return;
            }
            if (!Customer_1.default.getById(parsedCustomerId, database_1.default)) {
                res.status(404).json({ success: false, error: 'Customer not found' });
                return;
            }
            for (const alloc of invoice_allocations) {
                const parsedInvoiceId = parseInt(alloc.invoice_id, 10);
                if (isNaN(parsedInvoiceId)) {
                    res.status(400).json({ success: false, error: `Invalid invoice ID: ${alloc.invoice_id}` });
                    return;
                }
                const invoice = Invoice_1.default.getById(parsedInvoiceId, database_1.default);
                if (!invoice) {
                    res.status(404).json({ success: false, error: `Invoice ${parsedInvoiceId} not found` });
                    return;
                }
                if (Number(invoice.customer_id) !== Number(parsedCustomerId)) {
                    res.status(400).json({ success: false, error: `Invoice ${parsedInvoiceId} does not belong to customer ${parsedCustomerId}` });
                    return;
                }
                if ((0, currency_1.parseCurrency)(alloc.amount) <= 0) {
                    res.status(400).json({ success: false, error: `Allocation amount for invoice ${alloc.invoice_id} must be greater than 0` });
                    return;
                }
                if ((0, currency_1.parseCurrency)(alloc.amount) > (0, currency_1.parseCurrency)(invoice.balance_amount)) {
                    res.status(400).json({
                        success: false,
                        error: `Allocation amount (${(0, currency_1.parseCurrency)(alloc.amount).toFixed(2)}) for invoice ${alloc.invoice_id} exceeds the remaining balance (${(0, currency_1.parseCurrency)(invoice.balance_amount).toFixed(2)})`
                    });
                    return;
                }
            }
            const totalAllocated = invoice_allocations.reduce((sum, alloc) => sum + (0, currency_1.parseCurrency)(alloc.amount), 0);
            if (Math.abs(totalAllocated - parsedAmount) > 0.01) {
                res.status(400).json({ success: false, error: `Payment amount (${parsedAmount.toFixed(2)}) does not match total allocated amount (${totalAllocated.toFixed(2)})` });
                return;
            }
            const paymentId = Payment_1.default.create(database_1.default, {
                customer_id: parsedCustomerId, payment_date, amount: parsedAmount, payment_method, reference_no, notes, invoice_allocations,
                userId: req.user.id,
            });
            const customer = Customer_1.default.getById(parsedCustomerId, database_1.default);
            (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.PAYMENT_CREATE, 'Payment', paymentId, `Created payment - $${parsedAmount} from ${customer?.customer_name || 'Unknown'}`, req.user.id, { customer_id: parsedCustomerId, amount: parsedAmount, payment_method, invoice_allocations: invoice_allocations.length });
            req.activityLogged = true;
            res.status(201).json({ success: true, data: Payment_1.default.getById(database_1.default, paymentId) });
            return;
        }
        if (supplier_id) {
            const parsedSupplierId = parseInt(supplier_id, 10);
            const hasPoAllocs = po_allocations && Array.isArray(po_allocations) && po_allocations.length > 0;
            const hasPurchaseAllocs = purchase_allocations && Array.isArray(purchase_allocations) && purchase_allocations.length > 0;
            if (!hasPoAllocs && !hasPurchaseAllocs) {
                res.status(400).json({ success: false, error: 'At least one PO or purchase allocation is required for supplier payments' });
                return;
            }
            if (!Supplier_1.default.getById(parsedSupplierId, database_1.default)) {
                res.status(404).json({ success: false, error: 'Supplier not found' });
                return;
            }
            const paymentId = Payment_1.default.createSupplierPayment(database_1.default, {
                supplier_id: parsedSupplierId,
                payment_date,
                amount: parsedAmount,
                payment_method,
                reference_no,
                notes,
                po_allocations: hasPoAllocs ? po_allocations : [],
                purchase_allocations: hasPurchaseAllocs ? purchase_allocations : [],
                userId: req.user.id,
            });
            const supplier = Supplier_1.default.getById(parsedSupplierId, database_1.default);
            (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.PAYMENT_CREATE, 'Payment', paymentId, `Created supplier payment - $${parsedAmount} to ${supplier?.supplier_name || 'Unknown'}`, req.user.id, { supplier_id: parsedSupplierId, amount: parsedAmount, payment_method, allocation_count: (po_allocations || []).length + (purchase_allocations || []).length });
            req.activityLogged = true;
            res.status(201).json({ success: true, data: Payment_1.default.getById(database_1.default, paymentId) });
            return;
        }
    }
    catch (error) {
        const message = error instanceof Error ? error.message : '';
        logger_1.default.error('Error creating payment:', error);
        const isClientError = message.includes('not allowed') || message.includes('required') || message.includes('Invalid');
        res.status(isClientError ? 400 : 500).json({ success: false, error: message || 'Failed to create payment' });
    }
}
function updatePayment(req, res) {
    try {
        const id = parseInt(Array.isArray(req.params.id) ? req.params.id[0] : req.params.id, 10);
        const { payment_date, amount, payment_method, reference_no, notes } = req.body;
        const existing = Payment_1.default.getById(database_1.default, id);
        if (!existing) {
            res.status(404).json({ success: false, error: 'Payment not found' });
            return;
        }
        Payment_1.default.update(database_1.default, id, { payment_date, amount, payment_method, reference_no, notes });
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.PAYMENT_UPDATE, 'Payment', id, `Updated payment: ${existing.payment_no}`, req.user.id, { payment_no: existing.payment_no, changes: Object.keys(req.body).filter(k => req.body[k] !== undefined) });
        req.activityLogged = true;
        res.json({ success: true, message: 'Payment updated successfully' });
    }
    catch (error) {
        const message = error instanceof Error ? error.message : 'Failed to update payment';
        if (message === 'Payment not found') {
            res.status(404).json({ success: false, error: message });
            return;
        }
        // PAY-04 (task 2.1): amount edits are a client error — explain the policy.
        if (message.includes('Cannot change the amount')) {
            res.status(400).json({ success: false, error: message });
            return;
        }
        // CASH-02 (task 1.4): bad method on edit is a client error too.
        if (message.includes('Invalid payment_method')) {
            res.status(400).json({ success: false, error: message });
            return;
        }
        logger_1.default.error('Error updating payment:', error);
        res.status(500).json({ success: false, error: 'Failed to update payment' });
    }
}
function deletePayment(req, res) {
    try {
        const id = parseInt((0, queryUtils_2.getRouteParam)(req.params.id), 10);
        if (isNaN(id)) {
            res.status(400).json({ success: false, error: 'Invalid payment ID' });
            return;
        }
        const existing = Payment_1.default.getById(database_1.default, id);
        if (!existing) {
            res.status(404).json({ success: false, error: 'Payment not found' });
            return;
        }
        Payment_1.default.delete(database_1.default, id);
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.PAYMENT_DELETE, 'Payment', id, `Deleted payment: ${existing.payment_no} - $${existing.amount}`, req.user.id, { payment_no: existing.payment_no, amount: existing.amount });
        req.activityLogged = true;
        res.json({ success: true, message: 'Payment deleted successfully' });
    }
    catch (error) {
        logger_1.default.error('Error deleting payment:', error);
        res.status(500).json({ success: false, error: 'Failed to delete payment' });
    }
}
function getPaymentReceipt(req, res) {
    try {
        const id = parseInt(Array.isArray(req.params.id) ? req.params.id[0] : req.params.id, 10);
        const payment = Payment_1.default.getById(database_1.default, id);
        if (!payment) {
            res.status(404).json({ success: false, error: 'Payment not found' });
            return;
        }
        let entityName = '';
        let entityAddress = '';
        let entityPhone = '';
        let entityEmail = '';
        let currentBalance = 0;
        let previousBalance = 0;
        let allocations = [];
        let entityType = 'customer';
        if (payment.customer_id) {
            entityType = 'customer';
            const customer = database_1.default.prepare(`
        SELECT id, customer_name, billing_address as entity_address, phone as entity_phone, email as entity_email, current_balance
        FROM customers WHERE id = ?
      `).get(payment.customer_id);
            if (!customer) {
                res.status(404).json({ success: false, error: 'Customer not found' });
                return;
            }
            entityName = customer.customer_name;
            entityAddress = customer.entity_address || '';
            entityPhone = customer.entity_phone || '';
            entityEmail = customer.entity_email || '';
            currentBalance = (0, currency_1.parseCurrency)(customer.current_balance);
            // PAY-11 (task 2.6): previous balance comes from the payment's own
            // ledger row — today's balance is polluted by everything since.
            const ownRow = database_1.default.prepare(`
        SELECT debit, credit, balance FROM customer_ledger
        WHERE reference_no = ? AND transaction_type = 'PAYMENT' AND customer_id = ? AND voided = 0
        ORDER BY id DESC LIMIT 1
      `).get(payment.payment_no, payment.customer_id);
            previousBalance = ownRow
                ? (0, currency_1.parseCurrency)((0, currency_1.parseCurrency)(ownRow.balance) + (0, currency_1.parseCurrency)(ownRow.credit) - (0, currency_1.parseCurrency)(ownRow.debit))
                : (0, currency_1.parseCurrency)(currentBalance + (0, currency_1.parseCurrency)(payment.amount)); // legacy fallback
            allocations = database_1.default.prepare(`
        SELECT pa.invoice_id, i.invoice_no, pa.amount
        FROM payment_allocations pa
        LEFT JOIN invoices i ON pa.invoice_id = i.id
        WHERE pa.payment_id = ?
        ORDER BY pa.id
      `).all(id);
        }
        else if (payment.supplier_id) {
            entityType = 'supplier';
            const supplier = database_1.default.prepare(`
        SELECT id, supplier_name, address as entity_address, phone as entity_phone, email as entity_email, current_balance
        FROM suppliers WHERE id = ?
      `).get(payment.supplier_id);
            if (!supplier) {
                res.status(404).json({ success: false, error: 'Supplier not found' });
                return;
            }
            entityName = supplier.supplier_name;
            entityAddress = supplier.entity_address || '';
            entityPhone = supplier.entity_phone || '';
            entityEmail = supplier.entity_email || '';
            currentBalance = (0, currency_1.parseCurrency)(supplier.current_balance);
            // PAY-11 (task 2.6): supplier sign convention — debit increases what
            // we owe, credit (a payment) decreases it.
            const supOwnRow = database_1.default.prepare(`
        SELECT debit, credit, balance FROM supplier_ledger
        WHERE reference_no = ? AND transaction_type = 'PAYMENT' AND supplier_id = ? AND voided = 0
        ORDER BY id DESC LIMIT 1
      `).get(payment.payment_no, payment.supplier_id);
            previousBalance = supOwnRow
                ? (0, currency_1.parseCurrency)((0, currency_1.parseCurrency)(supOwnRow.balance) + (0, currency_1.parseCurrency)(supOwnRow.debit) - (0, currency_1.parseCurrency)(supOwnRow.credit))
                : (0, currency_1.parseCurrency)(currentBalance + (0, currency_1.parseCurrency)(payment.amount)); // legacy fallback
            const poRows = database_1.default.prepare(`
        SELECT pa.po_id as invoice_id, po.po_no as invoice_no, pa.amount
        FROM po_allocations pa
        LEFT JOIN purchase_orders po ON pa.po_id = po.id
        WHERE pa.payment_id = ?
        ORDER BY pa.id
      `).all(id);
            const purchaseRows = database_1.default.prepare(`
        SELECT pa.purchase_id as invoice_id, p.purchase_no as invoice_no, pa.amount
        FROM purchase_allocations pa
        LEFT JOIN purchases p ON pa.purchase_id = p.id
        WHERE pa.payment_id = ?
        ORDER BY pa.id
      `).all(id);
            allocations = [...poRows, ...purchaseRows];
        }
        const amount = (0, currency_1.parseCurrency)(payment.amount);
        const settingsRows = database_1.default.prepare("SELECT key, value FROM settings WHERE key IN ('company_name','company_address','company_phone','company_email','company_tax_id')").all();
        const company = {};
        for (const row of settingsRows) {
            company[row.key.replace('company_', '')] = row.value;
        }
        res.json({
            success: true,
            data: {
                payment: {
                    id: payment.id,
                    payment_no: payment.payment_no,
                    payment_date: payment.payment_date,
                    amount,
                    payment_method: payment.payment_method,
                    reference_no: payment.reference_no || '',
                    notes: payment.notes || '',
                    created_at: payment.created_at,
                },
                [entityType]: {
                    name: entityName,
                    address: entityAddress,
                    phone: entityPhone,
                    email: entityEmail,
                },
                balance: {
                    previous_balance: previousBalance,
                    payment_amount: amount,
                    current_balance: currentBalance,
                },
                allocations,
                company: {
                    name: company.name || 'Mini ERP',
                    address: company.address || '',
                    phone: company.phone || '',
                    email: company.email || '',
                    tax_id: company.tax_id || '',
                },
            },
        });
    }
    catch (error) {
        logger_1.default.error('Error fetching payment receipt:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch receipt data' });
    }
}
function allocatePaymentToInvoice(req, res) {
    try {
        const id = parseInt((0, queryUtils_2.getRouteParam)(req.params.id), 10);
        if (isNaN(id)) {
            res.status(400).json({ success: false, error: 'Invalid payment ID' });
            return;
        }
        const { allocations } = req.body;
        if (!allocations || !Array.isArray(allocations) || allocations.length === 0) {
            res.status(400).json({ success: false, error: 'At least one allocation is required' });
            return;
        }
        const payment = Payment_1.default.getById(database_1.default, id);
        if (!payment) {
            res.status(404).json({ success: false, error: 'Payment not found' });
            return;
        }
        if (!payment.customer_id) {
            res.status(400).json({ success: false, error: 'Manual invoice allocation applies to customer payments only' });
            return;
        }
        const paymentAmount = (0, currency_1.parseCurrency)(payment.amount);
        // Currently allocated total for THIS payment.
        const currentRows = database_1.default.prepare('SELECT COALESCE(SUM(amount), 0) AS total FROM payment_allocations WHERE payment_id = ?').get(id);
        const currentlyAllocated = (0, currency_1.parseCurrency)(currentRows.total);
        const unallocated = paymentAmount - currentlyAllocated;
        let newTotal = 0;
        for (const alloc of allocations) {
            const parsedInvoiceId = parseInt(alloc.invoice_id, 10);
            if (isNaN(parsedInvoiceId)) {
                res.status(400).json({ success: false, error: `Invalid invoice ID: ${alloc.invoice_id}` });
                return;
            }
            const amount = (0, currency_1.parseCurrency)(alloc.amount);
            if (amount <= 0) {
                res.status(400).json({ success: false, error: `Allocation amount for invoice ${parsedInvoiceId} must be greater than 0` });
                return;
            }
            const invoice = Invoice_1.default.getById(parsedInvoiceId, database_1.default);
            if (!invoice) {
                res.status(404).json({ success: false, error: `Invoice ${parsedInvoiceId} not found` });
                return;
            }
            if (Number(invoice.customer_id) !== Number(payment.customer_id)) {
                res.status(400).json({ success: false, error: `Invoice ${parsedInvoiceId} does not belong to this payment's customer` });
                return;
            }
            if (amount > (0, currency_1.parseCurrency)(invoice.balance_amount) + 0.01) {
                res.status(400).json({
                    success: false,
                    error: `Allocation (${amount.toFixed(2)}) exceeds invoice ${parsedInvoiceId} balance (${(0, currency_1.parseCurrency)(invoice.balance_amount).toFixed(2)})`,
                });
                return;
            }
            newTotal += amount;
        }
        if (Math.abs(newTotal - unallocated) > 0.01) {
            res.status(400).json({
                success: false,
                error: `Allocations total (${newTotal.toFixed(2)}) must equal the unallocated remainder (${unallocated.toFixed(2)})`,
            });
            return;
        }
        database_1.default.transaction(() => {
            const insert = database_1.default.prepare('INSERT INTO payment_allocations (payment_id, invoice_id, amount) VALUES (?, ?, ?)');
            for (const alloc of allocations) {
                insert.run(id, parseInt(alloc.invoice_id, 10), (0, currency_1.parseCurrency)(alloc.amount));
            }
            for (const alloc of allocations) {
                const invoiceId = parseInt(alloc.invoice_id, 10);
                ledgerUtils_1.default.calculateInvoiceBalance(invoiceId);
                ledgerUtils_1.default.updateInvoiceStatus(invoiceId);
            }
        })();
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.PAYMENT_UPDATE, 'Payment', id, `Allocated ${newTotal.toFixed(2)} of ${payment.payment_no} across ${allocations.length} invoice(s)`, req.user.id, { payment_no: payment.payment_no, allocated: newTotal });
        req.activityLogged = true;
        res.json({ success: true, message: 'Allocation recorded', data: Payment_1.default.getById(database_1.default, id) });
    }
    catch (error) {
        const message = error instanceof Error ? error.message : 'Failed to allocate payment';
        logger_1.default.error('Error allocating payment:', error);
        res.status(500).json({ success: false, error: message });
    }
}
exports.default = {
    getPayments, getUnifiedPayments, getPayment, createPayment, updatePayment, deletePayment, getPaymentReceipt, allocatePaymentToInvoice,
};
