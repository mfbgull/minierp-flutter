import Database from 'better-sqlite3';
import { parseCurrency, roundCurrency } from '../utils/currency';
import { roundQty } from '../utils/quantity';
import { generateDocNo, getNextSequenceNumber } from '../utils/sequence';
import { sanitizeSortParams, PRODUCTION_SORT_COLUMNS } from '../utils/sqlSanitizer';
import StockMovementModel from './StockMovement';
import AccountingService from '../services/accountingService';
import { SqlParam } from '../utils/sqlTypes';

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
  outputs?: ProductionOutput[];
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

interface ProductionOutput {
  id: number;
  production_id: number;
  item_id: number;
  quantity: number;
  unit_cost: number;
  allocated_cost: number;
  item_code?: string;
  item_name?: string;
  unit_of_measure?: string;
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

/**
 * D6: a production may yield several items (joint products - mustard oil +
 * mustard cake). Each output line carries its own quantity; the joint cost
 * (materials + overhead) is split across them by relative sales value.
 * When `outputs` is absent the production is single-output and
 * `output_item_id` / `output_quantity` behave exactly as before.
 */
interface ProductionOutputLine {
  item_id: number;
  quantity: number;
}

interface CreateProductionDTO {
  output_item_id?: number;
  output_quantity?: number;
  outputs?: ProductionOutputLine[];
  warehouse_id: number;
  raw_materials_warehouse_id?: number;
  production_date: string;
  input_items: { item_id: number; quantity: number }[];
  bom_id?: number;
  remarks?: string;
  overhead_cost?: number;
  expiry_date?: string;
}

/**
 * Normalizes the two accepted request shapes into one output list:
 * the D6 `outputs: [...]` array, or the legacy single
 * `output_item_id` + `output_quantity` pair.
 *
 * Validation that must reach the client as a 400 happens in the controller;
 * these guards protect any other caller of the model.
 */
function normalizeOutputLines(data: CreateProductionDTO): ProductionOutputLine[] {
  const lines: ProductionOutputLine[] = (data.outputs && data.outputs.length > 0)
    ? data.outputs.map((o) => ({ item_id: Number(o.item_id), quantity: Number(o.quantity) }))
    : [{ item_id: Number(data.output_item_id), quantity: Number(data.output_quantity) }];

  if (lines.length === 0) {
    throw new Error('At least one output item is required');
  }
  const seen = new Set<number>();
  for (const line of lines) {
    if (!Number.isInteger(line.item_id) || line.item_id <= 0) {
      throw new Error('Each output needs a valid item_id');
    }
    if (!Number.isFinite(line.quantity) || line.quantity <= 0) {
      throw new Error('Output quantity must be positive');
    }
    if (seen.has(line.item_id)) {
      throw new Error(`Output item ${line.item_id} is listed more than once`);
    }
    seen.add(line.item_id);
  }
  return lines;
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
    const now = new Date();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const year = String(now.getFullYear()).slice(-2);
    const settingKey = `BATCH_last_no_${month}${year}`;
    const nextNo = getNextSequenceNumber(db, settingKey);
    return `BATCH-${month}${year}-PRD-${String(nextNo).padStart(5, '0')}`;
  }

  static generateProductionNo(db: Database.Database): string {
    return generateDocNo(db, 'PROD');
  }

  static recordProduction(data: CreateProductionDTO, userId: number, db: Database.Database): Production {
    const {
      warehouse_id,
      raw_materials_warehouse_id,
      production_date,
      input_items,
      bom_id,
      remarks,
      overhead_cost,
      expiry_date
    } = data;

    // D6: one production -> N output lines. The header keeps the FIRST line
    // as the primary output so list/report/search queries stay valid.
    const outputLines = normalizeOutputLines(data);
    const primaryOutput = outputLines[0];
    const output_item_id = primaryOutput.item_id;
    const output_quantity = primaryOutput.quantity;

    const materialsWarehouseId = raw_materials_warehouse_id || warehouse_id;

    // PROD-004 / PROD-007 / PROD-006: reject inputs that would create a
    // negative-cost batch, a circular recipe, or a posting in a closed period.
    const overheadValue = overhead_cost ?? 0;
    if (typeof overheadValue !== 'number' || !Number.isFinite(overheadValue) || overheadValue < 0) {
      throw new Error('Overhead cost must be a non-negative number');
    }
    if (input_items.some((line) => outputLines.some((o) => Number(line.item_id) === o.item_id))) {
      throw new Error('An item cannot be produced from itself');
    }
    AccountingService.assertPeriodNotClosed(db, production_date, 'Production');

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
        `).get(input.item_id, materialsWarehouseId) as { quantity: number } | undefined;

        const availableStock = roundQty(stockBalance ? parseFloat(String(stockBalance.quantity)) : 0);
        const requiredQty = roundQty(input.quantity);

        if (availableStock < requiredQty) {
          const item = db.prepare('SELECT item_name FROM items WHERE id = ?').get(input.item_id) as { item_name: string };
          throw new Error(`Insufficient stock for ${item.item_name} in warehouse. Available: ${availableStock}, Required: ${requiredQty}`);
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

        StockMovementModel.refreshItemStockMirror(input.item_id, db);
      }

      // PROD-001: consuming raw materials must relieve inventory. The output
      // posting below is Dr Inventory / Cr Production Clearing for the whole
      // batch cost, so the clearing account has to be debited, and inventory
      // credited, with the material cost actually consumed (FIFO). Net effect:
      // inventory moves by (output value - materials) and 7000 keeps only the
      // absorbed overhead. Keyed by the production id so delete can void it.
      const consumedValue = roundCurrency(totalMaterialCost);
      if (consumedValue > 0) {
        AccountingService.postLegacyStockEntry(db, {
          referenceType: 'production_consume',
          referenceId: Number(productionId),
          entryDate: production_date,
          description: `Production ${productionNo}: raw materials consumed (${consumedValue.toFixed(2)})`,
          debitTextCode: 'production_clearing',
          creditTextCode: 'inventory_asset',
          amount: consumedValue,
          createdBy: userId,
        });
      }

      // Calculate total batch cost from actual FIFO consumption
      const totalOverhead = overhead_cost ?? 0;

      // D6: overhead is not a separately recorded expense, so production itself
      // must accrue it. Without this the clearing account keeps a net credit for
      // the absorbed overhead and profit is inflated by that amount.
      const overheadValue = roundCurrency(totalOverhead);
      if (overheadValue > 0) {
        AccountingService.postLegacyStockEntry(db, {
          referenceType: 'production_overhead',
          referenceId: Number(productionId),
          entryDate: production_date,
          description: `Production ${productionNo}: overhead accrued unpaid (${overheadValue.toFixed(2)})`,
          debitTextCode: 'production_clearing',
          creditTextCode: 'production_overhead_payable',
          amount: overheadValue,
          createdBy: userId,
        });
      }

      // D6: allocate the joint cost (materials + overhead) across the output
      // lines by RELATIVE SALES VALUE — each line's share is its quantity x
      // the item's standard selling price, over the total of those. The pool
      // is what was actually posted (materials + overhead, each rounded to
      // cents), so Dr/Cr production_clearing nets to exactly zero. The last
      // line absorbs the rounding remainder; a production with no priced
      // outputs falls back to a quantity split rather than dividing by zero.
      const allocationPool = roundCurrency(consumedValue + overheadValue);
      const priceStmt = db.prepare(`SELECT standard_selling_price FROM items WHERE id = ?`);
      const salesValues = outputLines.map((line) => {
        const price = Number((priceStmt.get(line.item_id) as { standard_selling_price: number | null } | undefined)?.standard_selling_price ?? 0);
        const qty = Number(line.quantity);
        return Number.isFinite(price) && price > 0 && Number.isFinite(qty) && qty > 0 ? price * qty : 0;
      });
      const totalSalesValue = salesValues.reduce((sum, v) => sum + v, 0);
      const weights = totalSalesValue > 0
        ? salesValues
        : outputLines.map((line) => Number(line.quantity));
      const totalWeight = weights.reduce((sum, v) => sum + v, 0) || 1;

      let allocatedSoFar = 0;
      const allocations = outputLines.map((line, index) => {
        if (index === outputLines.length - 1) {
          const rest = roundCurrency(allocationPool - allocatedSoFar);
          allocatedSoFar = allocationPool;
          return rest;
        }
        const share = roundCurrency(allocationPool * (weights[index] / totalWeight));
        allocatedSoFar = roundCurrency(allocatedSoFar + share);
        return share;
      });

      // One stock_batch + one PRODUCTION movement + one GL posting per output
      // line, each carrying that line's allocated cost.
      const outputBatchIds: number[] = [];
      const primaryBatchIds: number[] = [];
      // D6: the request carries ONE expiry date but a joint production
      // yields several outputs. Only an output whose item actually tracks
      // expiry may carry it — the boot-time expiry sweep filters batches
      // on expiry_date alone, so stamping a non-expiry co-product would
      // later move it to the EXPIRED warehouse.
      const tracksExpiryStmt = db.prepare(
        'SELECT has_expiry FROM items WHERE id = ?',
      );
      const itemTracksExpiry = (itemId: number): boolean => {
        const row = tracksExpiryStmt.get(itemId) as
          { has_expiry: number | null } | undefined;
        return row?.has_expiry === 1;
      };

      for (let index = 0; index < outputLines.length; index++) {
        const line = outputLines[index];
        const lineQty = Number(line.quantity);
        const allocated = allocations[index];
        const lineBatchNo = this.generateBatchNo(db);
        const lineUnitCost = lineQty > 0 ? roundQty(allocated / lineQty, 6) : 0;
        const lineExpiryDate = itemTracksExpiry(line.item_id)
          ? expiry_date || null
          : null;

        db.prepare(`
          INSERT INTO stock_batches (
            batch_no, item_id, warehouse_id, source_type,
            source_id, quantity_original, quantity_remaining,
            unit_cost, received_date, expiry_date
          ) VALUES (?, ?, ?, 'PRODUCTION', ?, ?, ?, ?, ?, ?)
        `).run(
          lineBatchNo,
          line.item_id,
          warehouse_id,
          productionId,
          lineQty,
          lineQty,
          lineUnitCost,
          production_date,
          lineExpiryDate
        );

        const batchRecord = db.prepare(`
          SELECT id FROM stock_batches
          WHERE source_type = 'PRODUCTION' AND source_id = ? AND item_id = ?
        `).get(productionId, line.item_id) as { id: number } | undefined;
        const outputBatchId = batchRecord?.id;
        if (outputBatchId) outputBatchIds.push(outputBatchId);
        if (index === 0 && outputBatchId) primaryBatchIds.push(outputBatchId);

        db.prepare(`
          INSERT INTO production_outputs (production_id, item_id, quantity, unit_cost, allocated_cost)
          VALUES (?, ?, ?, ?, ?)
        `).run(productionId, line.item_id, lineQty, lineUnitCost, allocated);

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
          line.item_id,
          warehouse_id,
          'PRODUCTION',
          lineQty,
          lineUnitCost,
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
          item_id: line.item_id,
          quantity: lineQty,
          total_batch_cost: allocated,
          movement_date: production_date,
          created_by: userId
        }, db);

        // Update stock_balances for this output item
        const outputExistingBalance = db.prepare(`
          SELECT * FROM stock_balances
          WHERE item_id = ? AND warehouse_id = ?
        `).get(line.item_id, warehouse_id) as Record<string, unknown> | undefined;

        if (outputExistingBalance) {
          db.prepare(`
            UPDATE stock_balances
            SET quantity = quantity + ?,
                last_updated = CURRENT_TIMESTAMP
            WHERE item_id = ? AND warehouse_id = ?
          `).run(lineQty, line.item_id, warehouse_id);
        } else {
          db.prepare(`
            INSERT INTO stock_balances (item_id, warehouse_id, quantity)
            VALUES (?, ?, ?)
          `).run(line.item_id, warehouse_id, lineQty);
        }

        StockMovementModel.refreshItemStockMirror(line.item_id, db);
      }

      // Update production record with batch costing info. The header keeps the
      // PRIMARY (first) output for list/report compatibility; the full split
      // lives in production_outputs.
      const totalBatchCost = allocationPool;
      const costPerUnit = output_quantity > 0 ? roundQty(allocations[0] / output_quantity) : 0;
      db.prepare(`
        UPDATE productions
        SET batch_no = ?,
            unit_cost = ?,
            total_material_cost = ?,
            total_batch_cost = ?,
            batch_id = ?
        WHERE id = ?
      `).run(batchNo, costPerUnit, totalMaterialCost, totalBatchCost, primaryBatchIds[0] ?? null, productionId);

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
    const params: SqlParam[] = [];

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

      // D6: the output split (one row for legacy single-output productions,
      // one per joint product otherwise).
      production.outputs = db.prepare(`
        SELECT
          po.*,
          i.item_code,
          i.item_name,
          i.unit_of_measure
        FROM production_outputs po
        JOIN items i ON po.item_id = i.id
        WHERE po.production_id = ?
        ORDER BY po.id
      `).all(id) as ProductionOutput[];
    }

    return production;
  }

  static getSummaryByItem(item_id: number, db: Database.Database) {
    // D6: read the output lines, not the header's primary-output column —
    // a joint production names only its first output there, so the secondary
    // product (mustard cake) would otherwise report zero production. Legacy
    // single-output productions are backfilled with one row by the migration,
    // so their numbers are unchanged.
    return db.prepare(`
      SELECT
        COUNT(*) as production_count,
        SUM(po.quantity) as total_quantity_produced,
        MIN(p.production_date) as first_production_date,
        MAX(p.production_date) as last_production_date
      FROM production_outputs po
      JOIN productions p ON p.id = po.production_id
      WHERE po.item_id = ?
    `).get(item_id);
  }

  static delete(id: number, userId: number, db: Database.Database): boolean {
    const production = this.getById(id, db);

    if (!production) {
      throw new Error('Production not found');
    }

    const transaction = db.transaction(() => {
      // Reversal rules: a posting dated in a closed period cannot be undone.
      AccountingService.assertPeriodNotClosed(db, production.production_date, `Production ${production.production_no}`);

      // PROD-005: the output must be intact. Once any of it was sold,
      // transferred or consumed, deleting would conjure stock (raw materials
      // restored in full while part of the output is already gone).
      // D6: a production now yields one batch per output line; every one of
      // them has to be intact before the record can go.
      const producedBatches = db.prepare(`
        SELECT item_id, quantity_original, quantity_remaining
        FROM stock_batches
        WHERE source_type = 'PRODUCTION' AND source_id = ?
      `).all(id) as Array<{ item_id: number; quantity_original: number; quantity_remaining: number }>;
      for (const producedBatch of producedBatches) {
        if (roundQty(producedBatch.quantity_remaining) < roundQty(producedBatch.quantity_original)) {
          throw new Error(
            `Cannot delete production ${production.production_no}: ` +
            `${roundQty(producedBatch.quantity_original - producedBatch.quantity_remaining)} of its ` +
            `${roundQty(producedBatch.quantity_original)} output units have already been sold or moved`
          );
        }
      }

      // D6: one positive PRODUCTION movement (and one GL posting) per output
      // line — void every one of them, not just the newest.
      const outputMovements = db.prepare(`
        SELECT id, journal_entry_id, unit_cost, quantity,
          (SELECT COUNT(*) FROM journal_lines
           WHERE reference_type = 'production' AND reference_id = stock_movements.id AND voided_at IS NULL) AS active_gl_lines
        FROM stock_movements
        WHERE movement_type = 'PRODUCTION' AND reference_docno = ? AND quantity > 0
        ORDER BY id DESC
      `).all(production.production_no) as Array<{ id: number; journal_entry_id: number | null; unit_cost: number; active_gl_lines: number; quantity: number }>;

      // Reversal-rules C2 (FIRST, before stock is touched): void the
      // canonical journal_lines posted for production output
      // (postFinancialEntryForProduction: Dr inventory_asset / Cr
      // production_clearing) and keep the legacy header consistent.
      // Without this, deleting a production removed the stock but left
      // its GL entry active forever.
      let voidedOutputPosting = false;
      for (const outputMovement of outputMovements) {
        if (outputMovement.active_gl_lines > 0 || outputMovement.journal_entry_id) {
          AccountingService.voidJournalLinesByReference(db, 'production', outputMovement.id);
          if (outputMovement.journal_entry_id) {
            StockMovementModel.voidJournalEntry(outputMovement.journal_entry_id, db);
          }
          voidedOutputPosting = true;
        }
      }
      if (!voidedOutputPosting && parseCurrency(production.total_batch_cost) > 0) {
        // Must-void guard: a production with real cost but no linked
        // GL lines means GL state is unexpected — refuse rather than
        // silently orphan.
        throw new Error(
          `Refusing to delete production ${production.production_no}: its GL journal entry is missing — GL state unexpected`
        );
      }

      // PROD-001: void the raw-material consumption posting too (productions
      // recorded before it existed simply have none).
      const activeConsume = db.prepare(`
        SELECT COUNT(*) AS n FROM journal_lines
        WHERE reference_type = 'production_consume' AND reference_id = ? AND voided = 0
      `).get(id) as { n: number };
      if (activeConsume.n > 0) {
        AccountingService.voidJournalLinesByReference(db, 'production_consume', id);
        db.prepare(`UPDATE journal_entries SET voided = TRUE WHERE reference_type = 'production_consume' AND reference_id = ?`).run(id);
      }

      // The overhead accrual is reversed with the production, so the payable
      // returns to what it was before this record existed.
      const activeOverhead = db.prepare(`
        SELECT COUNT(*) AS n FROM journal_lines
        WHERE reference_type = 'production_overhead' AND reference_id = ? AND voided = 0
      `).get(id) as { n: number };
      if (activeOverhead.n > 0) {
        AccountingService.voidJournalLinesByReference(db, 'production_overhead', id);
        db.prepare(`UPDATE journal_entries SET voided = TRUE WHERE reference_type = 'production_overhead' AND reference_id = ?`).run(id);
      }

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
            // PROD-005: the consumed batch was restored above, and the GL is
            // undone by voiding the consumption posting - so no second batch
            // and no inventory-adjustment posting here.
            batch_id: movement.batch_id ?? undefined,
            skipAdjustmentFinancialPosting: true,
          },
          userId,
          db
        );
      }

      // 2. Handle every output batch this production created (D6: one per
      // output line; legacy productions have exactly one).
      const outputBatches = db.prepare(`
        SELECT id, item_id, quantity_remaining, unit_cost
        FROM stock_batches
        WHERE source_type = 'PRODUCTION' AND source_id = ?
      `).all(id) as Array<{ id: number; item_id: number; quantity_remaining: number; unit_cost: number }>;

      for (const outputBatch of outputBatches) {
        if (outputBatch.quantity_remaining > 0) {
          // Create ADJUSTMENT movement to remove output stock
          StockMovementModel.recordMovement(
            {
              item_id: outputBatch.item_id,
              warehouse_id: production.warehouse_id,
              movement_type: 'ADJUSTMENT',
              quantity: -outputBatch.quantity_remaining,
              unit_cost: outputBatch.unit_cost,
              reference_doctype: 'PRODUCTION_DELETE',
              reference_docno: production.production_no,
              remarks: `Stock reversed - Production ${production.production_no} deleted (output)`,
              movement_date: new Date().toISOString().split('T')[0],
              batch_id: outputBatch.id,
              skipAdjustmentFinancialPosting: true,
            },
            userId,
            db
          );

          // Zero out the output batch (keep for FK integrity with stock_movements)
          db.prepare('UPDATE stock_batches SET quantity_remaining = 0 WHERE id = ?').run(outputBatch.id);
        }
      }

      // 3. Delete production inputs, output lines and production record
      db.prepare('DELETE FROM production_outputs WHERE production_id = ?').run(id);
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
