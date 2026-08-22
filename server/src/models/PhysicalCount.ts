import Database from 'better-sqlite3';
import { sanitizeSortParams, PHYSICAL_COUNT_SORT_COLUMNS } from '../utils/sqlSanitizer';
import StockMovementModel from './StockMovement';

/** Next sequence number for ADJUSTMENT-sourced batch numbers. */
function getNextBatchSequence(db: Database.Database): number {
  db.prepare(`
    INSERT INTO settings (key, value, updated_at)
    VALUES ('BATCH_ADJ_last_no', '1', CURRENT_TIMESTAMP)
    ON CONFLICT(key) DO UPDATE SET
      value = CAST(CAST(settings.value AS INTEGER) + 1 AS TEXT),
      updated_at = CURRENT_TIMESTAMP
  `).run();
  const row = db.prepare(`SELECT value FROM settings WHERE key = 'BATCH_ADJ_last_no'`).get() as { value: string };
  return parseInt(row.value, 10);
}

interface PhysicalCount {
  id: number;
  count_no: string;
  count_date: string;
  warehouse_id: number;
  status: string;
  notes?: string;
  created_by: number;
  completed_by?: number;
  completed_at?: string;
  created_at?: string;
  updated_at?: string;
  warehouse_code?: string;
  warehouse_name?: string;
  created_by_name?: string;
  completed_by_name?: string;
  total_items?: number;
  counted_items?: number;
  variance_items?: number;
}

interface PhysicalCountItem {
  id: number;
  count_id: number;
  item_id: number;
  system_quantity: number;
  counted_quantity: number | null;
  variance: number | null;
  unit_cost: number | null;
  variance_value: number | null;
  adjustment_posted: boolean;
  adjustment_movement_id: number | null;
  counted_at?: string;
  counted_by?: number;
  notes?: string;
  created_at?: string;
  item_code?: string;
  item_name?: string;
  unit_of_measure?: string;
  category?: string;
  counted_by_name?: string;
}

interface CreateCountDTO {
  warehouse_id: number;
  count_date?: string;
  notes?: string;
}

interface CountFilters {
  search?: string;
  sortBy?: string;
  sortOrder?: string;
  page?: number;
  limit?: number;
}

interface PaginatedCounts {
  rows: PhysicalCount[];
  total: number;
  pageNum: number;
  limitNum: number;
}

// Whitelisted sort columns → qualified SQL column for the list query
// (the users join makes bare `created_at` ambiguous).
const COUNT_SORT_COLUMN_MAP: Record<string, string> = {
  count_no: 'pc.count_no',
  count_date: 'pc.count_date',
  warehouse_name: 'w.warehouse_name',
  status: 'pc.status',
  created_at: 'pc.created_at',
};

class PhysicalCountModel {
  static generateCountNo(db: Database.Database): string {
    const year = new Date().getFullYear();
    const settingKey = `PC_last_no_${year}`;

    db.prepare(`
      INSERT INTO settings (key, value, updated_at)
      VALUES (?, '1', CURRENT_TIMESTAMP)
      ON CONFLICT(key) DO UPDATE SET
        value = CAST(CAST(settings.value AS INTEGER) + 1 AS TEXT),
        updated_at = CURRENT_TIMESTAMP
    `).run(settingKey);

    const setting = db.prepare('SELECT value FROM settings WHERE key = ?').get(settingKey) as { value: string };
    const nextNo = parseInt(setting.value);

    return `PC-${year}-${nextNo.toString().padStart(4, '0')}`;
  }

  static create(data: CreateCountDTO, userId: number, db: Database.Database): number {
    const transaction = db.transaction(() => {
      const countNo = this.generateCountNo(db);

      const result = db.prepare(`
        INSERT INTO physical_counts (count_no, count_date, warehouse_id, status, notes, created_by)
        VALUES (?, ?, ?, 'Draft', ?, ?)
      `).run(
        countNo,
        data.count_date || new Date().toISOString().split('T')[0],
        data.warehouse_id,
        data.notes || null,
        userId
      );

      const countId = result.lastInsertRowid as number;

      // Snapshot current stock for all items in the warehouse
      const stockItems = db.prepare(`
        SELECT sb.item_id, sb.quantity, i.standard_cost
        FROM stock_balances sb
        JOIN items i ON sb.item_id = i.id
        WHERE sb.warehouse_id = ? AND sb.quantity > 0 AND i.is_active = 1
        ORDER BY i.item_code
      `).all(data.warehouse_id) as { item_id: number; quantity: number; standard_cost: number }[];

      const insertItem = db.prepare(`
        INSERT INTO physical_count_items (count_id, item_id, system_quantity, unit_cost)
        VALUES (?, ?, ?, ?)
      `);

      for (const item of stockItems) {
        insertItem.run(countId, item.item_id, item.quantity, item.standard_cost || 0);
      }

      return countId;
    });

    return transaction() as number;
  }

  static getById(id: number, db: Database.Database): PhysicalCount | undefined {
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
    `).get(id) as PhysicalCount | undefined;
  }

  static getAll(
    filters: CountFilters = {},
    db: Database.Database
  ): PaginatedCounts {
    const pageNum = filters.page || 1;
    const limitNum = filters.limit || 10;

    const select = `
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
      WHERE 1=1
    `;
    const conditions: string[] = [];
    const params: any[] = [];

    if (filters.search) {
      conditions.push(
        '(pc.count_no LIKE ? OR w.warehouse_name LIKE ? OR pc.status LIKE ?)'
      );
      const term = `%${filters.search}%`;
      params.push(term, term, term);
    }

    const where = conditions.length ? ` AND ${conditions.join(' AND ')}` : '';

    // Sort — whitelisted via sqlSanitizer, mapped to qualified columns
    // (default matches the pre-paging behavior: newest count first).
    const { column, order } = sanitizeSortParams(
      filters.sortBy || 'created_at',
      filters.sortOrder || 'DESC',
      PHYSICAL_COUNT_SORT_COLUMNS,
      'created_at',
      'DESC'
    );
    const sortColumn = COUNT_SORT_COLUMN_MAP[column] || 'pc.created_at';

    const offset = (pageNum - 1) * limitNum;
    const query =
      `${select}${where} ORDER BY ${sortColumn} ${order}, pc.id DESC LIMIT ? OFFSET ?`;
    const countQuery =
      `SELECT COUNT(*) as total FROM physical_counts pc
       JOIN warehouses w ON pc.warehouse_id = w.id
       LEFT JOIN users u ON pc.created_by = u.id
       WHERE 1=1${where}`;

    const countRow = db.prepare(countQuery).get(...params) as { total: number };
    const rows = db.prepare(query).all(...params, limitNum, offset) as PhysicalCount[];

    return { rows, total: countRow.total, pageNum, limitNum };
  }

  static getItems(countId: number, db: Database.Database): PhysicalCountItem[] {
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
    `).all(countId) as PhysicalCountItem[];
  }

  static recordCount(
    countId: number,
    itemId: number,
    countedQuantity: number,
    userId: number,
    notes: string | null,
    db: Database.Database
  ): void {
    const count = this.getById(countId, db);
    if (!count) throw new Error('Physical count not found');
    if (count.status === 'Completed' || count.status === 'Cancelled') {
      throw new Error(`Cannot record count for ${count.status} session`);
    }

    // INV-24: explicit null-safe read — a missing snapshot row is an error
    // (abort), never silently treated as zero system quantity.
    const snapshot = db.prepare(
      'SELECT system_quantity FROM physical_count_items WHERE count_id = ? AND item_id = ?'
    ).get(countId, itemId) as { system_quantity: number } | undefined;
    if (!snapshot) {
      throw new Error(
        `No snapshot row in physical_count_items for item ${itemId} in count ${countId} — ` +
        `the count session must be (re)started so a snapshot exists before recording counts`
      );
    }
    const variance = countedQuantity - snapshot.system_quantity;

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

  static completeCount(countId: number, userId: number, db: Database.Database): void {
    const count = this.getById(countId, db);
    if (!count) throw new Error('Physical count not found');
    if (count.status === 'Completed' || count.status === 'Cancelled') {
      throw new Error(`Cannot complete ${count.status} session`);
    }

    const transaction = db.transaction(() => {
      // Post adjustments for all items with variances
      const items = this.getItems(countId, db);
      const adjustmentItems = items.filter(i => i.counted_quantity !== null && i.variance !== 0);

      for (const item of adjustmentItems) {
        // INV-01: count completion reconciles ALL THREE tables — movements,
        // balances AND cost layers — inside this one transaction.
        let consumedCost = item.unit_cost;
        let consumption: Array<{ batchId: number | null; consumed: number; unitCost: number }> = [];
        if (item.variance < 0) {
          // Shortage: consume FIFO-oldest layers at their actual costs.
          consumption = StockMovementModel.consumeFromOldestBatches(
            item.item_id,
            count.warehouse_id,
            Math.abs(item.variance),
            db
          );
          const totalConsumed = consumption.reduce((s, c) => s + c.consumed, 0);
          consumedCost = totalConsumed > 0
            ? consumption.reduce((s, c) => s + c.consumed * c.unitCost, 0) / totalConsumed
            : item.unit_cost;
        }

        // ADJUSTMENT movement via the shared sequential generator
        // (INV-23 — no epoch-suffixed ad-hoc numbers).
        const movementNo = StockMovementModel.generateMovementNo(db);
        const primaryBatchId = consumption.length > 0 ? consumption[0].batchId : null;
        const movementResult = db.prepare(`
          INSERT INTO stock_movements (
            movement_no, item_id, warehouse_id, movement_type,
            quantity, unit_cost, reference_doctype, reference_docno,
            remarks, movement_date, created_by, batch_id
          ) VALUES (?, ?, ?, 'ADJUSTMENT', ?, ?, 'PhysicalCount', ?, ?, ?, ?, ?)
        `).run(
          movementNo,
          item.item_id,
          count.warehouse_id,
          item.variance,
          consumedCost,
          count.count_no,
          `Physical count adjustment: ${item.variance > 0 ? '+' : ''}${item.variance} (system: ${item.system_quantity}, counted: ${item.counted_quantity})`,
          count.count_date,
          userId,
          primaryBatchId
        );

        const movementId = movementResult.lastInsertRowid as number;

        // Surplus: insert an ADJUSTMENT-sourced cost layer at item.unit_cost.
        if (item.variance > 0) {
          const nextBatchNo = getNextBatchSequence(db);
          db.prepare(`
            INSERT INTO stock_batches (
              batch_no, item_id, warehouse_id, source_type,
              source_id, quantity_original, quantity_remaining,
              unit_cost, received_date
            ) VALUES (?, ?, ?, 'ADJUSTMENT', ?, ?, ?, ?, ?)
          `).run(
            `BATCH-${new Date().getFullYear() % 100}-ADJ-${nextBatchNo.toString().padStart(4, '0')}`,
            item.item_id,
            count.warehouse_id,
            countId,
            item.variance,
            item.variance,
            item.unit_cost,
            count.count_date
          );
        }

        // Update stock_balances
        const existingBalance = db.prepare(
          'SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?'
        ).get(item.item_id, count.warehouse_id) as { quantity: number } | undefined;

        if (existingBalance) {
          db.prepare(`
            UPDATE stock_balances
            SET quantity = quantity + ?,
                last_updated = CURRENT_TIMESTAMP
            WHERE item_id = ? AND warehouse_id = ?
          `).run(item.variance, item.item_id, count.warehouse_id);
        } else {
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

        // Post financial entry for adjustment — valued at the ACTUAL
        // consumed layer costs on shortages (not the snapshot unit_cost).
        if (consumedCost && item.variance !== 0) {
          const value = Math.abs(item.variance) * consumedCost;
          const isRemoval = item.variance < 0;
          const accounts = isRemoval
            ? { debit: 'inventory_shrinkage', credit: 'inventory_asset' }
            : { debit: 'inventory_asset', credit: 'inventory_correction' };

          const jeResult = db.prepare(`
            INSERT INTO journal_entries
              (reference_type, reference_id, entry_date, description,
               debit_account, credit_account, amount, created_by)
            VALUES ('stock_adjustment', ?, ?, ?, ?, ?, ?, ?)
          `).run(
            movementId,
            count.count_date,
            `Physical count: ${item.item_code} ${isRemoval ? 'shrinkage' : 'correction'} ${Math.abs(item.variance)} units @ ${consumedCost}`,
            accounts.debit,
            accounts.credit,
            value,
            userId
          );

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

  static cancelCount(countId: number, userId: number, db: Database.Database): void {
    const count = this.getById(countId, db);
    if (!count) throw new Error('Physical count not found');
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

  static deleteCount(countId: number, db: Database.Database): void {
    const count = this.getById(countId, db);
    if (!count) throw new Error('Physical count not found');
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

export default PhysicalCountModel;
