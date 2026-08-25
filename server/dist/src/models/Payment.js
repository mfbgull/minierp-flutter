"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.PaymentModel = void 0;
const sequence_1 = require("../utils/sequence");
const ledgerUtils_1 = __importDefault(require("../utils/ledgerUtils"));
const accountingService_1 = __importDefault(require("../services/accountingService"));
const currency_1 = require("../utils/currency");
const logger_1 = __importDefault(require("../utils/logger"));
const SupplierLedger_1 = __importDefault(require("./SupplierLedger"));
const cashService_1 = require("../services/cashService");
// Static class for Payment model operations
class PaymentModel {
    /**
     * Generate payment number using sequence utility.
     * Re-syncs from the actual max in the table on every call to prevent
     * duplicate payment_no errors when data is manually inserted or restored.
     */
    static generatePaymentNo(db) {
        // Use numeric MAX (not string MAX) so PAY1000 sorts after PAY999.
        // String comparison would make PAY999 > PAY1000, causing duplicate generation.
        const maxResult = db.prepare(`SELECT MAX(CAST(SUBSTR(payment_no, 4) AS INTEGER)) as max_val FROM payments WHERE payment_no LIKE 'PAY%'`).get();
        const maxNo = maxResult?.max_val ?? 0;
        const currentSetting = db.prepare("SELECT value FROM settings WHERE key = 'PAY_last_no'").get();
        const currentSeq = currentSetting ? parseInt(currentSetting.value, 10) || 0 : 0;
        if (maxNo > currentSeq) {
            db.prepare("UPDATE settings SET value = ?, updated_at = CURRENT_TIMESTAMP WHERE key = 'PAY_last_no'").run(maxNo.toString());
        }
        const nextNo = (0, sequence_1.getNextSequenceNumber)(db, 'PAY_last_no');
        return `PAY${String(nextNo).padStart(3, '0')}`;
    }
    /**
     * Get payment by ID
     */
    static getById(db, id) {
        const payment = db.prepare(`
      SELECT p.id, p.payment_no, p.customer_id, c.customer_name, p.supplier_id, p.invoice_id, i.invoice_no,
             p.payment_date, p.amount, p.payment_method, p.reference_no, p.notes, p.created_at,
             GROUP_CONCAT(pa.invoice_id, ',') as allocated_invoices,
             GROUP_CONCAT(pa.amount, ',') as allocation_amounts,
             GROUP_CONCAT(pa.id, ',') as allocation_ids
      FROM payments p LEFT JOIN customers c ON p.customer_id = c.id
      LEFT JOIN invoices i ON p.invoice_id = i.id
      LEFT JOIN payment_allocations pa ON p.id = pa.payment_id
      WHERE p.id = ? GROUP BY p.id
    `).get(id);
        if (payment && payment.allocated_invoices) {
            payment.allocations = db.prepare(`
        SELECT pa.id, pa.payment_id, pa.invoice_id, i.invoice_no, pa.amount
        FROM payment_allocations pa LEFT JOIN invoices i ON pa.invoice_id = i.id
        WHERE pa.payment_id = ? ORDER BY pa.id
      `).all(id);
        }
        else if (payment) {
            payment.allocations = [];
        }
        return payment;
    }
    /**
     * Get all payments with filtering
     */
    static getAll(db, filters = {}, sortColumns, defaultSort, defaultOrder) {
        const pageNum = filters.page || 1;
        const limitNum = filters.limit || 10;
        let query = `
      SELECT p.id, p.payment_no, p.customer_id, c.customer_name, p.supplier_id, s.supplier_name as supplier_name,
             p.invoice_id, i.invoice_no,
             p.payment_date, p.amount, p.payment_method, p.reference_no, p.notes, p.created_at,
             GROUP_CONCAT(pa.invoice_id, ',') as allocated_invoices,
             GROUP_CONCAT(pa.amount, ',') as allocation_amounts
      FROM payments p
      LEFT JOIN customers c ON p.customer_id = c.id
      LEFT JOIN suppliers s ON p.supplier_id = s.id
      LEFT JOIN invoices i ON p.invoice_id = i.id
      LEFT JOIN payment_allocations pa ON p.id = pa.payment_id
      WHERE 1=1
    `;
        const params = [];
        if (filters.search) {
            const term = `%${filters.search}%`;
            query += ` AND (p.payment_no LIKE ? OR COALESCE(c.customer_name, s.supplier_name) LIKE ? OR p.reference_no LIKE ?)`;
            params.push(term, term, term);
        }
        if (filters.customerId) {
            query += ' AND p.customer_id = ?';
            params.push(parseInt(filters.customerId, 10));
        }
        if (filters.supplierId) {
            query += ' AND p.supplier_id = ?';
            params.push(parseInt(filters.supplierId, 10));
        }
        if (filters.fromDate) {
            query += ' AND p.payment_date >= ?';
            params.push(filters.fromDate);
        }
        if (filters.toDate) {
            query += ' AND p.payment_date <= ?';
            params.push(filters.toDate);
        }
        const sortBy = filters.sortBy && sortColumns.includes(filters.sortBy) ? filters.sortBy : defaultSort;
        const sortOrder = filters.sortOrder === 'ASC' ? 'ASC' : defaultOrder;
        query += ` GROUP BY p.id ORDER BY ${sortBy} ${sortOrder} LIMIT ? OFFSET ?`;
        params.push(limitNum, (pageNum - 1) * limitNum);
        const payments = db.prepare(query).all(...params);
        let countQuery = `
      SELECT COUNT(DISTINCT p.id) as total FROM payments p
      LEFT JOIN customers c ON p.customer_id = c.id
      LEFT JOIN suppliers s ON p.supplier_id = s.id
      WHERE 1=1
    `;
        const countParams = [];
        if (filters.search) {
            const term = `%${filters.search}%`;
            countQuery += ` AND (p.payment_no LIKE ? OR COALESCE(c.customer_name, s.supplier_name) LIKE ? OR p.reference_no LIKE ?)`;
            countParams.push(term, term, term);
        }
        if (filters.customerId) {
            countQuery += ' AND p.customer_id = ?';
            countParams.push(parseInt(filters.customerId, 10));
        }
        if (filters.supplierId) {
            countQuery += ' AND p.supplier_id = ?';
            countParams.push(parseInt(filters.supplierId, 10));
        }
        if (filters.fromDate) {
            countQuery += ' AND p.payment_date >= ?';
            countParams.push(filters.fromDate);
        }
        if (filters.toDate) {
            countQuery += ' AND p.payment_date <= ?';
            countParams.push(filters.toDate);
        }
        const total = db.prepare(countQuery).get(...countParams);
        return { payments, total: total.total, pageNum, limitNum };
    }
    /**
     * Create a new payment
     */
    static create(db, data) {
        return db.transaction(() => {
            // Input validation
            if (!data.customer_id || data.customer_id <= 0) {
                throw new Error('Valid customer_id is required');
            }
            if (!data.amount || data.amount <= 0) {
                throw new Error('Payment amount must be greater than 0');
            }
            if (!data.payment_date) {
                throw new Error('Payment date is required');
            }
            // CASH-02 (task 1.4): reject unrecognized payment methods outright
            if (!(0, cashService_1.isValidPaymentMethod)(data.payment_method)) {
                throw new Error(`Invalid payment_method "${data.payment_method ?? ''}" — use Cash, Bank, Easypaisa, JazzCash or Upaisa`);
            }
            if (!data.invoice_allocations || data.invoice_allocations.length === 0) {
                throw new Error('At least one invoice allocation is required');
            }
            // Validate customer exists
            const customer = db.prepare('SELECT id FROM customers WHERE id = ?').get(data.customer_id);
            if (!customer) {
                throw new Error(`Customer ${data.customer_id} not found`);
            }
            // Validate each allocated invoice exists
            for (const alloc of data.invoice_allocations) {
                const invoiceId = parseInt(alloc.invoice_id, 10);
                const invoice = db.prepare('SELECT id, customer_id FROM invoices WHERE id = ?').get(invoiceId);
                if (!invoice) {
                    throw new Error(`Invoice ${invoiceId} not found`);
                }
                if (invoice.customer_id !== data.customer_id) {
                    throw new Error(`Invoice ${invoiceId} does not belong to customer ${data.customer_id}`);
                }
                if (!alloc.amount || alloc.amount <= 0) {
                    throw new Error(`Allocation amount for invoice ${invoiceId} must be greater than 0`);
                }
            }
            const paymentNo = this.generatePaymentNo(db);
            const paymentResult = db.prepare(`
        INSERT INTO payments (payment_no, customer_id, payment_date, amount, payment_method, reference_no, notes)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      `).run(paymentNo, data.customer_id, data.payment_date, data.amount, data.payment_method || 'Cash', data.reference_no || '', data.notes || '');
            const paymentId = paymentResult.lastInsertRowid;
            for (const alloc of data.invoice_allocations) {
                const invoiceId = parseInt(alloc.invoice_id, 10);
                db.prepare('INSERT INTO payment_allocations (payment_id, invoice_id, amount) VALUES (?, ?, ?)').run(paymentId, invoiceId, alloc.amount);
                ledgerUtils_1.default.calculateInvoiceBalance(invoiceId);
                ledgerUtils_1.default.updateInvoiceStatus(invoiceId);
            }
            const currentBalance = db.prepare('SELECT current_balance FROM customers WHERE id = ?').get(data.customer_id);
            const newBalance = (0, currency_1.subtractCurrency)((0, currency_1.parseCurrency)(currentBalance.current_balance), (0, currency_1.parseCurrency)(data.amount));
            const invoiceNumbers = data.invoice_allocations.map((alloc) => {
                const invoiceId = parseInt(alloc.invoice_id, 10);
                const inv = db.prepare('SELECT invoice_no FROM invoices WHERE id = ?').get(invoiceId);
                return inv?.invoice_no || `Invoice #${invoiceId}`;
            });
            db.prepare(`
        INSERT INTO customer_ledger (customer_id, transaction_date, transaction_type, reference_no, debit, credit, balance, description)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      `).run(data.customer_id, data.payment_date, 'PAYMENT', paymentNo, 0, data.amount, newBalance, `Payment against ${invoiceNumbers.join(', ')}`);
            // GL Phase-2 wiring: post the payment to the journal so the
            // new TB and BS pick it up. The customer_ledger above is the
            // sub-ledger; this is the GL posting. Both must happen in the
            // same transaction for atomicity.
            accountingService_1.default.postPaymentEntry(db, {
                paymentId,
                paymentNo,
                amount: (0, currency_1.parseCurrency)(data.amount),
                paymentDate: data.payment_date,
                paymentMethod: data.payment_method,
                customerId: data.customer_id,
                userId: data.userId,
            });
            ledgerUtils_1.default.recalcCustomerBalanceFromLedger(data.customer_id);
            return paymentId;
        })();
    }
    static createSupplierPayment(db, data) {
        return db.transaction(() => {
            if (!data.supplier_id || data.supplier_id <= 0) {
                throw new Error('Valid supplier_id is required');
            }
            if (!data.amount || data.amount <= 0) {
                throw new Error('Payment amount must be greater than 0');
            }
            if (!data.payment_date) {
                throw new Error('Payment date is required');
            }
            // CASH-02 (task 1.4): same method whitelist as the customer path.
            if (!(0, cashService_1.isValidPaymentMethod)(data.payment_method)) {
                throw new Error(`Invalid payment_method "${data.payment_method ?? ''}" — use Cash, Bank, Easypaisa, JazzCash or Upaisa`);
            }
            const poAllocs = data.po_allocations || [];
            const purchaseAllocs = data.purchase_allocations || [];
            if (poAllocs.length === 0 && purchaseAllocs.length === 0) {
                throw new Error('At least one PO or purchase allocation is required');
            }
            const supplier = db.prepare('SELECT id FROM suppliers WHERE id = ?').get(data.supplier_id);
            if (!supplier) {
                throw new Error(`Supplier ${data.supplier_id} not found`);
            }
            for (const alloc of poAllocs) {
                const poId = parseInt(alloc.po_id, 10);
                const po = db.prepare(`
          SELECT po.id, po.supplier_id, po.total_amount, COALESCE(SUM(pa.amount), 0) as paid_amount
          FROM purchase_orders po
          LEFT JOIN po_allocations pa ON pa.po_id = po.id
          WHERE po.id = ? GROUP BY po.id
        `).get(poId);
                if (!po) {
                    throw new Error(`Purchase order ${poId} not found`);
                }
                if (po.supplier_id !== data.supplier_id) {
                    throw new Error(`PO ${poId} does not belong to supplier ${data.supplier_id}`);
                }
                if (!alloc.amount || alloc.amount <= 0) {
                    throw new Error(`Allocation amount for PO ${poId} must be greater than 0`);
                }
                const remainingBalance = Math.max(0, (0, currency_1.parseCurrency)(po.total_amount) - (0, currency_1.parseCurrency)(po.paid_amount));
                if ((0, currency_1.parseCurrency)(alloc.amount) > remainingBalance) {
                    throw new Error(`Allocation amount (${(0, currency_1.parseCurrency)(alloc.amount).toFixed(2)}) for PO ${poId} exceeds the remaining balance (${remainingBalance.toFixed(2)})`);
                }
            }
            for (const alloc of purchaseAllocs) {
                const purchaseId = parseInt(alloc.purchase_id, 10);
                const purchase = db.prepare(`
          SELECT p.id, p.supplier_id, p.total_cost, COALESCE(SUM(pa.amount), 0) as paid_amount
          FROM purchases p
          LEFT JOIN purchase_allocations pa ON pa.purchase_id = p.id
          WHERE p.id = ? GROUP BY p.id
        `).get(purchaseId);
                if (!purchase) {
                    throw new Error(`Purchase ${purchaseId} not found`);
                }
                if (!purchase.supplier_id || purchase.supplier_id !== data.supplier_id) {
                    throw new Error(`Purchase ${purchaseId} does not belong to supplier ${data.supplier_id}`);
                }
                if (!alloc.amount || alloc.amount <= 0) {
                    throw new Error(`Allocation amount for purchase ${purchaseId} must be greater than 0`);
                }
                const remainingBalance = Math.max(0, (0, currency_1.parseCurrency)(purchase.total_cost) - (0, currency_1.parseCurrency)(purchase.paid_amount));
                if ((0, currency_1.parseCurrency)(alloc.amount) > remainingBalance) {
                    throw new Error(`Allocation amount (${(0, currency_1.parseCurrency)(alloc.amount).toFixed(2)}) for purchase ${purchaseId} exceeds the remaining balance (${remainingBalance.toFixed(2)})`);
                }
            }
            const paymentNo = this.generatePaymentNo(db);
            // When the payment settles exactly one PO (and no purchases), reflect it on
            // the denormalized payments.purchase_order_id so PO-level reporting joins
            // correctly. Multi-PO / mixed allocations stay NULL — the column is
            // single-valued and po_allocations remains the authoritative record.
            const singlePoId = poAllocs.length === 1 && purchaseAllocs.length === 0
                ? parseInt(poAllocs[0].po_id, 10)
                : null;
            const paymentResult = db.prepare(`
        INSERT INTO payments (payment_no, supplier_id, payment_date, amount, payment_method, reference_no, notes, purchase_order_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      `).run(paymentNo, data.supplier_id, data.payment_date, data.amount, data.payment_method || 'Cash', data.reference_no || '', data.notes || '', singlePoId);
            const paymentId = paymentResult.lastInsertRowid;
            for (const alloc of poAllocs) {
                const poId = parseInt(alloc.po_id, 10);
                db.prepare('INSERT INTO po_allocations (payment_id, po_id, amount) VALUES (?, ?, ?)').run(paymentId, poId, alloc.amount);
            }
            for (const alloc of purchaseAllocs) {
                const purchaseId = parseInt(alloc.purchase_id, 10);
                db.prepare('INSERT INTO purchase_allocations (payment_id, purchase_id, amount) VALUES (?, ?, ?)').run(paymentId, purchaseId, alloc.amount);
            }
            const currentBalance = SupplierLedger_1.default.getBalance(data.supplier_id, db);
            const newBalance = currentBalance - (0, currency_1.parseCurrency)(data.amount);
            const poNumbers = poAllocs.map((alloc) => {
                const poId = parseInt(alloc.po_id, 10);
                const po = db.prepare('SELECT po_no FROM purchase_orders WHERE id = ?').get(poId);
                return po?.po_no || `PO #${poId}`;
            });
            const purchaseNumbers = purchaseAllocs.map((alloc) => {
                const purchaseId = parseInt(alloc.purchase_id, 10);
                const p = db.prepare('SELECT purchase_no FROM purchases WHERE id = ?').get(purchaseId);
                return p?.purchase_no || `Purchase #${purchaseId}`;
            });
            const references = [...poNumbers, ...purchaseNumbers];
            db.prepare(`
        INSERT INTO supplier_ledger (supplier_id, transaction_date, transaction_type, reference_no, debit, credit, balance, description)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      `).run(data.supplier_id, data.payment_date, 'PAYMENT', paymentNo, 0, data.amount, newBalance, `Payment against ${references.join(', ')}`);
            db.prepare('UPDATE suppliers SET current_balance = ? WHERE id = ?').run(newBalance, data.supplier_id);
            // GL posting (ACC-03): Dr 2000 AP / Cr cash-per-method. Without this
            // the cash the business paid out never leaves GL account 1000.
            accountingService_1.default.postSupplierPaymentEntry(db, {
                paymentId,
                paymentNo,
                amount: (0, currency_1.parseCurrency)(data.amount),
                paymentDate: data.payment_date,
                paymentMethod: data.payment_method,
                userId: data.userId,
            });
            return paymentId;
        })();
    }
    /**
     * Update payment
     */
    static update(db, id, data) {
        const existing = this.getById(db, id);
        if (!existing)
            throw new Error('Payment not found');
        // PAY-04 (financial-audit-p0-remediation 2.1): amount edits on an
        // allocated payment silently rescaled allocations past invoice balances
        // and desynced allocations/ledger/GL. Policy: void-and-reissue.
        const amountChanged = data.amount !== undefined && (0, currency_1.parseCurrency)(data.amount) !== (0, currency_1.parseCurrency)(existing.amount);
        if (amountChanged) {
            throw new Error(`Cannot change the amount of payment ${existing.payment_no} — it has recorded allocations. ` +
                `Void this payment and record a new one with the correct amount.`);
        }
        // CASH-02 (task 1.4): method edits must pass the same whitelist.
        if (data.payment_method !== undefined && !(0, cashService_1.isValidPaymentMethod)(data.payment_method)) {
            throw new Error(`Invalid payment_method "${data.payment_method ?? ''}" — use Cash, Bank, Easypaisa, JazzCash or Upaisa`);
        }
        const methodChanged = data.payment_method !== undefined &&
            data.payment_method.toLowerCase() !== String(existing.payment_method).toLowerCase();
        db.transaction(() => {
            db.prepare(`
        UPDATE payments SET
          payment_date = COALESCE(?, payment_date),
          payment_method = COALESCE(?, payment_method), reference_no = COALESCE(?, reference_no),
          notes = COALESCE(?, notes) WHERE id = ?
      `).run(data.payment_date, data.payment_method, data.reference_no, data.notes, id);
            // Method change moves money between accounts → GL void + repost only.
            if (methodChanged && existing.customer_id) {
                accountingService_1.default.voidJournalLinesByReference(db, 'PAYMENT', id);
                const finalPayment = this.getById(db, id);
                if (finalPayment) {
                    accountingService_1.default.postPaymentEntry(db, {
                        paymentId: id,
                        paymentNo: finalPayment.payment_no,
                        amount: (0, currency_1.parseCurrency)(finalPayment.amount),
                        paymentDate: finalPayment.payment_date,
                        paymentMethod: finalPayment.payment_method,
                        customerId: existing.customer_id,
                    });
                }
            }
        })();
    }
    /**
     * Delete payment
     */
    static delete(db, id) {
        const existing = this.getById(db, id);
        if (!existing)
            throw new Error('Payment not found');
        db.transaction(() => {
            // GL consistency (ACC-09): the payment's journal lines (Dr Cash /
            // Cr AR, or supplier-side) must not survive as active orphans once
            // the payment row is gone.
            accountingService_1.default.voidJournalLinesByReference(db, 'PAYMENT', id);
            const allocations = db.prepare('SELECT * FROM payment_allocations WHERE payment_id = ?').all(id);
            db.prepare('DELETE FROM payment_allocations WHERE payment_id = ?').run(id);
            db.prepare('DELETE FROM purchase_allocations WHERE payment_id = ?').run(id);
            db.prepare('DELETE FROM payments WHERE id = ?').run(id);
            // ACC-14: reverse the payment's subledger rows (append-only) instead
            // of deleting them. Scoped by reference_no AND transaction_type so a
            // colliding reference cannot touch another party's rows.
            const custRows = db.prepare(`SELECT id FROM customer_ledger WHERE reference_no = ? AND voided = 0 AND transaction_type = 'PAYMENT' AND customer_id = ?`).all(existing.payment_no, existing.customer_id);
            for (const row of custRows) {
                ledgerUtils_1.default.reverseLedgerEntry('customer_ledger', row.id, `payment ${existing.payment_no} deleted`);
            }
            const supRows = db.prepare(`SELECT id FROM supplier_ledger WHERE reference_no = ? AND voided = 0 AND transaction_type = 'PAYMENT' AND supplier_id = ?`).all(existing.payment_no, existing.supplier_id);
            for (const row of supRows) {
                ledgerUtils_1.default.reverseLedgerEntry('supplier_ledger', row.id, `payment ${existing.payment_no} deleted`);
            }
            if (existing.supplier_id) {
                // Deleting a payment may leave the running chain inconsistent
                // (mid-chain gap or stale balance); recompute it in full.
                SupplierLedger_1.default.rebuildBalances(existing.supplier_id, db);
            }
            for (const alloc of allocations) {
                try {
                    ledgerUtils_1.default.calculateInvoiceBalance(alloc.invoice_id);
                    ledgerUtils_1.default.updateInvoiceStatus(alloc.invoice_id);
                }
                catch (err) {
                    logger_1.default.warn('Payment.delete: failed to update invoice balance', { invoice_id: alloc.invoice_id, error: err instanceof Error ? err.message : err });
                }
            }
            try {
                ledgerUtils_1.default.recalcCustomerBalanceFromLedger(existing.customer_id);
            }
            catch (err) {
                logger_1.default.warn('Payment.delete: failed to update customer balance', { customer_id: existing.customer_id, error: err instanceof Error ? err.message : err });
            }
            try {
                ledgerUtils_1.default.rebuildLedgerBalances(existing.customer_id);
            }
            catch (err) {
                logger_1.default.warn('Payment.delete: failed to rebuild ledger balances', { customer_id: existing.customer_id, error: err instanceof Error ? err.message : err });
            }
        })();
    }
    /**
     * Get payment allocations by payment ID
     */
    static getAllocationsByPaymentId(db, paymentId) {
        return db.prepare('SELECT invoice_id FROM payment_allocations WHERE payment_id = ?').all(paymentId);
    }
    /**
     * Get payment allocations by invoice ID
     */
    static getAllocationsByInvoiceId(db, invoiceId) {
        return db.prepare(`
      SELECT payment_id, amount FROM payment_allocations WHERE invoice_id = ?
    `).all(invoiceId);
    }
    /**
     * Delete payment allocations by payment ID
     */
    static deleteAllocationsByPaymentId(db, paymentId) {
        db.prepare('DELETE FROM payment_allocations WHERE payment_id = ?').run(paymentId);
    }
    /**
     * Delete payment allocations by invoice ID
     */
    static deleteAllocationsByInvoiceId(db, invoiceId) {
        db.prepare('DELETE FROM payment_allocations WHERE invoice_id = ?').run(invoiceId);
    }
    /**
     * Get total paid for an invoice
     */
    static getTotalPaidByInvoiceId(db, invoiceId) {
        const result = db.prepare(`
      SELECT COALESCE(SUM(amount), 0) as total_paid
      FROM payment_allocations
      WHERE invoice_id = ?
    `).get(invoiceId);
        return result.total_paid;
    }
}
exports.PaymentModel = PaymentModel;
exports.default = PaymentModel;
