"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const StockMovement_1 = __importDefault(require("./StockMovement"));
const SupplierLedger_1 = __importDefault(require("./SupplierLedger"));
const accountingService_1 = __importDefault(require("../services/accountingService"));
const sequence_1 = require("../utils/sequence");
const sqlSanitizer_1 = require("../utils/sqlSanitizer");
// Whitelisted sort columns → qualified SQL column (the warehouse/user/credit
// note joins make bare names ambiguous).
const RETURN_SORT_COLUMN_MAP = {
    return_no: 'pr.return_no',
    return_date: 'pr.return_date',
    source_no: 'pr.source_no',
    total_amount: 'pr.total_amount',
    status: 'pr.status',
    warehouse_name: 'w.warehouse_name',
    created_at: 'pr.created_at',
};
const HEADER_SELECT = `
  SELECT
    pr.*,
    w.warehouse_code,
    w.warehouse_name,
    u.username as created_by_username,
    cn.credit_no,
    (SELECT COUNT(*) FROM purchase_return_items pri WHERE pri.purchase_return_id = pr.id) as line_count
  FROM purchase_returns pr
  JOIN warehouses w ON pr.warehouse_id = w.id
  LEFT JOIN users u ON pr.created_by = u.id
  LEFT JOIN credit_notes cn ON cn.id = pr.credit_note_id
`;
class PurchaseReturnModel {
    static generateReturnNo(db) {
        return (0, sequence_1.generateDocNo)(db, 'PR');
    }
    static generateCreditNo(db) {
        return (0, sequence_1.generateDocNo)(db, 'CN');
    }
    // ------------------------------------------------------------------
    // Reads
    // ------------------------------------------------------------------
    static getAll(filters = {}, db) {
        const pageNum = filters.page || 1;
        const limitNum = filters.limit || 10;
        const conditions = [];
        const params = [];
        if (filters.search) {
            conditions.push(`(pr.return_no LIKE ? OR pr.source_no LIKE ? OR
          EXISTS (SELECT 1 FROM purchase_return_items pri JOIN items i ON pri.item_id = i.id
                  WHERE pri.purchase_return_id = pr.id AND (i.item_name LIKE ? OR i.item_code LIKE ?)))`);
            const term = `%${filters.search}%`;
            params.push(term, term, term, term);
        }
        if (filters.start_date) {
            conditions.push('pr.return_date >= ?');
            params.push(filters.start_date);
        }
        if (filters.end_date) {
            conditions.push('pr.return_date <= ?');
            params.push(filters.end_date);
        }
        if (filters.type) {
            conditions.push('pr.return_type = ?');
            params.push(filters.type);
        }
        if (filters.status) {
            conditions.push('pr.status = ?');
            params.push(filters.status);
        }
        if (filters.warehouse_id) {
            conditions.push('pr.warehouse_id = ?');
            params.push(filters.warehouse_id);
        }
        const where = conditions.length ? ` WHERE ${conditions.join(' AND ')}` : '';
        const { column, order } = (0, sqlSanitizer_1.sanitizeSortParams)(filters.sortBy || 'return_date', filters.sortOrder || 'DESC', sqlSanitizer_1.PURCHASE_RETURN_HEADER_SORT_COLUMNS, 'return_date', 'DESC');
        const sortColumn = RETURN_SORT_COLUMN_MAP[column] || 'pr.return_date';
        const offset = (pageNum - 1) * limitNum;
        const rows = db
            .prepare(`${HEADER_SELECT}${where} ORDER BY ${sortColumn} ${order}, pr.id DESC LIMIT ? OFFSET ?`)
            .all(...params, limitNum, offset);
        const countRow = db
            .prepare(`SELECT COUNT(*) as total FROM purchase_returns pr
        JOIN warehouses w ON pr.warehouse_id = w.id${where}`)
            .get(...params);
        return { rows, total: countRow.total, pageNum, limitNum };
    }
    static getById(id, db) {
        const header = db
            .prepare(`${HEADER_SELECT} WHERE pr.id = ?`)
            .get(id);
        if (!header)
            return undefined;
        header.items = db.prepare(`
      SELECT
        pri.*,
        i.item_code,
        i.item_name,
        i.unit_of_measure
      FROM purchase_return_items pri
      JOIN items i ON pri.item_id = i.id
      WHERE pri.purchase_return_id = ?
      ORDER BY pri.id ASC
    `).all(id);
        return header;
    }
    // ------------------------------------------------------------------
    // Create (transactional: stock + GL + credit note + ledger + audit)
    // ------------------------------------------------------------------
    static create(data, userId, db) {
        if (!data.return_date)
            throw new Error('return_date is required');
        if (!data.source_type || !data.source_id)
            throw new Error('Source document is required');
        if (!data.warehouse_id)
            throw new Error('Restock warehouse is required');
        if (!data.items || data.items.length === 0)
            throw new Error('At least one item is required');
        const transaction = db.transaction(() => {
            // Load the source document and validate every line against its
            // returnable quantity BEFORE mutating anything.
            const lines = [];
            let totalQty = 0;
            let totalAmount = 0;
            // PRET-01 (task 4.1): aggregate duplicate lines for the same source
            // item BEFORE validating — each line previously validated against the
            // same pre-request returned_quantity, so duplicates over-returned.
            const aggregated = new Map();
            for (const line of data.items) {
                if (!line.quantity || line.quantity <= 0) {
                    throw new Error('Return quantity must be positive');
                }
                if (!line.source_item_id)
                    throw new Error('source_item_id is required');
                const key = Number(line.source_item_id);
                const entry = aggregated.get(key);
                if (entry) {
                    // Duplicate lines for the same source item must price identically.
                    if (Math.abs(Number(line.unit_cost ?? 0) - entry.unit_cost) > 0.001) {
                        throw new Error(`Conflicting unit costs for source item ${key}: ${entry.unit_cost} vs ${line.unit_cost}`);
                    }
                    entry.quantity += line.quantity;
                }
                else {
                    aggregated.set(key, { quantity: line.quantity, unit_cost: Number(line.unit_cost ?? 0) });
                }
            }
            // Validate each AGGREGATE against its source document headroom.
            for (const [sourceItemId, agg] of aggregated) {
                if (data.source_type === 'PURCHASE') {
                    const purchase = db.prepare(`
            SELECT p.*, i.item_name
            FROM purchases p JOIN items i ON p.item_id = i.id
            WHERE p.id = ?
          `).get(sourceItemId);
                    if (!purchase)
                        throw new Error(`Purchase line ${sourceItemId} not found`);
                    if (purchase.id !== data.source_id) {
                        throw new Error(`Purchase ${sourceItemId} does not belong to source ${data.source_id}`);
                    }
                    const returned = purchase.returned_quantity || 0;
                    const returnable = purchase.quantity - returned;
                    if (agg.quantity > returnable + 0.001) {
                        throw new Error(`Return quantity (${agg.quantity}) exceeds remaining available (${returnable}) ` +
                            `for purchase ${purchase.id}`);
                    }
                    const amount = agg.quantity * purchase.unit_cost;
                    lines.push({
                        source_item_id: purchase.id,
                        item_id: purchase.item_id,
                        item_name: purchase.item_name,
                        unit_cost: purchase.unit_cost,
                        quantity: agg.quantity,
                        amount,
                    });
                    totalQty += agg.quantity;
                    totalAmount += amount;
                }
                else {
                    // PURCHASE_ORDER — source_item_id is a purchase_order_items.id
                    const poItem = db.prepare(`
            SELECT poi.*, i.item_name
            FROM purchase_order_items poi JOIN items i ON poi.item_id = i.id
            WHERE poi.id = ?
          `).get(sourceItemId);
                    if (!poItem)
                        throw new Error(`PO line ${sourceItemId} not found`);
                    if (poItem.po_id !== data.source_id) {
                        throw new Error(`PO line ${sourceItemId} does not belong to PO ${data.source_id}`);
                    }
                    const returned = poItem.returned_quantity || 0;
                    const netReceived = (poItem.received_quantity || 0) - returned;
                    if (agg.quantity > netReceived + 0.001) {
                        throw new Error(`Return quantity (${agg.quantity}) exceeds net received quantity ` +
                            `(${netReceived}) for PO line ${poItem.id}`);
                    }
                    const amount = agg.quantity * poItem.unit_price;
                    lines.push({
                        source_item_id: poItem.id,
                        item_id: poItem.item_id,
                        item_name: poItem.item_name,
                        unit_cost: poItem.unit_price,
                        quantity: agg.quantity,
                        amount,
                    });
                    totalQty += agg.quantity;
                    totalAmount += amount;
                }
            }
            // PRET-06 (task 4.5): returning goods worth more than is still owed
            // drives the supplier balance negative (a hidden receivable). Require
            // an explicit disposition and stamp it on the credit note's status.
            const unpaidBalance = this.sourceUnpaidBalance(data.source_type, data.source_id, db);
            if (totalAmount > unpaidBalance + 0.01) {
                const d = data.disposition;
                if (d !== 'credit_on_account' && d !== 'refund_expected') {
                    throw new Error(`Return value (${totalAmount.toFixed(2)}) exceeds the unpaid balance (${unpaidBalance.toFixed(2)}). ` +
                        `Supply a disposition: 'credit_on_account' or 'refund_expected'.`);
                }
            }
            else if (data.disposition &&
                data.disposition !== 'credit_on_account' && data.disposition !== 'refund_expected') {
                throw new Error(`Invalid disposition '${data.disposition}' — use 'credit_on_account' or 'refund_expected'`);
            }
            // Header
            const returnNo = this.generateReturnNo(db);
            const headerResult = db.prepare(`
        INSERT INTO purchase_returns (
          return_no, return_date, return_type, source_type, source_id,
          source_no, warehouse_id, reason, status, total_qty, total_amount,
          created_by
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'POSTED', ?, ?, ?)
      `).run(returnNo, data.return_date, data.source_type === 'PURCHASE' ? 'PURCHASE_RETURN' : 'PO_RETURN', data.source_type, data.source_id, this.resolveSourceNo(data.source_type, data.source_id, db), data.warehouse_id, data.reason || null, totalQty, totalAmount, userId);
            const returnId = headerResult.lastInsertRowid;
            const insertLine = db.prepare(`
        INSERT INTO purchase_return_items (
          purchase_return_id, source_item_id, item_id, item_name,
          unit_cost, quantity, amount
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
      `);
            // Stock: verify availability, then record negative movements per line.
            for (const line of lines) {
                // Stock must exist in the restock warehouse before we remove it.
                const balance = db.prepare(`
          SELECT quantity FROM stock_balances
          WHERE item_id = ? AND warehouse_id = ?
        `).get(line.item_id, data.warehouse_id);
                const available = balance ? Number(balance.quantity) : 0;
                if (available < line.quantity - 0.001) {
                    throw new Error(`Insufficient stock for ${line.item_name} in warehouse ${data.warehouse_id}: ` +
                        `available ${available}, required ${line.quantity}`);
                }
                // Deduct returned_quantity on the source document.
                if (data.source_type === 'PURCHASE') {
                    db.prepare(`UPDATE purchases SET returned_quantity = COALESCE(returned_quantity, 0) + ? WHERE id = ?`)
                        .run(line.quantity, line.source_item_id);
                }
                else {
                    db.prepare(`UPDATE purchase_order_items SET returned_quantity = COALESCE(returned_quantity, 0) + ? WHERE id = ?`)
                        .run(line.quantity, line.source_item_id);
                }
                // Negative stock movement — recordMovement handles stock_balances,
                // items.current_stock and the ADJUSTMENT financial entry.
                const movement = StockMovement_1.default.recordMovement({
                    item_id: line.item_id,
                    warehouse_id: data.warehouse_id,
                    movement_type: 'ADJUSTMENT',
                    quantity: -line.quantity,
                    unit_cost: line.unit_cost,
                    reference_doctype: data.source_type === 'PURCHASE' ? 'PURCHASE_RETURN' : 'PO_RETURN',
                    reference_docno: returnNo,
                    remarks: `Return ${returnNo}${data.reason ? ': ' + data.reason : ''}`,
                    movement_date: data.return_date,
                }, userId, db);
                // Track the movement on the movement row itself.
                db.prepare('UPDATE stock_movements SET purchase_return_id = ? WHERE id = ?')
                    .run(returnId, movement.id);
                // PRET-02 (task 4.2): consume the SOURCE DOCUMENT's own batch, not
                // FIFO-oldest layers — returning goods must deplete the batch they
                // came from at their own cost. Short coverage is an error: never
                // silently under-consume while recording a full return.
                const sourceBatch = db.prepare(`
          SELECT id, quantity_remaining FROM stock_batches
          WHERE source_type = ? AND source_id = ?
            AND item_id = ? AND warehouse_id = ? AND quantity_remaining > 0
          ORDER BY id LIMIT 1
        `).get(data.source_type === 'PURCHASE' ? 'PURCHASE' : 'GOODS_RECEIPT', line.source_item_id, line.item_id, data.warehouse_id);
                if (!sourceBatch || sourceBatch.quantity_remaining < line.quantity - 0.001) {
                    throw new Error(`Insufficient stock in the source batch for ${line.item_name}: ` +
                        `available ${sourceBatch?.quantity_remaining ?? 0}, required ${line.quantity}. ` +
                        `Goods already sold cannot be returned to the supplier.`);
                }
                db.prepare('UPDATE stock_batches SET quantity_remaining = quantity_remaining - ? WHERE id = ?')
                    .run(line.quantity, sourceBatch.id);
                insertLine.run(returnId, line.source_item_id, line.item_id, line.item_name, line.unit_cost, line.quantity, line.amount);
                // Persist per-line batch consumption so void restores exactly
                // these batches (PRET-05, task 4.4) — create-then-void is a
                // value-identity operation.
                db.prepare(`
          INSERT INTO purchase_return_batches (return_line_id, batch_id, quantity)
          SELECT id, ?, ? FROM purchase_return_items
          WHERE purchase_return_id = ? AND source_item_id = ?
          ORDER BY id DESC LIMIT 1
        `).run(sourceBatch.id, line.quantity, returnId, line.source_item_id);
            }
            // GL reversal — Dr AP / Cr Inventory at actual return cost, keyed to
            // the return header so void can reverse it.
            if (totalAmount > 0) {
                accountingService_1.default.postPurchaseReturnEntry(db, {
                    purchaseId: returnId,
                    purchaseNo: returnNo,
                    returnAmount: totalAmount,
                    returnDate: data.return_date,
                    userId,
                });
            }
            // Supplier credit note + ledger entry.
            const creditNoteId = this.postCreditNote(db, returnId, returnNo, data, totalAmount, data.return_date, userId);
            db.prepare('UPDATE purchase_returns SET credit_note_id = ? WHERE id = ?').run(creditNoteId, returnId);
            // Audit
            db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(userId, 'CREATE', 'PurchaseReturn', returnId, `Created purchase return ${returnNo}: ${lines.length} line(s), ${totalQty} units, ${totalAmount.toFixed(2)} total`);
            return this.getById(returnId, db);
        });
        return transaction();
    }
    // ------------------------------------------------------------------
    // Void — full reversal (stock + GL + credit note + ledger + audit)
    // ------------------------------------------------------------------
    static voidReturn(id, userId, reason, db) {
        const header = this.getById(id, db);
        if (!header)
            throw new Error('Purchase return not found');
        if (header.status !== 'POSTED')
            throw new Error('Only POSTED returns can be voided');
        const transaction = db.transaction(() => {
            const lines = header.items || [];
            for (const line of lines) {
                // Restore returned_quantity on the source document.
                if (header.source_type === 'PURCHASE' && line.source_item_id) {
                    db.prepare(`UPDATE purchases SET returned_quantity = MAX(0, COALESCE(returned_quantity, 0) - ?) WHERE id = ?`)
                        .run(line.quantity, line.source_item_id);
                }
                else if (line.source_item_id) {
                    db.prepare(`UPDATE purchase_order_items SET returned_quantity = MAX(0, COALESCE(returned_quantity, 0) - ?) WHERE id = ?`)
                        .run(line.quantity, line.source_item_id);
                }
                // Positive reversal movement — puts stock back (balances +
                // current_stock + adjustment entry handled by recordMovement).
                const reversal = StockMovement_1.default.recordMovement({
                    item_id: line.item_id,
                    warehouse_id: header.warehouse_id,
                    movement_type: 'ADJUSTMENT',
                    quantity: line.quantity,
                    unit_cost: line.unit_cost,
                    reference_doctype: header.return_type,
                    reference_docno: header.return_no,
                    remarks: `Voided return ${header.return_no}${reason ? ': ' + reason : ''}`,
                    movement_date: new Date().toISOString().split('T')[0],
                }, userId, db);
                // Track the reversal movement on the return header too.
                db.prepare('UPDATE stock_movements SET purchase_return_id = ? WHERE id = ?')
                    .run(id, reversal.id);
                // PRET-05 (task 4.4): restore EXACTLY the batches the return
                // consumed (from purchase_return_batches) — not the newest layer.
                // Falls back to the newest-layer restore only for legacy returns
                // created before the consumption ledger existed.
                const consumed = db.prepare(`
          SELECT prb.batch_id, prb.quantity
          FROM purchase_return_batches prb
          WHERE prb.return_line_id = ?
        `).all(line.id);
                if (consumed.length > 0) {
                    for (const c of consumed) {
                        db.prepare(`UPDATE stock_batches SET quantity_remaining = MAX(0, quantity_remaining + ?) WHERE id = ?`)
                            .run(c.quantity, c.batch_id);
                    }
                }
                else {
                    const latest = db.prepare(`
            SELECT id FROM stock_batches
            WHERE item_id = ? AND warehouse_id = ?
            ORDER BY received_date DESC, id DESC
            LIMIT 1
          `).get(line.item_id, header.warehouse_id);
                    if (latest) {
                        db.prepare(`UPDATE stock_batches SET quantity_remaining = quantity_remaining + ? WHERE id = ?`)
                            .run(line.quantity, latest.id);
                    }
                }
            }
            // Reverse the GL entry (journal_lines voided by reference).
            accountingService_1.default.voidJournalLinesByReference(db, 'PURCHASE_RETURN', id);
            // Reverse the supplier credit note + ledger entry.
            if (header.credit_note_id) {
                const note = db.prepare(`SELECT * FROM credit_notes WHERE id = ?`)
                    .get(header.credit_note_id);
                if (note) {
                    db.prepare(`
            UPDATE credit_notes SET status = 'VOIDED', voided_at = datetime('now'), voided_by = ? WHERE id = ?
          `).run(userId, header.credit_note_id);
                    if (note.supplier_id) {
                        // Debit restores the supplier balance (credit note had reduced it).
                        SupplierLedger_1.default.createEntry({
                            supplier_id: note.supplier_id,
                            transaction_date: new Date().toISOString().split('T')[0],
                            transaction_type: 'CREDIT_NOTE_VOID',
                            reference_no: note.credit_no,
                            debit: note.amount,
                            credit: 0,
                            description: `Void credit note ${note.credit_no} (return ${header.return_no})`,
                        }, db);
                        // PRET-04 (task 4.3): rebuild the running balance chain after
                        // the voiding debit, same as every other createEntry site.
                        SupplierLedger_1.default.rebuildBalances(note.supplier_id, db);
                    }
                }
            }
            db.prepare(`
        UPDATE purchase_returns
        SET status = 'VOIDED', voided_at = datetime('now'), voided_by = ?, voided_reason = ?
        WHERE id = ?
      `).run(userId, reason || null, id);
            db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(userId, 'VOID', 'PurchaseReturn', id, `Voided purchase return ${header.return_no}${reason ? ': ' + reason : ''}`);
            return this.getById(id, db);
        });
        return transaction();
    }
    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------
    static resolveSourceNo(sourceType, sourceId, db) {
        if (sourceType === 'PURCHASE') {
            const row = db.prepare('SELECT purchase_no FROM purchases WHERE id = ?').get(sourceId);
            if (!row)
                throw new Error('Purchase not found');
            return row.purchase_no;
        }
        const row = db.prepare('SELECT po_no FROM purchase_orders WHERE id = ?').get(sourceId);
        if (!row)
            throw new Error('Purchase Order not found');
        return row.po_no;
    }
    /**
     * Create the supplier credit note + supplier ledger entry for a return.
     * PRET-03 (task 4.3): the supplier is resolved by FOREIGN KEY only
     * (purchases.supplier_id / purchase_orders.supplier_id). The old
     * name-based lookup silently picked an arbitrary match on duplicate
     * names and skipped the ledger entry on a miss — a credit note without
     * its supplier credit. Unresolvable → throw; the transaction rolls back.
     */
    static postCreditNote(db, returnId, returnNo, data, totalAmount, creditDate, userId) {
        let supplierId;
        if (data.source_type === 'PURCHASE_ORDER') {
            const po = db.prepare('SELECT supplier_id FROM purchase_orders WHERE id = ?')
                .get(data.source_id);
            if (!po?.supplier_id) {
                throw new Error(`Purchase order ${data.source_id} has no resolvable supplier — cannot post the credit note`);
            }
            supplierId = po.supplier_id;
        }
        else {
            const purchase = db.prepare('SELECT supplier_id FROM purchases WHERE id = ?')
                .get(data.source_id);
            if (!purchase?.supplier_id) {
                throw new Error(`Purchase ${data.source_id} has no linked supplier — cannot post the credit note`);
            }
            supplierId = purchase.supplier_id;
        }
        const creditNo = this.generateCreditNo(db);
        const result = db.prepare(`
      INSERT INTO credit_notes (
        credit_no, credit_date, supplier_id, source_type, source_id,
        amount, status, posted_by
      ) VALUES (?, ?, ?, 'PURCHASE_RETURN', ?, ?, 'POSTED', ?)
    `).run(creditNo, creditDate, supplierId, returnId, totalAmount, userId);
        const creditNoteId = result.lastInsertRowid;
        SupplierLedger_1.default.createEntry({
            supplier_id: supplierId,
            transaction_date: creditDate,
            transaction_type: 'CREDIT_NOTE',
            reference_no: creditNo,
            debit: 0,
            credit: totalAmount,
            description: `Credit note ${creditNo} for return ${returnNo}`,
        }, db);
        // PRET-04 (task 4.3): keep suppliers.current_balance in lockstep —
        // createEntry alone never touches the header balance.
        SupplierLedger_1.default.rebuildBalances(supplierId, db);
        return creditNoteId;
    }
    /**
     * Unpaid balance of the return's source document (PRET-06, task 4.5):
     * total minus what supplier payments have already settled, derived from
     * the authoritative allocation tables.
     */
    static sourceUnpaidBalance(sourceType, sourceId, db) {
        if (sourceType === 'PURCHASE') {
            const row = db.prepare(`
        SELECT p.total_cost,
          COALESCE((SELECT SUM(amount) FROM purchase_allocations WHERE purchase_id = p.id), 0) AS paid
        FROM purchases p WHERE p.id = ?
      `).get(sourceId);
            if (!row)
                throw new Error('Purchase not found');
            return Number(row.total_cost) - Number(row.paid);
        }
        const row = db.prepare(`
      SELECT po.total_amount,
        COALESCE((SELECT SUM(amount) FROM po_allocations WHERE po_id = po.id), 0) AS paid
      FROM purchase_orders po WHERE po.id = ?
    `).get(sourceId);
        if (!row)
            throw new Error('Purchase Order not found');
        return Number(row.total_amount) - Number(row.paid);
    }
}
exports.default = PurchaseReturnModel;
