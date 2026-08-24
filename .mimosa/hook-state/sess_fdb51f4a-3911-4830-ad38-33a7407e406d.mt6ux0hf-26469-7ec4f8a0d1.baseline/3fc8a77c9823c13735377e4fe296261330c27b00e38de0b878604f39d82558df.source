import Database from 'better-sqlite3';
import { generateDocNo, getNextSequenceNumber } from '../utils/sequence';
import { sanitizeSortParams, PURCHASE_SORT_COLUMNS } from '../utils/sqlSanitizer';
import StockMovementModel from './StockMovement';
import SupplierLedgerModel from './SupplierLedger';
import AccountingService from '../services/accountingService';
import ledgerUtils from '../utils/ledgerUtils';

interface Purchase {
  id: number;
  purchase_no: string;
  item_id: number;
  warehouse_id: number;
  quantity: number;
  unit_cost: number;
  total_cost: number;
  supplier_id?: number;
  supplier_name?: string;
  purchase_date: string;
  invoice_no?: string;
  remarks?: string;
  batch_no?: string;
  batch_id?: number;
  returned_quantity?: number;
  paid_amount?: number;
  balance_amount?: number;
  created_by: number;
  created_at?: string;
  item_code?: string;
  item_name?: string;
  unit_of_measure?: string;
  warehouse_code?: string;
  warehouse_name?: string;
  created_by_username?: string;
}

interface PurchaseFilters {
  start_date?: string;
  end_date?: string;
  item_id?: number;
  warehouse_id?: number;
  supplier_name?: string;
  search?: string;
  limit?: number;
  sortBy?: string;
  sortOrder?: string;
  page?: number;
}

interface PaginatedPurchases {
  rows: Purchase[];
  total: number;
  pageNum: number;
  limitNum: number;
}

// Whitelisted sort columns → qualified SQL column for the list query (the
// item/warehouse/user joins make bare names ambiguous).
const PURCHASE_SORT_COLUMN_MAP: Record<string, string> = {
  purchase_no: 'p.purchase_no',
  purchase_date: 'p.purchase_date',
  item_name: 'i.item_name',
  supplier_name: 'p.supplier_name',
  quantity: 'p.quantity',
  unit_cost: 'p.unit_cost',
  total_cost: 'p.total_cost',
  // ORDER BY can reference the SELECT aliases.
  paid_amount: 'paid_amount',
  balance_amount: 'balance_amount',
  warehouse_name: 'w.warehouse_name',
  created_at: 'p.created_at',
};

interface CreatePurchaseDTO {
  item_id: number;
  warehouse_id: number;
  quantity: number;
  unit_cost: number;
  supplier_id?: number;
  supplier_name?: string;
  purchase_date: string;
  invoice_no?: string;
  remarks?: string;
  expiry_date?: string;
}

class PurchaseModel {
  static generatePurchaseNo(db: Database.Database): string {
    return generateDocNo(db, 'PURCH');
  }

  static generateBatchNo(db: Database.Database): string {
    const year = new Date().getFullYear();
    const settingKey = `BATCH_last_no_${year}`;
    const nextNo = getNextSequenceNumber(db, settingKey);
    return `BATCH-${year % 100}-PUR-${nextNo.toString().padStart(4, '0')}`;
  }

  static generateMovementNo(db: Database.Database): string {
    return generateDocNo(db, 'STK');
  }

  static recordPurchase(data: CreatePurchaseDTO, userId: number, db: Database.Database): Purchase {
    if (!data.item_id || data.item_id <= 0) throw new Error('Invalid item_id');
    if (!data.warehouse_id || data.warehouse_id <= 0) throw new Error('Invalid warehouse_id');
    if (!data.quantity || data.quantity <= 0) throw new Error('Quantity must be positive');
    if (data.unit_cost === undefined || data.unit_cost < 0) throw new Error('unit_cost must be non-negative');
    if (!data.purchase_date) throw new Error('purchase_date is required');

    const { item_id, warehouse_id, quantity, unit_cost, supplier_id, supplier_name, purchase_date, invoice_no, remarks, expiry_date } = data;

    // A linked supplier wins over any free-text name: resolve the
    // display name from the suppliers table so the purchase always
    // shows the supplier's current name.
    const resolvedSupplierId: number | undefined = supplier_id;
    let resolvedSupplierName: string | undefined = supplier_name;
    if (resolvedSupplierId) {
      const supplier = db.prepare(
        'SELECT id, supplier_name FROM suppliers WHERE id = ?'
      ).get(resolvedSupplierId) as { id: number; supplier_name: string } | undefined;
      if (!supplier) throw new Error(`Supplier ${resolvedSupplierId} not found`);
      resolvedSupplierName = supplier.supplier_name;
    }

    const transaction = db.transaction(() => {
      const purchaseNo = this.generatePurchaseNo(db);
      const batchNo = this.generateBatchNo(db);

      const purchaseStmt = db.prepare(`
        INSERT INTO purchases (
          purchase_no, item_id, warehouse_id, quantity, unit_cost, total_cost,
          supplier_id, supplier_name, purchase_date, invoice_no, remarks, created_by
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `);

      const totalCost = quantity * unit_cost;

      const result = purchaseStmt.run(
        purchaseNo,
        item_id,
        warehouse_id,
        quantity,
        unit_cost,
        totalCost,
        resolvedSupplierId || null,
        resolvedSupplierName || null,
        purchase_date,
        invoice_no || null,
        remarks || null,
        userId
      );

      const purchaseId = result.lastInsertRowid as number;

      // Create a stock_batch record for the purchased item. Identity comes
      // from the INSERT result (task 3.4 / PUR-02 residue) — re-querying
      // (source_type, source_id) could return another writer's batch when
      // id spaces ever collide.
      const batchResult = db.prepare(`
        INSERT INTO stock_batches (
          batch_no, item_id, warehouse_id, source_type,
          source_id, quantity_original, quantity_remaining,
          unit_cost, received_date, expiry_date
        ) VALUES (?, ?, ?, 'PURCHASE', ?, ?, ?, ?, ?, ?)
      `).run(
        batchNo,
        item_id,
        warehouse_id,
        purchaseId,
        quantity,
        quantity,
        unit_cost,
        purchase_date,
        expiry_date || null
      );
      const outputBatchId = Number(batchResult.lastInsertRowid);

      // Record stock movement linked to the new batch
      const movementNo = this.generateMovementNo(db);
      db.prepare(`
        INSERT INTO stock_movements (
          movement_no, item_id, warehouse_id, movement_type,
          quantity, unit_cost, reference_doctype, reference_docno,
          remarks, movement_date, created_by, batch_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).run(
        movementNo,
        item_id,
        warehouse_id,
        'PURCHASE',
        quantity,
        unit_cost,
        'Purchase',
        purchaseNo,
        `Purchase: ${purchaseNo}${supplier_name ? ' from ' + supplier_name : ''} (batch ${outputBatchId})`,
        purchase_date,
        userId,
        outputBatchId
      );

      // Update purchase record with batch info
      db.prepare(`
        UPDATE purchases SET batch_no = ?, batch_id = ? WHERE id = ?
      `).run(batchNo, outputBatchId, purchaseId);

      // Update stock_balances
      const existingBalance = db.prepare(`
        SELECT * FROM stock_balances
        WHERE item_id = ? AND warehouse_id = ?
      `).get(item_id, warehouse_id) as Record<string, unknown> | undefined;

      if (existingBalance) {
        db.prepare(`
          UPDATE stock_balances
          SET quantity = quantity + ?,
              last_updated = CURRENT_TIMESTAMP
          WHERE item_id = ? AND warehouse_id = ?
        `).run(quantity, item_id, warehouse_id);
      } else {
        db.prepare(`
          INSERT INTO stock_balances (item_id, warehouse_id, quantity)
          VALUES (?, ?, ?)
        `).run(item_id, warehouse_id, quantity);
      }

      db.prepare(`
        UPDATE items
        SET current_stock = (
          SELECT COALESCE(SUM(quantity), 0)
          FROM stock_balances
          WHERE item_id = ?
        )
        WHERE id = ?
      `).run(item_id, item_id);

      // Supplier AP entry: a linked purchase increases the supplier's
      // payable balance (mirrors the PO submit flow's PURCHASE_ORDER
      // entry; the payment flow then credits it down).
      if (resolvedSupplierId) {
        SupplierLedgerModel.createEntry({
          supplier_id: resolvedSupplierId,
          transaction_date: purchase_date,
          transaction_type: 'PURCHASE',
          reference_no: purchaseNo,
          debit: totalCost,
          credit: 0,
          description: `Purchase ${purchaseNo}`,
        }, db);
        SupplierLedgerModel.rebuildBalances(resolvedSupplierId, db);
      }

      // GL posting (ACC-02): Dr 1200 Inventory Asset /
      // Cr 2000 AP. Direct purchases are recorded on credit in this
      // flow — immediate payment happens through the supplier-payment
      // path, which posts its own cash-side entry.
      AccountingService.postPurchaseEntry(db, {
        purchaseId,
        purchaseNo,
        totalCost,
        purchaseDate: purchase_date,
        paymentMethod: 'credit',
        userId,
      });

      // Mark the movement financially posted so no backfill treats it
      // as unposted (audit ACC-02 note).
      db.prepare(`
        UPDATE stock_movements SET financial_posted = 1
        WHERE reference_docno = ? AND movement_type = 'PURCHASE'
      `).run(purchaseNo);

      db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(
        userId,
        'CREATE',
        'Purchase',
        purchaseId,
        `Recorded purchase ${purchaseNo}: ${quantity} units (Batch: ${batchNo}, Cost: ${unit_cost}/unit)`
      );

      return this.getById(purchaseId, db) as Purchase;
    });

    return transaction();
  }

  static getAll(filters: PurchaseFilters = {}, db: Database.Database): PaginatedPurchases {
    const pageNum = filters.page || 1;
    const limitNum = filters.limit || 10;

    const select = `
      SELECT
        p.*,
        i.item_code,
        i.item_name,
        i.unit_of_measure,
        w.warehouse_code,
        w.warehouse_name,
        u.username as created_by_username,
        COALESCE(pa.paid_amount, 0) as paid_amount,
        p.total_cost - COALESCE(pa.paid_amount, 0) as balance_amount
      FROM purchases p
      JOIN items i ON p.item_id = i.id
      JOIN warehouses w ON p.warehouse_id = w.id
      JOIN users u ON p.created_by = u.id
      LEFT JOIN (
        SELECT purchase_id, SUM(amount) as paid_amount
        FROM purchase_allocations GROUP BY purchase_id
      ) pa ON pa.purchase_id = p.id
      WHERE 1=1
    `;
    const conditions: string[] = [];
    const params: any[] = [];

    if (filters.start_date) {
      conditions.push('p.purchase_date >= ?');
      params.push(filters.start_date);
    }

    if (filters.end_date) {
      conditions.push('p.purchase_date <= ?');
      params.push(filters.end_date);
    }

    if (filters.item_id) {
      conditions.push('p.item_id = ?');
      params.push(filters.item_id);
    }

    if (filters.warehouse_id) {
      conditions.push('p.warehouse_id = ?');
      params.push(filters.warehouse_id);
    }

    if (filters.supplier_name) {
      conditions.push('p.supplier_name LIKE ?');
      params.push(`%${filters.supplier_name}%`);
    }

    if (filters.search) {
      conditions.push('(p.purchase_no LIKE ? OR i.item_name LIKE ? OR p.supplier_name LIKE ?)');
      const term = `%${filters.search}%`;
      params.push(term, term, term);
    }

    const where = conditions.length ? ` AND ${conditions.join(' AND ')}` : '';

    // Sort — whitelisted via sqlSanitizer, mapped to qualified columns
    // (default matches the pre-paging behavior: newest purchase first).
    const { column, order } = sanitizeSortParams(
      filters.sortBy || 'purchase_date',
      filters.sortOrder || 'DESC',
      PURCHASE_SORT_COLUMNS,
      'purchase_date',
      'DESC'
    );
    const sortColumn = PURCHASE_SORT_COLUMN_MAP[column] || 'p.purchase_date';

    const offset = (pageNum - 1) * limitNum;
    const purchases = db
      .prepare(`${select}${where} ORDER BY ${sortColumn} ${order}, p.id DESC LIMIT ? OFFSET ?`)
      .all(...params, limitNum, offset) as Purchase[];

    const countRow = db
      .prepare(`SELECT COUNT(*) as total FROM purchases p
        JOIN items i ON p.item_id = i.id
        JOIN warehouses w ON p.warehouse_id = w.id
        JOIN users u ON p.created_by = u.id
        WHERE 1=1${where}`)
      .get(...params) as { total: number };

    return { rows: purchases, total: countRow.total, pageNum, limitNum };
  }

  static getById(id: number, db: Database.Database): Purchase | undefined {
    return db.prepare(`
      SELECT
        p.*,
        i.item_code,
        i.item_name,
        i.unit_of_measure,
        w.warehouse_code,
        w.warehouse_name,
        u.username as created_by_username,
        COALESCE(pa.paid_amount, 0) as paid_amount,
        p.total_cost - COALESCE(pa.paid_amount, 0) as balance_amount
      FROM purchases p
      JOIN items i ON p.item_id = i.id
      JOIN warehouses w ON p.warehouse_id = w.id
      JOIN users u ON p.created_by = u.id
      LEFT JOIN (
        SELECT purchase_id, SUM(amount) as paid_amount
        FROM purchase_allocations GROUP BY purchase_id
      ) pa ON pa.purchase_id = p.id
      WHERE p.id = ?
    `).get(id) as Purchase | undefined;
  }

  /**
   * Payments allocated to this direct purchase (`purchase_allocations`)
   * — the payment header joined with the per-purchase allocation amount,
   * newest first. Mirrors `PurchaseOrderModel.getPayments`; the client
   * renders these as the purchase's payment history.
   */
  static getPayments(purchaseId: number, db: Database.Database): Array<{
    id: number; payment_no: string; payment_date: string;
    payment_method: string; reference_no: string; notes: string; amount: number;
  }> {
    return db.prepare(`
      SELECT p.id, p.payment_no, p.payment_date, p.payment_method,
             p.reference_no, p.notes, pa.amount
      FROM purchase_allocations pa JOIN payments p ON pa.payment_id = p.id
      WHERE pa.purchase_id = ? ORDER BY p.payment_date DESC, p.id DESC
    `).all(purchaseId) as Array<{
      id: number; payment_no: string; payment_date: string;
      payment_method: string; reference_no: string; notes: string; amount: number;
    }>;
  }

  static getSummaryByItem(item_id: number, db: Database.Database) {
    return db.prepare(`
      SELECT
        COUNT(*) as purchase_count,
        SUM(quantity) as total_quantity,
        SUM(total_cost) as total_cost,
        AVG(unit_cost) as avg_unit_cost,
        MIN(purchase_date) as first_purchase_date,
        MAX(purchase_date) as last_purchase_date
      FROM purchases
      WHERE item_id = ?
    `).get(item_id);
  }

  static getSummaryByDateRange(start_date: string, end_date: string, db: Database.Database) {
    return db.prepare(`
      SELECT
        COUNT(*) as purchase_count,
        SUM(quantity) as total_quantity,
        SUM(total_cost) as total_cost,
        COUNT(DISTINCT item_id) as unique_items,
        COUNT(DISTINCT supplier_name) as unique_suppliers
      FROM purchases
      WHERE purchase_date BETWEEN ? AND ?
    `).get(start_date, end_date);
  }

  static getTopSuppliers(limit: number = 10, db: Database.Database) {
    return db.prepare(`
      SELECT
        supplier_name,
        COUNT(*) as purchase_count,
        SUM(quantity) as total_quantity,
        SUM(total_cost) as total_cost
      FROM purchases
      WHERE supplier_name IS NOT NULL
      GROUP BY supplier_name
      ORDER BY total_cost DESC
      LIMIT ?
    `).all(limit);
  }

  /**
   * Void a purchase (PUR-03, task 3.2) — replaces hard delete.
   * Guards: open purchase returns, returned stock, sold stock, allocations.
   * Reverses subledger (append-only), voids the GL entry, removes only the
   * genuinely remaining stock, stamps void attribution.
   */
  static void(id: number, userId: number, reason: string, db: Database.Database): boolean {
    if (!reason || !reason.trim()) {
      throw new Error('A void reason is required');
    }

    const purchase = this.getById(id, db);
    if (!purchase) {
      throw new Error('Purchase not found');
    }

    const existing = db.prepare(
      'SELECT voided_at FROM purchases WHERE id = ?'
    ).get(id) as { voided_at: string | null } | undefined;
    if (existing?.voided_at) {
      throw new Error(`Purchase ${purchase.purchase_no} is already voided`);
    }

    const transaction = db.transaction(() => {
      // Guard: a purchase with recorded payments cannot be voided —
      // the allocations/ledger would be orphaned. Reverse payments first.
      const paymentAlloc = db.prepare(
        'SELECT id FROM purchase_allocations WHERE purchase_id = ? LIMIT 1'
      ).get(id) as { id: number } | undefined;
      if (paymentAlloc) {
        throw new Error(
          'Cannot void purchase with recorded payments — delete the payments first'
        );
      }

      // Guard: open (non-voided) purchase returns against this purchase.
      const openReturn = db.prepare(`
        SELECT id FROM purchase_returns
        WHERE source_type = 'PURCHASE' AND source_id = ? AND status != 'VOIDED'
        LIMIT 1
      `).get(id) as { id: number } | undefined;
      if (openReturn) {
        throw new Error(
          `Cannot void purchase ${purchase.purchase_no} — void its purchase returns first`
        );
      }

      // Guard: any returned quantity makes the return history unreversable.
      const returned = Number((purchase as { returned_quantity?: number }).returned_quantity) || 0;
      if (returned > 0.001) {
        throw new Error(
          `Cannot void purchase ${purchase.purchase_no} — ${returned} unit(s) already returned`
        );
      }

      // Find the stock_batch created by this purchase
      const batch = db.prepare(`
        SELECT id, batch_no, quantity_original, quantity_remaining, unit_cost
        FROM stock_batches
        WHERE source_type = 'PURCHASE' AND source_id = ?
      `).get(id) as { id: number; batch_no: string; quantity_original: number; quantity_remaining: number; unit_cost: number } | undefined;

      // Guard: stock already sold — remaining < original means consumption
      // happened that cannot be attributed back once the purchase is voided.
      if (batch) {
        const original = Number(batch.quantity_original);
        const remaining = Number(batch.quantity_remaining);
        if (remaining < original - 0.01) {
          throw new Error(
            `Cannot void purchase ${purchase.purchase_no} — ${(original - remaining).toFixed(3)} unit(s) of its stock already sold/consumed`
          );
        }
      }

      // Reverse the supplier AP entry posted at record time (keeps the
      // running balance chain consistent).
      if (purchase.supplier_id) {
        const rows = db.prepare(
          `SELECT id FROM supplier_ledger
           WHERE supplier_id = ? AND reference_no = ? AND transaction_type = 'PURCHASE' AND voided = 0`
        ).all(purchase.supplier_id, purchase.purchase_no) as Array<{ id: number }>;
        for (const row of rows) {
          ledgerUtils.reverseLedgerEntry('supplier_ledger', row.id, `purchase ${purchase.purchase_no} voided`);
        }
      }

      // Void the GL journal entry posted at record time (Dr Inventory / Cr AP).
      AccountingService.voidJournalLinesByReference(db, 'PURCHASE', id, {
        voidedBy: userId,
        voidReason: reason.trim(),
      });

      if (batch && batch.quantity_remaining > 0) {
        // ADJUSTMENT movement to remove only the genuinely remaining stock
        StockMovementModel.recordMovement(
          {
            item_id: purchase.item_id,
            warehouse_id: purchase.warehouse_id,
            movement_type: 'ADJUSTMENT',
            quantity: -batch.quantity_remaining,
            unit_cost: batch.unit_cost,
            reference_doctype: 'PURCHASE_VOID',
            reference_docno: purchase.purchase_no,
            remarks: `Stock reversed - Purchase ${purchase.purchase_no} voided (batch ${batch.batch_no}): ${reason.trim()}`,
            movement_date: new Date().toISOString().split('T')[0],
          },
          userId,
          db
        );

        // Zero out the batch record (keep for FK integrity with stock_movements)
        db.prepare('UPDATE stock_batches SET quantity_remaining = 0 WHERE id = ?').run(batch.id);
      }

      // Stamp void attribution instead of deleting
      db.prepare(`
        UPDATE purchases
        SET voided_at = datetime('now'), voided_by = ?, void_reason = ?
        WHERE id = ?
      `).run(userId, reason.trim(), id);

      db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(
        userId,
        'VOID',
        'Purchase',
        id,
        `Voided purchase ${purchase.purchase_no}: ${reason.trim()}`
      );
    });

    transaction();

    return true;
  }
}

export default PurchaseModel;
