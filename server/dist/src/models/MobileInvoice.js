"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const StockMovement_1 = __importDefault(require("./StockMovement"));
const sequence_1 = require("../utils/sequence");
const ledgerUtils_1 = __importDefault(require("../utils/ledgerUtils"));
const accountingService_1 = __importDefault(require("../services/accountingService"));
const currency_1 = require("../utils/currency");
function getDraftById(db, id) {
    return db.prepare('SELECT * FROM invoice_drafts WHERE id = ?').get(id);
}
function getDraftBySession(db, sessionId) {
    return db.prepare(`
    SELECT * FROM invoice_drafts
    WHERE session_id = ? AND status = 'draft' AND expires_at > datetime('now')
  `).get(sessionId);
}
function createDraft(db, data, sessionId) {
    const result = db.prepare(`
    INSERT INTO invoice_drafts (
      session_id, customer_id, invoice_date, due_date,
      terms, notes, items_data, status
    ) VALUES (?, ?, ?, ?, ?, ?, ?, 'draft')
  `).run(sessionId, data.customer_id || null, data.invoice_date || null, data.due_date || null, data.terms || null, data.notes || null, data.items_data ? JSON.stringify(data.items_data) : null);
    return result.lastInsertRowid;
}
function updateDraft(db, id, data) {
    db.prepare(`
    UPDATE invoice_drafts
    SET customer_id = ?, invoice_date = ?, due_date = ?,
        terms = ?, notes = ?, items_data = ?, status = ?,
        updated_at = datetime('now')
    WHERE id = ?
  `).run(data.customer_id || null, data.invoice_date || null, data.due_date || null, data.terms || null, data.notes || null, data.items_data ? JSON.stringify(data.items_data) : null, data.status || 'draft', id);
}
function deleteDraft(db, id) {
    const result = db.prepare('DELETE FROM invoice_drafts WHERE id = ?').run(id);
    return result.changes > 0;
}
function searchItems(db, q, limit) {
    let query = `
    SELECT id, item_code, item_name, description, category, unit_of_measure,
           current_stock, standard_selling_price as price, standard_cost as cost,
           is_raw_material, is_finished_good, is_purchased
    FROM items WHERE is_active = 1
  `;
    const params = [];
    if (q && q.trim().length > 0) {
        const term = `%${q.trim()}%`;
        query += ` AND (item_name LIKE ? OR item_code LIKE ? OR description LIKE ?)`;
        params.push(term, term, term);
    }
    query += ` AND (is_finished_good = 1 OR is_purchased = 1) AND is_raw_material = 0`;
    query += ` ORDER BY item_name ASC LIMIT ?`;
    params.push(limit);
    return db.prepare(query).all(...params);
}
function searchCustomers(db, q, limit) {
    let query = `
    SELECT id, customer_code, customer_name, contact_person, email, phone,
           billing_address, payment_terms, is_active
    FROM customers WHERE is_active = 1
  `;
    const params = [];
    if (q && q.trim().length > 0) {
        const term = `%${q.trim()}%`;
        query += ` AND (customer_name LIKE ? OR customer_code LIKE ? OR phone LIKE ? OR email LIKE ?)`;
        params.push(term, term, term, term);
    }
    query += ` ORDER BY customer_name ASC LIMIT ?`;
    params.push(limit);
    return db.prepare(query).all(...params);
}
function getTaxRates(db) {
    return db.prepare(`
    SELECT id, name, rate, is_default FROM tax_rates WHERE is_active = 1 ORDER BY rate ASC
  `).all();
}
function getPaymentTerms(db) {
    return db.prepare(`
    SELECT id, name, days, is_default FROM payment_terms WHERE is_active = 1 ORDER BY days ASC
  `).all();
}
function findWarehouseForItem(db, itemId, quantity) {
    const balance = db.prepare(`
    SELECT warehouse_id, quantity FROM stock_balances
    WHERE item_id = ? AND quantity >= ? ORDER BY quantity DESC LIMIT 1
  `).get(itemId, quantity);
    if (balance?.warehouse_id)
        return balance.warehouse_id;
    const anyBalance = db.prepare(`
    SELECT warehouse_id, quantity FROM stock_balances
    WHERE item_id = ? AND quantity > 0 ORDER BY quantity DESC LIMIT 1
  `).get(itemId);
    if (anyBalance?.warehouse_id)
        return anyBalance.warehouse_id;
    const defaultWh = db.prepare('SELECT id FROM warehouses WHERE warehouse_code = ? AND is_active = 1').get('WH-001');
    return defaultWh?.id || 1;
}
function submitInvoice(db, data) {
    if (!data.customer_id || data.customer_id <= 0)
        throw new Error('Invalid customer_id');
    if (!data.invoice_date)
        throw new Error('invoice_date is required');
    if (!data.items || data.items.length === 0)
        throw new Error('At least one invoice item is required');
    for (const item of data.items) {
        if (!item.item_id || item.item_id <= 0)
            throw new Error('Invalid item_id in invoice items');
        if (!item.quantity || item.quantity <= 0)
            throw new Error('Invalid quantity in invoice items');
        if (item.unit_price === undefined || item.unit_price < 0)
            throw new Error('Invalid unit_price in invoice items');
    }
    return db.transaction(() => {
        // ACC-18 interim: server-authoritative money — each line is
        // round(qty × price − discount) with tax at the line boundary; the
        // header total is the sum of those lines.
        const totalAmount = (0, currency_1.computeInvoiceTotal)(data.items);
        const totalTax = data.items.reduce((sum, item) => {
            const gross = (item.quantity || 0) * (item.unit_price || 0);
            return sum + gross * ((item.tax_rate || 0) / 100);
        }, 0);
        const invoiceResult = db.prepare(`
      INSERT INTO invoices (
        invoice_no, customer_id, invoice_date, due_date, status,
        total_amount, paid_amount, balance_amount, notes, terms, created_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(data.invoice_no || generateInvoiceNumber(), data.customer_id, data.invoice_date, data.due_date || data.invoice_date, data.status || 'Unpaid', totalAmount, 0, totalAmount, data.notes || null, data.terms || null, data.userId);
        const invoiceId = invoiceResult.lastInsertRowid;
        const invoiceNo = data.invoice_no || (invoiceResult.lastInsertRowid ? `INV-${Date.now()}` : '');
        for (const item of data.items) {
            const { amount, netAmount, taxAmount } = (0, currency_1.decomposeLineAmount)(item);
            db.prepare(`
        INSERT INTO invoice_items (
          invoice_id, item_id, quantity, unit_price, amount, tax_rate, discount_type, discount_value,
          net_amount, tax_amount
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).run(invoiceId, item.item_id, item.quantity, item.unit_price, amount, item.tax_rate || 0, item.discount_type || 'percentage', item.discount_value || 0, netAmount, taxAmount);
            const warehouseId = item.warehouse_id || findWarehouseForItem(db, item.item_id, item.quantity);
            // INV-03: mobile sales go through the SAME guarded, batch-consuming
            // path as desktop invoices — availability is enforced inside the
            // transaction and FIFO cost layers are consumed (no balance-only
            // writes, no unbatched rows). GL posting happens below.
            const movements = StockMovement_1.default.recordBatchMovement({
                item_id: item.item_id,
                warehouse_id: warehouseId,
                movement_type: 'SALE',
                quantity: -item.quantity,
                unit_cost: item.unit_price,
                reference_doctype: 'INVOICE',
                reference_docno: String(invoiceId),
                remarks: `Sold via Invoice ${invoiceId}`,
                movement_date: data.invoice_date,
            }, data.userId, db);
        }
        if (data.record_payment && data.payment) {
            const paymentAmount = data.payment.amount || 0;
            (0, sequence_1.initializeSequenceFromMax)(db, 'PAY_last_no', 'payments', 'payment_no', 'PAY');
            const nextPaymentNo = (0, sequence_1.getNextSequenceNumber)(db, 'PAY_last_no');
            const paymentNo = `PAY${String(nextPaymentNo).padStart(3, '0')}`;
            const paymentResult = db.prepare(`
        INSERT INTO payments (
          payment_no, customer_id, invoice_id, payment_date,
          amount, payment_method, reference_no, notes, created_by
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).run(paymentNo, data.customer_id, invoiceId, data.payment.payment_date || data.invoice_date, paymentAmount, data.payment.payment_method || 'Cash', data.payment.reference_no || null, data.payment.notes || null, data.userId);
            const paymentId = paymentResult.lastInsertRowid;
            db.prepare('INSERT INTO payment_allocations (payment_id, invoice_id, amount) VALUES (?, ?, ?)').run(paymentId, invoiceId, paymentAmount);
            db.prepare(`
        UPDATE invoices SET paid_amount = ?, balance_amount = ?, status = ? WHERE id = ?
      `).run(paymentAmount, totalAmount - paymentAmount, paymentAmount >= totalAmount ? 'Paid' : 'Partially Paid', invoiceId);
            // Create ledger entry for payment (credit to reduce AR)
            ledgerUtils_1.default.createLedgerEntry(data.customer_id, data.payment.payment_date || data.invoice_date, 'PAYMENT', paymentNo, 0, paymentAmount, `Payment ${paymentNo} for Invoice ${invoiceId}`);
        }
        // Create customer ledger entry for the invoice (debit to increase AR)
        ledgerUtils_1.default.createLedgerEntry(data.customer_id, data.invoice_date, 'INVOICE', invoiceNo, totalAmount, 0, `Invoice ${invoiceNo}`);
        // GL postings (ACC-06): mobile invoices previously posted nothing.
        // Same sequence as the standard invoice path — revenue entry with the
        // computed tax split, COGS at recorded unit cost, and the payment
        // entry when one was recorded inline.
        accountingService_1.default.postInvoiceEntry(db, {
            invoiceId,
            invoiceNo,
            totalAmount,
            invoiceDate: data.invoice_date,
            userId: data.userId,
            taxAmount: totalTax,
        });
        const cogsRows = db.prepare(`
      SELECT quantity * unit_cost AS line_cogs FROM stock_movements
      WHERE reference_doctype = 'INVOICE' AND reference_docno = ?
        AND movement_type = 'SALE'
    `).all(String(invoiceId));
        const cogsTotal = cogsRows.reduce((s, r) => s + Math.abs(Number(r.line_cogs)), 0);
        if (cogsTotal > 0) {
            accountingService_1.default.postCOGSEntry(db, {
                invoiceId,
                invoiceNo,
                cogsAmount: (0, currency_1.parseCurrency)(cogsTotal),
                invoiceDate: data.invoice_date,
                userId: data.userId,
            });
        }
        if (data.record_payment && data.payment && (data.payment.amount || 0) > 0) {
            const payRow = db.prepare('SELECT id, payment_no, amount, payment_date, payment_method FROM payments WHERE invoice_id = ? ORDER BY id DESC LIMIT 1').get(invoiceId);
            if (payRow) {
                accountingService_1.default.postPaymentEntry(db, {
                    paymentId: payRow.id,
                    paymentNo: payRow.payment_no,
                    amount: Number(payRow.amount),
                    paymentDate: payRow.payment_date,
                    paymentMethod: payRow.payment_method,
                    customerId: data.customer_id,
                    userId: data.userId,
                });
            }
        }
        // Update customer balance
        ledgerUtils_1.default.recalcCustomerBalanceFromLedger(data.customer_id);
        if (data.draft_id) {
            db.prepare('DELETE FROM invoice_drafts WHERE id = ?').run(data.draft_id);
        }
        return invoiceId;
    })();
}
function getInvoiceWithCustomer(db, invoiceId) {
    return db.prepare(`
    SELECT i.*, c.customer_name, c.email as customer_email,
           c.phone as customer_phone, c.billing_address as customer_address
    FROM invoices i LEFT JOIN customers c ON i.customer_id = c.id
    WHERE i.id = ?
  `).get(invoiceId);
}
function generateInvoiceNumber() {
    const year = new Date().getFullYear();
    const timestamp = Date.now().toString().slice(-6);
    const random = Math.floor(Math.random() * 1000).toString().padStart(3, '0');
    return `INV-${year}-${timestamp}${random}`;
}
exports.default = {
    getDraftById,
    getDraftBySession,
    createDraft,
    updateDraft,
    deleteDraft,
    searchItems,
    searchCustomers,
    getTaxRates,
    getPaymentTerms,
    submitInvoice,
    getInvoiceWithCustomer,
};
