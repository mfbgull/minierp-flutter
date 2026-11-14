import Database from 'better-sqlite3';
import SupplierLedgerModel from './SupplierLedger';
import AccountingService from '../services/accountingService';
import logger from '../utils/logger';
import { generateDocNo } from '../utils/sequence';
import { assertCashTimeline } from '../services/cashBalanceGuard';
import { roundCurrency } from '../utils/currency';
import { claimRemaining, RefundClaimRow, SupplierRefundClaimModel } from './SupplierRefundClaim';
/**
 * SupplierRefundModel — refund RECEIPT: the cash event that settles a
 * supplier refund claim (PRET-002) or a legacy credit-note payout.
 *
 * A `refund_expected` return creates a CLAIM (expected → received — no
 * GL). This model records the supplier actually paying the money back:
 *
 *   - supplier_ledger REFUND_RECEIPT debit  (reduces the credit; legacy
 *     rows keep SUPPLIER_REFUND)
 *   - GL  Dr Cash/Bank / Cr AP (2000)  (the CN already posted Dr AP /
 *     Cr Inventory, so this collects the refund in cash)
 *   - the receipt allocates to the claim (refund_receipt_allocations);
 *     void releases the allocation and falls the claim back
 *   - void lifecycle: reverses ledger + GL + allocation, restores the
 *     credit note
 *
 * Payment methods are cash | bank only (D19 PRET-002). Wallets were
 * accepted historically; new receipts reject them.
 *
 * Runs inside the caller's transaction where one exists.
 */

export interface CreateSupplierRefundDTO {
  refund_date: string;        // YYYY-MM-DD
  credit_note_id?: number;    // required unless claim_id identifies a standalone claim
  claim_id?: number;          // allocate the receipt to this claim (defaults to the note's live claim)
  amount: number;
  payment_method?: string;    // cash | bank
  reference_no?: string;
  /** Allow an amount above the claim/note room: the overage rides on the
   * same entry as supplier credit (Cr AP) instead of being refused. */
  treat_excess_as_advance?: boolean;
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
  /** Only receipts allocated to this claim (BUG-008). The link is
   * refund_receipt_allocations — supplier_refunds has no claim_id column. */
  claim_id?: number;
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
  const note = db.prepare<[number], { amount: number; status: string; source_type: string; source_id: number }>(`
    SELECT cn.amount, cn.status, pr.source_type, pr.source_id
    FROM credit_notes cn JOIN purchase_returns pr ON pr.id = cn.source_id
    WHERE cn.id = ? AND cn.source_type = 'PURCHASE_RETURN'
  `).get(creditNoteId);
  if (!note || note.status !== 'POSTED') return 0;

  const paid = note.source_type === 'PURCHASE'
    ? db.prepare<[number], { amount: number }>(`
        SELECT COALESCE(SUM(a.amount), 0) AS amount
        FROM purchase_allocations a JOIN payments p ON p.id = a.payment_id
        WHERE a.purchase_id = ? AND a.voided_at IS NULL AND p.voided_at IS NULL
      `).get(note.source_id)
    : db.prepare<[number], { amount: number }>(`
        SELECT COALESCE(SUM(a.amount), 0) AS amount
        FROM po_allocations a JOIN payments p ON p.id = a.payment_id
        WHERE a.po_id = ? AND a.voided_at IS NULL AND p.voided_at IS NULL
      `).get(note.source_id);
  const refunded = db.prepare<{ note: number; type: string; source: number }, { note_paid: number; source_paid: number }>(`
    SELECT COALESCE(SUM(CASE WHEN sr.credit_note_id = @note THEN sr.amount ELSE 0 END), 0) AS note_paid,
      COALESCE(SUM(sr.amount), 0) AS source_paid
    FROM supplier_refunds sr JOIN purchase_returns pr ON pr.id = sr.return_id
    WHERE sr.status = 'POSTED' AND pr.source_type = @type AND pr.source_id = @source
  `).get({ note: creditNoteId, type: note.source_type, source: note.source_id });

  return roundCurrency(Math.max(0, Math.min(
    note.amount - (refunded?.note_paid ?? 0), (paid?.amount ?? 0) - (refunded?.source_paid ?? 0),
  )));
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
    // A receipt reaches a claim only through its allocation row. The EXISTS
    // form keeps the row count right; a JOIN would multiply rows when one
    // receipt were ever split across claims.
    if (filters.claim_id) {
      where += ` AND EXISTS (SELECT 1 FROM refund_receipt_allocations a
        WHERE a.receipt_id = sr.id AND a.claim_id = ?)`;
      params.push(filters.claim_id);
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

  /** Resolve the explicit claim_id reference (cancelled / note-mismatch guards). */
  private static resolveExplicitClaim(
    claimId: number | undefined,
    creditNoteId: number | undefined,
    db: Database.Database
  ): RefundClaimRow | undefined {
    if (!claimId) return undefined;
    const claim = SupplierRefundClaimModel.getById(claimId, db);
    if (!claim) throw new Error(`Refund claim ${claimId} not found`);
    if (claim.status === 'CANCELLED') {
      throw new Error(`Refund claim ${claim.claim_no} is cancelled`);
    }
    if (creditNoteId && claim.credit_note_id && claim.credit_note_id !== creditNoteId) {
      throw new Error(`Refund claim ${claim.claim_no} belongs to credit note ${claim.credit_note_id}, not ${creditNoteId}`);
    }
    return claim;
  }

  /** Resolve the credit note reference and validate it is refundable. */
  private static resolveNote(claim: RefundClaimRow | undefined, data: CreateSupplierRefundDTO, db: Database.Database): CreditNoteRow | undefined {
    const noteId = claim?.credit_note_id ?? data.credit_note_id;
    if (!noteId) {
      if (!claim) throw new Error('A credit_note_id or claim_id is required');
      return undefined;
    }
    const note = db.prepare(`SELECT * FROM credit_notes WHERE id = ?`)
      .get(noteId) as CreditNoteRow | undefined;
    if (!note) throw new Error(`Credit note ${noteId} not found`);
    if (note.status !== 'POSTED') {
      throw new Error(`Credit note ${note.credit_no} is not POSTED — cannot refund`);
    }
    if (!note.supplier_id) {
      throw new Error(`Credit note ${note.credit_no} has no resolvable supplier — cannot refund`);
    }
    return note;
  }

  /** Resolve note + claim from explicit ids, binding a note to its live claim. */
  private static resolveNoteAndClaim(
    data: CreateSupplierRefundDTO,
    db: Database.Database
  ): { note?: CreditNoteRow; claim: RefundClaimRow | undefined; supplierId: number } {
    const claim = this.resolveExplicitClaim(data.claim_id, data.credit_note_id, db);
    const note = this.resolveNote(claim, data, db);

    const supplierId = note?.supplier_id ?? claim!.supplier_id;
    if (claim && claim.supplier_id !== supplierId) {
      throw new Error(`Refund claim ${claim.claim_no} belongs to a different supplier`);
    }

    // A note without an explicit claim binds to its live claim (a
    // refund_expected note always carries one) so the caps below see it.
    const boundClaim = claim ?? (note ? SupplierRefundClaimModel.getByCreditNoteId(note.id, db) : undefined);

    return { note, claim: boundClaim, supplierId };
  }

  /** Caps: allocatable = min(note refundable, claim remaining); overage refused or booked as excess. */
  private static computeAllocation(
    amount: number,
    note: CreditNoteRow | undefined,
    claim: RefundClaimRow | undefined,
    treatExcess: boolean | undefined,
    db: Database.Database
  ): { allocatable: number; excess: number; allocated: number } {
    const noteCap = note ? creditNoteRefundable(note.id, db) : Infinity;
    const claimCap = claim ? claimRemaining(claim) : Infinity;
    const allocatable = roundCurrency(Math.min(noteCap, claimCap));
    let excess = 0;
    if (amount > allocatable + 0.005) {
      if (!treatExcess) {
        if (claim) {
          throw new Error(
            `Amount (${amount.toFixed(2)}) exceeds the remaining balance ` +
            `(${allocatable.toFixed(2)}) on claim ${claim.claim_no}. Record the balance due, ` +
            `or use "treat excess as advance".`
          );
        }
        throw new Error(
          `Refund amount (${amount.toFixed(2)}) exceeds the refundable credit ` +
          `(${allocatable.toFixed(2)}) on ${note!.credit_no}`
        );
      }
      excess = roundCurrency(amount - allocatable);
    }
    const allocated = roundCurrency(Math.min(amount, Math.max(0, allocatable)));
    return { allocatable, excess, allocated };
  }

  /** Validate create input; returns the resolved amount. */
  private static validateCreateRequest(data: CreateSupplierRefundDTO): number {
    if (!data.refund_date) throw new Error('refund_date is required');
    const amount = Number(data.amount);
    if (!amount || amount <= 0) throw new Error('Refund amount must be positive');
    const paymentMethod = (data.payment_method || 'cash').toLowerCase().trim();
    if (paymentMethod !== 'cash' && paymentMethod !== 'bank') {
      throw new Error('Refund receipts accept Cash or Bank transfer only');
    }
    return amount;
  }

  /** Post ledger mirror, GL entry and activity log for a refund receipt. */
  private static postReceiptEffects(args: {
    db: Database.Database; userId: number; refundId: number; refundNo: string;
    supplierId: number; refundDate: string; amount: number;
    cashCode: string; cashAccountId: number;
    claim: RefundClaimRow | undefined; note: CreditNoteRow | undefined;
  }): void {
    const { db, userId, refundId, refundNo, supplierId, refundDate, amount, cashCode, cashAccountId, claim, note } = args;

    // Supplier ledger: debit restores the balance the credit note reduced.
    SupplierLedgerModel.createEntry({
      supplier_id: supplierId,
      transaction_date: refundDate,
      transaction_type: 'REFUND_RECEIPT',
      reference_no: refundNo,
      debit: amount,
      credit: 0,
      description: claim
        ? `Refund receipt ${refundNo} on claim ${claim.claim_no}`
        : `Supplier refund ${refundNo} against credit note ${note?.credit_no}`,
    }, db);
    SupplierLedgerModel.rebuildBalances(supplierId, db);

    // GL: Dr Cash (refund collected) / Cr AP (clears the credit balance).
    const ap = AccountingService.getAccountByCode(db, '2000');
    if (!ap) {
      throw new Error('Chart of accounts is missing required account: 2000 (AP)');
    }
    AccountingService.postEntry(db, {
      entry_date: refundDate,
      description: `Refund receipt ${refundNo} — ${amount.toFixed(2)} (${cashCode})`,
      reference_type: 'REFUND_RECEIPT',
      reference_id: refundId,
      created_by: userId,
      lines: [
        { account_id: cashAccountId, debit: amount, description: `Cash received via refund ${refundNo}` },
        { account_id: ap.id, credit: amount, description: `AP settled by refund ${refundNo}` },
      ],
    });

    db.prepare(`
      INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
      VALUES (?, ?, ?, ?, ?)
    `).run(
      userId, 'CREATE', 'SupplierRefund', refundId,
      claim
        ? `Recorded refund receipt ${refundNo}: ${amount.toFixed(2)} on claim ${claim.claim_no}`
        : `Issued supplier refund ${refundNo}: ${amount.toFixed(2)} against credit note ${note?.credit_no}`
    );
  }

  static create(
    data: CreateSupplierRefundDTO,
    userId: number,
    db: Database.Database
  ): SupplierRefundRow & { excess: number } {
    const amount = this.validateCreateRequest(data);
    const paymentMethod = (data.payment_method || 'cash').toLowerCase().trim();

    const { note, claim, supplierId } = this.resolveNoteAndClaim(data, db);
    const { excess, allocated } = this.computeAllocation(
      amount, note, claim, data.treat_excess_as_advance, db
    );

    const refundNo = generateDocNo(db, 'SR');

    // Cash account for the method the supplier pays back on.
    const cashCode = AccountingService._cashOrBankAccountCode(paymentMethod);
    const cashAccount = AccountingService.getAccountByCode(db, cashCode);
    if (!cashAccount) {
      throw new Error(`Chart of accounts is missing required account: ${cashCode}`);
    }

    const result = db.prepare(`
      INSERT INTO supplier_refunds (
        refund_no, refund_date, supplier_id, credit_note_id, return_id,
        amount, payment_method, reference_no, status, created_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'POSTED', ?)
    `).run(
      refundNo,
      data.refund_date,
      supplierId,
      note?.id ?? null,
      note?.source_id ?? claim?.return_id ?? null,
      amount,
      paymentMethod,
      data.reference_no || null,
      userId
    );
    const refundId = result.lastInsertRowid as number;

    // Claim allocation — the receipt advances the claim toward RECEIVED.
    // The excess (if any) is supplier credit on account, not claim room.
    const claimId = claim?.id;
    if (claimId) {
      SupplierRefundClaimModel.applyReceipt(claimId, refundId, allocated, db);
    }

    this.postReceiptEffects({
      db, userId, refundId, refundNo, supplierId, refundDate: data.refund_date,
      amount, cashCode, cashAccountId: cashAccount.id, claim, note,
    });

    return { ...this.getById(refundId, db), excess } as SupplierRefundRow & { excess: number };
  }

  static void(id: number, userId: number, reason: string, db: Database.Database): SupplierRefundRow {
    return db.transaction(() => {
      const refund = this.getById(id, db);
      if (!refund) throw new Error('Supplier refund not found');
      if (refund.status !== 'POSTED') throw new Error('Only POSTED refunds can be voided');
      AccountingService.assertPeriodNotClosed(db, refund.refund_date, `Supplier refund ${refund.refund_no}`);

      // Legacy rows posted as SUPPLIER_REFUND; PRET-002 receipts post as
      // REFUND_RECEIPT. Void whatever this row actually posted.
      const glType = (db.prepare(`
        SELECT DISTINCT reference_type FROM journal_lines
        WHERE reference_type IN ('SUPPLIER_REFUND', 'REFUND_RECEIPT')
          AND reference_id = ?
      `).get(id) as { reference_type: string } | undefined)?.reference_type ?? 'REFUND_RECEIPT';
      const ledgerVoidType = glType === 'SUPPLIER_REFUND' ? 'SUPPLIER_REFUND_VOID' : 'REFUND_RECEIPT_VOID';

      // Release the claim allocation first so the claim falls back to its
      // un-collected state (EXPECTED / PARTIAL) as the cash reverses.
      SupplierRefundClaimModel.releaseReceipt(id, db);

      AccountingService.voidJournalLinesByReference(db, glType, id, {
        voidedBy: userId,
        voidReason: reason || 'Supplier refund voided',
      });
      assertCashTimeline(db, { paymentMethod: refund.payment_method, fromDate: refund.refund_date });

      db.prepare(`
        UPDATE supplier_refunds
        SET status = 'VOIDED', voided_at = datetime('now'), voided_by = ?, voided_reason = ?
        WHERE id = ?
      `).run(userId, reason || null, id);

      SupplierLedgerModel.createEntry({
        supplier_id: refund.supplier_id,
        transaction_date: new Date().toISOString().split('T')[0],
        transaction_type: ledgerVoidType,
        reference_no: refund.refund_no,
        debit: 0,
        credit: refund.amount,
        description: `Void refund receipt ${refund.refund_no}${reason ? ': ' + reason : ''}`,
      }, db);
      SupplierLedgerModel.rebuildBalances(refund.supplier_id, db);

      db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (?, ?, ?, ?, ?)
      `).run(
        userId, 'VOID', 'SupplierRefund', id,
        `Voided refund receipt ${refund.refund_no}${reason ? ': ' + reason : ''}`
      );

      logger.info(`Refund receipt ${refund.refund_no} voided by user ${userId}`);
      return this.getById(id, db) as SupplierRefundRow;
    })();
  }
}

export default SupplierRefundModel;
