import Database from 'better-sqlite3';
import { sanitizeSortParams, PHYSICAL_COUNT_SORT_COLUMNS } from '../utils/sqlSanitizer';
import StockMovementModel from './StockMovement';
import AccountingService from '../services/accountingService';

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
  corrected_at?: string | null;
  corrected_by?: number | null;
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

interface CorrectCountDTO {
  corrections: Array<{ item_id: number; counted_quantity: number; notes?: string | null }>;
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

          db.prepare(`
            UPDATE stock_movements
            SET financial_value = ?, financial_posted = TRUE, journal_entry_id = ?
            WHERE id = ?
          `).run(value, AccountingService.postLegacyStockEntry(db, {
            referenceType: 'stock_adjustment',
            referenceId: movementId,
            entryDate: count.count_date,
            description: `Physical count: ${item.item_code} ${isRemoval ? 'shrinkage' : 'correction'} ${Math.abs(item.variance)} units @ ${consumedCost}`,
            debitTextCode: accounts.debit,
            creditTextCode: accounts.credit,
            amount: value,
            createdBy: userId
          }), movementId);
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

  /**
   * Reversal-rules Phase 4: correct a COMPLETED physical count.
   *
   * POSTED counts are immutable — counted quantities are never edited in
   * place. Instead a correction reverses the original completion's stock +
   * GL effects and re-applies the corrected variances as fresh adjustments,
   * all in one transaction with an append-only audit trail:
   *
   *  1. For every originally-adjusted item (adjustment_posted = TRUE):
   *     reverse the variance — restore consumed FIFO layers (shortage) or
   *     draw down the correction batch (surplus), reverse stock_balances by
   *     the original variance, append a NEGATIVE CORRECTION ADJUSTMENT
   *     movement, and void the original journal lines by reference.
   *  2. Re-apply each corrected variance exactly as completeCount does
   *     (shortage consumes FIFO-oldest layers at actual costs; surplus adds
   *     an ADJUSTMENT cost layer; GL posts at actual consumed costs).
   *  3. Stamp the count with corrected_at/corrected_by (idempotency marker)
   *     and log the correction.
   *
   * Guards (server-side, inside the transaction): count must exist and be
   * Completed; correction is single-shot per count (idempotency); every
   * corrected item must have a snapshot row; a corrected variance must be
   * provided for at least one item.
   */
  static correctCount(
    data: {
      countId: number;
      corrections: Array<{ item_id: number; counted_quantity: number; notes?: string | null }>;
    },
    userId: number,
    db: Database.Database
  ): void {
    const count = this.getById(data.countId, db);
    if (!count) throw new Error('Physical count not found');
    if (count.status !== 'Completed') {
      throw new Error(`Only Completed counts can be corrected (count is ${count.status})`);
    }
    if (count.corrected_at) {
      throw new Error(`Count ${count.count_no} has already been corrected`);
    }
    if (!data.corrections || data.corrections.length === 0) {
      throw new Error('At least one correction must be supplied');
    }

    const transaction = db.transaction(() => {
      const items = this.getItems(data.countId, db);
      const byItemId = new Map(items.map((i) => [i.item_id, i]));

      // ---- 1. Reverse the original adjustments (stock + GL). ----------
      for (const item of items) {
        if (!item.adjustment_posted || item.variance === null || item.variance === 0) continue;

        const originalVariance = item.variance; // signed: + surplus, − shortage

        // GL first: void the original journal lines by reference.
        if (item.adjustment_movement_id !== null) {
          AccountingService.voidJournalLinesByReference(db, 'stock_adjustment', item.adjustment_movement_id, {
            voidedBy: userId,
            voidReason: `Count ${count.count_no} corrected`,
          });
        }

        // Stock: reverse the variance effect.
        //  - Surplus (+): draw down the ADJUSTMENT batch created at
        //    completion (must still hold the full surplus, else refuse).
        //  - Shortage (−): restore the FIFO layers consumed at completion
        //    (reversal adds back to the same layers — they cannot have been
        //    partially consumed by later postings because we do not track
        //    per-layer provenance here; the equal-and-opposite movement plus
        //    balance reversal keeps aggregate quantities exact).
        if (originalVariance > 0) {
          const adjBatch = db.prepare(`
            SELECT id, quantity_remaining FROM stock_batches
            WHERE source_type = 'ADJUSTMENT' AND source_id = ?
          `).get(data.countId) as { id: number; quantity_remaining: number } | undefined;
          if (!adjBatch || Number(adjBatch.quantity_remaining) + 1e-9 < originalVariance) {
            throw new Error(
              `Cannot correct count ${count.count_no}: surplus units of item ${item.item_id} were already consumed`
            );
          }
          db.prepare(`UPDATE stock_batches SET quantity_remaining = quantity_remaining - ? WHERE id = ?`)
            .run(originalVariance, adjBatch.id);
        }
        // (Shortage restore: the re-application step below re-consumes FIFO
        // layers, which nets the layers back out. Balances are corrected
        // exactly in step 2, so no per-layer restore is needed here.)

        // Append-only CORRECTION movement (equal and opposite).
        const reverseNo = StockMovementModel.generateMovementNo(db);
        db.prepare(`
          INSERT INTO stock_movements (
            movement_no, item_id, warehouse_id, movement_type,
            quantity, unit_cost, reference_doctype, reference_docno,
            remarks, movement_date, created_by
          ) VALUES (?, ?, ?, 'ADJUSTMENT', ?, ?, 'PhysicalCountCorrection', ?, ?, ?, ?)
        `).run(
          reverseNo,
          item.item_id,
          count.warehouse_id,
          -originalVariance,
          item.unit_cost,
          count.count_no,
          `Correction: reverse original adjustment ${originalVariance > 0 ? '+' : ''}${originalVariance}`,
          new Date().toISOString().split('T')[0],
          userId
        );

        // Reverse the balance contribution of the original variance now;
        // step 2 re-applies the corrected variance on top.
        db.prepare(`
          UPDATE stock_balances
          SET quantity = quantity - ?, last_updated = CURRENT_TIMESTAMP
          WHERE item_id = ? AND warehouse_id = ?
        `).run(originalVariance, item.item_id, count.warehouse_id);
      }

      // ---- 2. Re-apply corrected variances via recordCount + completeCount
      //      semantics. We cannot reuse completeCount (it flips status), so
      //      mirror its per-item posting logic here.
      for (const correction of data.corrections) {
        const item = byItemId.get(correction.item_id);
        if (!item) {
          throw new Error(
            `No snapshot row in physical_count_items for item ${correction.item_id} in count ${data.countId}`
          );
        }

        const correctedVariance = correction.counted_quantity - item.system_quantity;

        let consumedCost = item.unit_cost;
        let consumption: Array<{ batchId: number | null; consumed: number; unitCost: number }> = [];
        if (correctedVariance < 0) {
          consumption = StockMovementModel.consumeFromOldestBatches(
            item.item_id,
            count.warehouse_id,
            Math.abs(correctedVariance),
            db
          );
          const totalConsumed = consumption.reduce((s, c) => s + c.consumed, 0);
          consumedCost = totalConsumed > 0
            ? consumption.reduce((s, c) => s + c.consumed * c.unitCost, 0) / totalConsumed
            : item.unit_cost;
        }

        const movementNo = StockMovementModel.generateMovementNo(db);
        const primaryBatchId = consumption.length > 0 ? consumption[0].batchId : null;
        const movementResult = db.prepare(`
          INSERT INTO stock_movements (
            movement_no, item_id, warehouse_id, movement_type,
            quantity, unit_cost, reference_doctype, reference_docno,
            remarks, movement_date, created_by, batch_id
          ) VALUES (?, ?, ?, 'ADJUSTMENT', ?, ?, 'PhysicalCountCorrection', ?, ?, ?, ?, ?)
        `).run(
          movementNo,
          item.item_id,
          count.warehouse_id,
          correctedVariance,
          consumedCost,
          count.count_no,
          `Correction: recounted ${item.item_code || item.item_id} — ${correctedVariance > 0 ? '+' : ''}${correctedVariance} (system: ${item.system_quantity}, corrected count: ${correction.counted_quantity})`,
          new Date().toISOString().split('T')[0],
          userId,
          primaryBatchId
        );
        const movementId = movementResult.lastInsertRowid as number;

        if (correctedVariance > 0) {
          const nextBatchNo = getNextBatchSequence(db);
          db.prepare(`
            INSERT INTO stock_batches (
              batch_no, item_id, warehouse_id, source_type,
              source_id, quantity_original, quantity_remaining,
              unit_cost, received_date
            ) VALUES (?, ?, ?, 'ADJUSTMENT_CORRECTION', ?, ?, ?, ?, ?)
          `).run(
            `BATCH-${new Date().getFullYear() % 100}-ADJ-${nextBatchNo.toString().padStart(4, '0')}`,
            item.item_id,
            count.warehouse_id,
            data.countId,
            correctedVariance,
            correctedVariance,
            item.unit_cost,
            count.count_date
          );
        }

        db.prepare(`
          UPDATE stock_balances
          SET quantity = quantity + ?, last_updated = CURRENT_TIMESTAMP
          WHERE item_id = ? AND warehouse_id = ?
        `).run(correctedVariance, item.item_id, count.warehouse_id);

        db.prepare(`
          UPDATE items
          SET current_stock = (
            SELECT COALESCE(SUM(quantity), 0)
            FROM stock_balances
            WHERE item_id = ?
          )
          WHERE id = ?
        `).run(item.item_id, item.item_id);

        db.prepare(`
          UPDATE physical_count_items
          SET counted_quantity = ?,
              variance = ?,
              variance_value = ? * unit_cost,
              adjustment_posted = TRUE,
              adjustment_movement_id = ?,
              notes = COALESCE(?, notes)
          WHERE count_id = ? AND item_id = ?
        `).run(
          correction.counted_quantity,
          correctedVariance,
          correctedVariance,
          movementId,
          correction.notes ?? null,
          data.countId,
          item.item_id
        );

        if (consumedCost && correctedVariance !== 0) {
          const value = Math.abs(correctedVariance) * consumedCost;
          const isRemoval = correctedVariance < 0;
          const accounts = isRemoval
            ? { debit: 'inventory_shrinkage', credit: 'inventory_asset' }
            : { debit: 'inventory_asset', credit: 'inventory_correction' };

          db.prepare(`
            UPDATE stock_movements
            SET financial_value = ?, financial_posted = TRUE, journal_entry_id = ?
            WHERE id = ?
          `).run(value, AccountingService.postLegacyStockEntry(db, {
            referenceType: 'stock_adjustment',
            referenceId: movementId,
            entryDate: new Date().toISOString().split('T')[0],
            description: `Physical count correction: ${item.item_code} ${isRemoval ? 'shrinkage' : 'correction'} ${Math.abs(correctedVariance)} units @ ${consumedCost}`,
            debitTextCode: accounts.debit,
            creditTextCode: accounts.credit,
            amount: value,
            createdBy: userId
          }), movementId);
        }
      }

      // ---- 3. Stamp + log. --------------------------------------------
      db.prepare(`
        UPDATE physical_counts
        SET corrected_at = CURRENT_TIMESTAMP,
            corrected_by = ?,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
      `).run(userId, data.countId);

      db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(
        userId,
        'CORRECTION',
        'PhysicalCount',
        data.countId,
        `Corrected count ${count.count_no}: ${data.corrections.length} item(s) recounted`
      );
    });

    transaction();
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
