"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const currency_1 = require("../utils/currency");
const sequence_1 = require("../utils/sequence");
const sqlSanitizer_1 = require("../utils/sqlSanitizer");
const logger_1 = __importDefault(require("../utils/logger"));
const StockMovement_1 = __importDefault(require("./StockMovement"));
// Whitelisted sort columns → qualified SQL column for the list query (the
// customer/sales-order/quotation/user joins make bare names ambiguous).
const INVOICE_SORT_COLUMN_MAP = {
    invoice_no: 'i.invoice_no',
    invoice_date: 'i.invoice_date',
    customer_name: 'COALESCE(c.customer_name, i.customer_name)',
    status: 'i.status',
    total_amount: 'i.total_amount',
    paid_amount: 'i.paid_amount',
    balance_amount: 'i.balance_amount',
    due_date: 'i.due_date',
    created_at: 'i.created_at',
};
// Whitelisted sort columns → qualified SQL column for the returns query
// (the item/warehouse/user/invoice joins make bare names ambiguous).
const INVOICE_RETURN_SORT_COLUMN_MAP = {
    movement_no: 'sm.movement_no',
    return_date: 'sm.movement_date',
    item_name: 'i.item_name',
    customer_name: 'inv.customer_name',
    warehouse_name: 'w.warehouse_name',
    quantity: 'sm.quantity',
    unit_cost: 'sm.unit_cost',
    created_at: 'sm.created_at',
};
class InvoiceModel {
    /**
     * Consume a quantity of an item from the oldest available stock batches (FIFO).
     * Delegates to the centralized implementation in StockMovementModel.
     */
    static consumeFromOldestBatches(itemId, warehouseId, quantity, db) {
        return StockMovement_1.default.consumeFromOldestBatches(itemId, warehouseId, quantity, db);
    }
    /**
     * After stock consumption, denormalize expiry info onto invoice items
     * and build the invoice-level expiry_notes string.
     *
     * @param invoiceId - The invoice to process
     * @param consumptions - Array of { itemId, consumption[] } per line item
     * @param db - Database connection
     */
    static denormalizeExpiryInfo(invoiceId, consumptions, db) {
        const today = new Date().toISOString().split('T')[0];
        const expiryNotes = [];
        for (const { itemId, consumption } of consumptions) {
            // Get ALL invoice item rows for this item (handles duplicate lines)
            const invoiceItems = db.prepare('SELECT id, item_id FROM invoice_items WHERE invoice_id = ? AND item_id = ?').all(invoiceId, itemId);
            if (invoiceItems.length === 0)
                continue;
            // Look up expiry dates from consumed batches
            const batchIds = consumption.filter(c => c.batchId !== null).map(c => c.batchId);
            if (batchIds.length === 0)
                continue;
            const batches = db.prepare(`SELECT id, expiry_date FROM stock_batches WHERE id IN (${batchIds.map(() => '?').join(',')})`).all(...batchIds);
            // Find the earliest expiry date across consumed batches
            const expiryDates = batches
                .filter(b => b.expiry_date)
                .map(b => b.expiry_date)
                .sort();
            if (expiryDates.length === 0)
                continue;
            const earliestExpiry = expiryDates[0];
            const isExpired = earliestExpiry < today;
            // Get item name for the note
            const item = db.prepare('SELECT item_name FROM items WHERE id = ?').get(itemId);
            const itemName = item?.item_name || `Item ${itemId}`;
            // Update ALL invoice item rows for this item with expiry info
            for (const ii of invoiceItems) {
                db.prepare('UPDATE invoice_items SET expiry_date = ?, is_expired_at_sale = ? WHERE id = ?').run(earliestExpiry, isExpired ? 1 : 0, ii.id);
            }
            // Build note line (only once per item, not per line)
            if (isExpired) {
                const expiryDate = new Date(earliestExpiry);
                const todayDate = new Date(today);
                const daysExpired = Math.floor((todayDate.getTime() - expiryDate.getTime()) / (1000 * 60 * 60 * 24));
                expiryNotes.push(`• ${itemName} — expired on ${earliestExpiry} (sold ${daysExpired} days after expiry)`);
            }
        }
        // Build the expiry_notes string
        if (expiryNotes.length > 0) {
            const notes = `⚠️ Expiry Notice\n${expiryNotes.join('\n')}`;
            db.prepare('UPDATE invoices SET expiry_notes = ? WHERE id = ?').run(notes, invoiceId);
        }
    }
    /**
     * Get invoice by ID with items and source links
     */
    static getById(id, db) {
        const invoice = db.prepare(`
      SELECT
        i.*,
        so.so_no,
        q.quotation_no,
        u.username as created_by_username
      FROM invoices i
      LEFT JOIN sales_orders so ON i.so_id = so.id
      LEFT JOIN quotations q ON i.quotation_id = q.id
      LEFT JOIN users u ON i.created_by = u.id
      WHERE i.id = ?
    `).get(id);
        if (!invoice) {
            return undefined;
        }
        // Get items
        const items = db.prepare(`
       SELECT
         ii.id, ii.invoice_id, ii.item_id, ii.quantity, ii.returned_qty, ii.unit_price, ii.amount,
         ii.tax_rate, ii.discount_type, ii.discount_value,
         ii.expiry_date, ii.is_expired_at_sale,
         i.item_code, i.item_name
       FROM invoice_items ii
       LEFT JOIN items i ON ii.item_id = i.id
       WHERE ii.invoice_id = ?
       ORDER BY ii.id
     `).all(id);
        return {
            ...invoice,
            items
        };
    }
    /**
     * Get all invoices with filters — paged. Returns the canonical
     * `{ rows, total, pageNum, limitNum }` shape (grid-pagination §1).
     */
    static getAll(filters = {}, db) {
        const pageNum = filters.page || 1;
        const limitNum = filters.limit || 10;
        const select = `
      SELECT
        i.*,
        COALESCE(c.customer_name, i.customer_name) as customer_name,
        so.so_no,
        q.quotation_no,
        u.username as created_by_username
      FROM invoices i
      LEFT JOIN customers c ON i.customer_id = c.id
      LEFT JOIN sales_orders so ON i.so_id = so.id
      LEFT JOIN quotations q ON i.quotation_id = q.id
      LEFT JOIN users u ON i.created_by = u.id
      WHERE 1=1
    `;
        const conditions = [];
        const params = [];
        if (filters.statuses && filters.statuses.length > 0) {
            conditions.push(`i.status IN (${filters.statuses.map(() => '?').join(',')})`);
            params.push(...filters.statuses);
        }
        if (filters.customer_id) {
            conditions.push('i.customer_id = ?');
            params.push(filters.customer_id);
        }
        if (filters.customer_name) {
            conditions.push('i.customer_name LIKE ?');
            params.push(`%${filters.customer_name}%`);
        }
        if (filters.search) {
            conditions.push('(i.invoice_no LIKE ? OR COALESCE(c.customer_name, i.customer_name) LIKE ?)');
            const term = `%${filters.search}%`;
            params.push(term, term);
        }
        if (filters.start_date) {
            conditions.push('i.invoice_date >= ?');
            params.push(filters.start_date);
        }
        if (filters.end_date) {
            conditions.push('i.invoice_date <= ?');
            params.push(filters.end_date);
        }
        if (filters.source_type) {
            conditions.push('i.source_type = ?');
            params.push(filters.source_type);
        }
        if (filters.so_id) {
            conditions.push('i.so_id = ?');
            params.push(filters.so_id);
        }
        const where = conditions.length ? ` AND ${conditions.join(' AND ')}` : '';
        // Sort — whitelisted via sqlSanitizer, mapped to qualified columns
        // (default matches the pre-paging behavior: newest invoice first).
        const { column, order } = (0, sqlSanitizer_1.sanitizeSortParams)(filters.sortBy || 'invoice_date', filters.sortOrder || 'DESC', sqlSanitizer_1.INVOICE_SORT_COLUMNS, 'invoice_date', 'DESC');
        const sortColumn = INVOICE_SORT_COLUMN_MAP[column] || 'i.invoice_date';
        const offset = (pageNum - 1) * limitNum;
        const invoices = db
            .prepare(`${select}${where} ORDER BY ${sortColumn} ${order}, i.id DESC LIMIT ? OFFSET ?`)
            .all(...params, limitNum, offset);
        const countRow = db
            .prepare(`SELECT COUNT(*) as total FROM invoices i
        LEFT JOIN customers c ON i.customer_id = c.id
        WHERE 1=1${where}`)
            .get(...params);
        // Get items for each invoice
        const rows = invoices.map(invoice => {
            const items = db.prepare(`
        SELECT
          ii.id, ii.invoice_id, ii.item_id, ii.quantity, ii.returned_qty, ii.unit_price, ii.amount,
          ii.tax_rate, ii.discount_type, ii.discount_value,
          ii.expiry_date, ii.is_expired_at_sale,
          i.item_code, i.item_name
        FROM invoice_items ii
        LEFT JOIN items i ON ii.item_id = i.id
        WHERE ii.invoice_id = ?
        ORDER BY ii.id
      `).all(invoice.id);
            return {
                ...invoice,
                items
            };
        });
        return { rows, total: countRow.total, pageNum, limitNum };
    }
    /**
    * Get sales cycle chain for an invoice (quotation -> SO -> invoice)
    */
    static getSalesCycleChain(invoiceId, db) {
        const invoice = this.getById(invoiceId, db);
        let salesOrder = undefined;
        let quotation = undefined;
        if (invoice?.so_id) {
            salesOrder = db.prepare(`
        SELECT
          so.*,
          w.warehouse_code,
          w.warehouse_name,
          u.username as created_by_username,
          q.quotation_no
        FROM sales_orders so
        LEFT JOIN warehouses w ON so.warehouse_id = w.id
        LEFT JOIN users u ON so.created_by = u.id
        LEFT JOIN quotations q ON so.source_id = q.id AND so.source_type = 'QUOTATION'
        WHERE so.id = ?
      `).get(invoice.so_id);
            // Get quotation if SO has source
            if (salesOrder?.source_type === 'QUOTATION' && salesOrder.source_id) {
                quotation = db.prepare(`
          SELECT
            q.*,
            w.warehouse_code,
            w.warehouse_name,
            u.username as created_by_username
          FROM quotations q
          LEFT JOIN warehouses w ON q.warehouse_id = w.id
          LEFT JOIN users u ON q.created_by = u.id
          WHERE q.id = ?
        `).get(salesOrder.source_id);
            }
        }
        else if (invoice?.quotation_id) {
            // Direct quotation link (if invoice was created directly from quotation)
            quotation = db.prepare(`
        SELECT
          q.*,
          w.warehouse_code,
          w.warehouse_name,
          u.username as created_by_username
        FROM quotations q
        LEFT JOIN warehouses w ON q.warehouse_id = w.id
        LEFT JOIN users u ON q.created_by = u.id
        WHERE q.id = ?
      `).get(invoice.quotation_id);
        }
        return {
            quotation,
            salesOrder,
            invoice
        };
    }
    /**
     * Generate the next payment number atomically using a transaction.
     * This prevents race conditions where two concurrent requests could
     * read the same MAX(payment_no) and generate duplicates.
     */
    static generatePaymentNoAtomic(db) {
        const settingKey = 'PAY_last_no';
        // Sync the PAY_last_no setting with the actual max payment_no by numeric
        // comparison (not string comparison). String MAX on PAY1000 vs PAY999
        // would return PAY999 because '9' > '1' at position 3, so we must
        // extract the numeric portion and use MAX on INTEGER.
        const maxResult = db.prepare(`SELECT MAX(CAST(SUBSTR(payment_no, 4) AS INTEGER)) as max_val FROM payments WHERE payment_no LIKE 'PAY%'`).get();
        const maxNo = maxResult?.max_val ?? 0;
        if (maxNo > 0) {
            // Atomically bump setting to at least maxNo so next number is fresh
            db.prepare(`
          INSERT INTO settings (key, value, updated_at)
          VALUES (?, CAST(? AS TEXT), CURRENT_TIMESTAMP)
          ON CONFLICT(key) DO UPDATE SET
            value = CAST(MAX(CAST(settings.value AS INTEGER), ?) AS TEXT),
            updated_at = CURRENT_TIMESTAMP
        `).run(settingKey, maxNo.toString(), maxNo.toString());
        }
        // Atomically increment and get the next sequence number
        const nextNo = (0, sequence_1.getNextSequenceNumber)(db, settingKey);
        return `PAY${String(nextNo).padStart(3, '0')}`;
    }
    /**
     * Find the best warehouse for an item, with stock validation logging.
     * Returns the warehouse_id to use for deduction.
     */
    static findWarehouseForItem(db, itemId, requestedQty, explicitWarehouseId) {
        if (explicitWarehouseId) {
            // Validate stock at the explicit warehouse
            const balance = db.prepare(`
        SELECT warehouse_id, quantity
        FROM stock_balances
        WHERE item_id = ? AND warehouse_id = ?
      `).get(itemId, explicitWarehouseId);
            if (!balance || balance.quantity < requestedQty) {
                logger_1.default.warn(`Insufficient stock for item ${itemId} at warehouse ${explicitWarehouseId}: ` +
                    `available=${balance?.quantity ?? 0}, requested=${requestedQty}. Proceeding anyway.`);
            }
            return explicitWarehouseId;
        }
        // Find warehouse with sufficient stock
        const warehouseWithStock = db.prepare(`
      SELECT warehouse_id, quantity
      FROM stock_balances
      WHERE item_id = ? AND quantity >= ?
      ORDER BY quantity DESC
      LIMIT 1
    `).get(itemId, requestedQty);
        if (warehouseWithStock) {
            return warehouseWithStock.warehouse_id;
        }
        // Fallback: any warehouse with this item (even if insufficient)
        const anyWarehouse = db.prepare(`
      SELECT warehouse_id, quantity
      FROM stock_balances
      WHERE item_id = ? AND quantity > 0
      ORDER BY quantity DESC
      LIMIT 1
    `).get(itemId);
        if (anyWarehouse) {
            logger_1.default.warn(`No warehouse has sufficient stock for item ${itemId}: ` +
                `best available=${anyWarehouse.quantity}, requested=${requestedQty}. ` +
                `Using warehouse ${anyWarehouse.warehouse_id}.`);
            return anyWarehouse.warehouse_id;
        }
        // Last resort: default warehouse
        const defaultWarehouse = db.prepare(`SELECT id FROM warehouses WHERE warehouse_code = ? AND is_active = 1`).get('WH-001');
        logger_1.default.warn(`No stock found for item ${itemId} in any warehouse. ` +
            `Falling back to default warehouse.`);
        return defaultWarehouse ? defaultWarehouse.id : 1;
    }
    /**
     * Reverse stock movements for a list of invoice items that were previously sold.
     * Restores quantity_remaining on stock_batches and creates ADJUSTMENT movements
     * to fix stock_balances. Used during invoice update and delete.
     */
    static reverseStockForItems(db, items, invoiceNo, userId, referenceDoctype, explicitWarehouseId) {
        for (const item of items) {
            // Find all SALE movements for this item + invoice (they have batch_id links)
            const saleMovements = db.prepare(`
        SELECT warehouse_id, quantity, unit_cost, batch_id
        FROM stock_movements
        WHERE item_id = ? AND reference_docno = ? AND movement_type = 'SALE'
        ORDER BY id
      `).all(item.item_id, invoiceNo);
            if (saleMovements.length === 0) {
                logger_1.default.warn(`[BatchReversal] No SALE movements found for item ${item.item_id} on invoice ${invoiceNo}`);
                continue;
            }
            // A customer return is restocked into the warehouse the user chose
            // (return form); otherwise it goes back to the warehouse the sale
            // was dispatched from. Batch-quantity restore below stays on the
            // ORIGINAL sale batches either way — the chosen warehouse only
            // affects where the visible stock-summary movement lands.
            const warehouseId = explicitWarehouseId ?? saleMovements[0].warehouse_id;
            // Calculate how much was ALREADY returned for this item on this invoice
            const alreadyReturned = db.prepare(`
        SELECT COALESCE(SUM(quantity), 0) as total_returned
        FROM stock_movements
        WHERE item_id = ? AND reference_docno = ? AND movement_type = 'ADJUSTMENT' AND reference_doctype = 'RETURN'
      `).get(item.item_id, invoiceNo);
            const totalSold = saleMovements.reduce((sum, m) => sum + Math.abs(m.quantity), 0);
            const totalToReturn = Math.abs(item.quantity);
            const alreadyReturnedQty = Math.abs(alreadyReturned.total_returned);
            const remainingToReturn = Math.max(0, totalToReturn - alreadyReturnedQty);
            if (remainingToReturn <= 0) {
                logger_1.default.warn(`[BatchReversal] Item ${item.item_id} already fully returned on invoice ${invoiceNo}`);
                continue;
            }
            // Ratio based on remaining-to-return vs total sold
            const ratio = Math.abs(totalSold) < 0.001 ? 1 : Math.min(remainingToReturn / totalSold, 1);
            // Restore quantity_remaining on each consumed batch (except legacy/fallback entries)
            for (const movement of saleMovements) {
                if (movement.batch_id !== null) {
                    const restoreQty = Math.abs(movement.quantity) * ratio;
                    db.prepare(`
            UPDATE stock_batches
            SET quantity_remaining = quantity_remaining + ?
            WHERE id = ?
          `).run(restoreQty, movement.batch_id);
                }
            }
            // Calculate the total actual cost from the original SALE movements
            let totalActualCost = 0;
            let totalQty = 0;
            for (const movement of saleMovements) {
                const absQty = Math.abs(movement.quantity);
                totalActualCost += absQty * movement.unit_cost;
                totalQty += absQty;
            }
            const avgUnitCost = totalQty > 0 ? totalActualCost / totalQty : item.unit_price;
            // Add stock back (positive quantity to reverse the sale) — only the remaining qty
            StockMovement_1.default.recordMovement({
                item_id: item.item_id,
                warehouse_id: warehouseId,
                movement_type: 'ADJUSTMENT',
                quantity: remainingToReturn, // Only the remaining qty to return
                unit_cost: avgUnitCost,
                reference_doctype: referenceDoctype,
                reference_docno: invoiceNo,
                remarks: `Stock reversed - Invoice ${invoiceNo} ${referenceDoctype === 'INVOICE_DELETE' ? 'deleted' : referenceDoctype === 'RETURN' ? 'returned' : 'updated'}`,
                movement_date: new Date().toISOString().split('T')[0],
            }, userId, db);
        }
    }
    /**
     * Create a new invoice
     */
    static createInvoice(db, data, userId) {
        if (!data.customer_id || data.customer_id <= 0) {
            throw new Error('Invalid customer_id');
        }
        if (!data.invoice_date) {
            throw new Error('invoice_date is required');
        }
        if (!data.items || data.items.length === 0) {
            throw new Error('At least one invoice item is required');
        }
        for (const item of data.items) {
            if (!item.item_id || item.item_id <= 0)
                throw new Error('Invalid item_id in invoice items');
            if (!item.quantity || item.quantity <= 0)
                throw new Error('Invalid quantity in invoice items');
            if (item.unit_price === undefined || item.unit_price < 0)
                throw new Error('Invalid unit_price in invoice items');
        }
        // CRITICAL-1 fix: when the caller supplies paid_amount/balance_amount
        // overrides (e.g., an initial payment was recorded as part of the
        // same request), honor them. Otherwise default to 0 paid and the
        // full total as balance. This is critical for A/R correctness:
        // every invoice created with an initial payment was previously
        // saved with paid=0/balance=total, which left the monetary
        // columns inconsistent with the recorded payment_allocations.
        const totalAmount = data.total_amount ?? 0;
        const paidAmount = data.paid_amount ?? 0;
        const balanceAmount = data.balance_amount ?? Math.max(0, totalAmount - paidAmount);
        const result = db.prepare(`
      INSERT INTO invoices (
        invoice_no, customer_id, invoice_date, due_date, status,
        total_amount, paid_amount, balance_amount, notes,
        discount_scope, discount_type, discount_value, terms, created_by,
        source_type
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(data.invoice_no || null, data.customer_id, data.invoice_date, data.due_date || null, data.status || 'Unpaid', totalAmount, paidAmount, balanceAmount, data.notes || null, data.discount_scope || 'invoice', data.discount_type || 'percentage', data.discount_value || 0, data.terms || null, userId, data.source_type || null);
        return result.lastInsertRowid;
    }
    /**
     * Create a new invoice item
     */
    static createInvoiceItem(db, invoiceId, item) {
        const amount = (0, currency_1.multiplyCurrency)(item.quantity, item.unit_price);
        db.prepare(`
      INSERT INTO invoice_items (
        invoice_id, item_id, quantity, unit_price, amount,
        tax_rate, discount_type, discount_value
      )
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)
     `).run(invoiceId, item.item_id, item.quantity, item.unit_price, amount, item.tax_rate || 0, item.discount_type || 'percentage', item.discount_value || 0);
    }
    /**
     * Create a new payment
     */
    static createPayment(db, paymentNo, customerId, paymentDate, amount, paymentMethod, referenceNo, notes) {
        const result = db.prepare(`
      INSERT INTO payments (
        payment_no, customer_id, payment_date, amount,
        payment_method, reference_no, notes
      )
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `).run(paymentNo, customerId, paymentDate, amount, paymentMethod || null, referenceNo || null, notes || null);
        return result.lastInsertRowid;
    }
    /**
     * Create a payment allocation
     */
    static createPaymentAllocation(db, paymentId, invoiceId, amount) {
        db.prepare(`
      INSERT INTO payment_allocations (payment_id, invoice_id, amount)
      VALUES (?, ?, ?)
    `).run(paymentId, invoiceId, amount);
    }
    /**
     * Create a ledger entry
     */
    static createLedgerEntry(db, customerId, type, referenceNo, debit, credit, description) {
        // Calculate running balance from last entry for this customer
        const lastBalanceResult = db.prepare(`
      SELECT balance FROM customer_ledger
      WHERE customer_id = ?
      ORDER BY id DESC
      LIMIT 1
    `).get(customerId);
        const lastBalance = (0, currency_1.parseCurrency)(lastBalanceResult?.balance);
        const safeDebit = (0, currency_1.parseCurrency)(debit);
        const safeCredit = (0, currency_1.parseCurrency)(credit);
        const newBalance = (0, currency_1.subtractCurrency)((0, currency_1.addCurrency)(lastBalance, safeDebit), safeCredit);
        db.prepare(`
      INSERT INTO customer_ledger (
        customer_id, transaction_date, transaction_type, reference_no,
        debit, credit, balance, description
      )
      VALUES (?, DATE('now'), ?, ?, ?, ?, ?, ?)
    `).run(customerId, type, referenceNo, safeDebit, safeCredit, newBalance, description);
    }
    /**
     * Update customer balance
     */
    static updateCustomerBalance(db, customerId) {
        // Balance is recalculated from ledger entries — no action needed here
    }
    /**
     * Get total paid for an invoice
     */
    static getTotalPaid(db, invoiceId) {
        const result = db.prepare(`
      SELECT COALESCE(SUM(amount), 0) as total_paid
      FROM payment_allocations
      WHERE invoice_id = ?
    `).get(invoiceId);
        return result.total_paid;
    }
    /**
     * Get invoice by ID for balance calculation
     */
    static getInvoiceForBalance(db, invoiceId) {
        return db.prepare(`SELECT total_amount, status FROM invoices WHERE id = ?`).get(invoiceId);
    }
    /**
     * Update invoice record
     */
    static updateInvoice(db, invoiceId, data) {
        db.prepare(`
      UPDATE invoices
      SET
        invoice_no = ?, customer_id = ?, invoice_date = ?, due_date = ?,
        status = ?, total_amount = ?, paid_amount = ?, balance_amount = ?, notes = ?,
        discount_scope = ?, discount_type = ?, discount_value = ?, terms = ?,
        updated_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `).run(data.invoice_no, data.customer_id, data.invoice_date, data.due_date, data.status, data.total_amount, data.paid_amount, data.balance_amount, data.notes || null, data.discount_scope || 'invoice', data.discount_type || 'percentage', data.discount_value || 0, data.terms || null, invoiceId);
    }
    /**
     * Get invoice items for stock reversal
     */
    static getInvoiceItemsForStockReverse(db, invoiceId) {
        return db.prepare(`SELECT item_id, quantity, unit_price FROM invoice_items WHERE invoice_id = ?`).all(invoiceId);
    }
    /**
     * Delete invoice items
     */
    static deleteInvoiceItems(db, invoiceId) {
        db.prepare(`DELETE FROM invoice_items WHERE invoice_id = ?`).run(invoiceId);
    }
    /**
     * Delete customer ledger entry by reference
     */
    static deleteLedgerEntryByReference(db, referenceNo) {
        db.prepare(`DELETE FROM customer_ledger WHERE reference_no = ?`).run(referenceNo);
    }
    /**
     * Delete payment allocations by invoice ID
     */
    static deletePaymentAllocationsByInvoiceId(db, invoiceId) {
        db.prepare(`DELETE FROM payment_allocations WHERE invoice_id = ?`).run(invoiceId);
    }
    /**
     * Delete payment by ID
     */
    static deletePaymentById(db, paymentId) {
        db.prepare(`DELETE FROM payments WHERE id = ?`).run(paymentId);
    }
    /**
     * Delete invoice
     */
    static deleteInvoice(db, invoiceId) {
        db.prepare(`DELETE FROM invoices WHERE id = ?`).run(invoiceId);
    }
    /**
     * Get invoices by quotation ID (via SO or direct)
     */
    static getByQuotationId(quotationId, db) {
        const query = `
      SELECT
        i.*,
        so.so_no,
        q.quotation_no,
        u.username as created_by_username
      FROM invoices i
      LEFT JOIN sales_orders so ON i.so_id = so.id AND so.source_id = ?
      LEFT JOIN quotations q ON i.quotation_id = q.id OR (so.source_id = q.id)
      LEFT JOIN users u ON i.created_by = u.id
      WHERE i.quotation_id = ? OR i.so_id IN (SELECT id FROM sales_orders WHERE source_id = ?)
      ORDER BY i.invoice_date DESC
    `;
        const invoices = db.prepare(query).all(quotationId, quotationId, quotationId);
        // Get items for each invoice
        return invoices.map(invoice => {
            const items = db.prepare(`
        SELECT
          ii.id, ii.invoice_id, ii.item_id, ii.quantity, ii.returned_qty, ii.unit_price, ii.amount,
          ii.tax_rate, ii.discount_type, ii.discount_value,
          ii.expiry_date, ii.is_expired_at_sale,
          i.item_code, i.item_name
        FROM invoice_items ii
        LEFT JOIN items i ON ii.item_id = i.id
        WHERE ii.invoice_id = ?
        ORDER BY ii.id
      `).all(invoice.id);
            return {
                ...invoice,
                items
            };
        });
    }
    /**
     * Update invoice source tracking (used when converting SO to invoice)
     */
    static updateSourceTracking(invoiceId, soId, quotationId, db) {
        db.prepare(`
      UPDATE invoices
      SET source_type = 'SALES_ORDER',
          so_id = ?,
          quotation_id = ?,
          updated_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `).run(soId, quotationId, invoiceId);
    }
    /**
     * Get invoice statistics by customer
     */
    static getStatsByCustomer(customerId, db) {
        return db.prepare(`
      SELECT
        COUNT(*) as total_invoices,
        COALESCE(SUM(total_amount), 0) as total_amount,
        COALESCE(SUM(paid_amount), 0) as paid_amount,
        COALESCE(SUM(balance_amount), 0) as outstanding_amount,
        COALESCE(AVG(total_amount), 0) as avg_invoice_value
      FROM invoices
      WHERE customer_id = ?
    `).get(customerId);
    }
    /**
     * Get invoices by status filter — delegates to the paged query so the
     * status-CSV path and the paged list share one definition. Kept for
     * backward compatibility (returns the full unfiltered-by-page set).
     */
    static getByStatus(statusList, db) {
        return this.getAll({ statuses: statusList }, db).rows;
    }
    static getWithCustomer(id, db) {
        return db.prepare(`
      SELECT i.*, c.customer_name, c.email as customer_email,
             c.phone as customer_phone, c.billing_address as customer_address
      FROM invoices i LEFT JOIN customers c ON i.customer_id = c.id WHERE i.id = ?
    `).get(id);
    }
    static getItems(invoiceId, db) {
        return db.prepare(`
      SELECT ii.id, ii.item_id, ii.quantity, ii.returned_qty, ii.unit_price, ii.amount, ii.tax_rate,
             ii.discount_type, ii.discount_value, item.item_name, item.item_code
      FROM invoice_items ii LEFT JOIN items item ON ii.item_id = item.id
      WHERE ii.invoice_id = ?
    `).all(invoiceId);
    }
    static getPayments(invoiceId, db) {
        return db.prepare(`
      SELECT p.id, p.payment_no, p.payment_date, p.payment_method,
             p.reference_no, p.notes, pa.amount
      FROM payment_allocations pa JOIN payments p ON pa.payment_id = p.id
      WHERE pa.invoice_id = ? ORDER BY p.payment_date DESC
    `).all(invoiceId);
    }
    static getItemsForStockReverse(invoiceId, db) {
        return db.prepare(`SELECT item_id, quantity, unit_price FROM invoice_items WHERE invoice_id = ?`).all(invoiceId);
    }
    static deleteItems(db, invoiceId) {
        db.prepare(`DELETE FROM invoice_items WHERE invoice_id = ?`).run(invoiceId);
    }
    static getBySalesOrderId(soId, db) {
        return db.prepare(`
      SELECT i.*, c.customer_name
      FROM invoices i
      LEFT JOIN customers c ON i.customer_id = c.id
      WHERE i.so_id = ?
    `).all(soId);
    }
    static getStatsByDateRange(startDate, endDate, db) {
        return db.prepare(`
      SELECT COUNT(*) as total_invoices, COALESCE(SUM(total_amount), 0) as total_revenue,
        COUNT(DISTINCT customer_id) as unique_customers
      FROM invoices
      WHERE invoice_date BETWEEN ? AND ?
    `).all(startDate, endDate);
    }
    /**
     * Return a list of all invoice-return stock movements for the returns
     * history page — paged. Filters by reference_doctype = 'RETURN' (from
     * invoice return processing). Returns the canonical `{ rows, total,
     * pageNum, limitNum }` shape.
     */
    static getReturnHistory(filters = {}, db) {
        const pageNum = filters.page || 1;
        const limitNum = filters.limit || 10;
        const select = `
      SELECT
        sm.id,
        sm.movement_no,
        sm.item_id,
        sm.warehouse_id,
        sm.quantity,
        sm.unit_cost,
        sm.reference_doctype,
        sm.reference_docno as invoice_no,
        sm.remarks,
        sm.movement_date as return_date,
        sm.created_at,
        sm.created_by,
        i.item_code,
        i.item_name,
        i.unit_of_measure,
        w.warehouse_code,
        w.warehouse_name,
        u.username as created_by_username,
        inv.customer_name,
        inv.customer_id
      FROM stock_movements sm
      JOIN items i ON sm.item_id = i.id
      JOIN warehouses w ON sm.warehouse_id = w.id
      LEFT JOIN users u ON sm.created_by = u.id
      LEFT JOIN invoices inv ON sm.reference_docno = inv.invoice_no
      WHERE sm.reference_doctype = 'RETURN'
        AND sm.quantity > 0
    `;
        const conditions = [];
        const params = [];
        if (filters.start_date) {
            conditions.push('sm.movement_date >= ?');
            params.push(filters.start_date);
        }
        if (filters.end_date) {
            conditions.push('sm.movement_date <= ?');
            params.push(filters.end_date);
        }
        if (filters.item_id) {
            conditions.push('sm.item_id = ?');
            params.push(filters.item_id);
        }
        if (filters.warehouse_name) {
            conditions.push('w.warehouse_name = ?');
            params.push(filters.warehouse_name);
        }
        if (filters.search) {
            conditions.push('(sm.movement_no LIKE ? OR i.item_name LIKE ? OR inv.customer_name LIKE ? OR sm.reference_docno LIKE ?)');
            const term = `%${filters.search}%`;
            params.push(term, term, term, term);
        }
        const where = conditions.length ? ` AND ${conditions.join(' AND ')}` : '';
        // Sort — whitelisted via sqlSanitizer, mapped to qualified columns
        // (default matches the pre-paging behavior: newest return first).
        const { column, order } = (0, sqlSanitizer_1.sanitizeSortParams)(filters.sortBy || 'return_date', filters.sortOrder || 'DESC', sqlSanitizer_1.INVOICE_RETURN_SORT_COLUMNS, 'return_date', 'DESC');
        const sortColumn = INVOICE_RETURN_SORT_COLUMN_MAP[column] || 'sm.movement_date';
        const offset = (pageNum - 1) * limitNum;
        const rows = db
            .prepare(`${select}${where} ORDER BY ${sortColumn} ${order}, sm.id DESC LIMIT ? OFFSET ?`)
            .all(...params, limitNum, offset);
        const countRow = db
            .prepare(`SELECT COUNT(*) as total FROM stock_movements sm
        JOIN items i ON sm.item_id = i.id
        JOIN warehouses w ON sm.warehouse_id = w.id
        LEFT JOIN invoices inv ON sm.reference_docno = inv.invoice_no
        WHERE sm.reference_doctype = 'RETURN' AND sm.quantity > 0${where}`)
            .get(...params);
        return { rows, total: countRow.total, pageNum, limitNum };
    }
}
exports.default = InvoiceModel;
//# sourceMappingURL=Invoice.js.map