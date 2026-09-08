import Database from 'better-sqlite3';
import SupplierLedgerModel from './SupplierLedger';
import AccountingService from '../services/accountingService';
import logger from '../utils/logger';
import { generateDocNo } from '../utils/sequence';

/**
 * SupplierRefundModel — cash payout against a supplier credit note.
 *
 * `refund_expected` on a purchase return means the supplier owes the
 * company money (the credit note drove the balance negative). This
 * model settles that receivable with real money out:
 *
 *   - supplier_ledger SUPPLIER_REFUND debit  (reduces the credit)
 *   - GL  Dr AP (2000) / Cr Cash-per-method  (mirrors postRefundEntry
 *     but on the AP side — the CN already posted Dr AP / Cr Inventory)
 *   - cash funds guard (no negative cash)
 *   - void lifecycle: reverses ledger + GL, restores the credit note
 *
 * Runs inside the caller's transaction where one exists.
 */

export interface CreateSupplierRefundDTO {
  refund_date: string;        // YYYY-MM-DD
  credit_note_id: number;
  amount: number;
  payment_method?: string;    // cash | bank | easypaisa | jazzcash | upaisa
  reference_no?: string;
}

export interface SupplierRefundRow {
  id: number;
  refund_no: string;
  refund_date: string;
  supplier_id: number;
  supplier_name?: string;
  credit_note_id: number;
  credit_no?: string;
  return_id: number | null;
  amount: number;
  payment_method: string;
  reference_no: string | null;
  status: string;
  voided_at: string | null;
  voided_by: number | null;
  voided_reason: string | null;
  created_by: number | null;
  created_at: string;
}

interface RefundFilters {
  supplier_id?: number;
  page?: number;
  limit?: number;
}

interface CreditNoteRow {
  id: number;
  credit_no: string;
  supplier_id: number | null;
  amount: number;
  status: string;
  source_id: number | null;
}

const REFUND_SELECT = `
  SELECT sr.*, s.supplier_name, cn.credit_no
  FROM supplier_refunds sr
  LEFT JOIN suppliers s ON s.id = sr.supplier_id
  LEFT JOIN credit_notes cn ON cn.id = sr.credit_note_id
`;

/** Amount of a credit note not yet paid out (excludes voided refunds). */
export function creditNoteRefundable(creditNoteId: number, db: Database.Database): number {
  const note = db.prepare(`SELECT amount, status FROM credit_notes WHERE id = ?`)
    .get(creditNoteId) as { amount: number; status: string } | undefined;
  if (!note || note.status !== 'POSTED') return 0;

  const refunded = db.prepare(`
    SELECT COALESCE(SUM(amount), 0) AS paid FROM supplier_refunds
    WHERE credit_note_id = ? AND status = 'POSTED'
  `).get(creditNoteId) as { paid: number };

  return Number(note.amount) - Number(refunded.paid);
}

class SupplierRefundModel {

  static getAll(filters: RefundFilters, db: Database.Database): {
    rows: SupplierRefundRow[]; total: number; pageNum: number; limitNum: number;
  } {
    const page = filters.page || 1;
    const limit = filters.limit || 10;
    const offset = (page - 1) * limit;

    let where = ' WHERE 1=1';
    const params: (string | number)[] = [];
    if (filters.supplier_id) {
      where += ' AND sr.supplier_id = ?';
      params.push(filters.supplier_id);
    }

    const total = (db.prepare(
      `SELECT COUNT(*) AS n FROM supplier_refunds sr${where}`
    ).get(...params) as { n: number }).n;

    const rows = db.prepare(
      `${REFUND_SELECT}${where} ORDER BY sr.refund_date DESC, sr.id DESC LIMIT ? OFFSET ?`
    ).all(...params, limit, offset) as SupplierRefundRow[];

    return { rows, total, pageNum: page, limitNum: limit };
  }

  static getById(id: number, db: Database.Database): SupplierRefundRow | undefined {
    return db.prepare(`${REFUND_SELECT} WHERE sr.id = ?`).get(id) as
      SupplierRefundRow | undefined;
  }

  static create(
    data: CreateSupplierRefundDTO,
    userId: number,
    db: Database.Database
  ): SupplierRefundRow {
    if (!data.refund_date) throw new Error('refund_date is required');
    const amount = Number(data.amount);
    if (!amount || amount <= 0) throw new Error('Refund amount must be positive');

    const note = db.prepare(`SELECT * FROM credit_notes WHERE id = ?`)
      .get(data.credit_note_id) as CreditNoteRow | undefined;
    if (!note) throw new Error(`Credit note ${data.credit_note_id} not found`);
    if (note.status !== 'POSTED') {
      throw new Error(`Credit note ${note.credit_no} is not POSTED — cannot refund`);
    }
    if (!note.supplier_id) {
      throw new Error(`Credit note ${note.credit_no} has no resolvable supplier — cannot refund`);
    }

    const refundable = creditNoteRefundable(note.id, db);
    if (amount > refundable + 0.005) {
      throw new Error(
        `Refund amount (${amount.toFixed(2)}) exceeds the refundable credit ` +
        `(${refundable.toFixed(2)}) on ${note.credit_no}`
      );
    }

    const paymentMethod = data.payment_method || 'cash';
    const refundNo = generateDocNo(db, 'SR');

    // Funds guard — refunds are cash-out, same primitive expenses use.
    const cashCode = AccountingService._cashOrBankAccountCode(paymentMethod);
    const cashAccount = AccountingService.getAccountByCode(db, cashCode);
    if (!cashAccount) {
      throw new Error(`Chart of accounts is missing required account: ${cashCode}`);
    }
    AccountingService.assertSufficientFunds(db, {
      accountId: cashAccount.id,
      amount,
      asOfDate: data.refund_date,
      label: `supplier refund ${refundNo}`,
    });

    const result = db.prepare(`
      INSERT INTO supplier_refunds (
        refund_no, refund_date, supplier_id, credit_note_id, return_id,
        amount, payment_method, reference_no, status, created_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'POSTED', ?)
    `).run(
      refundNo,
      data.refund_date,
      note.supplier_id,
      note.id,
      note.source_id,
      amount,
      paymentMethod,
      data.reference_no || null,
      userId
    );
    const refundId = result.lastInsertRowid as number;

    // Supplier ledger: debit restores the balance the credit note reduced.
    SupplierLedgerModel.createEntry({
      supplier_id: note.supplier_id,
      transaction_date: data.refund_date,
      transaction_type: 'SUPPLIER_REFUND',
      reference_no: refundNo,
      debit: amount,
      credit: 0,
      description: `Supplier refund ${refundNo} against credit note ${note.credit_no}`,
    }, db);
    SupplierLedgerModel.rebuildBalances(note.supplier_id, db);

    // GL: Dr AP (settles the CN's Dr AP leg with cash) / Cr Cash.
    const ap = AccountingService.getAccountByCode(db, '2000');
    if (!ap) {
      throw new Error('Chart of accounts is missing required account: 2000 (AP)');
    }
    AccountingService.postEntry(db, {
      entry_date: data.refund_date,
      description: `Supplier refund ${refundNo} — ${amount.toFixed(2)} (${cashCode})`,
      reference_type: 'SUPPLIER_REFUND',
      reference_id: refundId,
      created_by: userId,
      lines: [
        { account_id: ap.id, debit: amount, description: `AP settled by refund ${refundNo}` },
        { account_id: cashAccount.id, credit: amount, description: `Cash paid via refund ${refundNo}` },
      ],
    });

    db.prepare(`
      INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
      VALUES (?, ?, ?, ?, ?)
    `).run(
      userId, 'CREATE', 'SupplierRefund', refundId,
      `Issued supplier refund ${refundNo}: ${amount.toFixed(2)} against credit note ${note.credit_no}`
    );

    return this.getById(refundId, db) as SupplierRefundRow;
  }

  static void(id: number, userId: number, reason: string, db: Database.Database): SupplierRefundRow {
    const refund = this.getById(id, db);
    if (!refund) throw new Error('Supplier refund not found');
    if (refund.status !== 'POSTED') throw new Error('Only POSTED refunds can be voided');

    db.prepare(`
      UPDATE supplier_refunds
      SET status = 'VOIDED', voided_at = datetime('now'), voided_by = ?, voided_reason = ?
      WHERE id = ?
    `).run(userId, reason || null, id);

    // Reverse the ledger debit (credit side) + rebuild the balance chain.
    SupplierLedgerModel.createEntry({
      supplier_id: refund.supplier_id,
      transaction_date: new Date().toISOString().split('T')[0],
      transaction_type: 'SUPPLIER_REFUND_VOID',
      reference_no: refund.refund_no,
      debit: 0,
      credit: refund.amount,
      description: `Void supplier refund ${refund.refund_no}${reason ? ': ' + reason : ''}`,
    }, db);
    SupplierLedgerModel.rebuildBalances(refund.supplier_id, db);

    // Reverse the GL entry by reference.
    AccountingService.voidJournalLinesByReference(db, 'SUPPLIER_REFUND', id);

    db.prepare(`
      INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
      VALUES (?, ?, ?, ?, ?)
    `).run(
      userId, 'VOID', 'SupplierRefund', id,
      `Voided supplier refund ${refund.refund_no}${reason ? ': ' + reason : ''}`
    );

    logger.info(`Supplier refund ${refund.refund_no} voided by user ${userId}`);
    return this.getById(id, db) as SupplierRefundRow;
  }
}

export default SupplierRefundModel;
