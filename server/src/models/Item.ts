import Database from 'better-sqlite3';

interface Item {
  id: number;
  item_code: string;
  item_name: string;
  description?: string;
  category?: string;
  unit_of_measure: string;
  reorder_level?: number;
  standard_cost?: number;
  standard_selling_price?: number;
  is_raw_material: number;
  is_finished_good: number;
  is_purchased: number;
  is_manufactured?: number;
  sale_type?: string;
  qty_decimal_precision?: number;
  rounding_step?: number | null;
  current_stock?: number;
  created_by?: number;
  is_active?: number;
  created_at?: string;
  updated_at?: string;
}

interface CreateItemDTO {
  item_code: string;
  item_name: string;
  description?: string;
  category?: string;
  unit_of_measure?: string;
  reorder_level?: number;
  standard_cost?: number;
  standard_selling_price?: number;
  is_raw_material?: boolean;
  is_finished_good?: boolean;
  is_purchased?: boolean;
  is_manufactured?: boolean;
  sale_type?: 'packed' | 'loose';
  qty_decimal_precision?: number;
  rounding_step?: number | null;
}

interface UpdateItemDTO {
  item_name: string;
  description?: string;
  category?: string;
  unit_of_measure: string;
  reorder_level?: number;
  standard_cost?: number;
  standard_selling_price?: number;
  is_raw_material: boolean;
  is_finished_good: boolean;
  is_purchased: boolean;
  is_manufactured: boolean;
  sale_type?: 'packed' | 'loose';
  qty_decimal_precision?: number;
  rounding_step?: number | null;
}

interface ItemFilters {
  category?: string;
  search?: string;
  is_raw_material?: boolean;
  is_finished_good?: boolean;
}

interface StockByWarehouse {
  warehouse_id: number;
  warehouse_code: string;
  warehouse_name: string;
  quantity: number;
}

class ItemModel {
  private db: Database.Database;

  constructor(database: Database.Database) {
    this.db = database;
  }

  static getAll(filters: ItemFilters = {}, db: Database.Database): Item[] {
    let query = 'SELECT * FROM items WHERE is_active = 1';
    const params: any[] = [];

    if (filters.category) {
      query += ' AND category = ?';
      params.push(filters.category);
    }

    if (filters.search) {
      query += ' AND (item_code LIKE ? OR item_name LIKE ? OR description LIKE ?)';
      const searchTerm = `%${filters.search}%`;
      params.push(searchTerm, searchTerm, searchTerm);
    }

    if (filters.is_raw_material !== undefined) {
      query += ' AND is_raw_material = ?';
      params.push(filters.is_raw_material ? 1 : 0);
    }

    if (filters.is_finished_good !== undefined) {
      query += ' AND is_finished_good = ?';
      params.push(filters.is_finished_good ? 1 : 0);
    }

    query += ' ORDER BY item_name';

    return db.prepare(query).all(...params) as Item[];
  }

  static getById(id: number, db: Database.Database): Item | undefined {
    return db.prepare('SELECT * FROM items WHERE id = ?').get(id) as Item | undefined;
  }

  static getByCode(code: string, db: Database.Database): Item | undefined {
    return db.prepare('SELECT * FROM items WHERE item_code = ?').get(code) as Item | undefined;
  }

  static create(data: CreateItemDTO, userId: number, db: Database.Database): number {
    const stmt = db.prepare(`
      INSERT INTO items (
        item_code, item_name, description, category,
        unit_of_measure, reorder_level, standard_cost, standard_selling_price,
        is_raw_material, is_finished_good, is_purchased, is_manufactured,
        sale_type, qty_decimal_precision, rounding_step,
        created_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);

    const result = stmt.run(
      data.item_code,
      data.item_name,
      data.description || null,
      data.category || null,
      data.unit_of_measure || 'Nos',
      data.reorder_level || 0,
      data.standard_cost || 0,
      data.standard_selling_price || 0,
      data.is_raw_material ? 1 : 0,
      data.is_finished_good ? 1 : 0,
      data.is_purchased !== undefined ? (data.is_purchased ? 1 : 0) : 1,
      data.is_manufactured ? 1 : 0,
      data.sale_type === 'loose' ? 'loose' : 'packed',
      data.qty_decimal_precision || 0,
      data.rounding_step ?? null,
      userId
    );

    return result.lastInsertRowid as number;
  }

  static update(id: number, data: UpdateItemDTO, db: Database.Database): Database.RunResult {
    const stmt = db.prepare(`
      UPDATE items
      SET item_name = ?,
          description = ?,
          category = ?,
          unit_of_measure = ?,
          reorder_level = ?,
          standard_cost = ?,
          standard_selling_price = ?,
          is_raw_material = ?,
          is_finished_good = ?,
          is_purchased = ?,
          is_manufactured = ?,
          sale_type = ?,
          qty_decimal_precision = ?,
          rounding_step = ?,
          updated_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `);

    return stmt.run(
      data.item_name,
      data.description || null,
      data.category || null,
      data.unit_of_measure,
      data.reorder_level || 0,
      data.standard_cost || 0,
      data.standard_selling_price || 0,
      data.is_raw_material ? 1 : 0,
      data.is_finished_good ? 1 : 0,
      data.is_purchased ? 1 : 0,
      data.is_manufactured ? 1 : 0,
      data.sale_type === 'loose' ? 'loose' : 'packed',
      data.qty_decimal_precision || 0,
      data.rounding_step ?? null,
      id
    );
  }

  static delete(id: number, db: Database.Database): Database.RunResult {
    const stmt = db.prepare('UPDATE items SET is_active = 0 WHERE id = ?');
    return stmt.run(id);
  }

  static getStockByWarehouse(itemId: number, db: Database.Database): StockByWarehouse[] {
    return db.prepare(`
      SELECT
        w.id as warehouse_id,
        w.warehouse_code,
        w.warehouse_name,
        COALESCE(sb.quantity, 0) as quantity
      FROM warehouses w
      LEFT JOIN stock_balances sb ON sb.warehouse_id = w.id AND sb.item_id = ?
      WHERE w.is_active = 1
      ORDER BY w.warehouse_name
    `).all(itemId) as StockByWarehouse[];
  }

  static getCategories(db: Database.Database): { category: string }[] {
    return db.prepare(`
      SELECT DISTINCT category
      FROM items
      WHERE category IS NOT NULL AND is_active = 1
      ORDER BY category
    `).all() as { category: string }[];
  }

  static getUnitsOfMeasure(db: Database.Database): string[] {
    const usedUoms = db.prepare(`
      SELECT DISTINCT unit_of_measure
      FROM items
      WHERE unit_of_measure IS NOT NULL
      ORDER BY unit_of_measure
    `).all() as { unit_of_measure: string }[];

    const standardUoms = [
      'Nos', 'Kg', 'Ltr', 'Box', 'Pack', 'Bottle',
      'Meter', 'Roll', 'Set', 'Pcs', 'Dozen'
    ];

    return Array.from(new Set([
      ...standardUoms,
      ...usedUoms.map(u => u.unit_of_measure)
    ]));
  }

  static getLowStock(db: Database.Database): Item[] {
    return db.prepare(`
      SELECT *
      FROM items
      WHERE is_active = 1
      AND current_stock < reorder_level
      AND reorder_level > 0
      ORDER BY item_name
    `).all() as Item[];
  }
}

export default ItemModel;
