"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
class PhysicalCountModel {
    static generateCountNo(db) {
        const year = new Date().getFullYear();
        const settingKey = `PC_last_no_${year}`;
        db.prepare(`
      INSERT INTO settings (key, value, updated_at)
      VALUES (?, '1', CURRENT_TIMESTAMP)
      ON CONFLICT(key) DO UPDATE SET
        value = CAST(CAST(settings.value AS INTEGER) + 1 AS TEXT),
        updated_at = CURRENT_TIMESTAMP
    `).run(settingKey);
        const setting = db.prepare('SELECT value FROM settings WHERE key = ?').get(settingKey);
        const nextNo = parseInt(setting.value);
        return `PC-${year}-${nextNo.toString().padStart(4, '0')}`;
    }
    static create(data, userId, db) {
        const transaction = db.transaction(() => {
            const countNo = this.generateCountNo(db);
            const result = db.prepare(`
        INSERT INTO physical_counts (count_no, count_date, warehouse_id, status, notes, created_by)
        VALUES (?, ?, ?, 'Draft', ?, ?)
      `).run(countNo, data.count_date || new Date().toISOString().split('T')[0], data.warehouse_id, data.notes || null, userId);
            const countId = result.lastInsertRowid;
            // Snapshot current stock for all items in the warehouse
            const stockItems = db.prepare(`
        SELECT sb.item_id, sb.quantity, i.standard_cost
        FROM stock_balances sb
        JOIN items i ON sb.item_id = i.id
        WHERE sb.warehouse_id = ? AND sb.quantity > 0 AND i.is_active = 1
        ORDER BY i.item_code
      `).all(data.warehouse_id);
            const insertItem = db.prepare(`
        INSERT INTO physical_count_items (count_id, item_id, system_quantity, unit_cost)
        VALUES (?, ?, ?, ?)
      `);
            for (const item of stockItems) {
                insertItem.run(countId, item.item_id, item.quantity, item.standard_cost || 0);
            }
            return countId;
        });
        return transaction();
    }
    static getById(id, db) {
        return db.prepare(`
      SELECT
        pc.*,
        w.warehouse_code,
        w.warehouse_name,
        u.full_name as created_by_name,
        cu.full_name as completed_by_name,
        (SELECT COUNT(*) FROM physical_count_items WHERE count_id = pc.id) as total_items,
        (SELECT COUNT(*) FROM physical_count_items WHERE count_id = pc.id AND counted_quantity IS NOT NULL) as counted_items,
        (SELECT COUNT(*) FROM physical_count_items WHERE count_id = pc.id AND variance != 0 AND counted_quantity IS NOT NULL) as variance_items
      FROM physical_counts pc
      JOIN warehouses w ON pc.warehouse_id = w.id
      LEFT JOIN users u ON pc.created_by = u.id
      LEFT JOIN users cu ON pc.completed_by = cu.id
      WHERE pc.id = ?
    `).get(id);
    }
    static getAll(db) {
        return db.prepare(`
      SELECT
        pc.*,
        w.warehouse_code,
        w.warehouse_name,
        u.full_name as created_by_name,
        (SELECT COUNT(*) FROM physical_count_items WHERE count_id = pc.id) as total_items,
        (SELECT COUNT(*) FROM physical_count_items WHERE count_id = pc.id AND counted_quantity IS NOT NULL) as counted_items,
        (SELECT COUNT(*) FROM physical_count_items WHERE count_id = pc.id AND variance != 0 AND counted_quantity IS NOT NULL) as variance_items
      FROM physical_counts pc
      JOIN warehouses w ON pc.warehouse_id = w.id
      LEFT JOIN users u ON pc.created_by = u.id
      ORDER BY pc.created_at DESC
    `).all();
    }
    static getItems(countId, db) {
        return db.prepare(`
      SELECT
        pci.*,
        i.item_code,
        i.item_name,
        i.unit_of_measure,
        i.category,
        u.full_name as counted_by_name
      FROM physical_count_items pci
      JOIN items i ON pci.item_id = i.id
      LEFT JOIN users u ON pci.counted_by = u.id
      WHERE pci.count_id = ?
      ORDER BY i.item_code
    `).all(countId);
    }
    static recordCount(countId, itemId, countedQuantity, userId, notes, db) {
        const count = this.getById(countId, db);
        if (!count)
            throw new Error('Physical count not found');
        if (count.status === 'Completed' || count.status === 'Cancelled') {
            throw new Error(`Cannot record count for ${count.status} session`);
        }
        const variance = countedQuantity - db.prepare('SELECT system_quantity FROM physical_count_items WHERE count_id = ? AND item_id = ?').get(countId, itemId)?.system_quantity || 0;
        db.prepare(`
      UPDATE physical_count_items
      SET counted_quantity = ?,
          variance = ?,
          variance_value = ? * unit_cost,
          counted_at = CURRENT_TIMESTAMP,
          counted_by = ?,
          notes = ?
      WHERE count_id = ? AND item_id = ?
    `).run(countedQuantity, variance, variance, userId, notes, countId, itemId);
    }
    static completeCount(countId, userId, db) {
        const count = this.getById(countId, db);
        if (!count)
            throw new Error('Physical count not found');
        if (count.status === 'Completed' || count.status === 'Cancelled') {
            throw new Error(`Cannot complete ${count.status} session`);
        }
        const transaction = db.transaction(() => {
            // Post adjustments for all items with variances
            const items = this.getItems(countId, db);
            const adjustmentItems = items.filter(i => i.counted_quantity !== null && i.variance !== 0);
            for (const item of adjustmentItems) {
                // Create stock movement for the adjustment
                const movementResult = db.prepare(`
          INSERT INTO stock_movements (
            movement_no, item_id, warehouse_id, movement_type,
            quantity, unit_cost, reference_doctype, reference_docno,
            remarks, movement_date, created_by
          ) VALUES (?, ?, ?, 'ADJUSTMENT', ?, ?, 'PhysicalCount', ?, ?, ?, ?)
        `).run(`STK-${new Date().getFullYear()}-${Date.now()}`, item.item_id, count.warehouse_id, item.variance, item.unit_cost, count.count_no, `Physical count adjustment: ${item.variance > 0 ? '+' : ''}${item.variance} (system: ${item.system_quantity}, counted: ${item.counted_quantity})`, count.count_date, userId);
                const movementId = movementResult.lastInsertRowid;
                // Update stock_balances
                const existingBalance = db.prepare('SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?').get(item.item_id, count.warehouse_id);
                if (existingBalance) {
                    db.prepare(`
            UPDATE stock_balances
            SET quantity = quantity + ?,
                last_updated = CURRENT_TIMESTAMP
            WHERE item_id = ? AND warehouse_id = ?
          `).run(item.variance, item.item_id, count.warehouse_id);
                }
                else {
                    db.prepare(`
            INSERT INTO stock_balances (item_id, warehouse_id, quantity)
            VALUES (?, ?, ?)
          `).run(item.item_id, count.warehouse_id, item.variance);
                }
                // Update items.current_stock
                db.prepare(`
          UPDATE items
          SET current_stock = (
            SELECT COALESCE(SUM(quantity), 0)
            FROM stock_balances
            WHERE item_id = ?
          )
          WHERE id = ?
        `).run(item.item_id, item.item_id);
                // Mark adjustment as posted
                db.prepare(`
          UPDATE physical_count_items
          SET adjustment_posted = TRUE,
              adjustment_movement_id = ?
          WHERE count_id = ? AND item_id = ?
        `).run(movementId, countId, item.item_id);
                // Post financial entry for adjustment
                if (item.unit_cost && item.variance !== 0) {
                    const value = Math.abs(item.variance) * item.unit_cost;
                    const isRemoval = item.variance < 0;
                    const accounts = isRemoval
                        ? { debit: 'inventory_shrinkage', credit: 'inventory_asset' }
                        : { debit: 'inventory_asset', credit: 'inventory_correction' };
                    const jeResult = db.prepare(`
            INSERT INTO journal_entries
              (reference_type, reference_id, entry_date, description,
               debit_account, credit_account, amount, created_by)
            VALUES ('stock_adjustment', ?, ?, ?, ?, ?, ?, ?)
          `).run(movementId, count.count_date, `Physical count: ${item.item_code} ${isRemoval ? 'shrinkage' : 'correction'} ${Math.abs(item.variance)} units @ ${item.unit_cost}`, accounts.debit, accounts.credit, value, userId);
                    db.prepare(`
            UPDATE stock_movements
            SET financial_value = ?, financial_posted = TRUE, journal_entry_id = ?
            WHERE id = ?
          `).run(value, jeResult.lastInsertRowid, movementId);
                }
            }
            // Update count status
            db.prepare(`
        UPDATE physical_counts
        SET status = 'Completed',
            completed_by = ?,
            completed_at = CURRENT_TIMESTAMP,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
      `).run(userId, countId);
        });
        transaction();
    }
    static cancelCount(countId, userId, db) {
        const count = this.getById(countId, db);
        if (!count)
            throw new Error('Physical count not found');
        if (count.status === 'Completed') {
            throw new Error('Cannot cancel completed session');
        }
        db.prepare(`
      UPDATE physical_counts
      SET status = 'Cancelled',
          updated_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `).run(countId);
    }
    static deleteCount(countId, db) {
        const count = this.getById(countId, db);
        if (!count)
            throw new Error('Physical count not found');
        if (count.status !== 'Draft' && count.status !== 'Cancelled') {
            throw new Error('Only Draft or Cancelled counts can be deleted');
        }
        const transaction = db.transaction(() => {
            db.prepare('DELETE FROM physical_count_items WHERE count_id = ?').run(countId);
            db.prepare('DELETE FROM physical_counts WHERE id = ?').run(countId);
        });
        transaction();
    }
}
exports.default = PhysicalCountModel;
//# sourceMappingURL=PhysicalCount.js.map