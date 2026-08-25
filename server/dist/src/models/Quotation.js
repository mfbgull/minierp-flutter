"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const sequence_1 = require("../utils/sequence");
const sqlSanitizer_1 = require("../utils/sqlSanitizer");
// Whitelisted sort columns → qualified SQL column for the list query (the
// warehouse/user joins make bare names ambiguous).
const QUOTATION_SORT_COLUMN_MAP = {
    quotation_no: 'q.quotation_no',
    quotation_date: 'q.quotation_date',
    customer_name: 'q.customer_name',
    status: 'q.status',
    total_amount: 'q.total_amount',
    expiry_date: 'q.expiry_date',
    created_at: 'q.created_at',
};
class QuotationModel {
    /**
     * Create a new quotation with items
     */
    static create(data, userId, db) {
        const { customer_id, customer_name, quotation_date, expiry_date, status, source_type, notes, terms, warehouse_id, items } = data;
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
            // Validate items
            if (!items || items.length === 0) {
                throw new Error('Quotation must have at least one item');
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
            // Generate quotation number
            const quotationNo = this.generateQuotationNo(db);
            // Calculate total amount
            let totalAmount = 0;
            for (const item of items) {
                const lineAmount = this.calculateLineAmount(item);
                totalAmount += lineAmount;
            }
            // Insert quotation header
            const quotationStmt = db.prepare(`
        INSERT INTO quotations (
          quotation_no, customer_id, customer_name, quotation_date, expiry_date,
          status, source_type, total_amount, notes, terms, warehouse_id, created_by
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `);
            const result = quotationStmt.run(quotationNo, customer_id, customer_name || customer.customer_name, quotation_date, expiry_date || null, status || 'Draft', source_type || null, totalAmount, notes || null, terms || null, warehouse_id || null, userId);
            const quotationId = result.lastInsertRowid;
            // Insert quotation items
            const itemStmt = db.prepare(`
        INSERT INTO quotation_items (
          quotation_id, item_id, item_code, item_name,
          quantity, unit_price, discount_type, discount_value, tax_rate, amount
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `);
            for (const item of items) {
                const dbItem = db.prepare('SELECT item_code, item_name FROM items WHERE id = ?').get(item.item_id);
                const lineAmount = this.calculateLineAmount(item);
                itemStmt.run(quotationId, item.item_id, dbItem.item_code, dbItem.item_name, item.quantity, item.unit_price, item.discount_type || 'none', item.discount_value || 0, item.tax_rate || 0, lineAmount);
            }
            // Log activity
            db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(userId, 'CREATE', 'Quotation', quotationId, `Created quotation ${quotationNo} for ${customer_name || customer.customer_name}`);
            return this.getById(quotationId, db);
        });
        return transaction();
    }
    /**
     * Get quotation by ID with items
     */
    static getById(id, db) {
        const quotation = db.prepare(`
      SELECT
        q.*,
        w.warehouse_code,
        w.warehouse_name,
        u.username as created_by_username
      FROM quotations q
      LEFT JOIN warehouses w ON q.warehouse_id = w.id
      LEFT JOIN users u ON q.created_by = u.id
      WHERE q.id = ?
    `).get(id);
        if (!quotation) {
            return undefined;
        }
        // Get items
        const items = db.prepare(`
      SELECT
        id, quotation_id, item_id, item_code, item_name,
        quantity, unit_price, discount_type, discount_value, tax_rate, amount
      FROM quotation_items
      WHERE quotation_id = ?
      ORDER BY id
    `).all(id);
        return {
            ...quotation,
            items
        };
    }
    /**
     * Get all quotations with filters — paged. Returns the canonical
     * `{ rows, total, pageNum, limitNum }` shape (grid-pagination §1).
     */
    static getAll(filters = {}, db) {
        const pageNum = filters.page || 1;
        const limitNum = filters.limit || 10;
        const select = `
      SELECT
        q.*,
        w.warehouse_code,
        w.warehouse_name,
        u.username as created_by_username
      FROM quotations q
      LEFT JOIN warehouses w ON q.warehouse_id = w.id
      LEFT JOIN users u ON q.created_by = u.id
      WHERE 1=1
    `;
        const conditions = [];
        const params = [];
        if (filters.status) {
            conditions.push('q.status = ?');
            params.push(filters.status);
        }
        if (filters.customer_id) {
            conditions.push('q.customer_id = ?');
            params.push(filters.customer_id);
        }
        if (filters.customer_name) {
            conditions.push('q.customer_name LIKE ?');
            params.push(`%${filters.customer_name}%`);
        }
        if (filters.search) {
            conditions.push('(q.quotation_no LIKE ? OR q.customer_name LIKE ?)');
            const term = `%${filters.search}%`;
            params.push(term, term);
        }
        if (filters.start_date) {
            conditions.push('q.quotation_date >= ?');
            params.push(filters.start_date);
        }
        if (filters.end_date) {
            conditions.push('q.quotation_date <= ?');
            params.push(filters.end_date);
        }
        if (filters.warehouse_id) {
            conditions.push('q.warehouse_id = ?');
            params.push(filters.warehouse_id);
        }
        const where = conditions.length ? ` AND ${conditions.join(' AND ')}` : '';
        // Sort — whitelisted via sqlSanitizer, mapped to qualified columns
        // (default matches the pre-paging behavior: newest quotation first).
        const { column, order } = (0, sqlSanitizer_1.sanitizeSortParams)(filters.sortBy || 'quotation_date', filters.sortOrder || 'DESC', sqlSanitizer_1.QUOTATION_SORT_COLUMNS, 'quotation_date', 'DESC');
        const sortColumn = QUOTATION_SORT_COLUMN_MAP[column] || 'q.quotation_date';
        const offset = (pageNum - 1) * limitNum;
        const quotations = db
            .prepare(`${select}${where} ORDER BY ${sortColumn} ${order}, q.id DESC LIMIT ? OFFSET ?`)
            .all(...params, limitNum, offset);
        const countRow = db
            .prepare(`SELECT COUNT(*) as total FROM quotations q WHERE 1=1${where}`)
            .get(...params);
        // Get items for each quotation (only the page's rows — avoids loading
        // items for the full unfiltered table).
        const rows = quotations.map(quotation => {
            const items = db.prepare(`
        SELECT
          id, quotation_id, item_id, item_code, item_name,
          quantity, unit_price, discount_type, discount_value, tax_rate, amount
        FROM quotation_items
        WHERE quotation_id = ?
        ORDER BY id
      `).all(quotation.id);
            return {
                ...quotation,
                items
            };
        });
        return { rows, total: countRow.total, pageNum, limitNum };
    }
    /**
     * Update quotation
     */
    static update(id, data, userId, db) {
        const quotation = this.getById(id, db);
        if (!quotation) {
            throw new Error('Quotation not found');
        }
        if (quotation.status === 'Converted') {
            throw new Error('Cannot update a converted quotation');
        }
        const transaction = db.transaction(() => {
            const { customer_id, customer_name, quotation_date, expiry_date, status, notes, terms, warehouse_id, items } = data;
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
            if (quotation_date !== undefined) {
                updateFields.push('quotation_date = ?');
                updateParams.push(quotation_date);
            }
            if (expiry_date !== undefined) {
                updateFields.push('expiry_date = ?');
                updateParams.push(expiry_date);
            }
            if (status !== undefined) {
                updateFields.push('status = ?');
                updateParams.push(status);
            }
            if (notes !== undefined) {
                updateFields.push('notes = ?');
                updateParams.push(notes);
            }
            if (terms !== undefined) {
                updateFields.push('terms = ?');
                updateParams.push(terms);
            }
            if (warehouse_id !== undefined) {
                updateFields.push('warehouse_id = ?');
                updateParams.push(warehouse_id);
            }
            updateFields.push('updated_at = CURRENT_TIMESTAMP');
            updateParams.push(id);
            db.prepare(`UPDATE quotations SET ${updateFields.join(', ')} WHERE id = ?`).run(...updateParams);
            // Update items if provided
            if (items) {
                // Delete existing items
                db.prepare('DELETE FROM quotation_items WHERE quotation_id = ?').run(id);
                // Insert new items
                let totalAmount = 0;
                const itemStmt = db.prepare(`
          INSERT INTO quotation_items (
            quotation_id, item_id, item_code, item_name,
            quantity, unit_price, discount_type, discount_value, tax_rate, amount
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `);
                for (const item of items) {
                    const dbItem = db.prepare('SELECT item_code, item_name FROM items WHERE id = ?').get(item.item_id);
                    const lineAmount = this.calculateLineAmount(item);
                    totalAmount += lineAmount;
                    itemStmt.run(id, item.item_id, dbItem.item_code, dbItem.item_name, item.quantity, item.unit_price, item.discount_type || 'none', item.discount_value || 0, item.tax_rate || 0, lineAmount);
                }
                // Update total amount
                db.prepare('UPDATE quotations SET total_amount = ? WHERE id = ?').run(totalAmount, id);
            }
            // Log activity
            db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(userId, 'UPDATE', 'Quotation', id, `Updated quotation ${quotation.quotation_no}`);
            return this.getById(id, db);
        });
        return transaction();
    }
    /**
     * Delete quotation
     */
    static delete(id, userId, db) {
        const quotation = this.getById(id, db);
        if (!quotation) {
            throw new Error('Quotation not found');
        }
        if (quotation.status === 'Converted') {
            throw new Error('Cannot delete a converted quotation');
        }
        db.transaction(() => {
            db.prepare('DELETE FROM quotation_items WHERE quotation_id = ?').run(id);
            db.prepare('DELETE FROM quotations WHERE id = ?').run(id);
            db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(userId, 'DELETE', 'Quotation', id, `Deleted quotation ${quotation.quotation_no}`);
        })();
        return true;
    }
    /**
     * Convert quotation to sales order
     */
    static convertToSalesOrder(id, userId, db) {
        const quotation = this.getById(id, db);
        if (!quotation) {
            throw new Error('Quotation not found');
        }
        if (quotation.status === 'Converted') {
            throw new Error('Quotation already converted to sales order');
        }
        if (quotation.status === 'Expired') {
            throw new Error('Cannot convert expired quotation');
        }
        const transaction = db.transaction(() => {
            // Generate sales order number
            const soNo = this.generateSalesOrderNo(db);
            // Create sales order
            const soStmt = db.prepare(`
        INSERT INTO sales_orders (
          so_no, customer_id, customer_name, so_date, delivery_date,
          status, source_type, source_id, total_amount, notes, warehouse_id, created_by
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `);
            const result = soStmt.run(soNo, quotation.customer_id, quotation.customer_name, new Date().toISOString().split('T')[0], quotation.expiry_date || null, 'Confirmed', 'QUOTATION', id, quotation.total_amount, quotation.notes || null, quotation.warehouse_id || null, userId);
            const salesOrderId = result.lastInsertRowid;
            // Create sales order items from quotation items
            const soItemStmt = db.prepare(`
        INSERT INTO sales_order_items (so_id, item_id, quantity, unit_price, amount)
        VALUES (?, ?, ?, ?, ?)
      `);
            for (const item of quotation.items || []) {
                soItemStmt.run(salesOrderId, item.item_id, item.quantity, item.unit_price, item.amount);
            }
            // Update quotation status
            db.prepare('UPDATE quotations SET status = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?')
                .run('Converted', id);
            // Log activity
            db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(userId, 'CREATE', 'SalesOrder', salesOrderId, `Created sales order ${soNo} from quotation ${quotation.quotation_no}`);
            db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(userId, 'UPDATE', 'Quotation', id, `Converted quotation ${quotation.quotation_no} to sales order ${soNo}`);
            return { salesOrderId, salesOrderNo: soNo };
        });
        return transaction();
    }
    /**
     * Calculate line amount with discount and tax
     */
    static calculateLineAmount(item) {
        const baseAmount = item.quantity * item.unit_price;
        let afterDiscount;
        if (item.discount_type === 'percentage') {
            afterDiscount = baseAmount * (1 - (item.discount_value || 0) / 100);
        }
        else if (item.discount_type === 'amount') {
            afterDiscount = baseAmount - (item.discount_value || 0);
        }
        else {
            afterDiscount = baseAmount;
        }
        const afterTax = afterDiscount * (1 + (item.tax_rate || 0) / 100);
        return Math.round(afterTax * 100) / 100; // Round to 2 decimal places
    }
    /**
     * Generate quotation number
     */
    static generateQuotationNo(db) {
        return (0, sequence_1.generateDocNo)(db, 'QUO');
    }
    static generateSalesOrderNo(db) {
        return (0, sequence_1.generateDocNo)(db, 'SO');
    }
    /**
     * Get sales cycle chain (quotation -> SO -> invoice)
     */
    static getSalesCycleChain(quotationId, db) {
        const quotation = this.getById(quotationId, db);
        const salesOrder = db.prepare(`
      SELECT
        so.*,
        w.warehouse_code,
        w.warehouse_name,
        u.username as created_by_username
      FROM sales_orders so
      LEFT JOIN warehouses w ON so.warehouse_id = w.id
      LEFT JOIN users u ON so.created_by = u.id
      WHERE so.source_id = ?
    `).get(quotationId);
        let invoice = undefined;
        if (salesOrder) {
            invoice = db.prepare(`
        SELECT
        i.*,
        u.username as created_by_username
        FROM invoices i
        LEFT JOIN users u ON i.created_by = u.id
        WHERE i.so_id = ?
       `).get(salesOrder.id);
        }
        return {
            quotation,
            salesOrder,
            invoice
        };
    }
}
exports.default = QuotationModel;
