import Database from 'better-sqlite3';
import { sanitizeSortParams, ITEM_SORT_COLUMNS } from '../utils/sqlSanitizer';

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
  has_expiry?: boolean;
  near_expiry_threshold_days?: number;
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
  has_expiry?: boolean;
  near_expiry_threshold_days?: number;
}

interface ItemFilters {
  category?: string;
  search?: string;
  is_raw_material?: boolean;
  is_finished_good?: boolean;
  lowStock?: boolean;
  sortBy?: string;
  sortOrder?: string;
  page?: number;
  limit?: number;
}

interface PaginatedItems {
  rows: Item[];
  total: number;
  pageNum: number;
  limitNum: number;
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

  static getAll(filters: ItemFilters = {}, db: Database.Database): PaginatedItems {
    const pageNum = filters.page || 1;
    const limitNum = filters.limit || 10;

    // The low-stock rule mirrors the old `getLowStock` predicates:
    // at/below the reorder level with a positive threshold. `reorder_level 0`
    // (or null) means no reorder threshold.
    const conditions: string[] = ['is_active = 1'];
    const params: any[] = [];

    if (filters.category) {
      conditions.push('category = ?');
      params.push(filters.category);
    }

    if (filters.search) {
      conditions.push(
        '(item_code LIKE ? OR item_name LIKE ? OR description LIKE ?)'
      );
      const searchTerm = `%${filters.search}%`;
      params.push(searchTerm, searchTerm, searchTerm);
    }

    if (filters.is_raw_material !== undefined) {
      conditions.push('is_raw_material = ?');
      params.push(filters.is_raw_material ? 1 : 0);
    }

    if (filters.is_finished_good !== undefined) {
      conditions.push('is_finished_good = ?');
      params.push(filters.is_finished_good ? 1 : 0);
    }

    if (filters.lowStock) {
      conditions.push('current_stock < reorder_level AND reorder_level > 0');
    }

    const where = `WHERE ${conditions.join(' AND ')}`;

    // Sort — whitelisted via sqlSanitizer (default matches the
    // pre-paging behavior: alphabetical by item name).
    const { column, order } = sanitizeSortParams(
      filters.sortBy || 'item_name',
      filters.sortOrder || 'ASC',
      ITEM_SORT_COLUMNS,
      'item_name',
      'ASC'
    );

    const offset = (pageNum - 1) * limitNum;
    const rows = db
      .prepare(`SELECT * FROM items ${where} ORDER BY ${column} ${order} LIMIT ? OFFSET ?`)
      .all(...params, limitNum, offset) as Item[];

    const countRow = db
      .prepare(`SELECT COUNT(*) as total FROM items ${where}`)
      .get(...params) as { total: number };

    return { rows, total: countRow.total, pageNum, limitNum };
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
        has_expiry, near_expiry_threshold_days,
        created_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
      data.has_expiry ? 1 : 0,
      data.near_expiry_threshold_days ?? 30,
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
          has_expiry = ?,
          near_expiry_threshold_days = ?,
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
      data.has_expiry ? 1 : 0,
      data.near_expiry_threshold_days ?? 30,
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
    // Delegates to the paged query so `GET /inventory/items-low-stock`
    // and the paged `GET /inventory/items?low_stock=1` share one query
    // definition (and the same low-stock predicates).
    return ItemModel.getAll({ lowStock: true }, db).rows;
  }
}

export default ItemModel;
