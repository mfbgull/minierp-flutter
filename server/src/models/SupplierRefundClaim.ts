import Database from 'better-sqlite3';
import AccountingService from '../services/accountingService';
import SupplierLedgerModel from './SupplierLedger';
import { generateDocNo } from '../utils/sequence';
import { roundCurrency, addCurrency } from '../utils/currency';

/**
 * SupplierRefundClaimModel — PRET-002 one-claim-object lifecycle for money
 * a supplier owes back to the company (D19).
 *
 * A claim is created when a purchase return posts with the
 * `refund_expected` disposition (its credit note makes the supplier owe
 * the company) or standalone (overpayment, price compensation — no
 * return, no credit note).
 *
 * Lifecycle: EXPECTED → PARTIAL → RECEIVED, or CANCELLED.
 *   - Creating a claim posts NO journal lines. Cash and bank move only
 *     when a refund receipt (REFUND_RECEIPT) posts against the claim —
 *     see SupplierRefundModel.
 *   - A receipt allocates to the claim (refund_receipt_allocations) and
 *     advances received_amount; voiding the receipt releases it.
 *   - A short-paid claim is settled with a write-off: Dr 7300 Refund
 *     Write-offs / Cr AP, mandatory reason, owner (admin role) required
 *     above Rs 1,000.
 *
 * Runs inside the caller's transaction where one exists.
 */

export interface CreateRefundClaimDTO {
  supplier_id: number;
  claim_date: string;         // YYYY-MM-DD
  amount: number;             // expected total
  reason?: string;
  return_id?: number | null;
  credit_note_id?: number | null;
}

export interface RefundClaimRow {
  id: number;
  claim_no: string;
  supplier_id: number;
  supplier_name?: string;
  return_id: number | null;
  return_no?: string | null;
  credit_note_id: number | null;
  credit_no?: string | null;
  claim_date: string;
  amount: number;
  received_amount: number;
  written_off_amount: number;
  status: 'EXPECTED' | 'PARTIAL' | 'RECEIVED' | 'CANCELLED';
  reason: string | null;
  created_by: number | null;
  created_at: string;
  cancelled_at: string | null;
  cancel_reason: string | null;
  written_off_at: string | null;
  written_off_reason: string | null;
}

export const CLAIM_WRITE_OFF_APPROVAL_THRESHOLD = 1000; // Rs — owner sign-off above this

interface ClaimFilters {
  supplier_id?: number;
  status?: string;
  page?: number;
  limit?: number;
}

const CLAIM_SELECT = `
  SELECT c.*, s.supplier_name, pr.return_no, cn.credit_no
  FROM supplier_refund_claims c
  LEFT JOIN suppliers s ON s.id = c.supplier_id
  LEFT JOIN purchase_returns pr ON pr.id = c.return_id
  LEFT JOIN credit_notes cn ON cn.id = c.credit_note_id
`;

export function claimRemaining(claim: { amount: number; received_amount: number; written_off_amount: number }): number {
  return roundCurrency(claim.amount - claim.received_amount - claim.written_off_amount);
}

export class SupplierRefundClaimModel {
  static getById(id: number, db: Database.Database): RefundClaimRow | undefined {
    return db.prepare(`${CLAIM_SELECT} WHERE c.id = ?`).get(id) as RefundClaimRow | undefined;
  }

  static getByReturnId(returnId: number, db: Database.Database): RefundClaimRow | undefined {
    return db.prepare(`${CLAIM_SELECT} WHERE c.return_id = ? AND c.status <> 'CANCELLED'`)
      .get(returnId) as RefundClaimRow | undefined;
  }

  static getByCreditNoteId(creditNoteId: number, db: Database.Database): RefundClaimRow | undefined {
    return db.prepare(`${CLAIM_SELECT} WHERE c.credit_note_id = ? AND c.status <> 'CANCELLED'`)
      .get(creditNoteId) as RefundClaimRow | undefined;
  }

  static list(filters: ClaimFilters, db: Database.Database): {
    rows: RefundClaimRow[]; total: number; pageNum: number; limitNum: number;
  } {
    const page = filters.page || 1;
    const limit = filters.limit || 50;
    const offset = (page - 1) * limit;

    let where = ' WHERE 1=1';
    const params: (string | number)[] = [];
    if (filters.supplier_id) {
      where += ' AND c.supplier_id = ?';
      params.push(filters.supplier_id);
    }
    if (filters.status) {
      where += ' AND c.status = ?';
      params.push(filters.status);
    }

    const total = (db.prepare(
      `SELECT COUNT(*) AS n FROM supplier_refund_claims c${where}`
    ).get(...params) as { n: number }).n;

    const rows = db.prepare(
      `${CLAIM_SELECT}${where} ORDER BY c.claim_date DESC, c.id DESC LIMIT ? OFFSET ?`
    ).all(...params, limit, offset) as RefundClaimRow[];

    return { rows, total, pageNum: page, limitNum: limit };
  }

  /** Open (EXPECTED/PARTIAL) claims with their outstanding total — the
   * "refunds due" view. Deliberately NOT a cash figure: cash/bank move
   * only on REFUND_RECEIPT postings. */
  static refundsDue(db: Database.Database): { rows: RefundClaimRow[]; total_due: number } {
    const rows = db.prepare(`
      ${CLAIM_SELECT} WHERE c.status IN ('EXPECTED', 'PARTIAL')
      ORDER BY c.claim_date ASC, c.id ASC
    `).all() as RefundClaimRow[];
    const total_due = rows.reduce(
      (sum, r) => addCurrency(sum, claimRemaining(r)), 0,
    );
    return { rows, total_due: roundCurrency(total_due) };
  }

  /** Create a claim. No GL posting — the claim is a receivable memo, not
   * money. The credit note (return path) already posted its own entry. */
  static create(data: CreateRefundClaimDTO, userId: number, db: Database.Database): RefundClaimRow {
    if (!data.claim_date) throw new Error('claim_date is required');
    if (!data.supplier_id || data.supplier_id <= 0) throw new Error('A valid supplier_id is required');
    const amount = roundCurrency(Number(data.amount));
    if (!Number.isFinite(amount) || amount <= 0) throw new Error('Claim amount must be positive');

    const supplier = db.prepare('SELECT id FROM suppliers WHERE id = ?')
      .get(data.supplier_id) as { id: number } | undefined;
    if (!supplier) throw new Error(`Supplier ${data.supplier_id} not found`);

    const claimNo = generateDocNo(db, 'SRC');
    const result = db.prepare(`
      INSERT INTO supplier_refund_claims (
        claim_no, supplier_id, return_id, credit_note_id, claim_date,
        amount, status, reason, created_by
      ) VALUES (?, ?, ?, ?, ?, ?, 'EXPECTED', ?, ?)
    `).run(
      claimNo,
      data.supplier_id,
      data.return_id ?? null,
      data.credit_note_id ?? null,
      data.claim_date,
      amount,
      data.reason || null,
      userId,
    );
    const claimId = result.lastInsertRowid as number;

    db.prepare(`
      INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
      VALUES (?, ?, ?, ?, ?)
    `).run(
      userId, 'CREATE', 'SupplierRefundClaim', claimId,
      `Recorded refund claim ${claimNo}: ${amount.toFixed(2)} expected from supplier ${data.supplier_id}`,
    );

    return this.getById(claimId, db) as RefundClaimRow;
  }

  /** Cancel a claim. Refused while live receipts are allocated to it —
   * void those first (a purchase-return void hits the same rule via
   * PurchaseReturnModel.voidReturn). */
  static cancel(id: number, userId: number, reason: string, db: Database.Database): RefundClaimRow {
    const claim = this.getById(id, db);
    if (!claim) throw new Error('Refund claim not found');
    if (claim.status === 'CANCELLED') throw new Error('Refund claim is already cancelled');
    // A RECEIVED claim with no live allocations (legacy backfill shape) can
    // still be cancelled with its return; recorded receipts cannot.
    const liveReceipts = this.liveReceiptCount(id, db);
    if (liveReceipts > 0) {
      throw new Error(
        `Refund claim ${claim.claim_no} has ${liveReceipts} recorded receipt(s) — void the receipts first`
      );
    }

    db.prepare(`
      UPDATE supplier_refund_claims
      SET status = 'CANCELLED', cancelled_at = datetime('now'), cancelled_by = ?, cancel_reason = ?
      WHERE id = ?
    `).run(userId, reason || null, id);

    db.prepare(`
      INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
      VALUES (?, ?, ?, ?, ?)
    `).run(
      userId, 'CANCEL', 'SupplierRefundClaim', id,
      `Cancelled refund claim ${claim.claim_no}${reason ? ': ' + reason : ''}`,
    );

    return this.getById(id, db) as RefundClaimRow;
  }

  /**
   * Write off the uncollected remainder of a claim. Mandatory reason;
   * GL Dr 7300 Refund Write-offs / Cr AP. No cash moves, so no cash
   * timeline guard applies. [amount] defaults to the full remaining
   * balance; a smaller amount leaves the claim PARTIAL.
   */
  static writeOff(
    id: number,
    userId: number,
    data: { amount?: number; reason: string; write_off_date?: string },
    db: Database.Database,
  ): RefundClaimRow {
    if (!data.reason || !data.reason.trim()) {
      throw new Error('A write-off reason is required');
    }
    const claim = this.getById(id, db);
    if (!claim) throw new Error('Refund claim not found');
    if (claim.status === 'CANCELLED') throw new Error('Refund claim is cancelled');
    const remaining = claimRemaining(claim);
    if (remaining <= 0.005) throw new Error('Refund claim has no remaining balance to write off');

    const amount = data.amount === undefined ? remaining : roundCurrency(Number(data.amount));
    if (!Number.isFinite(amount) || amount <= 0) throw new Error('Write-off amount must be positive');
    if (amount > remaining + 0.005) {
      throw new Error(
        `Write-off amount (${amount.toFixed(2)}) exceeds the claim's remaining balance (${remaining.toFixed(2)})`,
      );
    }

    AccountingService.assertPeriodNotClosed(db, data.write_off_date || claim.claim_date, `Refund claim ${claim.claim_no}`);

    const writeOffAccount = AccountingService.getAccountByCode(db, '7300');
    if (!writeOffAccount) {
      throw new Error('Chart of accounts is missing required account: 7300 (Refund Write-offs)');
    }
    const ap = AccountingService.getAccountByCode(db, '2000');
    if (!ap) {
      throw new Error('Chart of accounts is missing required account: 2000 (AP)');
    }

    AccountingService.postEntry(db, {
      entry_date: data.write_off_date || claim.claim_date,
      description: `Refund claim ${claim.claim_no} write-off — ${data.reason.trim()}`,
      reference_type: 'REFUND_CLAIM_WRITE_OFF',
      reference_id: id,
      created_by: userId,
      lines: [
        { account_id: writeOffAccount.id, debit: amount, description: `Write-off ${claim.claim_no}` },
        { account_id: ap.id, credit: amount, description: `Claim ${claim.claim_no} balance written off` },
      ],
    });

    // Supplier ledger mirrors the AP movement (AP rises −70 → 0, same as
    // a receipt) so GL AP and the ledger balance stay aligned for the
    // supplier-balance invariant.
    SupplierLedgerModel.createEntry({
      supplier_id: claim.supplier_id,
      transaction_date: data.write_off_date || claim.claim_date,
      transaction_type: 'REFUND_CLAIM_WRITE_OFF',
      reference_no: claim.claim_no,
      debit: amount,
      credit: 0,
      description: `Refund claim ${claim.claim_no} written off: ${data.reason.trim()}`,
    }, db);
    SupplierLedgerModel.rebuildBalances(claim.supplier_id, db);

    db.prepare(`
      UPDATE supplier_refund_claims
      SET written_off_amount = written_off_amount + ?,
          written_off_at = datetime('now'),
          written_off_by = ?,
          written_off_reason = ?
      WHERE id = ?
    `).run(amount, userId, data.reason.trim(), id);

    this.recomputeStatus(id, db);

    db.prepare(`
      INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
      VALUES (?, ?, ?, ?, ?)
    `).run(
      userId, 'WRITE_OFF', 'SupplierRefundClaim', id,
      `Wrote off ${amount.toFixed(2)} on refund claim ${claim.claim_no}: ${data.reason.trim()}`,
    );

    return this.getById(id, db) as RefundClaimRow;
  }

  /** Link a receipt to a claim: record the allocation and advance the
   * received balance. Amount must fit the claim's remaining room —
   * excess is the controller's decision (reject or advance). */
  static applyReceipt(claimId: number, receiptId: number, amount: number, db: Database.Database): void {
    const claim = this.getById(claimId, db);
    if (!claim) throw new Error('Refund claim not found');
    if (claim.status === 'CANCELLED') throw new Error(`Refund claim ${claim.claim_no} is cancelled`);
    const remaining = claimRemaining(claim);
    const applied = roundCurrency(amount);
    if (applied > remaining + 0.005) {
      throw new Error(
        `Receipt ${applied.toFixed(2)} exceeds the remaining balance (${remaining.toFixed(2)}) on claim ${claim.claim_no}`,
      );
    }
    if (applied <= 0) return;

    db.prepare(`
      INSERT INTO refund_receipt_allocations (receipt_id, claim_id, amount)
      VALUES (?, ?, ?)
    `).run(receiptId, claimId, applied);

    db.prepare(`
      UPDATE supplier_refund_claims SET received_amount = received_amount + ? WHERE id = ?
    `).run(applied, claimId);

    this.recomputeStatus(claimId, db);
  }

  /** Receipt voided — release its allocations and fall the claim back to
   * whatever its un-collected state is (EXPECTED or PARTIAL). */
  static releaseReceipt(receiptId: number, db: Database.Database): void {
    const allocations = db.prepare(`
      SELECT claim_id, amount FROM refund_receipt_allocations WHERE receipt_id = ?
    `).all(receiptId) as Array<{ claim_id: number; amount: number }>;
    if (allocations.length === 0) return;

    db.prepare('DELETE FROM refund_receipt_allocations WHERE receipt_id = ?').run(receiptId);
    for (const a of allocations) {
      db.prepare(`
        UPDATE supplier_refund_claims SET received_amount = MAX(0, received_amount - ?) WHERE id = ?
      `).run(a.amount, a.claim_id);
      this.recomputeStatus(a.claim_id, db);
    }
  }

  /** Live receipts allocated to a claim (for void-guard checks). */
  static liveReceiptCount(claimId: number, db: Database.Database): number {
    return (db.prepare(`
      SELECT COUNT(*) AS n
      FROM refund_receipt_allocations a
      JOIN supplier_refunds sr ON sr.id = a.receipt_id AND sr.status = 'POSTED'
      WHERE a.claim_id = ?
    `).get(claimId) as { n: number }).n;
  }

  /** Recompute EXPECTED/PARTIAL/RECEIVED from the balances. CANCELLED is
   * terminal and never resurrected by recompute. */
  static recomputeStatus(claimId: number, db: Database.Database): void {
    const claim = db.prepare(
      'SELECT amount, received_amount, written_off_amount, status FROM supplier_refund_claims WHERE id = ?',
    ).get(claimId) as { amount: number; received_amount: number; written_off_amount: number; status: string } | undefined;
    if (!claim || claim.status === 'CANCELLED') return;

    const remaining = claimRemaining(claim);
    const status = remaining <= 0.005 ? 'RECEIVED' : claim.received_amount > 0.005 ? 'PARTIAL' : 'EXPECTED';
    db.prepare('UPDATE supplier_refund_claims SET status = ? WHERE id = ?').run(status, claimId);
  }
}
