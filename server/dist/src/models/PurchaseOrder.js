"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const StockMovement_1 = __importDefault(require("./StockMovement"));
const accountingService_1 = __importDefault(require("../services/accountingService"));
const sequence_1 = require("../utils/sequence");
const logger_1 = __importDefault(require("../utils/logger"));
class PurchaseOrderModel {
    static create(data, userId, db) {
        const { supplier_id, po_date, expected_delivery_date, status = 'Draft', notes, warehouse_id, items } = data;
        if (!items || items.length === 0) {
            throw new Error('At least one item is required');
        }
        const transaction = db.transaction(() => {
            // Generate PO number
            const poNo = this.generatePONo(db);
            // Calculate total amount
            const totalAmount = items.reduce((sum, item) => sum + (item.quantity * item.unit_price), 0);
            // Insert PO header
            const poStmt = db.prepare(`
        INSERT INTO purchase_orders (
          po_no, supplier_id, po_date, expected_delivery_date,
          status, total_amount, notes, warehouse_id, created_by
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      `);
            const poResult = poStmt.run(poNo, supplier_id, po_date, expected_delivery_date || null, status, totalAmount, notes || null, warehouse_id || null, userId);
            const poId = poResult.lastInsertRowid;
            // Insert PO items
            const itemStmt = db.prepare(`
        INSERT INTO purchase_order_items (
          po_id, item_id, quantity, unit_price, amount
        ) VALUES (?, ?, ?, ?, ?)
      `);
            for (const item of items) {
                const amount = item.quantity * item.unit_price;
                itemStmt.run(poId, item.item_id, item.quantity, item.unit_price, amount);
            }
            // Create AP ledger entry (if submitted)
            if (status === 'Submitted') {
                SupplierLedger_1.default.createEntry({
                    supplier_id,
                    transaction_date: po_date,
                    transaction_type: 'PURCHASE_ORDER',
                    reference_no: poNo,
                    debit: totalAmount,
                    credit: 0,
                    description: `Purchase Order ${poNo}`
                }, db);
                // GL Phase-2 wiring: post the PO commitment to the journal.
                // Dr Inventory Asset / Cr Accounts Payable. The supplier
                // ledger above is the sub-ledger; this is the GL posting.
                accountingService_1.default.postPurchaseOrderEntry(db, {
                    purchaseOrderId: poId,
                    poNo,
                    totalAmount,
                    poDate: po_date,
                    userId,
                });
            }
            // Log activity
            db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(userId, 'CREATE', 'PurchaseOrder', poId, `Created PO ${poNo} with ${items.length} items`);
            return this.getById(poId, db);
        });
        return transaction();
    }
    static generatePONo(db) {
        return (0, sequence_1.generateDocNo)(db, 'PO');
    }
    /**
     * Atomic batch number for goods-receipt cost layers, same sequence as
     * the direct-purchase flow (BATCH-last_no) so numbers stay unique across
     * both purchase paths.
     */
    static generateBatchNo(db) {
        const year = new Date().getFullYear();
        const settingKey = `BATCH_last_no_${year}`;
        const nextNo = (0, sequence_1.getNextSequenceNumber)(db, settingKey);
        return `BATCH-${year % 100}-PUR-${nextNo.toString().padStart(4, '0')}`;
    }
    static getAll(filters = {}, db) {
        let query = `
      SELECT
        po.*,
        s.supplier_name,
        s.supplier_code,
        w.warehouse_name,
        w.warehouse_code,
        u.username as created_by_username,
        COALESCE(pa.total_paid, 0) as paid_amount,
        MAX(0, po.total_amount - COALESCE(pa.total_paid, 0)) as balance_amount
      FROM purchase_orders po
      JOIN suppliers s ON po.supplier_id = s.id
      LEFT JOIN warehouses w ON po.warehouse_id = w.id
      JOIN users u ON po.created_by = u.id
      LEFT JOIN (
        SELECT po_id, SUM(amount) as total_paid
        FROM po_allocations
        GROUP BY po_id
      ) pa ON po.id = pa.po_id
      WHERE 1=1
    `;
        const params = [];
        if (filters.supplier_id) {
            query += ` AND po.supplier_id = ?`;
            params.push(filters.supplier_id);
        }
        if (filters.status) {
            query += ` AND po.status = ?`;
            params.push(filters.status);
        }
        if (filters.start_date) {
            query += ` AND po.po_date >= ?`;
            params.push(filters.start_date);
        }
        if (filters.end_date) {
            query += ` AND po.po_date <= ?`;
            params.push(filters.end_date);
        }
        query += ` ORDER BY po.po_date DESC, po.created_at DESC`;
        if (filters.limit) {
            query += ` LIMIT ?`;
            params.push(filters.limit);
        }
        return db.prepare(query).all(...params);
    }
    static getById(id, db) {
        try {
            return db.prepare(`
        SELECT
          po.*,
          s.supplier_name,
          s.supplier_code,
          w.warehouse_name,
          w.warehouse_code,
          u.username as created_by_username,
          COALESCE(pa.total_paid, 0) as paid_amount,
          MAX(0, po.total_amount - COALESCE(pa.total_paid, 0)) as balance_amount
        FROM purchase_orders po
        JOIN suppliers s ON po.supplier_id = s.id
        LEFT JOIN warehouses w ON po.warehouse_id = w.id
        JOIN users u ON po.created_by = u.id
        LEFT JOIN (
          SELECT po_id, SUM(amount) as total_paid
          FROM po_allocations
          GROUP BY po_id
        ) pa ON po.id = pa.po_id
        WHERE po.id = ?
        GROUP BY po.id
      `).get(id);
        }
        catch (error) {
            logger_1.default.warn('PO balance query failed, falling back to base query:', error);
            return db.prepare(`
        SELECT
          po.*,
          s.supplier_name,
          s.supplier_code,
          w.warehouse_name,
          w.warehouse_code,
          u.username as created_by_username
        FROM purchase_orders po
        JOIN suppliers s ON po.supplier_id = s.id
        LEFT JOIN warehouses w ON po.warehouse_id = w.id
        JOIN users u ON po.created_by = u.id
        WHERE po.id = ?
      `).get(id);
        }
    }
    static getItems(poId, db) {
        return db.prepare(`
      SELECT
        poi.*,
        i.item_code,
        i.item_name,
        i.unit_of_measure,
        (poi.quantity - poi.received_quantity) as pending_quantity
      FROM purchase_order_items poi
      JOIN items i ON poi.item_id = i.id
      WHERE poi.po_id = ?
      ORDER BY poi.id
    `).all(poId);
    }
    static update(id, data, userId, db) {
        const po = this.getById(id, db);
        if (!po) {
            throw new Error('Purchase Order not found');
        }
        if (po.status !== 'Draft') {
            throw new Error('Only Draft Purchase Orders can be edited');
        }
        const { supplier_id, po_date, expected_delivery_date, notes, warehouse_id } = data;
        const transaction = db.transaction(() => {
            // Recalculate total from existing items
            const totalAmount = db.prepare(`
        SELECT COALESCE(SUM(amount), 0) as total
        FROM purchase_order_items
        WHERE po_id = ?
      `).get(id);
            const stmt = db.prepare(`
        UPDATE purchase_orders
        SET supplier_id = COALESCE(?, supplier_id),
            po_date = COALESCE(?, po_date),
            expected_delivery_date = COALESCE(?, expected_delivery_date),
            total_amount = ?,
            notes = COALESCE(?, notes),
            warehouse_id = COALESCE(?, warehouse_id),
            updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
      `);
            stmt.run(supplier_id || null, po_date || null, expected_delivery_date || null, totalAmount.total, notes || null, warehouse_id || null, id);
            db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(userId, 'UPDATE', 'PurchaseOrder', id, `Updated PO ${po.po_no}`);
            return this.getById(id, db);
        });
        return transaction();
    }
    static addItem(poId, itemData, db) {
        const po = this.getById(poId, db);
        if (!po) {
            throw new Error('Purchase Order not found');
        }
        if (po.status !== 'Draft') {
            throw new Error('Cannot add items to non-Draft Purchase Orders');
        }
        const transaction = db.transaction(() => {
            const amount = itemData.quantity * itemData.unit_price;
            const stmt = db.prepare(`
        INSERT INTO purchase_order_items (po_id, item_id, quantity, unit_price, amount)
        VALUES (?, ?, ?, ?, ?)
      `);
            const result = stmt.run(poId, itemData.item_id, itemData.quantity, itemData.unit_price, amount);
            // Update total
            const totalAmount = db.prepare(`
        SELECT COALESCE(SUM(amount), 0) as total
        FROM purchase_order_items
        WHERE po_id = ?
      `).get(poId);
            db.prepare(`
        UPDATE purchase_orders
        SET total_amount = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
      `).run(totalAmount.total, poId);
            return db.prepare(`
        SELECT poi.*, i.item_code, i.item_name, i.unit_of_measure
        FROM purchase_order_items poi
        JOIN items i ON poi.item_id = i.id
        WHERE poi.id = ?
      `).get(result.lastInsertRowid);
        });
        return transaction();
    }
    static updateItem(itemId, itemData, db) {
        const item = db.prepare(`
      SELECT poi.*, po.status
      FROM purchase_order_items poi
      JOIN purchase_orders po ON poi.po_id = po.id
      WHERE poi.id = ?
    `).get(itemId);
        if (!item) {
            throw new Error('Purchase Order Item not found');
        }
        if (item.status !== 'Draft') {
            throw new Error('Cannot edit items in non-Draft Purchase Orders');
        }
        const amount = itemData.quantity * itemData.unit_price;
        const transaction = db.transaction(() => {
            db.prepare(`
        UPDATE purchase_order_items
        SET quantity = ?, unit_price = ?, amount = ?
        WHERE id = ?
      `).run(itemData.quantity, itemData.unit_price, amount, itemId);
            // Update PO total
            const totalAmount = db.prepare(`
        SELECT COALESCE(SUM(amount), 0) as total
        FROM purchase_order_items
        WHERE po_id = ?
      `).get(item.po_id);
            db.prepare(`
        UPDATE purchase_orders
        SET total_amount = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
      `).run(totalAmount.total, item.po_id);
            return db.prepare(`
        SELECT poi.*, i.item_code, i.item_name, i.unit_of_measure
        FROM purchase_order_items poi
        JOIN items i ON poi.item_id = i.id
        WHERE poi.id = ?
      `).get(itemId);
        });
        return transaction();
    }
    static removeItem(itemId, db) {
        const item = db.prepare(`
      SELECT poi.*, po.status
      FROM purchase_order_items poi
      JOIN purchase_orders po ON poi.po_id = po.id
      WHERE poi.id = ?
    `).get(itemId);
        if (!item) {
            throw new Error('Purchase Order Item not found');
        }
        if (item.status !== 'Draft') {
            throw new Error('Cannot remove items from non-Draft Purchase Orders');
        }
        const transaction = db.transaction(() => {
            db.prepare('DELETE FROM purchase_order_items WHERE id = ?').run(itemId);
            // Update PO total
            const totalAmount = db.prepare(`
        SELECT COALESCE(SUM(amount), 0) as total
        FROM purchase_order_items
        WHERE po_id = ?
      `).get(item.po_id);
            db.prepare(`
        UPDATE purchase_orders
        SET total_amount = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
      `).run(totalAmount.total, item.po_id);
            return true;
        });
        return transaction();
    }
    static updateStatus(id, status, userId, db) {
        const po = this.getById(id, db);
        if (!po) {
            throw new Error('Purchase Order not found');
        }
        const validTransitions = {
            'Draft': ['Submitted', 'Cancelled'],
            'Submitted': ['Partially Received', 'Cancelled'],
            'Partially Received': ['Completed', 'Cancelled'],
            'Completed': [],
            'Cancelled': []
        };
        if (!validTransitions[po.status]?.includes(status)) {
            throw new Error(`Cannot transition from ${po.status} to ${status}`);
        }
        const transaction = db.transaction(() => {
            db.prepare(`
        UPDATE purchase_orders
        SET status = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
      `).run(status, id);
            // Create AP ledger entry if submitting
            if (status === 'Submitted' && po.status !== 'Submitted') {
                SupplierLedger_1.default.createEntry({
                    supplier_id: po.supplier_id,
                    transaction_date: po.po_date,
                    transaction_type: 'PURCHASE_ORDER',
                    reference_no: po.po_no,
                    debit: po.total_amount,
                    credit: 0,
                    description: `Purchase Order ${po.po_no}`
                }, db);
            }
            db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(userId, 'UPDATE', 'PurchaseOrder', id, `Changed PO ${po.po_no} status from ${po.status} to ${status}`);
            return this.getById(id, db);
        });
        return transaction();
    }
    static delete(id, userId, db) {
        const po = this.getById(id, db);
        if (!po) {
            throw new Error('Purchase Order not found');
        }
        if (po.status !== 'Draft') {
            throw new Error('Only Draft Purchase Orders can be deleted');
        }
        db.transaction(() => {
            db.prepare('DELETE FROM purchase_order_items WHERE po_id = ?').run(id);
            db.prepare('DELETE FROM purchase_orders WHERE id = ?').run(id);
            db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(userId, 'DELETE', 'PurchaseOrder', id, `Deleted PO ${po.po_no}`);
        })();
        return true;
    }
    static getReceipts(poId, db) {
        return db.prepare(`
      SELECT
        gr.*,
        w.warehouse_name,
        u.username as created_by_username,
        COALESCE(SUM(gri.received_quantity), 0) as total_quantity,
        COALESCE(SUM(gri.received_quantity * poi.unit_price), 0) as total_amount
      FROM goods_receipts gr
      LEFT JOIN warehouses w ON gr.warehouse_id = w.id
      JOIN users u ON gr.created_by = u.id
      LEFT JOIN goods_receipt_items gri ON gr.id = gri.receipt_id
      LEFT JOIN purchase_order_items poi ON gri.po_item_id = poi.id
      WHERE gr.po_id = ?
      GROUP BY gr.id
      ORDER BY gr.receipt_date DESC, gr.created_at DESC
    `).all(poId);
    }
    static addReceipt(data, userId, db) {
        const { po_id, receipt_date, warehouse_id, remarks, items } = data;
        if (!items || items.length === 0) {
            throw new Error('At least one item must be received');
        }
        const po = this.getById(po_id, db);
        if (!po) {
            throw new Error('Purchase Order not found');
        }
        if (po.status === 'Draft' || po.status === 'Cancelled') {
            throw new Error('Cannot receive items for Draft or Cancelled Purchase Orders');
        }
        const transaction = db.transaction(() => {
            // Validate quantities
            for (const receiptItem of items) {
                const poItem = db.prepare(`
          SELECT * FROM purchase_order_items WHERE id = ?
        `).get(receiptItem.po_item_id);
                if (!poItem) {
                    throw new Error('Purchase Order Item not found');
                }
                const pending = poItem.quantity - poItem.received_quantity;
                if (receiptItem.received_quantity > pending) {
                    throw new Error(`Cannot receive more than pending quantity (${pending})`);
                }
            }
            // Generate receipt number
            const receiptNo = this.generateReceiptNo(db);
            // Insert goods receipt
            const receiptStmt = db.prepare(`
        INSERT INTO goods_receipts (
          receipt_no, po_id, receipt_date, warehouse_id, remarks, created_by
        ) VALUES (?, ?, ?, ?, ?, ?)
      `);
            const receiptResult = receiptStmt.run(receiptNo, po_id, receipt_date, warehouse_id, remarks || null, userId);
            const receiptId = receiptResult.lastInsertRowid;
            // Insert receipt items and update PO items
            const receiptItemStmt = db.prepare(`
        INSERT INTO goods_receipt_items (receipt_id, po_item_id, item_id, received_quantity)
        VALUES (?, ?, ?, ?)
      `);
            let totalQuantity = 0;
            let totalAmount = 0;
            for (const receiptItem of items) {
                const poItem = db.prepare(`
          SELECT * FROM purchase_order_items WHERE id = ?
        `).get(receiptItem.po_item_id);
                const receiptItemResult = receiptItemStmt.run(receiptId, receiptItem.po_item_id, poItem.item_id, receiptItem.received_quantity);
                const receiptItemId = receiptItemResult.lastInsertRowid;
                // Update PO item received_quantity
                const newReceived = poItem.received_quantity + receiptItem.received_quantity;
                db.prepare(`
          UPDATE purchase_order_items
          SET received_quantity = ?
          WHERE id = ?
        `).run(newReceived, receiptItem.po_item_id);
                // Batch costing: create a cost layer for the received stock so
                // batch-based valuation (dashboard stock value, stock valuation
                // report, balance sheet) actually sees PO-received goods. Without
                // this, receipts added stock to stock_balances but no stock_batches
                // row, so the received value was invisible to every batch-based
                // figure.
                const batchNo = this.generateBatchNo(db);
                const batchResult = db.prepare(`
          INSERT INTO stock_batches (
            batch_no, item_id, warehouse_id, source_type,
            source_id, quantity_original, quantity_remaining,
            unit_cost, received_date
          ) VALUES (?, ?, ?, 'PURCHASE', ?, ?, ?, ?, ?)
        `).run(batchNo, poItem.item_id, warehouse_id, receiptItemId, receiptItem.received_quantity, receiptItem.received_quantity, poItem.unit_price, receipt_date);
                const batchId = batchResult.lastInsertRowid;
                // Create stock movement using atomic movement number generation
                const movementNo = StockMovement_1.default.generateMovementNo(db);
                db.prepare(`
          INSERT INTO stock_movements (
            movement_no, item_id, warehouse_id, movement_type,
            quantity, unit_cost, reference_doctype, reference_docno,
            remarks, movement_date, created_by, batch_id
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `).run(movementNo, poItem.item_id, warehouse_id, 'PURCHASE', receiptItem.received_quantity, poItem.unit_price, 'GOODS_RECEIPT', receiptNo, `Receipt ${receiptNo} against PO ${po.po_no}`, receipt_date, userId, batchId);
                // Update stock balance
                const existingBalance = db.prepare(`
          SELECT * FROM stock_balances
          WHERE item_id = ? AND warehouse_id = ?
         `).get(poItem.item_id, warehouse_id);
                if (existingBalance) {
                    db.prepare(`
            UPDATE stock_balances
            SET quantity = quantity + ?, last_updated = CURRENT_TIMESTAMP
            WHERE item_id = ? AND warehouse_id = ?
          `).run(receiptItem.received_quantity, poItem.item_id, warehouse_id);
                }
                else {
                    db.prepare(`
            INSERT INTO stock_balances (item_id, warehouse_id, quantity)
            VALUES (?, ?, ?)
          `).run(poItem.item_id, warehouse_id, receiptItem.received_quantity);
                }
                totalQuantity += receiptItem.received_quantity;
                totalAmount += receiptItem.received_quantity * poItem.unit_price;
            }
            // Update item current_stock
            for (const receiptItem of items) {
                const poItem = db.prepare(`
          SELECT item_id FROM purchase_order_items WHERE id = ?
        `).get(receiptItem.po_item_id);
                db.prepare(`
          UPDATE items
          SET current_stock = (
            SELECT COALESCE(SUM(quantity), 0)
            FROM stock_balances
            WHERE item_id = ?
          )
          WHERE id = ?
        `).run(poItem.item_id, poItem.item_id);
            }
            // Calculate and update PO status
            const newStatus = this.calculateStatus(po_id, db);
            if (newStatus !== po.status) {
                db.prepare(`
          UPDATE purchase_orders
          SET status = ?, updated_at = CURRENT_TIMESTAMP
          WHERE id = ?
        `).run(newStatus, po_id);
            }
            // Log activity
            db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(userId, 'CREATE', 'GoodsReceipt', receiptId, `Recorded receipt ${receiptNo}: ${totalQuantity} units, ${totalAmount.toFixed(2)} total`);
            return db.prepare(`
        SELECT
          gr.*,
          w.warehouse_name,
          u.username as created_by_username
        FROM goods_receipts gr
        LEFT JOIN warehouses w ON gr.warehouse_id = w.id
        JOIN users u ON gr.created_by = u.id
        WHERE gr.id = ?
      `).get(receiptId);
        });
        return transaction();
    }
    /**
     * Return (reverse) items that were previously received via a Goods Receipt.
     * This reduces received_quantity on the PO item, reverses stock via an
     * ADJUSTMENT movement, updates stock_balances, and recalculates the PO status.
     *
     * @param poId - Purchase Order ID
     * @param items - Array of { po_item_id, return_quantity }
     * @param userId - User performing the return
     * @param db - Database connection
     * @param reason - Optional reason for the return
     * @returns Summary of returned items
     */
    static returnReceiptItems(poId, items, userId, db, reason) {
        if (!items || items.length === 0) {
            throw new Error('At least one item must be returned');
        }
        const po = this.getById(poId, db);
        if (!po)
            throw new Error('Purchase Order not found');
        if (po.status === 'Draft') {
            throw new Error('Cannot return items from a Draft Purchase Order');
        }
        const transaction = db.transaction(() => {
            let totalQuantity = 0;
            let totalAmount = 0;
            let returnedCount = 0;
            for (const returnItem of items) {
                if (returnItem.return_quantity <= 0) {
                    throw new Error('Return quantity must be positive');
                }
                const poItem = db.prepare(`
          SELECT * FROM purchase_order_items WHERE id = ?
        `).get(returnItem.po_item_id);
                if (!poItem) {
                    throw new Error(`Purchase Order Item ${returnItem.po_item_id} not found`);
                }
                if (poItem.po_id !== poId) {
                    throw new Error(`Item ${poItem.id} does not belong to PO ${poId}`);
                }
                // Net received = received_quantity - already returned
                const netReceived = (poItem.received_quantity || 0) - (poItem.returned_quantity || 0);
                if (returnItem.return_quantity > netReceived) {
                    throw new Error(`Return quantity (${returnItem.return_quantity}) exceeds net received quantity ` +
                        `(${netReceived}) for PO item ${poItem.id}`);
                }
                const returnAmount = returnItem.return_quantity * poItem.unit_price;
                // Reduce PO item received_quantity (net effect)
                db.prepare(`
          UPDATE purchase_order_items
          SET received_quantity = received_quantity - ?,
              returned_quantity = COALESCE(returned_quantity, 0) + ?
          WHERE id = ?
        `).run(returnItem.return_quantity, returnItem.return_quantity, returnItem.po_item_id);
                // Create ADJUSTMENT stock movement (negative qty = removal)
                const movementNo = StockMovement_1.default.generateMovementNo(db);
                db.prepare(`
          INSERT INTO stock_movements (
            movement_no, item_id, warehouse_id, movement_type,
            quantity, unit_cost, reference_doctype, reference_docno,
            remarks, movement_date, created_by
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `).run(movementNo, poItem.item_id, po.warehouse_id, 'ADJUSTMENT', -returnItem.return_quantity, poItem.unit_price, 'PO_RETURN', po.po_no, `Stock reversed - PO ${po.po_no} item return${reason ? ': ' + reason : ''}`, new Date().toISOString().split('T')[0], userId);
                // Update stock_balances
                const existingBalance = db.prepare(`
          SELECT * FROM stock_balances
          WHERE item_id = ? AND warehouse_id = ?
        `).get(poItem.item_id, po.warehouse_id);
                if (existingBalance) {
                    db.prepare(`
            UPDATE stock_balances
            SET quantity = quantity - ?,
                last_updated = CURRENT_TIMESTAMP
            WHERE item_id = ? AND warehouse_id = ?
          `).run(returnItem.return_quantity, poItem.item_id, po.warehouse_id);
                }
                // Batch costing: reduce the cost layers (oldest first, FIFO) for
                // the stock going back to the supplier, so batch coverage stays in
                // sync with on-hand stock.
                let toReturn = returnItem.return_quantity;
                const batches = db.prepare(`
          SELECT id, quantity_remaining
          FROM stock_batches
          WHERE item_id = ? AND warehouse_id = ? AND quantity_remaining > 0
          ORDER BY received_date ASC, id ASC
        `).all(poItem.item_id, po.warehouse_id);
                for (const batch of batches) {
                    if (toReturn <= 0)
                        break;
                    const consume = Math.min(toReturn, batch.quantity_remaining);
                    db.prepare(`
            UPDATE stock_batches SET quantity_remaining = quantity_remaining - ? WHERE id = ?
          `).run(consume, batch.id);
                    toReturn -= consume;
                }
                // If the batches didn't fully cover the return (legacy stock with no
                // batch rows), the remainder is unbatchable stock — leave it as-is;
                // the reconciliation migration will fold it into a batch later.
                // Update items.current_stock
                db.prepare(`
          UPDATE items
          SET current_stock = (
            SELECT COALESCE(SUM(quantity), 0)
            FROM stock_balances
            WHERE item_id = ?
          )
          WHERE id = ?
        `).run(poItem.item_id, poItem.item_id);
                totalQuantity += returnItem.return_quantity;
                totalAmount += returnAmount;
                returnedCount++;
            }
            // Recalculate PO status after return
            const newStatus = this.calculateStatus(poId, db);
            if (newStatus !== po.status) {
                db.prepare(`
          UPDATE purchase_orders
          SET status = ?, updated_at = CURRENT_TIMESTAMP
          WHERE id = ?
        `).run(newStatus, poId);
            }
            // Log activity
            db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(userId, 'RETURN', 'PurchaseOrder', poId, `Return processed for ${returnedCount} item(s) (${totalQuantity} units, ${totalAmount.toFixed(2)}) on PO ${po.po_no}${reason ? ': ' + reason : ''}`);
            return { returnedCount, totalQuantity, totalAmount };
        });
        return transaction();
    }
    static generateReceiptNo(db) {
        return (0, sequence_1.generateDocNo)(db, 'GR');
    }
    static calculateStatus(poId, db) {
        const result = db.prepare(`
      SELECT
        COUNT(*) as total_items,
        SUM(CASE WHEN received_quantity > 0 THEN 1 ELSE 0 END) as items_received,
        SUM(CASE WHEN received_quantity >= quantity THEN 1 ELSE 0 END) as items_completed
      FROM purchase_order_items
      WHERE po_id = ?
    `).get(poId);
        if (result.items_completed === result.total_items) {
            return 'Completed';
        }
        else if (result.items_received > 0) {
            return 'Partially Received';
        }
        else {
            return 'Submitted'; // Default if not Draft
        }
    }
    static getSummaryBySupplier(supplierId, db) {
        return db.prepare(`
      SELECT
        COUNT(*) as total_pos,
        SUM(CASE WHEN status = 'Draft' THEN 1 ELSE 0 END) as draft_pos,
        SUM(CASE WHEN status = 'Submitted' THEN 1 ELSE 0 END) as submitted_pos,
        SUM(CASE WHEN status = 'Partially Received' THEN 1 ELSE 0 END) as partially_received_pos,
        SUM(CASE WHEN status = 'Completed' THEN 1 ELSE 0 END) as completed_pos,
        SUM(total_amount) as total_value
      FROM purchase_orders
      WHERE supplier_id = ?
    `).get(supplierId);
    }
    static getPendingOrders(db) {
        return this.getAll({ status: 'Submitted' }, db);
    }
}
// Import SupplierLedgerModel at the bottom to avoid circular dependency
const SupplierLedger_1 = __importDefault(require("./SupplierLedger"));
exports.default = PurchaseOrderModel;
//# sourceMappingURL=PurchaseOrder.js.map