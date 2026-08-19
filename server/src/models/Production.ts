import Database from 'better-sqlite3';
import { generateDocNo, getNextSequenceNumber } from '../utils/sequence';
import { sanitizeSortParams, PRODUCTION_SORT_COLUMNS } from '../utils/sqlSanitizer';
import StockMovementModel from './StockMovement';

interface Production {
  id: number;
  production_no: string;
  output_item_id: number;
  output_quantity: number;
  warehouse_id: number;
  raw_materials_warehouse_id?: number;
  production_date: string;
  bom_id?: number;
  remarks?: string;
  overhead_cost?: number;
  batch_no?: string;
  unit_cost?: number;
  total_material_cost?: number;
  total_batch_cost?: number;
  batch_id?: number;
  created_by: number;
  created_at?: string;
  output_item_code?: string;
  output_item_name?: string;
  output_uom?: string;
  finished_goods_warehouse_code?: string;
  finished_goods_warehouse_name?: string;
  raw_materials_warehouse_code?: string;
  raw_materials_warehouse_name?: string;
  created_by_username?: string;
  inputs?: ProductionInput[];
}

interface ProductionInput {
  id: number;
  production_id: number;
  item_id: number;
  quantity: number;
  warehouse_id: number;
  item_code?: string;
  item_name?: string;
  unit_of_measure?: string;
  warehouse_code?: string;
  warehouse_name?: string;
}

interface ProductionFilters {
  start_date?: string;
  end_date?: string;
  output_item_id?: number;
  warehouse_id?: number;
  raw_materials_warehouse_id?: number;
  search?: string;
  sortBy?: string;
  sortOrder?: string;
  page?: number;
  limit?: number;
}

interface PaginatedProductions {
  rows: Production[];
  total: number;
  pageNum: number;
  limitNum: number;
}

// Whitelisted sort columns → qualified SQL column for the list query (the
// item/warehouse/user joins make bare names ambiguous).
const PRODUCTION_SORT_COLUMN_MAP: Record<string, string> = {
  production_no: 'p.production_no',
  production_date: 'p.production_date',
  output_item_name: 'i.item_name',
  warehouse_name: 'fgw.warehouse_name',
  output_quantity: 'p.output_quantity',
  unit_cost: 'p.unit_cost',
  total_batch_cost: 'p.total_batch_cost',
  batch_no: 'p.batch_no',
  created_at: 'p.created_at',
};

interface CreateProductionDTO {
  output_item_id: number;
  output_quantity: number;
  warehouse_id: number;
  raw_materials_warehouse_id?: number;
  production_date: string;
  input_items: { item_id: number; quantity: number }[];
  bom_id?: number;
  remarks?: string;
  overhead_cost?: number;
}

class ProductionModel {
  /**
   * Consume a quantity of an item from the oldest available stock batches (FIFO).
   * Delegates to the centralized implementation in StockMovementModel.
   */
  static consumeFromOldestBatches(
    itemId: number,
    warehouseId: number,
    quantity: number,
    db: Database.Database
  ): Array<{ batchId: number | null; consumed: number; unitCost: number }> {
    return StockMovementModel.consumeFromOldestBatches(itemId, warehouseId, quantity, db);
  }

  static generateBatchNo(db: Database.Database): string {
    const year = new Date().getFullYear();
    const settingKey = `BATCH_last_no_${year}`;
    const nextNo = getNextSequenceNumber(db, settingKey);
    return `BATCH-${year % 100}-PRD-${nextNo.toString().padStart(4, '0')}`;
  }

  static generateProductionNo(db: Database.Database): string {
    return generateDocNo(db, 'PROD');
  }

  static recordProduction(data: CreateProductionDTO, userId: number, db: Database.Database): Production {
    const {
      output_item_id,
      output_quantity,
      warehouse_id,
      raw_materials_warehouse_id,
      production_date,
      input_items,
      bom_id,
      remarks,
      overhead_cost
    } = data;

    const materialsWarehouseId = raw_materials_warehouse_id || warehouse_id;

    // Validate bom_id matches output_item_id
    if (bom_id) {
      const bom = db.prepare('SELECT finished_item_id FROM boms WHERE id = ?').get(bom_id) as { finished_item_id: number } | undefined;
      if (!bom) throw new Error(`BOM ${bom_id} not found`);
      if (bom.finished_item_id !== output_item_id) {
        throw new Error(`BOM ${bom_id} produces item ${bom.finished_item_id}, not item ${output_item_id}`);
      }
    }

    // CRITICAL-5 fix: use IMMEDIATE-mode transaction so the read of
    // stock_balances and the subsequent writes happen under a single
    // RESERVED writer lock. With the default DEFERRED mode, two
    // concurrent productions could both read the same stock_balances
    // row, both pass the "available >= requested" check, and then race
    // on the write. SQLite would SQLITE_BUSY the loser, but the brief
    // inconsistency window is exactly what allows negative stock under
    // load. IMMEDIATE upgrades to RESERVED on BEGIN, blocking any other
    // writer from starting a transaction until this one finishes.
    //
    // better-sqlite3 API: db.transaction(fn) returns a Transaction<F>
    // with .deferred / .immediate / .exclusive call modes.
    const transaction = db.transaction(() => {
      const productionNo = this.generateProductionNo(db);
      const batchNo = this.generateBatchNo(db);

      const productionStmt = db.prepare(`
        INSERT INTO productions (
          production_no, output_item_id, output_quantity, warehouse_id,
          raw_materials_warehouse_id, production_date, bom_id, remarks, overhead_cost, created_by
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `);

      const result = productionStmt.run(
        productionNo,
        output_item_id,
        output_quantity,
        warehouse_id,
        materialsWarehouseId,
        production_date,
        bom_id || null,
        remarks || null,
        overhead_cost ?? 0,
        userId
      );

      const productionId = result.lastInsertRowid as number;

      const inputStmt = db.prepare(`
        INSERT INTO production_inputs (
          production_id, item_id, quantity, warehouse_id
        ) VALUES (?, ?, ?, ?)
      `);

      let totalMaterialCost = 0;

      for (const input of input_items) {
        const stockBalance = db.prepare(`
          SELECT quantity FROM stock_balances
          WHERE item_id = ? AND warehouse_id = ?
        `).get(input.item_id, materialsWarehouseId) as { quantity: any } | undefined;

        const availableStock = stockBalance ? parseFloat(String(stockBalance.quantity)) : 0;

        if (availableStock < input.quantity) {
          const item = db.prepare('SELECT item_name FROM items WHERE id = ?').get(input.item_id) as { item_name: string };
          throw new Error(`Insufficient stock for ${item.item_name} in warehouse. Available: ${availableStock}, Required: ${input.quantity}`);
        }

        inputStmt.run(productionId, input.item_id, input.quantity, materialsWarehouseId);

        // FIFO consumption from oldest batches
        const consumption = this.consumeFromOldestBatches(input.item_id, materialsWarehouseId, input.quantity, db);

        // Create one stock_movement per consumed batch for full traceability
        for (const entry of consumption) {
          const inputMovementNo = StockMovementModel.generateMovementNo(db);
          db.prepare(`
            INSERT INTO stock_movements (
              movement_no, item_id, warehouse_id, movement_type,
              quantity, unit_cost, reference_doctype, reference_docno,
              remarks, movement_date, created_by, batch_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          `).run(
            inputMovementNo,
            input.item_id,
            materialsWarehouseId,
            'PRODUCTION',
            -entry.consumed,
            entry.unitCost,
            'Production',
            productionNo,
            `Consumed for production: ${productionNo} ${entry.batchId ? `(batch ${entry.batchId})` : '(legacy stock)'}`,
            production_date,
            userId,
            entry.batchId
          );

          totalMaterialCost += entry.consumed * entry.unitCost;
        }

        // Update stock_balances
        const existingBalance = db.prepare(`
          SELECT * FROM stock_balances
          WHERE item_id = ? AND warehouse_id = ?
        `).get(input.item_id, materialsWarehouseId) as Record<string, unknown> | undefined;

        if (existingBalance) {
          db.prepare(`
            UPDATE stock_balances
            SET quantity = quantity + ?,
                last_updated = CURRENT_TIMESTAMP
            WHERE item_id = ? AND warehouse_id = ?
          `).run(-input.quantity, input.item_id, materialsWarehouseId);
        } else {
          db.prepare(`
            INSERT INTO stock_balances (item_id, warehouse_id, quantity)
            VALUES (?, ?, ?)
          `).run(input.item_id, materialsWarehouseId, -input.quantity);
        }

        db.prepare(`
          UPDATE items
          SET current_stock = (
            SELECT COALESCE(SUM(quantity), 0)
            FROM stock_balances
            WHERE item_id = ?
          )
          WHERE id = ?
        `).run(input.item_id, input.item_id);
      }

      // Calculate total batch cost from actual FIFO consumption
      const totalOverhead = overhead_cost ?? 0;
      const totalBatchCost = totalMaterialCost + totalOverhead;
      const costPerUnit = output_quantity > 0 ? totalBatchCost / output_quantity : 0;

      // Create a stock_batch record for the finished good
      db.prepare(`
        INSERT INTO stock_batches (
          batch_no, item_id, warehouse_id, source_type,
          source_id, quantity_original, quantity_remaining,
          unit_cost, received_date
        ) VALUES (?, ?, ?, 'PRODUCTION', ?, ?, ?, ?, ?)
      `).run(
        batchNo,
        output_item_id,
        warehouse_id,
        productionId,
        output_quantity,
        output_quantity,
        costPerUnit,
        production_date
      );

      const batchRecord = db.prepare(`
        SELECT id FROM stock_batches
        WHERE source_type = 'PRODUCTION' AND source_id = ?
      `).get(productionId) as { id: number } | undefined;
      const outputBatchId = batchRecord?.id;

      // Record output stock movement linked to the new batch
      const outputMovementNo = StockMovementModel.generateMovementNo(db);
      const outputMovementResult = db.prepare(`
        INSERT INTO stock_movements (
          movement_no, item_id, warehouse_id, movement_type,
          quantity, unit_cost, reference_doctype, reference_docno,
          remarks, movement_date, created_by, batch_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).run(
        outputMovementNo,
        output_item_id,
        warehouse_id,
        'PRODUCTION',
        output_quantity,
        costPerUnit,
        'Production',
        productionNo,
        `Produced to: ${productionNo} (batch ${outputBatchId})`,
        production_date,
        userId,
        outputBatchId
      );

      // CRITICAL-4 fix: post a financial entry for the production output
      // so the inventory asset account on the GL is updated when goods
      // are produced. Previously this movement was inserted without a
      // journal entry, causing the GL inventory balance to drift from
      // the actual stock-on-hand value. See StockMovementModel.
      // postFinancialEntryForProduction for the full context.
      const outputMovementId = outputMovementResult.lastInsertRowid as number;
      StockMovementModel.postFinancialEntryForProduction({
        id: outputMovementId,
        item_id: output_item_id,
        quantity: output_quantity,
        total_batch_cost: totalBatchCost,
        movement_date: production_date,
        created_by: userId
      }, db);

      // Update production record with batch costing info
      db.prepare(`
        UPDATE productions
        SET batch_no = ?,
            unit_cost = ?,
            total_material_cost = ?,
            total_batch_cost = ?,
            batch_id = ?
        WHERE id = ?
      `).run(batchNo, costPerUnit, totalMaterialCost, totalBatchCost, outputBatchId, productionId);

      // Update stock_balances for output item
      const outputExistingBalance = db.prepare(`
        SELECT * FROM stock_balances
        WHERE item_id = ? AND warehouse_id = ?
      `).get(output_item_id, warehouse_id) as Record<string, unknown> | undefined;

      if (outputExistingBalance) {
        db.prepare(`
          UPDATE stock_balances
          SET quantity = quantity + ?,
              last_updated = CURRENT_TIMESTAMP
          WHERE item_id = ? AND warehouse_id = ?
        `).run(output_quantity, output_item_id, warehouse_id);
      } else {
        db.prepare(`
          INSERT INTO stock_balances (item_id, warehouse_id, quantity)
          VALUES (?, ?, ?)
        `).run(output_item_id, warehouse_id, output_quantity);
      }

      db.prepare(`
        UPDATE items
        SET current_stock = (
          SELECT COALESCE(SUM(quantity), 0)
          FROM stock_balances
          WHERE item_id = ?
        )
        WHERE id = ?
      `).run(output_item_id, output_item_id);

      db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(
        userId,
        'CREATE',
        'Production',
        productionId,
        `Recorded production ${productionNo}: ${output_quantity} units (Batch: ${batchNo}, Cost: ${costPerUnit.toFixed(4)}/unit)`
      );

      return this.getById(productionId, db) as Production;
    });

    // CRITICAL-5 fix: invoke with .immediate() so the transaction opens
    // with BEGIN IMMEDIATE (acquires RESERVED lock on entry, blocking
    // other writers from starting their own transactions until this one
    // commits or rolls back). This is the second half of the fix: the
    // inside-the-fxn check (now in consumeFromOldestBatches) is correct
    // only if it's serialized against concurrent production requests.
    return transaction.immediate();
  }

  static getAll(filters: ProductionFilters = {}, db: Database.Database): PaginatedProductions {
    const pageNum = filters.page || 1;
    const limitNum = filters.limit || 10;

    const select = `
      SELECT
        p.*,
        i.item_code as output_item_code,
        i.item_name as output_item_name,
        i.unit_of_measure as output_uom,
        fgw.warehouse_code as finished_goods_warehouse_code,
        fgw.warehouse_name as finished_goods_warehouse_name,
        rmw.warehouse_code as raw_materials_warehouse_code,
        rmw.warehouse_name as raw_materials_warehouse_name,
        u.username as created_by_username
      FROM productions p
      JOIN items i ON p.output_item_id = i.id
      JOIN warehouses fgw ON p.warehouse_id = fgw.id
      LEFT JOIN warehouses rmw ON p.raw_materials_warehouse_id = rmw.id
      JOIN users u ON p.created_by = u.id
      WHERE 1=1
    `;

    const conditions: string[] = [];
    const params: any[] = [];

    if (filters.start_date) {
      conditions.push('p.production_date >= ?');
      params.push(filters.start_date);
    }

    if (filters.end_date) {
      conditions.push('p.production_date <= ?');
      params.push(filters.end_date);
    }

    if (filters.output_item_id) {
      conditions.push('p.output_item_id = ?');
      params.push(filters.output_item_id);
    }

    if (filters.warehouse_id) {
      conditions.push('p.warehouse_id = ?');
      params.push(filters.warehouse_id);
    }

    if (filters.raw_materials_warehouse_id) {
      conditions.push('p.raw_materials_warehouse_id = ?');
      params.push(filters.raw_materials_warehouse_id);
    }

    if (filters.search) {
      conditions.push(
        '(p.production_no LIKE ? OR i.item_code LIKE ? OR i.item_name LIKE ? OR p.batch_no LIKE ? OR p.remarks LIKE ? OR fgw.warehouse_name LIKE ?)'
      );
      const term = `%${filters.search}%`;
      params.push(term, term, term, term, term, term);
    }

    const where = conditions.length ? ` AND ${conditions.join(' AND ')}` : '';

    // Sort — whitelisted via sqlSanitizer, mapped to qualified columns
    // (default matches the pre-paging behavior: newest production first).
    const { column, order } = sanitizeSortParams(
      filters.sortBy || 'production_date',
      filters.sortOrder || 'DESC',
      PRODUCTION_SORT_COLUMNS,
      'production_date',
      'DESC'
    );
    const sortColumn = PRODUCTION_SORT_COLUMN_MAP[column] || 'p.production_date';

    const offset = (pageNum - 1) * limitNum;
    const rows = db
      .prepare(`${select}${where} ORDER BY ${sortColumn} ${order}, p.id DESC LIMIT ? OFFSET ?`)
      .all(...params, limitNum, offset) as Production[];

    const countRow = db
      .prepare(`SELECT COUNT(*) as total FROM productions p
        JOIN items i ON p.output_item_id = i.id
        JOIN warehouses fgw ON p.warehouse_id = fgw.id
        LEFT JOIN warehouses rmw ON p.raw_materials_warehouse_id = rmw.id
        WHERE 1=1${where}`)
      .get(...params) as { total: number };

    return { rows, total: countRow.total, pageNum, limitNum };
  }

  static getById(id: number, db: Database.Database): Production | undefined {
    const production = db.prepare(`
      SELECT
        p.*,
        i.item_code as output_item_code,
        i.item_name as output_item_name,
        i.unit_of_measure as output_uom,
        fgw.warehouse_code as finished_goods_warehouse_code,
        fgw.warehouse_name as finished_goods_warehouse_name,
        rmw.warehouse_code as raw_materials_warehouse_code,
        rmw.warehouse_name as raw_materials_warehouse_name,
        u.username as created_by_username
      FROM productions p
      JOIN items i ON p.output_item_id = i.id
      JOIN warehouses fgw ON p.warehouse_id = fgw.id
      LEFT JOIN warehouses rmw ON p.raw_materials_warehouse_id = rmw.id
      JOIN users u ON p.created_by = u.id
      WHERE p.id = ?
    `).get(id) as Production | undefined;

    if (production) {
      production.inputs = db.prepare(`
        SELECT
          pi.*,
          i.item_code,
          i.item_name,
          i.unit_of_measure,
          w.warehouse_code as warehouse_code,
          w.warehouse_name as warehouse_name
        FROM production_inputs pi
        JOIN items i ON pi.item_id = i.id
        JOIN warehouses w ON pi.warehouse_id = w.id
        WHERE pi.production_id = ?
      `).all(id) as ProductionInput[];
    }

    return production;
  }

  static getSummaryByItem(item_id: number, db: Database.Database) {
    return db.prepare(`
      SELECT
        COUNT(*) as production_count,
        SUM(output_quantity) as total_quantity_produced,
        MIN(production_date) as first_production_date,
        MAX(production_date) as last_production_date
      FROM productions
      WHERE output_item_id = ?
    `).get(item_id);
  }

  static delete(id: number, userId: number, db: Database.Database): boolean {
    const production = this.getById(id, db);

    if (!production) {
      throw new Error('Production not found');
    }

    const transaction = db.transaction(() => {
      // 1. Restore raw material batch quantities from PRODUCTION movements
      const rawMovements = db.prepare(`
        SELECT item_id, warehouse_id, quantity, batch_id, unit_cost
        FROM stock_movements
        WHERE reference_docno = ? AND movement_type = 'PRODUCTION' AND quantity < 0
        ORDER BY id
      `).all(production.production_no) as Array<{
        item_id: number;
        warehouse_id: number;
        quantity: number;
        batch_id: number | null;
        unit_cost: number;
      }>;

      for (const movement of rawMovements) {
        const absQty = Math.abs(movement.quantity);

        // Restore quantity_remaining on the consumed batch
        if (movement.batch_id !== null) {
          db.prepare(`
            UPDATE stock_batches
            SET quantity_remaining = quantity_remaining + ?
            WHERE id = ?
          `).run(absQty, movement.batch_id);
        }

        // Create ADJUSTMENT movement to add stock back
        StockMovementModel.recordMovement(
          {
            item_id: movement.item_id,
            warehouse_id: movement.warehouse_id,
            movement_type: 'ADJUSTMENT',
            quantity: absQty,
            unit_cost: movement.unit_cost,
            reference_doctype: 'PRODUCTION_DELETE',
            reference_docno: production.production_no,
            remarks: `Stock reversed - Production ${production.production_no} deleted (raw material)`,
            movement_date: new Date().toISOString().split('T')[0],
          },
          userId,
          db
        );
      }

      // 2. Handle the output batch created by this production
      const outputBatch = db.prepare(`
        SELECT id, quantity_remaining, unit_cost
        FROM stock_batches
        WHERE source_type = 'PRODUCTION' AND source_id = ?
      `).get(id) as { id: number; quantity_remaining: number; unit_cost: number } | undefined;

      if (outputBatch && outputBatch.quantity_remaining > 0) {
        // Create ADJUSTMENT movement to remove output stock
        StockMovementModel.recordMovement(
          {
            item_id: production.output_item_id,
            warehouse_id: production.warehouse_id,
            movement_type: 'ADJUSTMENT',
            quantity: -outputBatch.quantity_remaining,
            unit_cost: outputBatch.unit_cost,
            reference_doctype: 'PRODUCTION_DELETE',
            reference_docno: production.production_no,
            remarks: `Stock reversed - Production ${production.production_no} deleted (output)`,
            movement_date: new Date().toISOString().split('T')[0],
          },
          userId,
          db
        );

        // Zero out the output batch (keep for FK integrity with stock_movements)
        db.prepare('UPDATE stock_batches SET quantity_remaining = 0 WHERE id = ?').run(outputBatch.id);
      }

      // 3. Delete production inputs and production record
      db.prepare('DELETE FROM production_inputs WHERE production_id = ?').run(id);
      db.prepare('DELETE FROM productions WHERE id = ?').run(id);

      db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(
        userId,
        'DELETE',
        'Production',
        id,
        `Deleted production ${production.production_no}`
      );
    });

    transaction();

    return true;
  }
}

export default ProductionModel;
