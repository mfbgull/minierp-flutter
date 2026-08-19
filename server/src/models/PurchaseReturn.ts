import Database from 'better-sqlite3';
import StockMovementModel from './StockMovement';
import SupplierLedgerModel from './SupplierLedger';
import AccountingService from '../services/accountingService';
import logger from '../utils/logger';
import { generateDocNo } from '../utils/sequence';
import { sanitizeSortParams, PURCHASE_RETURN_HEADER_SORT_COLUMNS } from '../utils/sqlSanitizer';

/**
 * PurchaseReturnModel — the redesigned, first-class purchase return document.
 *
 * Replaces the old "return = negative stock movement" model. A return is now a
 * header (`purchase_returns`) + lines (`purchase_return_items`), linked to its
 * negative stock movement(s) via `stock_movements.purchase_return_id`, and —
 * when posted — to a supplier `credit_notes` document + supplier ledger entry.
 *
 * Source documents:
 *   - `PURCHASE` (source_type) → direct purchase row (`purchases.id`)
 *   - `PURCHASE_ORDER` (source_type) → PO line (`purchase_order_items.id`)
 *
 * Returnable quantity per line:
 *   - direct purchase: `purchases.quantity - returned_quantity`
 *   - PO line:         `purchase_order_items.received_quantity - returned_quantity`
 *
 * GL posting reuses AccountingService.postPurchaseReturnEntry (Dr AP / Cr
 * Inventory) with reference_id = purchase_returns.id so void can reverse it;
 * supplier credit is a dedicated credit_notes row + supplier_ledger entry.
 */

interface CreatePurchaseReturnItemDTO {
  source_item_id: number;   // purchases.id | purchase_order_items.id
  quantity: number;         // positive magnitude
}

export interface CreatePurchaseReturnDTO {
  return_date: string;      // YYYY-MM-DD (user-selectable)
  source_type: 'PURCHASE' | 'PURCHASE_ORDER';
  source_id: number;
  warehouse_id: number;     // restock target — the warehouse stock is removed from
  reason?: string;
  items: CreatePurchaseReturnItemDTO[];
}

export interface PurchaseReturnItemRow {
  id: number;
  purchase_return_id: number;
  source_item_id: number | null;
  item_id: number;
  item_name: string;
  item_code?: string;
  unit_of_measure?: string;
  unit_cost: number;
  quantity: number;
  amount: number;
}

export interface PurchaseReturnHeaderRow {
  id: number;
  return_no: string;
  return_date: string;
  return_type: 'PURCHASE_RETURN' | 'PO_RETURN';
  source_type: string;
  source_id: number | null;
  source_no: string;
  warehouse_id: number;
  warehouse_code?: string;
  warehouse_name?: string;
  reason: string | null;
  status: string;
  total_qty: number;
  total_amount: number;
  credit_note_id: number | null;
  credit_no?: string | null;
  voided_at: string | null;
  voided_by: number | null;
  voided_reason: string | null;
  created_by: number | null;
  created_by_username?: string;
  created_at: string;
  line_count?: number;
  items?: PurchaseReturnItemRow[];
}

interface ReturnFilters {
  search?: string;
  start_date?: string;
  end_date?: string;
  type?: string;
  status?: string;
  warehouse_id?: number;
  sortBy?: string;
  sortOrder?: string;
  page?: number;
  limit?: number;
}

interface PaginatedReturns {
  rows: PurchaseReturnHeaderRow[];
  total: number;
  pageNum: number;
  limitNum: number;
}

// Whitelisted sort columns → qualified SQL column (the warehouse/user/credit
// note joins make bare names ambiguous).
const RETURN_SORT_COLUMN_MAP: Record<string, string> = {
  return_no: 'pr.return_no',
  return_date: 'pr.return_date',
  source_no: 'pr.source_no',
  total_amount: 'pr.total_amount',
  status: 'pr.status',
  warehouse_name: 'w.warehouse_name',
  created_at: 'pr.created_at',
};

const HEADER_SELECT = `
  SELECT
    pr.*,
    w.warehouse_code,
    w.warehouse_name,
    u.username as created_by_username,
    cn.credit_no,
    (SELECT COUNT(*) FROM purchase_return_items pri WHERE pri.purchase_return_id = pr.id) as line_count
  FROM purchase_returns pr
  JOIN warehouses w ON pr.warehouse_id = w.id
  LEFT JOIN users u ON pr.created_by = u.id
  LEFT JOIN credit_notes cn ON cn.id = pr.credit_note_id
`;

class PurchaseReturnModel {
  static generateReturnNo(db: Database.Database): string {
    return generateDocNo(db, 'PR');
  }

  static generateCreditNo(db: Database.Database): string {
    return generateDocNo(db, 'CN');
  }

  // ------------------------------------------------------------------
  // Reads
  // ------------------------------------------------------------------

  static getAll(filters: ReturnFilters = {}, db: Database.Database): PaginatedReturns {
    const pageNum = filters.page || 1;
    const limitNum = filters.limit || 10;

    const conditions: string[] = [];
    const params: any[] = [];

    if (filters.search) {
      conditions.push(
        `(pr.return_no LIKE ? OR pr.source_no LIKE ? OR
          EXISTS (SELECT 1 FROM purchase_return_items pri JOIN items i ON pri.item_id = i.id
                  WHERE pri.purchase_return_id = pr.id AND (i.item_name LIKE ? OR i.item_code LIKE ?)))`
      );
      const term = `%${filters.search}%`;
      params.push(term, term, term, term);
    }

    if (filters.start_date) {
      conditions.push('pr.return_date >= ?');
      params.push(filters.start_date);
    }

    if (filters.end_date) {
      conditions.push('pr.return_date <= ?');
      params.push(filters.end_date);
    }

    if (filters.type) {
      conditions.push('pr.return_type = ?');
      params.push(filters.type);
    }

    if (filters.status) {
      conditions.push('pr.status = ?');
      params.push(filters.status);
    }

    if (filters.warehouse_id) {
      conditions.push('pr.warehouse_id = ?');
      params.push(filters.warehouse_id);
    }

    const where = conditions.length ? ` WHERE ${conditions.join(' AND ')}` : '';

    const { column, order } = sanitizeSortParams(
      filters.sortBy || 'return_date',
      filters.sortOrder || 'DESC',
      PURCHASE_RETURN_HEADER_SORT_COLUMNS,
      'return_date',
      'DESC'
    );
    const sortColumn = RETURN_SORT_COLUMN_MAP[column] || 'pr.return_date';

    const offset = (pageNum - 1) * limitNum;
    const rows = db
      .prepare(`${HEADER_SELECT}${where} ORDER BY ${sortColumn} ${order}, pr.id DESC LIMIT ? OFFSET ?`)
      .all(...params, limitNum, offset) as PurchaseReturnHeaderRow[];

    const countRow = db
      .prepare(`SELECT COUNT(*) as total FROM purchase_returns pr
        JOIN warehouses w ON pr.warehouse_id = w.id${where}`)
      .get(...params) as { total: number };

    return { rows, total: countRow.total, pageNum, limitNum };
  }

  static getById(id: number, db: Database.Database): PurchaseReturnHeaderRow | undefined {
    const header = db
      .prepare(`${HEADER_SELECT} WHERE pr.id = ?`)
      .get(id) as PurchaseReturnHeaderRow | undefined;
    if (!header) return undefined;

    header.items = db.prepare(`
      SELECT
        pri.*,
        i.item_code,
        i.item_name,
        i.unit_of_measure
      FROM purchase_return_items pri
      JOIN items i ON pri.item_id = i.id
      WHERE pri.purchase_return_id = ?
      ORDER BY pri.id ASC
    `).all(id) as PurchaseReturnItemRow[];

    return header;
  }

  // ------------------------------------------------------------------
  // Create (transactional: stock + GL + credit note + ledger + audit)
  // ------------------------------------------------------------------

  static create(data: CreatePurchaseReturnDTO, userId: number, db: Database.Database): PurchaseReturnHeaderRow {
    if (!data.return_date) throw new Error('return_date is required');
    if (!data.source_type || !data.source_id) throw new Error('Source document is required');
    if (!data.warehouse_id) throw new Error('Restock warehouse is required');
    if (!data.items || data.items.length === 0) throw new Error('At least one item is required');

    const transaction = db.transaction(() => {
      // Load the source document and validate every line against its
      // returnable quantity BEFORE mutating anything.
      const lines: Array<{
        source_item_id: number;
        item_id: number;
        item_name: string;
        unit_cost: number;
        quantity: number;
        amount: number;
      }> = [];

      let totalQty = 0;
      let totalAmount = 0;

      for (const line of data.items) {
        if (!line.quantity || line.quantity <= 0) {
          throw new Error('Return quantity must be positive');
        }
        if (!line.source_item_id) throw new Error('source_item_id is required');

        if (data.source_type === 'PURCHASE') {
          const purchase = db.prepare(`
            SELECT p.*, i.item_name
            FROM purchases p JOIN items i ON p.item_id = i.id
            WHERE p.id = ?
          `).get(line.source_item_id) as {
            id: number; item_id: number; item_name: string;
            quantity: number; unit_cost: number; returned_quantity: number;
          } | undefined;
          if (!purchase) throw new Error(`Purchase line ${line.source_item_id} not found`);
          if (purchase.id !== data.source_id) {
            throw new Error(`Purchase ${line.source_item_id} does not belong to source ${data.source_id}`);
          }

          const returned = purchase.returned_quantity || 0;
          const returnable = purchase.quantity - returned;
          if (line.quantity > returnable + 0.001) {
            throw new Error(
              `Return quantity (${line.quantity}) exceeds remaining available (${returnable}) ` +
              `for purchase ${purchase.id}`
            );
          }

          const amount = line.quantity * purchase.unit_cost;
          lines.push({
            source_item_id: purchase.id,
            item_id: purchase.item_id,
            item_name: purchase.item_name,
            unit_cost: purchase.unit_cost,
            quantity: line.quantity,
            amount,
          });
          totalQty += line.quantity;
          totalAmount += amount;
        } else {
          // PURCHASE_ORDER — line.source_item_id is a purchase_order_items.id
          const poItem = db.prepare(`
            SELECT poi.*, i.item_name
            FROM purchase_order_items poi JOIN items i ON poi.item_id = i.id
            WHERE poi.id = ?
          `).get(line.source_item_id) as {
            id: number; po_id: number; item_id: number; item_name: string;
            received_quantity: number; returned_quantity: number; unit_price: number;
          } | undefined;
          if (!poItem) throw new Error(`PO line ${line.source_item_id} not found`);
          if (poItem.po_id !== data.source_id) {
            throw new Error(`PO line ${line.source_item_id} does not belong to PO ${data.source_id}`);
          }

          const returned = poItem.returned_quantity || 0;
          const netReceived = (poItem.received_quantity || 0) - returned;
          if (line.quantity > netReceived + 0.001) {
            throw new Error(
              `Return quantity (${line.quantity}) exceeds net received quantity ` +
              `(${netReceived}) for PO line ${poItem.id}`
            );
          }

          const amount = line.quantity * poItem.unit_price;
          lines.push({
            source_item_id: poItem.id,
            item_id: poItem.item_id,
            item_name: poItem.item_name,
            unit_cost: poItem.unit_price,
            quantity: line.quantity,
            amount,
          });
          totalQty += line.quantity;
          totalAmount += amount;
        }
      }

      // Header
      const returnNo = this.generateReturnNo(db);
      const headerResult = db.prepare(`
        INSERT INTO purchase_returns (
          return_no, return_date, return_type, source_type, source_id,
          source_no, warehouse_id, reason, status, total_qty, total_amount,
          created_by
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'POSTED', ?, ?, ?)
      `).run(
        returnNo,
        data.return_date,
        data.source_type === 'PURCHASE' ? 'PURCHASE_RETURN' : 'PO_RETURN',
        data.source_type,
        data.source_id,
        this.resolveSourceNo(data.source_type, data.source_id, db),
        data.warehouse_id,
        data.reason || null,
        totalQty,
        totalAmount,
        userId
      );
      const returnId = headerResult.lastInsertRowid as number;

      const insertLine = db.prepare(`
        INSERT INTO purchase_return_items (
          purchase_return_id, source_item_id, item_id, item_name,
          unit_cost, quantity, amount
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
      `);

      // Stock: verify availability, then record negative movements per line.
      for (const line of lines) {
        // Stock must exist in the restock warehouse before we remove it.
        const balance = db.prepare(`
          SELECT quantity FROM stock_balances
          WHERE item_id = ? AND warehouse_id = ?
        `).get(line.item_id, data.warehouse_id) as { quantity: number } | undefined;
        const available = balance ? Number(balance.quantity) : 0;
        if (available < line.quantity - 0.001) {
          throw new Error(
            `Insufficient stock for ${line.item_name} in warehouse ${data.warehouse_id}: ` +
            `available ${available}, required ${line.quantity}`
          );
        }

        // Deduct returned_quantity on the source document.
        if (data.source_type === 'PURCHASE') {
          db.prepare(`UPDATE purchases SET returned_quantity = COALESCE(returned_quantity, 0) + ? WHERE id = ?`)
            .run(line.quantity, line.source_item_id);
        } else {
          db.prepare(`UPDATE purchase_order_items SET returned_quantity = COALESCE(returned_quantity, 0) + ? WHERE id = ?`)
            .run(line.quantity, line.source_item_id);
        }

        // Negative stock movement — recordMovement handles stock_balances,
        // items.current_stock and the ADJUSTMENT financial entry.
        const movement = StockMovementModel.recordMovement({
          item_id: line.item_id,
          warehouse_id: data.warehouse_id,
          movement_type: 'ADJUSTMENT',
          quantity: -line.quantity,
          unit_cost: line.unit_cost,
          reference_doctype: data.source_type === 'PURCHASE' ? 'PURCHASE_RETURN' : 'PO_RETURN',
          reference_docno: returnNo,
          remarks: `Return ${returnNo}${data.reason ? ': ' + data.reason : ''}`,
          movement_date: data.return_date,
        }, userId, db);

        // Track the movement on the movement row itself.
        db.prepare('UPDATE stock_movements SET purchase_return_id = ? WHERE id = ?')
          .run(returnId, movement.id);

        // FIFO-reduce the cost layers so batch coverage stays in sync with
        // on-hand stock (mirrors the PO return flow).
        let toReturn = line.quantity;
        const batches = db.prepare(`
          SELECT id, quantity_remaining
          FROM stock_batches
          WHERE item_id = ? AND warehouse_id = ? AND quantity_remaining > 0
          ORDER BY received_date ASC, id ASC
        `).all(line.item_id, data.warehouse_id) as Array<{ id: number; quantity_remaining: number }>;
        for (const batch of batches) {
          if (toReturn <= 0.001) break;
          const consume = Math.min(toReturn, batch.quantity_remaining);
          db.prepare(`UPDATE stock_batches SET quantity_remaining = quantity_remaining - ? WHERE id = ?`)
            .run(consume, batch.id);
          toReturn -= consume;
        }
        // If batches didn't fully cover the return (legacy unbatchable stock),
        // the remainder is fine — the reconciliation migration folds it later.

        insertLine.run(
          returnId,
          line.source_item_id,
          line.item_id,
          line.item_name,
          line.unit_cost,
          line.quantity,
          line.amount
        );
      }

      // GL reversal — Dr AP / Cr Inventory at actual return cost, keyed to
      // the return header so void can reverse it.
      if (totalAmount > 0) {
        AccountingService.postPurchaseReturnEntry(db, {
          purchaseId: returnId,
          purchaseNo: returnNo,
          returnAmount: totalAmount,
          returnDate: data.return_date,
          userId,
        });
      }

      // Supplier credit note + ledger entry.
      const creditNoteId = this.postCreditNote(
        db, returnId, returnNo, data, totalAmount, data.return_date, userId
      );

      db.prepare('UPDATE purchase_returns SET credit_note_id = ? WHERE id = ?').run(creditNoteId, returnId);

      // Audit
      db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(
        userId,
        'CREATE',
        'PurchaseReturn',
        returnId,
        `Created purchase return ${returnNo}: ${lines.length} line(s), ${totalQty} units, ${totalAmount.toFixed(2)} total`
      );

      return this.getById(returnId, db) as PurchaseReturnHeaderRow;
    });

    return transaction();
  }

  // ------------------------------------------------------------------
  // Void — full reversal (stock + GL + credit note + ledger + audit)
  // ------------------------------------------------------------------

  static voidReturn(id: number, userId: number, reason: string, db: Database.Database): PurchaseReturnHeaderRow {
    const header = this.getById(id, db);
    if (!header) throw new Error('Purchase return not found');
    if (header.status !== 'POSTED') throw new Error('Only POSTED returns can be voided');

    const transaction = db.transaction(() => {
      const lines = header.items || [];

      for (const line of lines) {
        // Restore returned_quantity on the source document.
        if (header.source_type === 'PURCHASE' && line.source_item_id) {
          db.prepare(`UPDATE purchases SET returned_quantity = MAX(0, COALESCE(returned_quantity, 0) - ?) WHERE id = ?`)
            .run(line.quantity, line.source_item_id);
        } else if (line.source_item_id) {
          db.prepare(`UPDATE purchase_order_items SET returned_quantity = MAX(0, COALESCE(returned_quantity, 0) - ?) WHERE id = ?`)
            .run(line.quantity, line.source_item_id);
        }

        // Positive reversal movement — puts stock back (balances +
        // current_stock + adjustment entry handled by recordMovement).
        const reversal = StockMovementModel.recordMovement({
          item_id: line.item_id,
          warehouse_id: header.warehouse_id,
          movement_type: 'ADJUSTMENT',
          quantity: line.quantity,
          unit_cost: line.unit_cost,
          reference_doctype: header.return_type,
          reference_docno: header.return_no,
          remarks: `Voided return ${header.return_no}${reason ? ': ' + reason : ''}`,
          movement_date: new Date().toISOString().split('T')[0],
        }, userId, db);

        // Track the reversal movement on the return header too.
        db.prepare('UPDATE stock_movements SET purchase_return_id = ? WHERE id = ?')
          .run(id, reversal.id);

        // Restore batch coverage (add back to the newest cost layer so
        // quantity_remaining tracks stock again).
        const latest = db.prepare(`
          SELECT id FROM stock_batches
          WHERE item_id = ? AND warehouse_id = ?
          ORDER BY received_date DESC, id DESC
          LIMIT 1
        `).get(line.item_id, header.warehouse_id) as { id: number } | undefined;
        if (latest) {
          db.prepare(`UPDATE stock_batches SET quantity_remaining = quantity_remaining + ? WHERE id = ?`)
            .run(line.quantity, latest.id);
        }
      }

      // Reverse the GL entry (journal_lines voided by reference).
      AccountingService.voidJournalLinesByReference(db, 'PURCHASE_RETURN', id);

      // Reverse the supplier credit note + ledger entry.
      if (header.credit_note_id) {
        const note = db.prepare(`SELECT * FROM credit_notes WHERE id = ?`)
          .get(header.credit_note_id) as { credit_no: string; amount: number; supplier_id: number | null } | undefined;

        if (note) {
          db.prepare(`
            UPDATE credit_notes SET status = 'VOIDED', voided_at = datetime('now'), voided_by = ? WHERE id = ?
          `).run(userId, header.credit_note_id);

          if (note.supplier_id) {
            // Debit restores the supplier balance (credit note had reduced it).
            SupplierLedgerModel.createEntry({
              supplier_id: note.supplier_id,
              transaction_date: new Date().toISOString().split('T')[0],
              transaction_type: 'CREDIT_NOTE_VOID',
              reference_no: note.credit_no,
              debit: note.amount,
              credit: 0,
              description: `Void credit note ${note.credit_no} (return ${header.return_no})`,
            }, db);
          }
        }
      }

      db.prepare(`
        UPDATE purchase_returns
        SET status = 'VOIDED', voided_at = datetime('now'), voided_by = ?, voided_reason = ?
        WHERE id = ?
      `).run(userId, reason || null, id);

      db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(
        userId,
        'VOID',
        'PurchaseReturn',
        id,
        `Voided purchase return ${header.return_no}${reason ? ': ' + reason : ''}`
      );

      return this.getById(id, db) as PurchaseReturnHeaderRow;
    });

    return transaction();
  }

  // ------------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------------

  private static resolveSourceNo(
    sourceType: string,
    sourceId: number,
    db: Database.Database
  ): string {
    if (sourceType === 'PURCHASE') {
      const row = db.prepare('SELECT purchase_no FROM purchases WHERE id = ?').get(sourceId) as
        { purchase_no: string } | undefined;
      if (!row) throw new Error('Purchase not found');
      return row.purchase_no;
    }
    const row = db.prepare('SELECT po_no FROM purchase_orders WHERE id = ?').get(sourceId) as
      { po_no: string } | undefined;
    if (!row) throw new Error('Purchase Order not found');
    return row.po_no;
  }

  /**
   * Create the supplier credit note + supplier ledger entry for a return.
   * Direct purchases carry only a supplier_name (no FK), so the supplier is
   * resolved by name; when no match exists the credit note is still posted
   * (supplier_id NULL) but the ledger entry is skipped.
   */
  private static postCreditNote(
    db: Database.Database,
    returnId: number,
    returnNo: string,
    data: CreatePurchaseReturnDTO,
    totalAmount: number,
    creditDate: string,
    userId: number
  ): number {
    let supplierId: number | null = null;

    if (data.source_type === 'PURCHASE_ORDER') {
      const po = db.prepare('SELECT supplier_id FROM purchase_orders WHERE id = ?')
        .get(data.source_id) as { supplier_id: number } | undefined;
      supplierId = po?.supplier_id ?? null;
    } else {
      const purchase = db.prepare('SELECT supplier_name FROM purchases WHERE id = ?')
        .get(data.source_id) as { supplier_name: string | null } | undefined;
      if (purchase?.supplier_name) {
        const supplier = db.prepare(`
          SELECT id FROM suppliers WHERE supplier_name = ? COLLATE NOCASE LIMIT 1
        `).get(purchase.supplier_name) as { id: number } | undefined;
        supplierId = supplier?.id ?? null;
      }
    }

    const creditNo = this.generateCreditNo(db);
    const result = db.prepare(`
      INSERT INTO credit_notes (
        credit_no, credit_date, supplier_id, source_type, source_id,
        amount, status, posted_by
      ) VALUES (?, ?, ?, 'PURCHASE_RETURN', ?, ?, 'POSTED', ?)
    `).run(creditNo, creditDate, supplierId, returnId, totalAmount, userId);
    const creditNoteId = result.lastInsertRowid as number;

    if (supplierId) {
      SupplierLedgerModel.createEntry({
        supplier_id: supplierId,
        transaction_date: creditDate,
        transaction_type: 'CREDIT_NOTE',
        reference_no: creditNo,
        debit: 0,
        credit: totalAmount,
        description: `Credit note ${creditNo} for return ${returnNo}`,
      }, db);
    } else {
      // No resolvable supplier — document still posted, ledger skipped.
      const name = data.source_type === 'PURCHASE'
        ? (db.prepare('SELECT supplier_name FROM purchases WHERE id = ?').get(data.source_id) as { supplier_name?: string }).supplier_name
        : `supplier ${(db.prepare('SELECT supplier_id FROM purchase_orders WHERE id = ?').get(data.source_id) as { supplier_id?: number }).supplier_id}`;
      logger.warn(`[PurchaseReturn] Credit note ${creditNo} posted without supplier ledger entry (unresolved supplier: ${name ?? 'none'})`);
    }

    return creditNoteId;
  }
}

export default PurchaseReturnModel;
