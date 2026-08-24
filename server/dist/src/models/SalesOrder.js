"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const sequence_1 = require("../utils/sequence");
const sqlSanitizer_1 = require("../utils/sqlSanitizer");
const Invoice_1 = __importDefault(require("./Invoice"));
const ledgerUtils_1 = __importDefault(require("../utils/ledgerUtils"));
const accountingService_1 = __importDefault(require("../services/accountingService"));
const currency_1 = require("../utils/currency");
// Whitelisted sort columns → qualified SQL column for the list query (the
// warehouse/user/quotation joins make bare names ambiguous).
const SALES_ORDER_SORT_COLUMN_MAP = {
    so_no: 'so.so_no',
    so_date: 'so.so_date',
    customer_name: 'so.customer_name',
    status: 'so.status',
    total_amount: 'so.total_amount',
    delivery_date: 'so.delivery_date',
    created_at: 'so.created_at',
};
class SalesOrderModel {
    /**
     * Create a new sales order with items
     */
    static create(data, userId, db) {
        const { customer_id, customer_name, so_date, delivery_date, status, source_type, source_id, notes, warehouse_id, items } = data;
        const transaction = db.transaction(() => {
            // Validate customer exists
            const customer = db.prepare('SELECT id, customer_name FROM customers WHERE id = ? AND is_active = 1').get(customer_id);
            if (!customer) {
                throw new Error('Customer not found or inactive');
            }
            // Validate warehouse if provided
            if (warehouse_id) {
                const warehouse = db.prepare('SELECT id FROM warehouses WHERE id = ? AND is_active = 1').get(warehouse_id);
                if (!warehouse) {
                    throw new Error('Warehouse not found or inactive');
                }
            }
            // Validate source if provided
            if (source_type === 'QUOTATION' && source_id) {
                const quotation = db.prepare('SELECT id, status FROM quotations WHERE id = ?').get(source_id);
                if (!quotation) {
                    throw new Error('Source quotation not found');
                }
                if (quotation.status !== 'Accepted' && quotation.status !== 'Sent') {
                    throw new Error('Source quotation must be in Accepted or Sent status');
                }
            }
            // Validate items
            if (!items || items.length === 0) {
                throw new Error('Sales order must have at least one item');
            }
            for (const item of items) {
                const dbItem = db.prepare('SELECT id, is_active FROM items WHERE id = ?').get(item.item_id);
                if (!dbItem) {
                    throw new Error(`Item ${item.item_id} not found`);
                }
                if (!dbItem.is_active) {
                    throw new Error(`Item ${item.item_id} is inactive`);
                }
                if (item.quantity <= 0) {
                    throw new Error('Item quantity must be positive');
                }
                if (item.unit_price < 0) {
                    throw new Error('Item unit price cannot be negative');
                }
            }
            // Generate sales order number
            const soNo = this.generateSalesOrderNo(db);
            // Calculate total amount
            const totalAmount = items.reduce((sum, item) => sum + (item.quantity * item.unit_price), 0);
            // Insert sales order header
            const soStmt = db.prepare(`
        INSERT INTO sales_orders (
          so_no, customer_id, customer_name, so_date, delivery_date,
          status, source_type, source_id, total_amount, notes, warehouse_id, created_by
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `);
            const result = soStmt.run(soNo, customer_id, customer_name || customer.customer_name, so_date, delivery_date || null, status || 'Draft', source_type || 'DIRECT', source_id || null, totalAmount, notes || null, warehouse_id || null, userId);
            const salesOrderId = result.lastInsertRowid;
            // Insert sales order items
            const itemStmt = db.prepare(`
        INSERT INTO sales_order_items (so_id, item_id, quantity, unit_price, amount)
        VALUES (?, ?, ?, ?, ?)
      `);
            for (const item of items) {
                const lineAmount = item.quantity * item.unit_price;
                itemStmt.run(salesOrderId, item.item_id, item.quantity, item.unit_price, lineAmount);
            }
            // Log activity
            db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(userId, 'CREATE', 'SalesOrder', salesOrderId, `Created sales order ${soNo} for ${customer_name || customer.customer_name}`);
            return this.getById(salesOrderId, db);
        });
        return transaction();
    }
    /**
     * Get sales order by ID with items
     */
    static getById(id, db) {
        const salesOrder = db.prepare(`
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
    `).get(id);
        if (!salesOrder) {
            return undefined;
        }
        // Get items
        const items = db.prepare(`
      SELECT
        soi.id, soi.so_id, soi.item_id,
        i.item_code, i.item_name,
        soi.quantity, soi.delivered_quantity, soi.unit_price, soi.amount
      FROM sales_order_items soi
      LEFT JOIN items i ON soi.item_id = i.id
      WHERE soi.so_id = ?
      ORDER BY soi.id
    `).all(id);
        return {
            ...salesOrder,
            items
        };
    }
    /**
     * Get all sales orders with filters — paged. Returns the canonical
     * `{ rows, total, pageNum, limitNum }` shape (grid-pagination §1).
     */
    static getAll(filters = {}, db) {
        const pageNum = filters.page || 1;
        const limitNum = filters.limit || 10;
        const select = `
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
      WHERE 1=1
    `;
        const conditions = [];
        const params = [];
        if (filters.status) {
            conditions.push('so.status = ?');
            params.push(filters.status);
        }
        if (filters.customer_id) {
            conditions.push('so.customer_id = ?');
            params.push(filters.customer_id);
        }
        if (filters.customer_name) {
            conditions.push('so.customer_name LIKE ?');
            params.push(`%${filters.customer_name}%`);
        }
        if (filters.search) {
            conditions.push('(so.so_no LIKE ? OR so.customer_name LIKE ?)');
            const term = `%${filters.search}%`;
            params.push(term, term);
        }
        if (filters.start_date) {
            conditions.push('so.so_date >= ?');
            params.push(filters.start_date);
        }
        if (filters.end_date) {
            conditions.push('so.so_date <= ?');
            params.push(filters.end_date);
        }
        if (filters.warehouse_id) {
            conditions.push('so.warehouse_id = ?');
            params.push(filters.warehouse_id);
        }
        if (filters.source_type) {
            conditions.push('so.source_type = ?');
            params.push(filters.source_type);
        }
        const where = conditions.length ? ` AND ${conditions.join(' AND ')}` : '';
        // Sort — whitelisted via sqlSanitizer, mapped to qualified columns
        // (default matches the pre-paging behavior: newest order first).
        const { column, order } = (0, sqlSanitizer_1.sanitizeSortParams)(filters.sortBy || 'so_date', filters.sortOrder || 'DESC', sqlSanitizer_1.SALES_ORDER_SORT_COLUMNS, 'so_date', 'DESC');
        const sortColumn = SALES_ORDER_SORT_COLUMN_MAP[column] || 'so.so_date';
        const offset = (pageNum - 1) * limitNum;
        const salesOrders = db
            .prepare(`${select}${where} ORDER BY ${sortColumn} ${order}, so.id DESC LIMIT ? OFFSET ?`)
            .all(...params, limitNum, offset);
        const countRow = db
            .prepare(`SELECT COUNT(*) as total FROM sales_orders so WHERE 1=1${where}`)
            .get(...params);
        // Get items for each sales order (only the page's rows — avoids
        // loading items for the full unfiltered table).
        const rows = salesOrders.map(so => {
            const items = db.prepare(`
        SELECT
          soi.id, soi.so_id, soi.item_id,
          i.item_code, i.item_name,
          soi.quantity, soi.delivered_quantity, soi.unit_price, soi.amount
        FROM sales_order_items soi
        LEFT JOIN items i ON soi.item_id = i.id
        WHERE soi.so_id = ?
        ORDER BY soi.id
      `).all(so.id);
            return {
                ...so,
                items
            };
        });
        return { rows, total: countRow.total, pageNum, limitNum };
    }
    /**
     * Update sales order
     */
    static update(id, data, userId, db) {
        const salesOrder = this.getById(id, db);
        if (!salesOrder) {
            throw new Error('Sales order not found');
        }
        if (salesOrder.status === 'Completed' || salesOrder.status === 'Cancelled') {
            throw new Error(`Cannot update a ${salesOrder.status} sales order`);
        }
        const transaction = db.transaction(() => {
            const { customer_id, customer_name, so_date, delivery_date, status, notes, warehouse_id, items } = data;
            // Validate customer if provided
            if (customer_id) {
                const customer = db.prepare('SELECT id, customer_name FROM customers WHERE id = ? AND is_active = 1').get(customer_id);
                if (!customer) {
                    throw new Error('Customer not found or inactive');
                }
            }
            // Validate warehouse if provided
            if (warehouse_id) {
                const warehouse = db.prepare('SELECT id FROM warehouses WHERE id = ? AND is_active = 1').get(warehouse_id);
                if (!warehouse) {
                    throw new Error('Warehouse not found or inactive');
                }
            }
            // Update header
            const updateFields = [];
            const updateParams = [];
            if (customer_id !== undefined) {
                updateFields.push('customer_id = ?');
                updateParams.push(customer_id);
            }
            if (customer_name !== undefined) {
                updateFields.push('customer_name = ?');
                updateParams.push(customer_name);
            }
            if (so_date !== undefined) {
                updateFields.push('so_date = ?');
                updateParams.push(so_date);
            }
            if (delivery_date !== undefined) {
                updateFields.push('delivery_date = ?');
                updateParams.push(delivery_date);
            }
            if (status !== undefined) {
                updateFields.push('status = ?');
                updateParams.push(status);
            }
            if (notes !== undefined) {
                updateFields.push('notes = ?');
                updateParams.push(notes);
            }
            if (warehouse_id !== undefined) {
                updateFields.push('warehouse_id = ?');
                updateParams.push(warehouse_id);
            }
            updateFields.push('updated_at = CURRENT_TIMESTAMP');
            updateParams.push(id);
            db.prepare(`UPDATE sales_orders SET ${updateFields.join(', ')} WHERE id = ?`).run(...updateParams);
            // Update items if provided
            if (items) {
                // Delete existing items
                db.prepare('DELETE FROM sales_order_items WHERE so_id = ?').run(id);
                // Insert new items
                let totalAmount = 0;
                const itemStmt = db.prepare(`
          INSERT INTO sales_order_items (so_id, item_id, quantity, unit_price, amount)
          VALUES (?, ?, ?, ?, ?)
        `);
                for (const item of items) {
                    const lineAmount = item.quantity * item.unit_price;
                    totalAmount += lineAmount;
                    itemStmt.run(id, item.item_id, item.quantity, item.unit_price, lineAmount);
                }
                // Update total amount
                db.prepare('UPDATE sales_orders SET total_amount = ? WHERE id = ?').run(totalAmount, id);
            }
            // Log activity
            db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(userId, 'UPDATE', 'SalesOrder', id, `Updated sales order ${salesOrder.so_no}`);
            return this.getById(id, db);
        });
        return transaction();
    }
    /**
     * Delete sales order (only allowed for Draft/Confirmed — stock may not have been deducted yet).
     */
    static delete(id, userId, db) {
        const salesOrder = this.getById(id, db);
        if (!salesOrder) {
            throw new Error('Sales order not found');
        }
        if (salesOrder.status === 'Completed' || salesOrder.status === 'Invoiced') {
            throw new Error(`Cannot delete a ${salesOrder.status} sales order`);
        }
        db.transaction(() => {
            db.prepare('DELETE FROM sales_order_items WHERE so_id = ?').run(id);
            db.prepare('DELETE FROM sales_orders WHERE id = ?').run(id);
            db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(userId, 'DELETE', 'SalesOrder', id, `Deleted sales order ${salesOrder.so_no}`);
        })();
        return true;
    }
    /**
     * Cancel a sales order, reversing any linked invoice stock.
     * Works for Invoiced/Completed SOs — reverses stock and cancels the linked invoice.
     */
    static cancel(id, userId, db) {
        const salesOrder = this.getById(id, db);
        if (!salesOrder) {
            throw new Error('Sales order not found');
        }
        if (salesOrder.status === 'Cancelled') {
            throw new Error('Sales order is already cancelled');
        }
        let linkedInvoice;
        const transaction = db.transaction(() => {
            if (salesOrder.status === 'Invoiced' || salesOrder.status === 'Completed') {
                // Find the linked invoice
                linkedInvoice = db.prepare(`SELECT id, invoice_no, status FROM invoices WHERE so_id = ?`).get(id);
                if (linkedInvoice && linkedInvoice.status !== 'Cancelled') {
                    // Get items for stock reversal
                    const invoiceItems = Invoice_1.default.getInvoiceItemsForStockReverse(db, linkedInvoice.id);
                    // Reverse stock — restores batch quantity_remaining and creates ADJUSTMENT movement
                    Invoice_1.default.reverseStockForItems(db, invoiceItems, linkedInvoice.invoice_no, userId, 'SO_CANCEL');
                    // Cancel the invoice
                    db.prepare(`
            UPDATE invoices SET status = 'Cancelled', updated_at = CURRENT_TIMESTAMP WHERE id = ?
          `).run(linkedInvoice.id);
                    // Log activity for invoice cancellation
                    db.prepare(`
            INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
            VALUES (?, ?, ?, ?, ?)
          `).run(userId, 'CANCEL', 'Invoice', linkedInvoice.id, `Invoice ${linkedInvoice.invoice_no} cancelled due to Sales Order ${salesOrder.so_no} cancellation`);
                }
            }
            // Update SO status
            db.prepare(`UPDATE sales_orders SET status = 'Cancelled', updated_at = CURRENT_TIMESTAMP WHERE id = ?`)
                .run(id);
            // Log activity
            db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(userId, 'CANCEL', 'SalesOrder', id, `Cancelled sales order ${salesOrder.so_no}`);
            return { invoiceId: linkedInvoice?.id, invoiceNo: linkedInvoice?.invoice_no };
        });
        return transaction();
    }
    /**
     * Convert sales order to invoice
     * This creates an invoice and deducts inventory
     */
    static convertToInvoice(id, userId, db, invoiceData) {
        const salesOrder = this.getById(id, db);
        if (!salesOrder) {
            throw new Error('Sales order not found');
        }
        if (salesOrder.status === 'Cancelled') {
            throw new Error('Cannot convert cancelled sales order');
        }
        if (salesOrder.status === 'Invoiced' || salesOrder.status === 'Completed') {
            throw new Error(`Sales order already ${salesOrder.status}`);
        }
        const transaction = db.transaction(() => {
            // Validate stock availability
            for (const item of salesOrder.items || []) {
                const stockBalance = db.prepare(`
          SELECT quantity FROM stock_balances
          WHERE item_id = ? AND warehouse_id = ?
        `).get(item.item_id, salesOrder.warehouse_id);
                const availableStock = stockBalance ? parseFloat(String(stockBalance.quantity)) : 0;
                if (availableStock < item.quantity) {
                    throw new Error(`Insufficient stock for item ${item.item_code}. Available: ${availableStock}, Required: ${item.quantity}`);
                }
            }
            // Generate invoice number
            const invoiceNo = this.generateInvoiceNo(db);
            const invoiceDate = invoiceData?.invoice_date || new Date().toISOString().split('T')[0];
            // Create invoice
            const invoiceStmt = db.prepare(`
        INSERT INTO invoices (
          invoice_no, customer_id, customer_name, so_id, source_type, quotation_id,
          invoice_date, due_date, status, total_amount, paid_amount, balance_amount, notes, created_by
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `);
            // Get quotation_id if source is quotation
            let quotationId = null;
            if (salesOrder.source_type === 'QUOTATION' && salesOrder.source_id) {
                const quotation = db.prepare('SELECT id FROM quotations WHERE id = ?').get(salesOrder.source_id);
                quotationId = quotation ? quotation.id : null;
            }
            const result = invoiceStmt.run(invoiceNo, salesOrder.customer_id, salesOrder.customer_name, id, 'SALES_ORDER', quotationId, invoiceDate, invoiceData?.due_date || null, 'Unpaid', salesOrder.total_amount, 0, salesOrder.total_amount, invoiceData?.notes || salesOrder.notes || null, userId);
            const invoiceId = result.lastInsertRowid;
            // Create invoice items. SO lines carry a precomputed amount with no
            // discount/tax breakdown, so net = amount and tax = 0 (consistent
            // with the line's default tax_rate of 0).
            const invoiceItemStmt = db.prepare(`
         INSERT INTO invoice_items (invoice_id, item_id, quantity, unit_price, amount, net_amount, tax_amount)
         VALUES (?, ?, ?, ?, ?, ?, ?)
       `);
            for (const item of salesOrder.items || []) {
                invoiceItemStmt.run(invoiceId, item.item_id, item.quantity, item.unit_price, item.amount, item.amount, 0);
            }
            // Deduct inventory using FIFO batch consumption
            const movementDate = invoiceDate;
            for (const item of salesOrder.items || []) {
                const effectiveWarehouseId = salesOrder.warehouse_id || 1;
                // FIFO consumption from oldest batches
                const consumption = Invoice_1.default.consumeFromOldestBatches(item.item_id, effectiveWarehouseId, item.quantity, db);
                // Create one stock movement per consumed batch for full traceability
                let totalConsumed = 0;
                for (const entry of consumption) {
                    const movementNo = this.generateMovementNo(db);
                    const batchLabel = entry.batchId ? `(batch ${entry.batchId})` : '(legacy stock)';
                    db.prepare(`
            INSERT INTO stock_movements (
              movement_no, item_id, warehouse_id, movement_type,
              quantity, unit_cost, reference_doctype, reference_docno,
              remarks, movement_date, created_by, batch_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          `).run(movementNo, item.item_id, effectiveWarehouseId, 'SALE', -entry.consumed, entry.unitCost, 'Invoice', invoiceNo, `Invoice ${invoiceNo} from SO ${salesOrder.so_no} ${batchLabel}`, movementDate, userId, entry.batchId);
                    totalConsumed += entry.consumed;
                }
                // Update stock balance once per item (total consumed)
                db.prepare(`
          UPDATE stock_balances
          SET quantity = quantity + ?,
              last_updated = CURRENT_TIMESTAMP
          WHERE item_id = ? AND warehouse_id = ?
        `).run(-totalConsumed, item.item_id, effectiveWarehouseId);
                // Update item current_stock
                db.prepare(`
          UPDATE items
          SET current_stock = (
            SELECT COALESCE(SUM(quantity), 0)
            FROM stock_balances
            WHERE item_id = ?
          )
          WHERE id = ?
        `).run(item.item_id, item.item_id);
            }
            // Update sales order status
            db.prepare('UPDATE sales_orders SET status = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?')
                .run('Invoiced', id);
            // Update delivered quantity
            for (const item of salesOrder.items || []) {
                db.prepare(`
          UPDATE sales_order_items
          SET delivered_quantity = quantity
          WHERE so_id = ? AND item_id = ?
        `).run(id, item.item_id);
            }
            // ACC-07: the converted invoice previously appeared in NO subledger
            // and NO journal. Add the customer_ledger row and the standard GL
            // trio so statements, aging, and the trial balance all see it.
            ledgerUtils_1.default.createLedgerEntry(salesOrder.customer_id, invoiceDate, 'INVOICE', invoiceNo, salesOrder.total_amount, 0, `Invoice ${invoiceNo} from SO ${salesOrder.so_no}`);
            const cogsRows = db.prepare(`
        SELECT quantity * unit_cost AS line_cogs FROM stock_movements
        WHERE reference_doctype = 'Invoice' AND reference_docno = ?
          AND movement_type = 'SALE'
      `).all(invoiceNo);
            const cogsTotal = cogsRows.reduce((s, r) => s + Math.abs(Number(r.line_cogs)), 0);
            accountingService_1.default.postInvoiceEntry(db, {
                invoiceId,
                invoiceNo,
                totalAmount: salesOrder.total_amount,
                invoiceDate,
                userId,
            });
            if (cogsTotal > 0) {
                accountingService_1.default.postCOGSEntry(db, {
                    invoiceId,
                    invoiceNo,
                    cogsAmount: (0, currency_1.parseCurrency)(cogsTotal),
                    invoiceDate,
                    userId,
                });
            }
            // Log activity
            db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(userId, 'CREATE', 'Invoice', invoiceId, `Created invoice ${invoiceNo} from sales order ${salesOrder.so_no}`);
            db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(userId, 'UPDATE', 'SalesOrder', id, `Sales order ${salesOrder.so_no} invoiced as ${invoiceNo}`);
            return { invoiceId, invoiceNo };
        });
        return transaction();
    }
    /**
     * Get sales cycle chain (quotation -> SO -> invoice)
     */
    static getSalesCycleChain(salesOrderId, db) {
        const salesOrder = this.getById(salesOrderId, db);
        let quotation = undefined;
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
        const invoice = db.prepare(`
      SELECT
        i.*,
        u.username as created_by_username
      FROM invoices i
      WHERE i.so_id = ?
     `).get(salesOrderId);
        return {
            quotation,
            salesOrder,
            invoice
        };
    }
    /**
     * Generate sales order number
     */
    static generateSalesOrderNo(db) {
        return (0, sequence_1.generateDocNo)(db, 'SO');
    }
    static generateInvoiceNo(db) {
        return (0, sequence_1.generateDocNo)(db, 'INV');
    }
    static generateMovementNo(db) {
        return (0, sequence_1.generateDocNo)(db, 'MOV', 5);
    }
}
exports.default = SalesOrderModel;
//# sourceMappingURL=SalesOrder.js.map