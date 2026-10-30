import Database from 'better-sqlite3';
import { sanitizeSortParams, ITEM_SORT_COLUMNS } from '../utils/sqlSanitizer';
import StockMovementModel from './StockMovement';
import logger from '../utils/logger';
import { SqlParam } from '../utils/sqlTypes';
import { BusinessRuleError } from '../utils/businessRuleError';

interface Item {
  id: number;
  item_code: string;
  item_name: string;
  manufacturer_name?: string | null;
  company_id?: number | null;
  company_is_active?: number;
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
  has_expiry?: number;
  near_expiry_threshold_days?: number;
  current_stock?: number;
  created_by?: number;
  is_active?: number;
  created_at?: string;
  updated_at?: string;
  sellable_qty?: number;
}

interface CreateItemDTO {
  item_code: string;
  item_name: string;
  manufacturer_name?: string | null;
  company_id?: number | null;
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
  current_stock?: number;
  warehouse_id?: number;
}

function itemSupplyFlags(data: CreateItemDTO): number[] {
  return [
    data.is_raw_material ? 1 : 0,
    data.is_finished_good ? 1 : 0,
    data.is_purchased !== undefined ? (data.is_purchased ? 1 : 0) : 1,
    data.is_manufactured ? 1 : 0,
  ];
}

function pushBooleanFilter(
  conditions: string[],
  params: SqlParam[],
  condition: string,
  value: boolean | undefined,
): void {
  if (value === undefined) return;
  conditions.push(condition);
  params.push(value ? 1 : 0);
}

function itemFilterSql(filters: ItemFilters): { where: string; params: SqlParam[] } {
  // The low-stock rule mirrors the old `getLowStock` predicates:
  // at/below the reorder level with a positive threshold. `reorder_level 0`
  // (or null) means no reorder threshold.
  const conditions: string[] = ['i.is_active = 1', 'i.deleted_at IS NULL'];
  const params: SqlParam[] = [];

  if (filters.category) {
    conditions.push('i.category = ?');
    params.push(filters.category);
  }

  if (filters.search) {
    conditions.push(
      '(i.item_code LIKE ? OR i.item_name LIKE ? OR i.description LIKE ? OR i.manufacturer_name LIKE ?)'
    );
    const searchTerm = `%${filters.search}%`;
    params.push(searchTerm, searchTerm, searchTerm, searchTerm);
  }

  pushBooleanFilter(conditions, params, 'i.is_raw_material = ?', filters.is_raw_material);
  pushBooleanFilter(conditions, params, 'i.is_finished_good = ?', filters.is_finished_good);

  if (filters.lowStock) {
    conditions.push('i.current_stock < i.reorder_level AND i.reorder_level > 0');
  }

  if (filters.sellableOnly) {
    conditions.push('COALESCE(sa.sellable_qty, 0) > 0');
  }

  return { where: `WHERE ${conditions.join(' AND ')}`, params };
}

interface UpdateItemDTO {
  item_name: string;
  manufacturer_name?: string | null;
  company_id?: number | null;
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
  sellableOnly?: boolean;
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
    const { where, params } = itemFilterSql(filters);

    // Sort — whitelisted via sqlSanitizer (default matches the
    // pre-paging behavior: alphabetical by item name).
    const { column, order } = sanitizeSortParams(
      filters.sortBy || 'item_name',
      filters.sortOrder || 'ASC',
      ITEM_SORT_COLUMNS,
      'item_name',
      'ASC'
    );

    // Sellable availability (non-expired, non-halted, ACTIVE batches +
    // legacy stock) via the shared StockMovementModel fragment, so the
    // picker's offer can never disagree with backend sale validation.
    // LEFT JOIN keeps non-sellable items listed unless sellableOnly.
    const sellableJoin = `LEFT JOIN (${StockMovementModel.sellableAvailabilitySql(db)}) sa ON sa.item_id = i.id`;
    // Sort columns are whitelisted; qualify them against the items alias.
    const qualifiedColumn = column.startsWith('i.') ? column : `i.${column}`;

    const offset = (pageNum - 1) * limitNum;
    const rows = db
      .prepare(`SELECT i.*, COALESCE(sa.sellable_qty, 0) AS sellable_qty,
        COALESCE(c.company_name, i.manufacturer_name) AS display_manufacturer_name,
        COALESCE(c.is_active, 1) AS company_is_active
        FROM items i ${sellableJoin}
        LEFT JOIN item_companies c ON c.id = i.company_id
        ${where} ORDER BY ${qualifiedColumn} ${order} LIMIT ? OFFSET ?`)
      .all(...params, limitNum, offset) as ItemWithCompany[];

    const countRow = db
      .prepare(`SELECT COUNT(*) as total FROM items i ${sellableJoin} ${where}`)
      .get(...params) as { total: number };

    return { rows: rows.map(withCompanyFields), total: countRow.total, pageNum, limitNum };
  }

  static getById(id: number, db: Database.Database): Item | undefined {
    const row = db.prepare(`SELECT i.*,
        COALESCE(c.company_name, i.manufacturer_name) AS display_manufacturer_name,
        COALESCE(c.is_active, 1) AS company_is_active
      FROM items i LEFT JOIN item_companies c ON c.id = i.company_id
      WHERE i.id = ?`).get(id) as ItemWithCompany | undefined;
    return row ? withCompanyFields(row) : undefined;
  }

  static getByCode(code: string, db: Database.Database): Item | undefined {
    return db.prepare('SELECT * FROM items WHERE item_code = ?').get(code) as Item | undefined;
  }

  static create(data: CreateItemDTO, userId: number, db: Database.Database): number {
    return db.transaction(() => {
      const company = resolveCompanyForWrite(data, null, db);
      const stmt = db.prepare(`
        INSERT INTO items (
          item_code, item_name, description, category,
          unit_of_measure, reorder_level, standard_cost, standard_selling_price,
          is_raw_material, is_finished_good, is_purchased, is_manufactured,
          sale_type, qty_decimal_precision, rounding_step,
          has_expiry, near_expiry_threshold_days,
          created_by, manufacturer_name, company_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `);

      const result = stmt.run(
        ...itemCreateParams(data, company, userId)
      );

      return result.lastInsertRowid as number;
    })();
  }

  static update(id: number, data: UpdateItemDTO, db: Database.Database): Database.RunResult {
    return db.transaction(() => {
      const current = db.prepare('SELECT company_id FROM items WHERE id = ?').get(id) as
        { company_id: number | null } | undefined;
      const company = resolveCompanyForWrite(data, current?.company_id ?? null, db);
      const companyChanged = Number(company !== null);

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
            manufacturer_name = CASE WHEN ? THEN ? ELSE manufacturer_name END,
            company_id = CASE WHEN ? THEN ? ELSE company_id END,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
      `);

      return stmt.run(
        ...itemUpdateParams(data, company, companyChanged, id)
      );
    })();
  }

  /// Soft-delete (SHORTCOMINGS-FIX 4.2): stamps `deleted_at`/`deleted_by`
  /// and deactivates instead of removing the row, so an accidental delete
  /// can be undone via [restore].
  static delete(id: number, deletedBy: number, db: Database.Database): Database.RunResult {
    const stmt = db.prepare(`
      UPDATE items
      SET is_active = 0, deleted_at = datetime('now'), deleted_by = ?
      WHERE id = ?
    `);
    return stmt.run(deletedBy, id);
  }

  /// Reverts [delete]: clears the delete stamp and reactivates.
  static restore(id: number, db: Database.Database): Database.RunResult {
    const stmt = db.prepare(`
      UPDATE items
      SET is_active = 1, deleted_at = NULL, deleted_by = NULL
      WHERE id = ?
    `);
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

  /**
   * The expiry date a stock batch may carry, or null.
   *
   * Single source of truth for the invariant: **a batch whose item does not
   * track expiry never carries an expiry_date**. Every batch write path
   * (purchase, goods receipt, production output, batch PATCH) must route
   * its requested date through here rather than deciding for itself.
   *
   * This has to live in one place, not per caller. The boot sweep
   * (`boot/expiryDetection.ts`) filters on `has_expiry`, so a stray date on
   * a non-expiry item is invisible to the sweep today — but it surfaces on
   * the expiry report as soon as `has_expiry` is switched on for that item,
   * and every such historical batch then becomes sweep-eligible and is
   * relocated to the EXPIRED warehouse in one pass. D6 guarded the
   * production path only; purchase and goods receipt could still write it.
   *
   * A missing item row counts as "does not track expiry" — there is nothing
   * to expire against, and the sweep's LEFT JOIN keeps such batches visible
   * so they fail loudly there instead.
   */
  static batchExpiryDate(
    db: Database.Database,
    itemId: number,
    requested?: string | null,
  ): string | null {
    const row = db
      .prepare('SELECT has_expiry FROM items WHERE id = ?')
      .get(itemId) as { has_expiry: number | null } | undefined;
    if (row?.has_expiry !== 1) {
      if (requested) {
        logger.warn(
          `Discarded expiry_date ${requested} for item ${itemId}: the item does not track expiry ` +
            '(has_expiry is not 1). The batch was left without an expiry date.',
        );
      }
      return null;
    }
    return requested || null;
  }
}

function normalizeManufacturerName(value: string | null | undefined): string | null {
  return value?.trim() || null;
}

type ItemWithCompany = Item & { display_manufacturer_name?: string | null };

function withCompanyFields(row: ItemWithCompany): Item {
  const { display_manufacturer_name, ...rest } = row;
  return {
    ...rest,
    manufacturer_name: display_manufacturer_name ?? rest.manufacturer_name ?? null,
    company_id: rest.company_id ?? null,
    company_is_active: rest.company_is_active ?? 1,
  };
}

interface CompanyRow {
  id: number;
  company_name: string;
  is_active: number;
}

interface CompanyResolution {
  companyId: number | null;
  manufacturerName: string | null;
}

function itemCoreParams(data: CreateItemDTO): SqlParam[] {
  return [
    data.item_code,
    data.item_name,
    data.description || null,
    data.category || null,
    data.unit_of_measure || 'Nos',
    data.reorder_level || 0,
    data.standard_cost || 0,
    data.standard_selling_price || 0,
  ];
}

function itemBehaviorParams(data: CreateItemDTO): SqlParam[] {
  return [
    ...itemSupplyFlags(data),
    data.sale_type === 'loose' ? 'loose' : 'packed',
    data.qty_decimal_precision || 0,
    data.rounding_step ?? null,
    data.has_expiry ? 1 : 0,
    data.near_expiry_threshold_days ?? 30,
  ];
}

function companyWriteParams(company: CompanyResolution | null): SqlParam[] {
  return [company?.manufacturerName ?? null, company?.companyId ?? null];
}

function itemCreateParams(
  data: CreateItemDTO,
  company: CompanyResolution | null,
  userId: number,
): SqlParam[] {
  return [
    ...itemCoreParams(data),
    ...itemBehaviorParams(data),
    userId,
    ...companyWriteParams(company),
  ];
}

function flag(value: boolean): number {
  return value ? 1 : 0;
}

function itemUpdateTextParams(data: UpdateItemDTO): SqlParam[] {
  return [
    data.item_name,
    data.description || null,
    data.category || null,
    data.unit_of_measure,
  ];
}

function itemUpdatePriceParams(data: UpdateItemDTO): SqlParam[] {
  return [
    data.reorder_level || 0,
    data.standard_cost || 0,
    data.standard_selling_price || 0,
    flag(data.is_raw_material),
    flag(data.is_finished_good),
    flag(data.is_purchased),
    flag(data.is_manufactured),
  ];
}

function itemUpdateSaleParams(data: UpdateItemDTO): SqlParam[] {
  return [
    data.sale_type === 'loose' ? 'loose' : 'packed',
    data.qty_decimal_precision || 0,
    data.rounding_step ?? null,
  ];
}

function itemUpdateExpiryParams(data: UpdateItemDTO): SqlParam[] {
  return [
    data.has_expiry ? 1 : 0,
    data.near_expiry_threshold_days ?? 30,
  ];
}

function itemUpdateCoreParams(data: UpdateItemDTO): SqlParam[] {
  return [...itemUpdateTextParams(data), ...itemUpdatePriceParams(data)];
}

function itemUpdateTailParams(
  data: UpdateItemDTO,
  company: CompanyResolution | null,
  companyChanged: number,
  id: number,
): SqlParam[] {
  const [manufacturerName, companyId] = companyWriteParams(company);
  return [
    ...itemUpdateSaleParams(data),
    ...itemUpdateExpiryParams(data),
    companyChanged,
    manufacturerName,
    companyChanged,
    companyId,
    id,
  ];
}

function itemUpdateParams(
  data: UpdateItemDTO,
  company: CompanyResolution | null,
  companyChanged: number,
  id: number,
): SqlParam[] {
  return [
    ...itemUpdateCoreParams(data),
    ...itemUpdateTailParams(data, company, companyChanged, id),
  ];
}

function findCompanyByName(name: string, db: Database.Database): CompanyRow | undefined {
  return db.prepare(
    'SELECT id, company_name, is_active FROM item_companies WHERE company_name = ? COLLATE NOCASE',
  ).get(name) as CompanyRow | undefined;
}

function assertAssignable(company: CompanyRow, currentCompanyId: number | null): void {
  if (company.is_active !== 1 && company.id !== currentCompanyId) {
    throw new BusinessRuleError(400, 'Cannot assign an archived company to a product');
  }
}

function resolveExplicitCompany(
  companyId: number,
  currentCompanyId: number | null,
  db: Database.Database,
): CompanyResolution {
  const company = db.prepare(
    'SELECT id, company_name, is_active FROM item_companies WHERE id = ?',
  ).get(companyId) as CompanyRow | undefined;
  if (!company) {
    throw new BusinessRuleError(400, 'company_id must reference an existing company');
  }
  assertAssignable(company, currentCompanyId);
  return { companyId: company.id, manufacturerName: company.company_name };
}

function resolveCompanyByName(
  name: string,
  currentCompanyId: number | null,
  db: Database.Database,
): CompanyResolution {
  const existing = findCompanyByName(name, db);
  if (existing) {
    assertAssignable(existing, currentCompanyId);
    return { companyId: existing.id, manufacturerName: existing.company_name };
  }
  db.prepare(
    'INSERT INTO item_companies (company_name) VALUES (?) ON CONFLICT(company_name) DO NOTHING',
  ).run(name);
  const created = findCompanyByName(name, db);
  if (!created) {
    throw new Error('Company lookup failed after insert');
  }
  return { companyId: created.id, manufacturerName: created.company_name };
}

function resolveCompanyForWrite(
  data: { company_id?: number | null; manufacturer_name?: string | null },
  currentCompanyId: number | null,
  db: Database.Database,
): CompanyResolution | null {
  if (data.company_id !== undefined) {
    return data.company_id === null
      ? { companyId: null, manufacturerName: null }
      : resolveExplicitCompany(data.company_id, currentCompanyId, db);
  }
  if (data.manufacturer_name === undefined) {
    return null;
  }
  const name = normalizeManufacturerName(data.manufacturer_name);
  if (!name) {
    return { companyId: null, manufacturerName: null };
  }
  return resolveCompanyByName(name, currentCompanyId, db);
}

export default ItemModel;
