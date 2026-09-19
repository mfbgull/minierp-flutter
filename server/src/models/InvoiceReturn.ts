/**
 * InvoiceReturn — row model for the first-class return documents
 * (invoice-return-spec.md §4.1 / Milestone 1).
 *
 * Pure persistence: create/read header, items, settlements. All
 * statements prepared; callers own transaction boundaries (the service
 * in Milestone 2 wraps createReturn in the invoice transaction).
 */
import type Database from 'better-sqlite3';
import { getNextSequenceNumber } from '../utils/sequence';

export interface InvoiceReturnHeader {
  id: number;
  return_no: string;
  invoice_id: number;
  customer_id: number;
  return_date: string;
  reason: string | null;
  status: 'Unsettled' | 'Settled' | 'Voided';
  fee_type: 'none' | 'fixed' | 'percentage' | null;
  fee_value: number;
  fee_amount: number;
  returned_amount: number;
  net_amount: number;
  settled_amount: number;
  warehouse_id: number | null;
  created_by: number;
  created_at: string;
  voided_at: string | null;
  voided_by: number | null;
}

export interface InvoiceReturnItemRow {
  id: number;
  return_id: number;
  invoice_item_id: number;
  item_id: number;
  quantity: number;
  unit_price: number;
  tax_amount: number;
  line_amount: number;
}

export interface ReturnSettlementRow {
  id: number;
  return_id: number;
  settlement_no: string;
  type: 'refund' | 'credit' | 'adjust';
  amount: number;
  method: string | null;
  reference: string | null;
  target_invoice_id: number | null;
  payment_id: number | null;
  settled_date: string;
  created_by: number;
  created_at: string;
  voided_at: string | null;
}

export class InvoiceReturnModel {
  /**
   * Atomic return number: RET-MMYY-NNNNN (spec D19), pattern of
   * InvoiceModel.generatePaymentNoAtomic. Numeric max sync guards the
   * string-sort trap (RET1000 vs RET999) after legacy/manual inserts.
   */
  static generateReturnNoAtomic(db: Database.Database): string {
    // Parse the 5-digit sequence AFTER the second dash ('RET-MMYY-NNNNN'):
    // SUBSTR(..., -5) takes the last 5 chars — the MMYY- segment must not
    // leak into the numeric max (CAST would stop at the dash and return
    // the month, e.g. 926, corrupting the sync).
    const maxResult = db.prepare(
      `SELECT MAX(CAST(SUBSTR(return_no, -5) AS INTEGER)) as max_val
       FROM invoice_returns WHERE return_no LIKE 'RET-%'`
    ).get() as { max_val: number | null } | undefined;
    const maxNo = maxResult?.max_val ?? 0;
    if (maxNo > 0) {
      // Both MAX() args must have the SAME storage class: SQLite's scalar
      // MAX returns the TEXT operand over an INTEGER one (TEXT > INTEGER
      // in type ordering), so MAX(2, '1') === '1' — the max-sync upsert
      // would RESET the sequence. CAST the bound param to INTEGER too.
      db.prepare(`
        INSERT INTO settings (key, value, updated_at)
        VALUES ('RET_last_no', CAST(? AS TEXT), CURRENT_TIMESTAMP)
        ON CONFLICT(key) DO UPDATE SET
          value = CAST(MAX(CAST(settings.value AS INTEGER), CAST(? AS INTEGER)) AS TEXT),
          updated_at = CURRENT_TIMESTAMP
      `).run(maxNo.toString(), maxNo.toString());
    }
    const nextNo = getNextSequenceNumber(db, 'RET_last_no');
    const now = new Date();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const year = String(now.getFullYear()).slice(-2);
    return `RET-${month}${year}-${String(nextNo).padStart(5, '0')}`;
  }

  /** Atomic credit-note number: CR-MMYY-NNNNN (used by credit settlements). */
  static generateCreditNoAtomic(db: Database.Database): string {
    // Same last-5-char parse as generateReturnNoAtomic ('CR-MMYY-NNNNN').
    const maxResult = db.prepare(
      `SELECT MAX(CAST(SUBSTR(settlement_no, -5) AS INTEGER)) as max_val
       FROM return_settlements WHERE settlement_no LIKE 'CR-%'`
    ).get() as { max_val: number | null } | undefined;
    const maxNo = maxResult?.max_val ?? 0;
    if (maxNo > 0) {
      // Same-type MAX comparison — see generateReturnNoAtomic comment.
      db.prepare(`
        INSERT INTO settings (key, value, updated_at)
        VALUES ('CR_last_no', CAST(? AS TEXT), CURRENT_TIMESTAMP)
        ON CONFLICT(key) DO UPDATE SET
          value = CAST(MAX(CAST(settings.value AS INTEGER), CAST(? AS INTEGER)) AS TEXT),
          updated_at = CURRENT_TIMESTAMP
      `).run(maxNo.toString(), maxNo.toString());
    }
    const nextNo = getNextSequenceNumber(db, 'CR_last_no');
    const now = new Date();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const year = String(now.getFullYear()).slice(-2);
    return `CR-${month}${year}-${String(nextNo).padStart(5, '0')}`;
  }

  static createReturn(
    db: Database.Database,
    args: {
      invoice_id: number;
      customer_id: number;
      return_date: string;
      reason?: string;
      fee_type?: 'none' | 'fixed' | 'percentage';
      fee_value?: number;
      fee_amount?: number;
      returned_amount: number;
      net_amount: number;
      warehouse_id?: number | null;
      created_by: number;
    }
  ): InvoiceReturnHeader {
    const returnNo = InvoiceReturnModel.generateReturnNoAtomic(db);
    db.prepare(`
      INSERT INTO invoice_returns (
        return_no, invoice_id, customer_id, return_date, reason,
        fee_type, fee_value, fee_amount, returned_amount, net_amount,
        warehouse_id, created_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      returnNo,
      args.invoice_id,
      args.customer_id,
      args.return_date,
      args.reason ?? null,
      args.fee_type ?? 'none',
      args.fee_value ?? 0,
      args.fee_amount ?? 0,
      args.returned_amount,
      args.net_amount,
      args.warehouse_id ?? null,
      args.created_by,
    );
    return InvoiceReturnModel.getByReturnNo(db, returnNo) as InvoiceReturnHeader;
  }

  static addReturnItem(
    db: Database.Database,
    args: {
      return_id: number;
      invoice_item_id: number;
      item_id: number;
      quantity: number;
      unit_price: number;
      tax_amount: number;
      line_amount: number;
    }
  ): void {
    db.prepare(`
      INSERT INTO invoice_return_items (
        return_id, invoice_item_id, item_id, quantity, unit_price, tax_amount, line_amount
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
    `).run(
      args.return_id,
      args.invoice_item_id,
      args.item_id,
      args.quantity,
      args.unit_price,
      args.tax_amount,
      args.line_amount,
    );
  }

  static createSettlement(
    db: Database.Database,
    args: {
      return_id: number;
      settlement_no: string;
      type: 'refund' | 'credit' | 'adjust';
      amount: number;
      method?: string | null;
      reference?: string | null;
      target_invoice_id?: number | null;
      payment_id?: number | null;
      settled_date: string;
      created_by: number;
    }
  ): ReturnSettlementRow {
    db.prepare(`
      INSERT INTO return_settlements (
        return_id, settlement_no, type, amount, method, reference,
        target_invoice_id, payment_id, settled_date, created_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      args.return_id,
      args.settlement_no,
      args.type,
      args.amount,
      args.method ?? null,
      args.reference ?? null,
      args.target_invoice_id ?? null,
      args.payment_id ?? null,
      args.settled_date,
      args.created_by,
    );
    // Keep the header's settled_amount (Σ rows) AND the Settled/Unsettled
    // status in sync — the settlement write is the only state transition.
    InvoiceReturnModel.syncSettledAmount(db, args.return_id);
    InvoiceReturnModel.refreshStatus(db, args.return_id);
    return db.prepare(
      'SELECT * FROM return_settlements WHERE return_id = ? AND settlement_no = ?'
    ).get(args.return_id, args.settlement_no) as ReturnSettlementRow;
  }

  /** settled_amount = Σ active settlement rows (voided excluded). */
  static syncSettledAmount(db: Database.Database, returnId: number): number {
    const sum = db.prepare(`
      SELECT COALESCE(SUM(amount), 0) AS s
      FROM return_settlements WHERE return_id = ? AND voided_at IS NULL
    `).get(returnId) as { s: number };
    db.prepare('UPDATE invoice_returns SET settled_amount = ? WHERE id = ?')
      .run(Number(sum.s), returnId);
    return Number(sum.s);
  }

  /** Mark Settled when fully settled; back to Unsettled after a void frees room. */
  static refreshStatus(db: Database.Database, returnId: number): 'Unsettled' | 'Settled' {
    const row = db.prepare(
      'SELECT net_amount, settled_amount, voided_at FROM invoice_returns WHERE id = ?'
    ).get(returnId) as { net_amount: number; settled_amount: number; voided_at: string | null };
    if (!row || row.voided_at) return 'Unsettled';
    const status = row.settled_amount >= Number(row.net_amount) - 0.005 ? 'Settled' : 'Unsettled';
    db.prepare('UPDATE invoice_returns SET status = ? WHERE id = ?').run(status, returnId);
    return status;
  }

  static getById(db: Database.Database, id: number): InvoiceReturnHeader | undefined {
    return db.prepare('SELECT * FROM invoice_returns WHERE id = ?').get(id) as InvoiceReturnHeader | undefined;
  }

  static getByReturnNo(db: Database.Database, returnNo: string): InvoiceReturnHeader | undefined {
    return db.prepare('SELECT * FROM invoice_returns WHERE return_no = ?').get(returnNo) as InvoiceReturnHeader | undefined;
  }

  static getByInvoiceId(db: Database.Database, invoiceId: number): InvoiceReturnHeader[] {
    return db.prepare(
      'SELECT * FROM invoice_returns WHERE invoice_id = ? ORDER BY id'
    ).all(invoiceId) as InvoiceReturnHeader[];
  }

  static getItems(db: Database.Database, returnId: number): InvoiceReturnItemRow[] {
    return db.prepare(
      'SELECT * FROM invoice_return_items WHERE return_id = ? ORDER BY id'
    ).all(returnId) as InvoiceReturnItemRow[];
  }

  static getSettlements(db: Database.Database, returnId: number): ReturnSettlementRow[] {
    return db.prepare(
      'SELECT * FROM return_settlements WHERE return_id = ? ORDER BY id'
    ).all(returnId) as ReturnSettlementRow[];
  }

  // ───────────────────────────────────────────────────────────────
  // Void support (spec §5.3)
  // ───────────────────────────────────────────────────────────────

  /** Active (non-voided) returns for an invoice, oldest first. */
  static getActiveByInvoiceId(db: Database.Database, invoiceId: number): InvoiceReturnHeader[] {
    return db.prepare(
      'SELECT * FROM invoice_returns WHERE invoice_id = ? AND voided_at IS NULL ORDER BY id'
    ).all(invoiceId) as InvoiceReturnHeader[];
  }

  /** Settlement rows still in effect for a return (voided excluded). */
  static getActiveSettlements(db: Database.Database, returnId: number): ReturnSettlementRow[] {
    return db.prepare(
      'SELECT * FROM return_settlements WHERE return_id = ? AND voided_at IS NULL ORDER BY id'
    ).all(returnId) as ReturnSettlementRow[];
  }

  /**
   * Void the return header: status → Voided, voided_at/by set. The
   * caller reverses the stock, GL, ledger and settlement effects first —
   * this only marks the document.
   */
  static markVoided(db: Database.Database, returnId: number, userId: number, atIso?: string): void {
    db.prepare(`
      UPDATE invoice_returns
      SET status = 'Voided', voided_at = ?, voided_by = ?
      WHERE id = ? AND voided_at IS NULL
    `).run(atIso ?? new Date().toISOString(), userId, returnId);
  }

  /**
   * Void one settlement row and re-derive the header's settled_amount /
   * status from what remains. Returns the voided row, or undefined when
   * the row does not exist or is already voided.
   */
  static voidSettlement(db: Database.Database, settlementId: number, userId: number): ReturnSettlementRow | undefined {
    const row = db.prepare('SELECT * FROM return_settlements WHERE id = ?').get(settlementId) as ReturnSettlementRow | undefined;
    if (!row || row.voided_at) return undefined;
    db.prepare(`
      UPDATE return_settlements SET voided_at = ?, voided_by = ? WHERE id = ?
    `).run(new Date().toISOString(), userId, settlementId);
    InvoiceReturnModel.syncSettledAmount(db, row.return_id);
    InvoiceReturnModel.refreshStatus(db, row.return_id);
    return row;
  }

  /** Link a returned line to the restock movement it posted. */
  static setStockMovementId(db: Database.Database, returnItemId: number, stockMovementId: number): void {
    db.prepare('UPDATE invoice_return_items SET stock_movement_id = ? WHERE id = ?')
      .run(stockMovementId, returnItemId);
  }

  /** Restock movements this return posted (void attribution). */
  static getStockMovements(db: Database.Database, returnId: number): Array<{
    return_item_id: number; stock_movement_id: number; item_id: number;
    quantity: number; warehouse_id: number | null; unit_cost: number | null;
  }> {
    return db.prepare(`
      SELECT iri.id AS return_item_id, iri.stock_movement_id, iri.item_id,
             iri.quantity, sm.warehouse_id, sm.unit_cost
      FROM invoice_return_items iri
      LEFT JOIN stock_movements sm ON sm.id = iri.stock_movement_id
      WHERE iri.return_id = ? AND iri.stock_movement_id IS NOT NULL
      ORDER BY iri.id
    `).all(returnId) as Array<{
      return_item_id: number; stock_movement_id: number; item_id: number;
      quantity: number; warehouse_id: number | null; unit_cost: number | null;
    }>;
  }
}

export default InvoiceReturnModel;
