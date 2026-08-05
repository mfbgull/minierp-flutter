"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const sequence_1 = require("../utils/sequence");
const StockMovement_1 = __importDefault(require("./StockMovement"));
class PurchaseModel {
    static generatePurchaseNo(db) {
        return (0, sequence_1.generateDocNo)(db, 'PURCH');
    }
    static generateBatchNo(db) {
        const year = new Date().getFullYear();
        const settingKey = `BATCH_last_no_${year}`;
        const nextNo = (0, sequence_1.getNextSequenceNumber)(db, settingKey);
        return `BATCH-${year % 100}-PUR-${nextNo.toString().padStart(4, '0')}`;
    }
    static generateMovementNo(db) {
        return (0, sequence_1.generateDocNo)(db, 'STK');
    }
    static recordPurchase(data, userId, db) {
        if (!data.item_id || data.item_id <= 0)
            throw new Error('Invalid item_id');
        if (!data.warehouse_id || data.warehouse_id <= 0)
            throw new Error('Invalid warehouse_id');
        if (!data.quantity || data.quantity <= 0)
            throw new Error('Quantity must be positive');
        if (data.unit_cost === undefined || data.unit_cost < 0)
            throw new Error('unit_cost must be non-negative');
        if (!data.purchase_date)
            throw new Error('purchase_date is required');
        const { item_id, warehouse_id, quantity, unit_cost, supplier_name, purchase_date, invoice_no, remarks } = data;
        const transaction = db.transaction(() => {
            const purchaseNo = this.generatePurchaseNo(db);
            const batchNo = this.generateBatchNo(db);
            const purchaseStmt = db.prepare(`
        INSERT INTO purchases (
          purchase_no, item_id, warehouse_id, quantity, unit_cost, total_cost,
          supplier_name, purchase_date, invoice_no, remarks, created_by
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `);
            const totalCost = quantity * unit_cost;
            const result = purchaseStmt.run(purchaseNo, item_id, warehouse_id, quantity, unit_cost, totalCost, supplier_name || null, purchase_date, invoice_no || null, remarks || null, userId);
            const purchaseId = result.lastInsertRowid;
            // Create a stock_batch record for the purchased item
            db.prepare(`
        INSERT INTO stock_batches (
          batch_no, item_id, warehouse_id, source_type,
          source_id, quantity_original, quantity_remaining,
          unit_cost, received_date
        ) VALUES (?, ?, ?, 'PURCHASE', ?, ?, ?, ?, ?)
      `).run(batchNo, item_id, warehouse_id, purchaseId, quantity, quantity, unit_cost, purchase_date);
            const batchRecord = db.prepare(`
        SELECT id FROM stock_batches
        WHERE source_type = 'PURCHASE' AND source_id = ?
      `).get(purchaseId);
            const outputBatchId = batchRecord?.id;
            // Record stock movement linked to the new batch
            const movementNo = this.generateMovementNo(db);
            db.prepare(`
        INSERT INTO stock_movements (
          movement_no, item_id, warehouse_id, movement_type,
          quantity, unit_cost, reference_doctype, reference_docno,
          remarks, movement_date, created_by, batch_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).run(movementNo, item_id, warehouse_id, 'PURCHASE', quantity, unit_cost, 'Purchase', purchaseNo, `Purchase: ${purchaseNo}${supplier_name ? ' from ' + supplier_name : ''} (batch ${outputBatchId})`, purchase_date, userId, outputBatchId);
            // Update purchase record with batch info
            db.prepare(`
        UPDATE purchases SET batch_no = ?, batch_id = ? WHERE id = ?
      `).run(batchNo, outputBatchId, purchaseId);
            // Update stock_balances
            const existingBalance = db.prepare(`
        SELECT * FROM stock_balances
        WHERE item_id = ? AND warehouse_id = ?
      `).get(item_id, warehouse_id);
            if (existingBalance) {
                db.prepare(`
          UPDATE stock_balances
          SET quantity = quantity + ?,
              last_updated = CURRENT_TIMESTAMP
          WHERE item_id = ? AND warehouse_id = ?
        `).run(quantity, item_id, warehouse_id);
            }
            else {
                db.prepare(`
          INSERT INTO stock_balances (item_id, warehouse_id, quantity)
          VALUES (?, ?, ?)
        `).run(item_id, warehouse_id, quantity);
            }
            db.prepare(`
        UPDATE items
        SET current_stock = (
          SELECT COALESCE(SUM(quantity), 0)
          FROM stock_balances
          WHERE item_id = ?
        )
        WHERE id = ?
      `).run(item_id, item_id);
            db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(userId, 'CREATE', 'Purchase', purchaseId, `Recorded purchase ${purchaseNo}: ${quantity} units (Batch: ${batchNo}, Cost: ${unit_cost}/unit)`);
            return this.getById(purchaseId, db);
        });
        return transaction();
    }
    static getAll(filters = {}, db) {
        let query = `
      SELECT
        p.*,
        i.item_code,
        i.item_name,
        i.unit_of_measure,
        w.warehouse_code,
        w.warehouse_name,
        u.username as created_by_username
      FROM purchases p
      JOIN items i ON p.item_id = i.id
      JOIN warehouses w ON p.warehouse_id = w.id
      JOIN users u ON p.created_by = u.id
      WHERE 1=1
    `;
        const params = [];
        if (filters.start_date) {
            query += ` AND p.purchase_date >= ?`;
            params.push(filters.start_date);
        }
        if (filters.end_date) {
            query += ` AND p.purchase_date <= ?`;
            params.push(filters.end_date);
        }
        if (filters.item_id) {
            query += ` AND p.item_id = ?`;
            params.push(filters.item_id);
        }
        if (filters.warehouse_id) {
            query += ` AND p.warehouse_id = ?`;
            params.push(filters.warehouse_id);
        }
        if (filters.supplier_name) {
            query += ` AND p.supplier_name LIKE ?`;
            params.push(`%${filters.supplier_name}%`);
        }
        query += ` ORDER BY p.purchase_date DESC, p.created_at DESC`;
        if (filters.limit) {
            query += ` LIMIT ?`;
            params.push(filters.limit);
        }
        return db.prepare(query).all(...params);
    }
    static getById(id, db) {
        return db.prepare(`
      SELECT
        p.*,
        i.item_code,
        i.item_name,
        i.unit_of_measure,
        w.warehouse_code,
        w.warehouse_name,
        u.username as created_by_username
      FROM purchases p
      JOIN items i ON p.item_id = i.id
      JOIN warehouses w ON p.warehouse_id = w.id
      JOIN users u ON p.created_by = u.id
      WHERE p.id = ?
    `).get(id);
    }
    static getSummaryByItem(item_id, db) {
        return db.prepare(`
      SELECT
        COUNT(*) as purchase_count,
        SUM(quantity) as total_quantity,
        SUM(total_cost) as total_cost,
        AVG(unit_cost) as avg_unit_cost,
        MIN(purchase_date) as first_purchase_date,
        MAX(purchase_date) as last_purchase_date
      FROM purchases
      WHERE item_id = ?
    `).get(item_id);
    }
    static getSummaryByDateRange(start_date, end_date, db) {
        return db.prepare(`
      SELECT
        COUNT(*) as purchase_count,
        SUM(quantity) as total_quantity,
        SUM(total_cost) as total_cost,
        COUNT(DISTINCT item_id) as unique_items,
        COUNT(DISTINCT supplier_name) as unique_suppliers
      FROM purchases
      WHERE purchase_date BETWEEN ? AND ?
    `).get(start_date, end_date);
    }
    static getTopSuppliers(limit = 10, db) {
        return db.prepare(`
      SELECT
        supplier_name,
        COUNT(*) as purchase_count,
        SUM(quantity) as total_quantity,
        SUM(total_cost) as total_cost
      FROM purchases
      WHERE supplier_name IS NOT NULL
      GROUP BY supplier_name
      ORDER BY total_cost DESC
      LIMIT ?
    `).all(limit);
    }
    /**
     * Return a list of all purchase-return stock movements for the returns history page.
     * Filters by reference_doctype = 'PURCHASE_RETURN' (and optionally 'PO_RETURN').
     */
    static getReturnHistory(filters = {}, db) {
        let query = `
      SELECT
        sm.id,
        sm.movement_no,
        sm.item_id,
        sm.warehouse_id,
        sm.quantity,
        sm.unit_cost,
        sm.reference_doctype,
        sm.reference_docno,
        sm.remarks,
        sm.movement_date as return_date,
        sm.created_at,
        sm.created_by,
        i.item_code,
        i.item_name,
        i.unit_of_measure,
        w.warehouse_code,
        w.warehouse_name,
        u.username as created_by_username
      FROM stock_movements sm
      JOIN items i ON sm.item_id = i.id
      JOIN warehouses w ON sm.warehouse_id = w.id
      LEFT JOIN users u ON sm.created_by = u.id
      WHERE sm.reference_doctype IN ('PURCHASE_RETURN', 'PO_RETURN')
        AND sm.quantity < 0
    `;
        const params = [];
        if (filters.start_date) {
            query += ' AND sm.movement_date >= ?';
            params.push(filters.start_date);
        }
        if (filters.end_date) {
            query += ' AND sm.movement_date <= ?';
            params.push(filters.end_date);
        }
        if (filters.item_id) {
            query += ' AND sm.item_id = ?';
            params.push(filters.item_id);
        }
        query += ' ORDER BY sm.movement_date DESC, sm.created_at DESC';
        if (filters.limit) {
            query += ' LIMIT ?';
            params.push(filters.limit);
        }
        return db.prepare(query).all(...params);
    }
    static returnPurchaseItems(db, purchaseId, returnQuantity, userId, reason) {
        const purchase = this.getById(purchaseId, db);
        if (!purchase)
            throw new Error('Purchase not found');
        if (returnQuantity <= 0)
            throw new Error('Return quantity must be positive');
        const alreadyReturned = purchase.returned_quantity || 0;
        const totalReturnedAfter = alreadyReturned + returnQuantity;
        if (totalReturnedAfter > purchase.quantity) {
            throw new Error(`Return quantity (${returnQuantity}) would exceed remaining available quantity. ` +
                `Already returned: ${alreadyReturned}, Original: ${purchase.quantity}, ` +
                `Available for return: ${purchase.quantity - alreadyReturned}`);
        }
        const transaction = db.transaction(() => {
            // Find the stock_batch created by this purchase
            const batch = db.prepare(`
        SELECT id, batch_no, quantity_remaining, unit_cost
        FROM stock_batches
        WHERE source_type = 'PURCHASE' AND source_id = ?
      `).get(purchaseId);
            if (!batch)
                throw new Error('No stock batch found for this purchase');
            if (returnQuantity > batch.quantity_remaining) {
                throw new Error(`Insufficient stock remaining to return. Requested: ${returnQuantity}, Available: ${batch.quantity_remaining}`);
            }
            const returnCost = returnQuantity * batch.unit_cost;
            const now = new Date().toISOString().split('T')[0];
            // Create ADJUSTMENT movement to remove stock (negative quantity)
            StockMovement_1.default.recordMovement({
                item_id: purchase.item_id,
                warehouse_id: purchase.warehouse_id,
                movement_type: 'ADJUSTMENT',
                quantity: -returnQuantity,
                unit_cost: batch.unit_cost,
                reference_doctype: 'PURCHASE_RETURN',
                reference_docno: purchase.purchase_no,
                remarks: `Stock reversed - Purchase ${purchase.purchase_no} returned${reason ? ': ' + reason : ''} (batch ${batch.batch_no})`,
                movement_date: now,
            }, userId, db);
            // Reduce the batch quantity_remaining
            db.prepare('UPDATE stock_batches SET quantity_remaining = quantity_remaining - ? WHERE id = ?')
                .run(returnQuantity, batch.id);
            // Track cumulative returned quantity on the purchase record
            db.prepare('UPDATE purchases SET returned_quantity = COALESCE(returned_quantity, 0) + ? WHERE id = ?')
                .run(returnQuantity, purchaseId);
            // Note: stock_balances and items.current_stock are already updated
            // by StockMovementModel.recordMovement() above — no manual update needed.
            // Log activity
            db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(userId, 'RETURN', 'Purchase', purchaseId, `Return processed for ${returnQuantity} unit(s) on Purchase ${purchase.purchase_no}${reason ? ': ' + reason : ''}`);
            return { returnedQuantity: returnQuantity, totalCost: returnCost };
        });
        return transaction();
    }
    static delete(id, userId, db) {
        const purchase = this.getById(id, db);
        if (!purchase) {
            throw new Error('Purchase not found');
        }
        const transaction = db.transaction(() => {
            // Find the stock_batch created by this purchase
            const batch = db.prepare(`
        SELECT id, batch_no, quantity_remaining, unit_cost
        FROM stock_batches
        WHERE source_type = 'PURCHASE' AND source_id = ?
      `).get(id);
            if (batch && batch.quantity_remaining > 0) {
                // Create ADJUSTMENT movement to remove remaining stock
                StockMovement_1.default.recordMovement({
                    item_id: purchase.item_id,
                    warehouse_id: purchase.warehouse_id,
                    movement_type: 'ADJUSTMENT',
                    quantity: -batch.quantity_remaining,
                    unit_cost: batch.unit_cost,
                    reference_doctype: 'PURCHASE_DELETE',
                    reference_docno: purchase.purchase_no,
                    remarks: `Stock reversed - Purchase ${purchase.purchase_no} deleted (batch ${batch.batch_no})`,
                    movement_date: new Date().toISOString().split('T')[0],
                }, userId, db);
                // Zero out the batch record (keep for FK integrity with stock_movements)
                db.prepare('UPDATE stock_batches SET quantity_remaining = 0 WHERE id = ?').run(batch.id);
            }
            // Delete the purchase record
            db.prepare('DELETE FROM purchases WHERE id = ?').run(id);
            db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(userId, 'DELETE', 'Purchase', id, `Deleted purchase ${purchase.purchase_no}`);
        });
        transaction();
        return true;
    }
}
exports.default = PurchaseModel;
//# sourceMappingURL=Purchase.js.map