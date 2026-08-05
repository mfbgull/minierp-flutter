"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const database_1 = __importDefault(require("../config/database"));
const currency_1 = require("./currency");
/**
 * Create a ledger entry for a customer.
 * Wrapped in a transaction to prevent race conditions on running balance.
 * Uses currency utilities for safe arithmetic.
 */
function createLedgerEntry(customerId, type, referenceNo, debit, credit, description) {
    const insertEntry = database_1.default.transaction(() => {
        const lastBalanceResult = database_1.default.prepare(`
      SELECT balance FROM customer_ledger
      WHERE customer_id = ?
      ORDER BY id DESC
      LIMIT 1
    `).get(customerId);
        const lastBalance = (0, currency_1.parseCurrency)(lastBalanceResult?.balance);
        const safeDebit = (0, currency_1.parseCurrency)(debit);
        const safeCredit = (0, currency_1.parseCurrency)(credit);
        const newBalance = (0, currency_1.subtractCurrency)((0, currency_1.addCurrency)(lastBalance, safeDebit), safeCredit);
        const result = database_1.default.prepare(`
      INSERT INTO customer_ledger (
        customer_id, transaction_date, transaction_type, reference_no,
        debit, credit, balance, description
      ) VALUES (?, date('now'), ?, ?, ?, ?, ?, ?)
    `).run(customerId, type, referenceNo, safeDebit, safeCredit, newBalance, description);
        return result.lastInsertRowid;
    });
    return insertEntry();
}
function updateCustomerBalance(customerId) {
    return database_1.default.transaction(() => {
        const balanceResult = database_1.default.prepare(`
      SELECT COALESCE(SUM(balance_amount), 0) as total_balance
      FROM invoices
      WHERE customer_id = ? AND status IN ('Unpaid', 'Partially Paid', 'Overdue')
    `).get(customerId);
        const newBalance = (0, currency_1.parseCurrency)(balanceResult.total_balance);
        database_1.default.prepare('UPDATE customers SET current_balance = ? WHERE id = ?').run(newBalance, customerId);
        return newBalance;
    })();
}
function calculateInvoiceBalance(invoiceId) {
    const invoice = database_1.default.prepare('SELECT total_amount, returned_amount, return_fee FROM invoices WHERE id = ?').get(invoiceId);
    if (!invoice) {
        throw new Error(`Invoice ${invoiceId} not found`);
    }
    const paidResult = database_1.default.prepare(`
    SELECT COALESCE(SUM(amount), 0) as total_paid
    FROM payment_allocations
    WHERE invoice_id = ?
  `).get(invoiceId);
    const totalPaid = (0, currency_1.parseCurrency)(paidResult?.total_paid);
    const totalAmount = (0, currency_1.parseCurrency)(invoice.total_amount);
    const returnedAmount = (0, currency_1.parseCurrency)(invoice.returned_amount || 0);
    const returnFee = (0, currency_1.parseCurrency)(invoice.return_fee || 0);
    // Balance = total owed minus paid minus (returned minus fee)
    // Equivalent to: total - paid - returned + return_fee
    const netReturnReduction = (0, currency_1.subtractCurrency)(returnedAmount, returnFee);
    const newBalance = (0, currency_1.subtractCurrency)((0, currency_1.subtractCurrency)(totalAmount, totalPaid), netReturnReduction);
    database_1.default.prepare('UPDATE invoices SET paid_amount = ?, balance_amount = ? WHERE id = ?')
        .run(totalPaid, newBalance, invoiceId);
    return newBalance;
}
function updateInvoiceStatus(invoiceId) {
    const invoice = database_1.default.prepare('SELECT balance_amount, total_amount, paid_amount, due_date, returned_amount, status FROM invoices WHERE id = ?')
        .get(invoiceId);
    if (!invoice) {
        throw new Error(`Invoice ${invoiceId} not found`);
    }
    const balance = (0, currency_1.parseCurrency)(invoice.balance_amount);
    const total = (0, currency_1.parseCurrency)(invoice.total_amount);
    const returned = (0, currency_1.parseCurrency)(invoice.returned_amount || 0);
    const currentStatus = String(invoice.status || '');
    let newStatus = 'Unpaid';
    if (currentStatus === 'Cancelled') {
        newStatus = 'Cancelled';
    }
    else if (returned >= total && total > 0) {
        // All items returned
        newStatus = 'Returned';
    }
    else if (returned > 0 && total > 0) {
        // Some items returned, some remain
        newStatus = 'Partially Returned';
    }
    else if (balance <= 0 && total > 0) {
        newStatus = 'Paid';
    }
    else if (balance < total && balance > 0) {
        newStatus = 'Partially Paid';
    }
    else if (balance >= total && total > 0) {
        newStatus = 'Unpaid';
    }
    if (newStatus !== 'Paid' && newStatus !== 'Returned' && newStatus !== 'Partially Returned' && invoice.due_date && new Date(invoice.due_date) < new Date()) {
        newStatus = 'Overdue';
    }
    database_1.default.prepare('UPDATE invoices SET status = ? WHERE id = ?').run(newStatus, invoiceId);
    return newStatus;
}
function rebuildLedgerBalances(customerId) {
    database_1.default.transaction(() => {
        const entries = database_1.default.prepare(`
      SELECT id, debit, credit FROM customer_ledger
      WHERE customer_id = ?
      ORDER BY id ASC
    `).all(customerId);
        let runningBalance = 0;
        const updateStmt = database_1.default.prepare('UPDATE customer_ledger SET balance = ? WHERE id = ?');
        for (const entry of entries) {
            runningBalance = (0, currency_1.addCurrency)((0, currency_1.subtractCurrency)(runningBalance, entry.credit), entry.debit);
            updateStmt.run(runningBalance, entry.id);
        }
    })();
}
exports.default = {
    createLedgerEntry,
    updateCustomerBalance,
    calculateInvoiceBalance,
    updateInvoiceStatus,
    rebuildLedgerBalances
};
//# sourceMappingURL=ledgerUtils.js.map