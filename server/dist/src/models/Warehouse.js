"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
class WarehouseModel {
    /**
     * Get warehouse by code
     */
    static getByCode(db, warehouseCode) {
        return db.prepare('SELECT * FROM warehouses WHERE warehouse_code = ? AND is_active = 1').get(warehouseCode);
    }
    /**
     * Get default warehouse (WH-001)
     */
    static getDefaultWarehouse(db) {
        return this.getByCode(db, 'WH-001');
    }
    /**
     * Get all active warehouses
     */
    static getAllActive(db) {
        return db.prepare('SELECT * FROM warehouses WHERE is_active = 1').all();
    }
    static getAll(db) {
        return db.prepare('SELECT * FROM warehouses ORDER BY warehouse_code').all();
    }
    static getById(db, id) {
        return db.prepare('SELECT * FROM warehouses WHERE id = ?').get(id);
    }
    static create(db, data) {
        const result = db.prepare(`
      INSERT INTO warehouses (warehouse_code, warehouse_name, location)
      VALUES (?, ?, ?)
    `).run(data.warehouse_code, data.warehouse_name, data.location || null);
        return result.lastInsertRowid;
    }
    static update(db, id, data) {
        db.prepare(`
      UPDATE warehouses SET warehouse_code = ?, warehouse_name = ?, location = ?
      WHERE id = ?
    `).run(data.warehouse_code, data.warehouse_name, data.location || null, id);
    }
    static delete(db, id) {
        db.prepare('UPDATE warehouses SET is_active = 0 WHERE id = ?').run(id);
    }
    static getStockSummary(db) {
        return db.prepare(`
      SELECT w.*, COALESCE(SUM(sb.quantity), 0) as total_items,
        COUNT(DISTINCT sb.item_id) as unique_items
      FROM warehouses w
      LEFT JOIN stock_balances sb ON w.id = sb.warehouse_id
      WHERE w.is_active = 1
      GROUP BY w.id
      ORDER BY w.warehouse_name
    `).all();
    }
}
exports.default = WarehouseModel;
//# sourceMappingURL=Warehouse.js.map