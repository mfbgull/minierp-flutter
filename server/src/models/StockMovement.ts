import Database from 'better-sqlite3';
import logger from '../utils/logger';
import { sanitizeSortParams, STOCK_BALANCE_SORT_COLUMNS, STOCK_MOVEMENT_SORT_COLUMNS } from '../utils/sqlSanitizer';

interface StockMovement {
  id: number;
  movement_no: string;
  item_id: number;
  warehouse_id: number;
  movement_type: string;
  quantity: number;
  unit_cost?: number;
  reference_doctype?: string;
  reference_docno?: string;
  remarks?: string;
  movement_date: string;
  created_by: number;
  created_at?: string;
  item_code?: string;
  item_name?: string;
  unit_of_measure?: string;
  warehouse_code?: string;
  warehouse_name?: string;
  created_by_name?: string;
}

interface MovementFilters {
  item_id?: number;
  warehouse_id?: number;
  movement_type?: string;
  date_from?: string;
  date_to?: string;
  search?: string;
  sortBy?: string;
  sortOrder?: string;
  page?: number;
  limit?: number;
}

interface StockBalanceFilters {
  search?: string;
  warehouse_code?: string;
  warehouse_id?: number;
  sortBy?: string;
  sortOrder?: string;
  page?: number;
  limit?: number;
}

interface PaginatedStockBalances {
  rows: StockMovement[];
  total: number;
  pageNum: number;
  limitNum: number;
}

// Whitelisted sort columns → qualified SQL column for the stock-balances
// query (joined aliases; qualification avoids ambiguity).
const BALANCE_SORT_COLUMN_MAP: Record<string, string> = {
  item_code: 'i.item_code',
  item_name: 'i.item_name',
  warehouse_name: 'w.warehouse_name',
  quantity: 'sb.quantity',
};

interface PaginatedMovements {
  rows: StockMovement[];
  total: number;
  pageNum: number;
  limitNum: number;
}

// Whitelisted sort columns → qualified SQL column (the grid sorts on
// joined aliases like `item_name`; qualification avoids ambiguity).
const SORT_COLUMN_MAP: Record<string, string> = {
  movement_no: 'sm.movement_no',
  movement_date: 'sm.movement_date',
  item_name: 'i.item_name',
  warehouse_name: 'w.warehouse_name',
  movement_type: 'sm.movement_type',
  quantity: 'sm.quantity',
  reference_docno: 'sm.reference_docno',
  created_at: 'sm.created_at',
};

interface RecordMovementDTO {
  item_id: number;
  warehouse_id: number;
  quantity: number;
  unit_cost?: number;
  reference_doctype?: string;
  reference_docno?: string;
  remarks?: string;
  movement_type: string;
  movement_date?: string;
  batch_id?: number;
}

class StockMovementModel {
  static recordMovement(data: RecordMovementDTO, userId: number, db: Database.Database): { id: number; movement_no: string } {
    const transaction = db.transaction(() => {
      const movementNo = this.generateMovementNo(db);

      const movementStmt = db.prepare(`
        INSERT INTO stock_movements (
          movement_no, item_id, warehouse_id, movement_type,
          quantity, unit_cost, reference_doctype, reference_docno,
          remarks, movement_date, created_by, batch_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `);

      const result = movementStmt.run(
        movementNo,
        data.item_id,
        data.warehouse_id,
        data.movement_type,
        data.quantity,
        data.unit_cost || null,
        data.reference_doctype || null,
        data.reference_docno || null,
        data.remarks || null,
        data.movement_date || new Date().toISOString().split('T')[0],
        userId,
        data.batch_id || null
      );

      const existingBalance = db.prepare(`
        SELECT * FROM stock_balances
        WHERE item_id = ? AND warehouse_id = ?
      `).get(data.item_id, data.warehouse_id) as Record<string, unknown> | undefined;

      if (existingBalance) {
        db.prepare(`
          UPDATE stock_balances
          SET quantity = quantity + ?,
              last_updated = CURRENT_TIMESTAMP
          WHERE item_id = ? AND warehouse_id = ?
        `).run(data.quantity, data.item_id, data.warehouse_id);
      } else {
        db.prepare(`
          INSERT INTO stock_balances (item_id, warehouse_id, quantity)
          VALUES (?, ?, ?)
        `).run(data.item_id, data.warehouse_id, data.quantity);
      }

      db.prepare(`
        UPDATE items
        SET current_stock = (
          SELECT COALESCE(SUM(quantity), 0)
          FROM stock_balances
          WHERE item_id = ?
        )
        WHERE id = ?
      `).run(data.item_id, data.item_id);

      // Post financial entry for ADJUSTMENT movements
      const movementId = result.lastInsertRowid as number;
      if (data.movement_type === 'ADJUSTMENT') {
        this.postFinancialEntryForAdjustment({
          id: movementId,
          item_id: data.item_id,
          quantity: data.quantity,
          movement_date: data.movement_date || new Date().toISOString().split('T')[0],
          created_by: userId
        }, db);
      }

      return {
        id: movementId,
        movement_no: movementNo
      };
    });

    return transaction();
  }

  static generateMovementNo(db: Database.Database): string {
    const year = new Date().getFullYear();
    const settingKey = `STK_last_no_${year}`;

    db.prepare(`
      INSERT INTO settings (key, value, updated_at)
      VALUES (?, '1', CURRENT_TIMESTAMP)
      ON CONFLICT(key) DO UPDATE SET
        value = CAST(CAST(settings.value AS INTEGER) + 1 AS TEXT),
        updated_at = CURRENT_TIMESTAMP
    `).run(settingKey);

    const setting = db.prepare('SELECT value FROM settings WHERE key = ?').get(settingKey) as { value: string };
    const nextNo = parseInt(setting.value);

    return `STK-${year}-${nextNo.toString().padStart(4, '0')}`;
  }

  static getAll(filters: MovementFilters = {}, db: Database.Database): PaginatedMovements {
    const pageNum = filters.page || 1;
    const limitNum = filters.limit || 10;

    const select = `
      SELECT
        sm.*,
        i.item_code,
        i.item_name,
        i.unit_of_measure,
        w.warehouse_code,
        w.warehouse_name,
        u.full_name as created_by_name,
        sb.batch_no
      FROM stock_movements sm
      JOIN items i ON sm.item_id = i.id
      JOIN warehouses w ON sm.warehouse_id = w.id
      LEFT JOIN users u ON sm.created_by = u.id
      LEFT JOIN stock_batches sb ON sm.batch_id = sb.id
      WHERE 1=1
    `;
    const conditions: string[] = [];
    const params: any[] = [];

    if (filters.item_id) {
      conditions.push('sm.item_id = ?');
      params.push(filters.item_id);
    }

    if (filters.warehouse_id) {
      conditions.push('sm.warehouse_id = ?');
      params.push(filters.warehouse_id);
    }

    if (filters.movement_type) {
      conditions.push('sm.movement_type = ?');
      params.push(filters.movement_type);
    }

    if (filters.date_from) {
      conditions.push('sm.movement_date >= ?');
      params.push(filters.date_from);
    }

    if (filters.date_to) {
      conditions.push('sm.movement_date <= ?');
      params.push(filters.date_to);
    }

    if (filters.search) {
      conditions.push(
        '(sm.movement_no LIKE ? OR i.item_name LIKE ? OR i.item_code LIKE ? OR COALESCE(sm.reference_docno, \'\') LIKE ? OR w.warehouse_name LIKE ?)'
      );
      const term = `%${filters.search}%`;
      params.push(term, term, term, term, term);
    }

    const where = conditions.length ? ` AND ${conditions.join(' AND ')}` : '';

    // Sort — whitelisted via sqlSanitizer, mapped to qualified columns
    // (default matches the pre-paging behavior: newest movement first).
    const { column, order } = sanitizeSortParams(
      filters.sortBy || 'movement_date',
      filters.sortOrder || 'DESC',
      STOCK_MOVEMENT_SORT_COLUMNS,
      'movement_date',
      'DESC'
    );
    const sortColumn = SORT_COLUMN_MAP[column] || 'sm.movement_date';

    const offset = (pageNum - 1) * limitNum;
    const query =
      `${select}${where} ORDER BY ${sortColumn} ${order}, sm.id DESC LIMIT ? OFFSET ?`;

    const countQuery =
      `SELECT COUNT(*) as total FROM stock_movements sm
       JOIN items i ON sm.item_id = i.id
       JOIN warehouses w ON sm.warehouse_id = w.id
       WHERE 1=1${where}`;
    const countRow = db.prepare(countQuery).get(...params) as { total: number };

    const rows = db.prepare(query).all(...params, limitNum, offset) as StockMovement[];

    return { rows, total: countRow.total, pageNum, limitNum };
  }

  static getById(id: number, db: Database.Database): StockMovement | undefined {
    return db.prepare(`
      SELECT
        sm.*,
        i.item_code,
        i.item_name,
        i.unit_of_measure,
        w.warehouse_code,
        w.warehouse_name
      FROM stock_movements sm
      JOIN items i ON sm.item_id = i.id
      JOIN warehouses w ON sm.warehouse_id = w.id
      WHERE sm.id = ?
    `).get(id) as StockMovement | undefined;
  }

  static getItemLedger(itemId: number, warehouseId: number | null = null, db: Database.Database): StockMovement[] {
    let query = `
      SELECT
        sm.*,
        w.warehouse_code,
        w.warehouse_name
      FROM stock_movements sm
      JOIN warehouses w ON sm.warehouse_id = w.id
      WHERE sm.item_id = ?
    `;
    const params: any[] = [itemId];

    if (warehouseId) {
      query += ' AND sm.warehouse_id = ?';
      params.push(warehouseId);
    }

    query += ' ORDER BY sm.movement_date DESC, sm.created_at DESC';

    return db.prepare(query).all(...params) as StockMovement[];
  }

  static getStockSummary(db: Database.Database) {
    return db.prepare(`
      SELECT
        i.id,
        i.item_code,
        i.item_name,
        i.category,
        i.unit_of_measure,
        i.current_stock,
        i.reorder_level,
        i.standard_cost,
        i.current_stock * i.standard_cost as stock_value,
        CASE
          WHEN i.current_stock <= i.reorder_level AND i.reorder_level > 0 THEN 1
          ELSE 0
        END as low_stock
      FROM items i
      WHERE i.is_active = 1
      ORDER BY i.item_name
    `).all();
  }

  static getBalance(itemId: number, warehouseId: number, db: Database.Database) {
    return db.prepare(`
      SELECT COALESCE(quantity, 0) as quantity
      FROM stock_balances
      WHERE item_id = ? AND warehouse_id = ?
    `).get(itemId, warehouseId);
  }

  static postFinancialEntryForAdjustment(params: {
    id: number;
    item_id: number;
    quantity: number;
    movement_date: string;
    created_by: number;
  }, db: Database.Database): void {
    const { id, item_id, quantity, movement_date, created_by } = params;

    const item = db.prepare(`
      SELECT standard_cost FROM items WHERE id = ?
    `).get(item_id) as { standard_cost: number } | undefined;

    if (!item) return;

    const standardCost = item.standard_cost || 0;
    const value = Math.abs(quantity) * standardCost;

    if (value === 0) return;

    const isRemoval = quantity < 0;

    const accounts = isRemoval
      ? { debit: 'inventory_shrinkage', credit: 'inventory_asset' }
      : { debit: 'inventory_asset', credit: 'inventory_correction' };

    const description = isRemoval
      ? `Stock removal: ${Math.abs(quantity)} units @ ${standardCost}`
      : `Stock addition: ${Math.abs(quantity)} units @ ${standardCost}`;

    const jeResult = db.prepare(`
      INSERT INTO journal_entries
        (reference_type, reference_id, entry_date, description,
         debit_account, credit_account, amount, created_by)
      VALUES ('stock_adjustment', ?, ?, ?, ?, ?, ?, ?)
    `).run(id, movement_date, description, accounts.debit, accounts.credit, value, created_by);

    const journalEntryId = jeResult.lastInsertRowid as number;

    db.prepare(`
      UPDATE stock_movements
      SET financial_value = ?, financial_posted = TRUE, journal_entry_id = ?
      WHERE id = ?
    `).run(value, journalEntryId, id);
  }

  static voidJournalEntry(journalEntryId: number, db: Database.Database): void {
    db.prepare(`
      UPDATE journal_entries SET voided = TRUE WHERE id = ?
    `).run(journalEntryId);
  }

  /**
   * Post a financial entry for a PRODUCTION output movement.
   *
   * Context: prior to this fix, ProductionModel.recordProduction inserted
   * the output stock_movement row with financial_value=NULL and
   * financial_posted=FALSE. StockMovementModel.postFinancialEntryForAdjustment
   * only handles movement_type='ADJUSTMENT', so production output was
   * never linked to a journal entry. The result: the inventory asset
   * account on the GL was never updated when goods were produced, and
   * the balance sheet inventory figure drifted from the actual
   * stock-on-hand value.
   *
   * This posts a single-line journal entry:
   *   Debit:  inventory_asset
   *   Credit: production_clearing
   *   Amount: totalBatchCost (material + overhead), using the
   *           cost-per-unit already computed by the production flow.
   *
   * The clearing account is a temporary holding account that reflects
   * the net cost of goods produced in a period; a year-end / period-end
   * close can clear it to COGS. A multi-line split (Dr finished goods,
   * Cr raw materials, Cr overhead) requires a journal_lines table
   * upgrade and is out of scope for this fix.
   */
  static postFinancialEntryForProduction(params: {
    id: number;            // stock_movements.id of the output row
    item_id: number;
    quantity: number;
    total_batch_cost: number;  // already includes overhead
    movement_date: string;
    created_by: number;
  }, db: Database.Database): void {
    const { id, total_batch_cost, movement_date, created_by } = params;

    // Defensive: skip zero-value movements so we don't create noise
    // journal entries for $0 productions (e.g., pure rework).
    if (!total_batch_cost || total_batch_cost <= 0) {
      return;
    }

    const value = total_batch_cost;

    const jeResult = db.prepare(`
      INSERT INTO journal_entries
        (reference_type, reference_id, entry_date, description,
         debit_account, credit_account, amount, created_by)
      VALUES ('production', ?, ?, ?, 'inventory_asset', 'production_clearing', ?, ?)
    `).run(
      id,
      movement_date,
      `Production output: ${params.quantity} units (total cost ${value.toFixed(2)})`,
      value,
      created_by
    );

    const journalEntryId = jeResult.lastInsertRowid as number;

    db.prepare(`
      UPDATE stock_movements
      SET financial_value = ?, financial_posted = TRUE, journal_entry_id = ?
      WHERE id = ?
    `).run(value, journalEntryId, id);
  }

  static getStockBalances(
    filters: StockBalanceFilters = {},
    db: Database.Database
  ): PaginatedStockBalances {
    const pageNum = filters.page || 1;
    const limitNum = filters.limit || 10;

    const select = `
      SELECT
        sb.*,
        i.item_code,
        i.item_name,
        i.unit_of_measure,
        w.warehouse_code,
        w.warehouse_name
      FROM stock_balances sb
      JOIN items i ON sb.item_id = i.id
      JOIN warehouses w ON sb.warehouse_id = w.id
      WHERE 1=1
    `;
    const conditions: string[] = [];
    const params: any[] = [];

    if (filters.search) {
      conditions.push(
        '(i.item_code LIKE ? OR i.item_name LIKE ? OR w.warehouse_name LIKE ?)'
      );
      const term = `%${filters.search}%`;
      params.push(term, term, term);
    }

    if (filters.warehouse_code) {
      conditions.push('w.warehouse_code = ?');
      params.push(filters.warehouse_code);
    }

    if (filters.warehouse_id !== undefined) {
      conditions.push('sb.warehouse_id = ?');
      params.push(filters.warehouse_id);
    }

    const where = conditions.length ? ` AND ${conditions.join(' AND ')}` : '';

    // Sort — whitelisted via sqlSanitizer, mapped to qualified columns
    // (default matches the pre-paging behavior: item code then warehouse).
    const { column, order } = sanitizeSortParams(
      filters.sortBy || 'item_code',
      filters.sortOrder || 'ASC',
      STOCK_BALANCE_SORT_COLUMNS,
      'item_code',
      'ASC'
    );
    const sortColumn = BALANCE_SORT_COLUMN_MAP[column] || 'i.item_code';

    const offset = (pageNum - 1) * limitNum;
    const query =
      `${select}${where} ORDER BY ${sortColumn} ${order}, sb.item_id, w.warehouse_code LIMIT ? OFFSET ?`;
    const countQuery =
      `SELECT COUNT(*) as total FROM stock_balances sb
       JOIN items i ON sb.item_id = i.id
       JOIN warehouses w ON sb.warehouse_id = w.id
       WHERE 1=1${where}`;

    const countRow = db.prepare(countQuery).get(...params) as { total: number };
    const rows = db.prepare(query).all(...params, limitNum, offset) as StockMovement[];

    return { rows, total: countRow.total, pageNum, limitNum };
  }

  static getOriginalWarehouseForItem(db: Database.Database, itemId: number, invoiceNo: string): number | undefined {
    const result = db.prepare(`
      SELECT warehouse_id FROM stock_movements
      WHERE item_id = ? AND reference_docno = ? AND movement_type = 'SALE'
      LIMIT 1
    `).get(itemId, invoiceNo) as { warehouse_id: number } | undefined;
    return result ? result.warehouse_id : undefined;
  }

  /**
   * Consume a quantity of an item from the oldest available stock batches (FIFO).
   * Deducts quantity_remaining from each batch until the required quantity is met.
   * Returns an array of { batchId, consumed, unitCost } for recording movements.
   *
   * CRITICAL-5 fix: previously, when the total batch-tracked stock was less
   * than the requested quantity, the function silently fell back to the
   * item's standard_cost for the remainder, masking real shortages and
   * under-costing COGS. This made the pre-check in ProductionModel
   * recordProduction a lie under concurrent load, and could even let stock
   * go negative (the existing balance update would clamp at zero on the
   * next read but the batch update would still execute).
   *
   * New behavior:
   *  1. Reads the authoritative warehouse stock from stock_balances. If
   *     the available qty is strictly less than the requested qty, throws.
   *  2. If batches cover the request exactly, returns the FIFO breakdown.
   *  3. If the item has positive stock in the warehouse but no batch rows
   *     (legacy stock added before batch costing was enabled), falls back
   *     to standard_cost for the entire quantity, with a single
   *     warning-level log entry.
   *  4. If batches partially cover the request (some batches existed with
   *     qty but their sum is < requested), the function throws, because
   *     this case implies a partial migration or a stale batch, neither
   *     of which should be silently papered over.
   */
  static consumeFromOldestBatches(
    itemId: number,
    warehouseId: number,
    quantity: number,
    db: Database.Database
  ): Array<{ batchId: number | null; consumed: number; unitCost: number }> {
    if (quantity <= 0) {
      throw new Error(`consumeFromOldestBatches: quantity must be positive, got ${quantity}`);
    }

    // Authoritative check: stock_balances is the source of truth.
    const balanceRow = db.prepare(`
      SELECT quantity FROM stock_balances
      WHERE item_id = ? AND warehouse_id = ?
    `).get(itemId, warehouseId) as { quantity: number } | undefined;
    const availableQty = balanceRow ? parseFloat(String(balanceRow.quantity)) : 0;

    if (availableQty < quantity) {
      const item = db.prepare('SELECT item_name FROM items WHERE id = ?').get(itemId) as { item_name: string } | undefined;
      throw new Error(
        `Insufficient stock for ${item?.item_name || `item ${itemId}`} in warehouse ${warehouseId}: ` +
        `available ${availableQty}, required ${quantity}`
      );
    }

    const batches = db.prepare(`
      SELECT id, quantity_remaining, unit_cost
      FROM stock_batches
      WHERE item_id = ? AND warehouse_id = ? AND quantity_remaining > 0
      ORDER BY received_date ASC, id ASC
    `).all(itemId, warehouseId) as Array<{
      id: number;
      quantity_remaining: number;
      unit_cost: number;
    }>;

    // Legacy case: positive warehouse stock but no batch rows. This is
    // stock that was added before batch costing was enabled. Use
    // standard_cost for the entire consumption; do not throw.
    if (batches.length === 0) {
      const item = db.prepare('SELECT standard_cost, item_name FROM items WHERE id = ?').get(itemId) as { standard_cost: number; item_name: string } | undefined;
      const fallbackCost = item?.standard_cost ?? 0;
      logger.warn(
        `[BatchCosting] No batch rows for ${item?.item_name || 'item'} in warehouse. ` +
        `Using standard_cost (${fallbackCost}) for the entire ${quantity} units (legacy stock).`
      );
      return [{ batchId: null, consumed: quantity, unitCost: fallbackCost }];
    }

    // Normal FIFO path.
    let remaining = quantity;
    const consumption: Array<{ batchId: number | null; consumed: number; unitCost: number }> = [];

    for (const batch of batches) {
      if (remaining <= 0) break;
      const consumeFromThis = Math.min(remaining, batch.quantity_remaining);

      db.prepare(`
        UPDATE stock_batches
        SET quantity_remaining = quantity_remaining - ?
        WHERE id = ?
      `).run(consumeFromThis, batch.id);

      consumption.push({ batchId: batch.id, consumed: consumeFromThis, unitCost: batch.unit_cost });
      remaining -= consumeFromThis;
    }

    if (remaining > 0.001) {
      // Defensive: stock_balances said we have enough, but the batches
      // we found don't cover the request. This means the batch table is
      // out of sync with the balance. Throw rather than silently using
      // a different cost basis (which would mis-cost COGS).
      const item = db.prepare('SELECT item_name FROM items WHERE id = ?').get(itemId) as { item_name: string } | undefined;
      throw new Error(
        `Batch coverage shortfall for ${item?.item_name || `item ${itemId}`} in warehouse ${warehouseId}: ` +
        `stock_balances shows ${availableQty} but batches only cover ${(quantity - remaining).toFixed(3)}. ` +
        `Run a batch reconciliation.`
      );
    }

    return consumption;
  }

  /**
   * Record a batch-aware outgoing stock movement that consumes from oldest batches.
   * Creates one stock_movement per batch consumed, with batch_id and unit_cost.
   * For incoming movements (quantity >= 0), delegates to recordMovement.
   */
  static recordBatchMovement(
    data: RecordMovementDTO,
    userId: number,
    db: Database.Database
  ): Array<{ id: number; movement_no: string; quantity: number; unit_cost: number; batch_id: number | null }> {
    const absQty = Math.abs(data.quantity);

    if (data.quantity >= 0 || absQty === 0) {
      // Incoming or zero: just record normally
      const result = this.recordMovement(data, userId, db);
      return [{ ...result, quantity: data.quantity, unit_cost: data.unit_cost || 0, batch_id: null }];
    }

    // Outgoing: consume from oldest batches using FIFO
    const consumption = this.consumeFromOldestBatches(
      data.item_id,
      data.warehouse_id,
      absQty,
      db
    );

    const results: Array<{ id: number; movement_no: string; quantity: number; unit_cost: number; batch_id: number | null }> = [];

    for (const entry of consumption) {
      const result = this.recordMovement(
        {
          item_id: data.item_id,
          warehouse_id: data.warehouse_id,
          quantity: -entry.consumed,
          unit_cost: entry.unitCost,
          movement_type: data.movement_type,
          reference_doctype: data.reference_doctype,
          reference_docno: data.reference_docno,
          remarks: data.remarks
            ? `Batch: ${entry.batchId ?? 'Legacy'} - ${entry.consumed} @ ${entry.unitCost} | ${data.remarks}`
            : `Batch: ${entry.batchId ?? 'Legacy'} - ${entry.consumed} @ ${entry.unitCost}`,
          movement_date: data.movement_date,
          batch_id: entry.batchId ?? undefined,
        },
        userId,
        db
      );
      results.push({ ...result, quantity: -entry.consumed, unit_cost: entry.unitCost, batch_id: entry.batchId });
    }

    return results;
  }
}

export default StockMovementModel;
