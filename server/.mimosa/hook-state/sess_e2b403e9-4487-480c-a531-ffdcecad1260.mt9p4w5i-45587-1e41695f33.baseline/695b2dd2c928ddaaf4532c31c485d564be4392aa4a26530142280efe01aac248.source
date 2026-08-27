import Database from 'better-sqlite3';

interface Warehouse {
  id: number;
  warehouse_code: string;
  warehouse_name?: string;
  is_active?: number;
  created_at?: string;
  updated_at?: string;
}

class WarehouseModel {
  /**
   * Get warehouse by code
   */
  static getByCode(db: Database.Database, warehouseCode: string): Warehouse | undefined {
    return db.prepare('SELECT * FROM warehouses WHERE warehouse_code = ? AND is_active = 1').get(warehouseCode) as Warehouse | undefined;
  }

  /**
   * Get default warehouse (WH-001)
   */
  static getDefaultWarehouse(db: Database.Database): Warehouse | undefined {
    return this.getByCode(db, 'WH-001');
  }

  /**
   * Get all active warehouses
   */
  static getAllActive(db: Database.Database): Warehouse[] {
    return db.prepare('SELECT * FROM warehouses WHERE is_active = 1').all() as Warehouse[];
  }

  static getAll(db: Database.Database): Warehouse[] {
    return db.prepare('SELECT * FROM warehouses ORDER BY warehouse_code').all() as Warehouse[];
  }

  static getById(db: Database.Database, id: number): Warehouse | undefined {
    return db.prepare('SELECT * FROM warehouses WHERE id = ?').get(id) as Warehouse | undefined;
  }

  static create(db: Database.Database, data: { warehouse_code: string; warehouse_name: string; location?: string }): number {
    const result = db.prepare(`
      INSERT INTO warehouses (warehouse_code, warehouse_name, location)
      VALUES (?, ?, ?)
    `).run(data.warehouse_code, data.warehouse_name, data.location || null);
    return result.lastInsertRowid as number;
  }

  static update(db: Database.Database, id: number, data: { warehouse_code: string; warehouse_name: string; location?: string }): void {
    db.prepare(`
      UPDATE warehouses SET warehouse_code = ?, warehouse_name = ?, location = ?
      WHERE id = ?
    `).run(data.warehouse_code, data.warehouse_name, data.location || null, id);
  }

  static delete(db: Database.Database, id: number): void {
    db.prepare('UPDATE warehouses SET is_active = 0 WHERE id = ?').run(id);
  }

  static getStockSummary(db: Database.Database) {
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

export default WarehouseModel;
