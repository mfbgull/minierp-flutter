"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const database_1 = __importDefault(require("../config/database"));
const logger_1 = __importDefault(require("../utils/logger"));
const sequence_1 = require("../utils/sequence");
const Invoice_1 = __importDefault(require("../models/Invoice"));
const StockMovement_1 = __importDefault(require("../models/StockMovement"));
const Warehouse_1 = __importDefault(require("../models/Warehouse"));
function generatePOSTransactionNo() {
    const year = new Date().getFullYear();
    const settingKey = `POS_last_no_${year}`;
    const nextNo = (0, sequence_1.getNextSequenceNumber)(database_1.default, settingKey);
    return `POS-${year}-${nextNo.toString().padStart(6, '0')}`;
}
/**
 * Find or create the "Walk-in Customer" record for POS transactions.
 */
function ensureWalkinCustomer() {
    const existing = database_1.default.prepare(`
    SELECT id FROM customers WHERE customer_code = 'WALK-IN' LIMIT 1
  `).get();
    if (existing)
        return existing.id;
    const result = database_1.default.prepare(`
    INSERT INTO customers (customer_code, customer_name, is_active)
    VALUES ('WALK-IN', 'Walk-in Customer', 1)
  `).run();
    const walkinId = result.lastInsertRowid;
    logger_1.default.info(`Created Walk-in Customer with id=${walkinId}`);
    return walkinId;
}
function createPOSSale(req, res) {
    try {
        const { warehouse_id, sale_date, items, cash_received, customer_name } = req.body;
        const userId = req.user.id;
        if (!warehouse_id) {
            res.status(400).json({ error: 'Warehouse is required' });
            return;
        }
        if (!items || !Array.isArray(items) || items.length === 0) {
            res.status(400).json({ error: 'At least one item is required' });
            return;
        }
        if (!sale_date) {
            res.status(400).json({ error: 'Sale date is required' });
            return;
        }
        const warehouse = Warehouse_1.default.getById(database_1.default, warehouse_id);
        if (!warehouse) {
            res.status(400).json({ error: 'Warehouse not found' });
            return;
        }
        let total = 0;
        for (const item of items) {
            if (!item.item_id || !item.quantity || item.quantity <= 0) {
                res.status(400).json({ error: 'Each item must have item_id and quantity > 0' });
                return;
            }
            if (item.unit_price === undefined || item.unit_price < 0) {
                res.status(400).json({ error: 'Each item must have a valid unit_price' });
                return;
            }
            total += item.quantity * item.unit_price;
        }
        const cashAmount = parseFloat(cash_received) || total;
        if (cashAmount < total) {
            res.status(400).json({
                error: `Insufficient cash. Total: ${total.toFixed(2)}, Received: ${cashAmount.toFixed(2)}`
            });
            return;
        }
        const customerName = customer_name || 'Walk-in Customer';
        // Stock validation — check all items have sufficient stock before proceeding
        for (const item of items) {
            const stockBalance = database_1.default.prepare('SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?').get(item.item_id, warehouse_id);
            const availableStock = stockBalance ? Number(stockBalance.quantity) : 0;
            if (availableStock < item.quantity) {
                const itemRecord = database_1.default.prepare('SELECT item_name FROM items WHERE id = ?').get(item.item_id);
                res.status(400).json({
                    error: `Insufficient stock for ${itemRecord?.item_name || 'item ' + item.item_id}. Available: ${availableStock}, Required: ${item.quantity}`
                });
                return;
            }
        }
        // === Create invoice inside a transaction ===
        const transaction = database_1.default.transaction(() => {
            const walkinCustomerId = ensureWalkinCustomer();
            const transactionNo = generatePOSTransactionNo();
            // Create the invoice with status='Paid' since POS collects payment immediately
            const invoiceResult = database_1.default.prepare(`
        INSERT INTO invoices (
          invoice_no, customer_id, customer_name, invoice_date, due_date, status,
          total_amount, paid_amount, balance_amount, notes, created_by,
          source_type
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).run(transactionNo, walkinCustomerId, customerName, sale_date, sale_date, // due_date = sale_date (immediate payment)
            'Paid', total, cashAmount, Math.max(0, total - cashAmount), `POS Transaction: ${transactionNo}`, userId, 'POS');
            const invoiceId = invoiceResult.lastInsertRowid;
            // Create invoice_items and stock movements for each cart item
            const itemDetails = [];
            for (const item of items) {
                const itemRecord = database_1.default.prepare('SELECT id, item_code, item_name, unit_of_measure FROM items WHERE id = ?').get(item.item_id);
                if (!itemRecord) {
                    throw new Error(`Item with ID ${item.item_id} not found`);
                }
                const lineTotal = item.quantity * item.unit_price;
                // Create invoice item
                Invoice_1.default.createInvoiceItem(database_1.default, invoiceId, {
                    item_id: item.item_id,
                    quantity: item.quantity,
                    unit_price: item.unit_price,
                });
                // Deduct stock via FIFO batch consumption
                const consumption = Invoice_1.default.consumeFromOldestBatches(item.item_id, warehouse_id, item.quantity, database_1.default);
                for (const entry of consumption) {
                    const batchLabel = entry.batchId ? `(batch ${entry.batchId})` : '(legacy stock)';
                    StockMovement_1.default.recordMovement({
                        item_id: item.item_id,
                        warehouse_id: warehouse_id,
                        quantity: -entry.consumed,
                        movement_type: 'SALE',
                        unit_cost: entry.unitCost,
                        reference_doctype: 'POS',
                        reference_docno: transactionNo,
                        movement_date: sale_date,
                        remarks: `POS Sale: ${transactionNo} - ${itemRecord.item_name} ${batchLabel}`,
                        batch_id: entry.batchId ?? undefined,
                    }, userId, database_1.default);
                }
                itemDetails.push({
                    sale_id: invoiceId,
                    sale_no: transactionNo,
                    item_id: item.item_id,
                    item_code: itemRecord.item_code,
                    item_name: itemRecord.item_name,
                    unit_of_measure: itemRecord.unit_of_measure,
                    quantity: item.quantity,
                    unit_price: item.unit_price,
                    line_total: lineTotal
                });
            }
            // Record payment
            if (cashAmount > 0) {
                const paymentNo = Invoice_1.default.generatePaymentNoAtomic(database_1.default);
                const paymentId = Invoice_1.default.createPayment(database_1.default, paymentNo, walkinCustomerId, sale_date, cashAmount, 'Cash', null, `POS Transaction ${transactionNo}`);
                Invoice_1.default.createPaymentAllocation(database_1.default, paymentId, invoiceId, cashAmount);
                // Create ledger entry for payment
                Invoice_1.default.createLedgerEntry(database_1.default, walkinCustomerId, 'PAYMENT', paymentNo, 0, cashAmount, `Payment ${paymentNo} for POS ${transactionNo}`);
            }
            // Create ledger entry for the sale
            Invoice_1.default.createLedgerEntry(database_1.default, walkinCustomerId, 'INVOICE', transactionNo, total, 0, `POS Sale ${transactionNo}`);
            // Activity log
            database_1.default.prepare('INSERT INTO activity_log (user_id, action, entity_type, entity_id, description) VALUES (?, ?, ?, ?, ?)').run(userId, 'CREATE', 'POS', invoiceId, `POS Transaction ${transactionNo}: ${items.length} items`);
            return {
                transaction_no: transactionNo,
                sale_date,
                warehouse_id,
                warehouse_name: warehouse.warehouse_name,
                customer_name: customerName,
                items: itemDetails,
                subtotal: total,
                total,
                cash_received: cashAmount,
                change: cashAmount - total,
                items_count: items.length,
                sale_ids: [invoiceId]
            };
        });
        const result = transaction();
        res.status(201).json({
            success: true,
            message: 'POS sale completed successfully',
            data: result
        });
    }
    catch (error) {
        const message = error instanceof Error ? error.message : 'Failed to process POS sale';
        logger_1.default.error('POS Sale Error:', error);
        res.status(500).json({ error: message });
    }
}
function getPOSTransactions(req, res) {
    try {
        const startDate = req.query.start_date;
        const endDate = req.query.end_date;
        const limitParam = parseInt(req.query.limit) || 50;
        let query = `
      SELECT
        i.invoice_no as transaction_no,
        i.invoice_date as sale_date,
        COALESCE(i.customer_name, c.customer_name) as customer_name,
        w.warehouse_name,
        COUNT(ii.id) as items_count,
        i.total_amount as total,
        i.paid_amount,
        i.balance_amount
      FROM invoices i
      JOIN customers c ON i.customer_id = c.id
      JOIN invoice_items ii ON ii.invoice_id = i.id
      LEFT JOIN (
        SELECT reference_docno, w2.warehouse_name
        FROM stock_movements sm
        JOIN warehouses w2 ON sm.warehouse_id = w2.id
        WHERE sm.reference_doctype = 'POS'
        GROUP BY sm.reference_docno, w2.warehouse_name
      ) w ON w.reference_docno = i.invoice_no
      WHERE i.source_type = 'POS'
    `;
        const params = [];
        if (startDate) {
            query += ' AND i.invoice_date >= ?';
            params.push(startDate);
        }
        if (endDate) {
            query += ' AND i.invoice_date <= ?';
            params.push(endDate);
        }
        query += ` GROUP BY i.id ORDER BY i.created_at DESC LIMIT ?`;
        params.push(limitParam);
        const transactions = database_1.default.prepare(query).all(...params);
        res.json({
            success: true,
            data: transactions
        });
    }
    catch (error) {
        logger_1.default.error('Get POS Transactions Error:', error);
        res.status(500).json({ error: 'Failed to fetch POS transactions' });
    }
}
exports.default = {
    createPOSSale,
    getPOSTransactions
};
//# sourceMappingURL=posController.js.map