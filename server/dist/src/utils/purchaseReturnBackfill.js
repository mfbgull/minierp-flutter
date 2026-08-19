"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.backfillPurchaseReturns = backfillPurchaseReturns;
const sequence_1 = require("./sequence");
const logger_1 = __importDefault(require("./logger"));
/**
 * Backfill purchase_returns / purchase_return_items from the legacy negative
 * return movements (reference_doctype IN 'PURCHASE_RETURN' / 'PO_RETURN',
 * quantity < 0) created by the old return flows. Grouped by source doc +
 * date + item so each distinct return operation becomes one header with one
 * line; movements are back-linked via stock_movements.purchase_return_id.
 * Legacy returns never had credit notes, so status is POSTED with
 * credit_note_id NULL. Idempotent: only processes movements whose
 * purchase_return_id is still NULL.
 *
 * Returns the number of headers created (for logging/tests).
 */
function backfillPurchaseReturns(db) {
    const tableExists = db.prepare(`
    SELECT name FROM sqlite_master
    WHERE type='table' AND name='purchase_returns'
  `).get();
    if (!tableExists)
        return 0;
    const movements = db.prepare(`
    SELECT
      sm.id,
      sm.reference_doctype,
      sm.reference_docno,
      sm.movement_date,
      sm.item_id,
      sm.warehouse_id,
      sm.unit_cost,
      sm.quantity,
      sm.created_by,
      sm.created_at
    FROM stock_movements sm
    WHERE sm.reference_doctype IN ('PURCHASE_RETURN', 'PO_RETURN')
      AND sm.quantity < 0
      AND sm.purchase_return_id IS NULL
    ORDER BY sm.created_at ASC, sm.id ASC
  `).all();
    if (movements.length === 0)
        return 0;
    // Group by source doc + date + item → one header + one line each.
    const groups = new Map();
    for (const m of movements) {
        const key = [m.reference_doctype, m.reference_docno, m.movement_date, m.item_id].join('|');
        const bucket = groups.get(key);
        if (bucket) {
            bucket.push(m);
        }
        else {
            groups.set(key, [m]);
        }
    }
    const insertHeader = db.prepare(`
    INSERT INTO purchase_returns (
      return_no, return_date, return_type, source_type, source_id,
      source_no, warehouse_id, reason, status, total_qty, total_amount,
      created_by, created_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, NULL, 'POSTED', ?, ?, ?, ?)
  `);
    const insertLine = db.prepare(`
    INSERT INTO purchase_return_items (
      purchase_return_id, source_item_id, item_id, item_name,
      unit_cost, quantity, amount
    ) VALUES (?, ?, ?, ?, ?, ?, ?)
  `);
    const backlinkMovement = db.prepare('UPDATE stock_movements SET purchase_return_id = ? WHERE id = ?');
    // PO returns: source_item_id is the purchase_order_items.id for the
    // returned line (item + PO); direct-purchase lines are the purchase row
    // itself, so sourceItemId = sourceId.
    const resolvePoSourceItem = db.prepare(`
    SELECT id FROM purchase_order_items
    WHERE po_id = ? AND item_id = ?
    LIMIT 1
  `);
    const backfill = db.transaction(() => {
        for (const [key, bucket] of groups) {
            const [reference_doctype, reference_docno, movement_date, itemIdRaw] = key.split('|');
            const itemId = parseInt(itemIdRaw, 10);
            const first = bucket[0];
            const sourceType = reference_doctype === 'PO_RETURN' ? 'PURCHASE_ORDER' : 'PURCHASE';
            const item = db.prepare('SELECT item_name FROM items WHERE id = ?').get(itemId);
            if (!item) {
                // Orphaned movement (item deleted) — skip: a return needs a real
                // item row. The movement keeps purchase_return_id NULL.
                logger_1.default.warn(`[Backfill] Skipping legacy return movement ${first.id}: item ${itemId} no longer exists`);
                continue;
            }
            // Resolve the source document id from the denormalized doc number.
            const sourceId = sourceType === 'PURCHASE'
                ? db.prepare('SELECT id FROM purchases WHERE purchase_no = ?').get(reference_docno)?.id ?? null
                : db.prepare('SELECT id FROM purchase_orders WHERE po_no = ?').get(reference_docno)?.id ?? null;
            let totalQty = 0;
            let totalAmount = 0;
            for (const m of bucket) {
                const qty = Math.abs(m.quantity);
                const unitCost = m.unit_cost || 0;
                totalQty += qty;
                totalAmount += qty * unitCost;
            }
            const headerResult = insertHeader.run((0, sequence_1.generateDocNo)(db, 'PR'), movement_date, reference_doctype, sourceType, sourceId, reference_docno, first.warehouse_id, totalQty, totalAmount, first.created_by, first.created_at);
            const headerId = headerResult.lastInsertRowid;
            for (const m of bucket) {
                const qty = Math.abs(m.quantity);
                const unitCost = m.unit_cost || 0;
                let sourceItemId = sourceId;
                if (sourceType === 'PURCHASE_ORDER') {
                    const poi = resolvePoSourceItem.get(sourceId, m.item_id);
                    sourceItemId = poi?.id ?? null;
                }
                insertLine.run(headerId, sourceItemId, m.item_id, item.item_name, unitCost, qty, qty * unitCost);
                backlinkMovement.run(headerId, m.id);
            }
        }
    });
    backfill();
    return groups.size;
}
//# sourceMappingURL=purchaseReturnBackfill.js.map