/**
 * OverheadSettlement (D30 — "Settle overhead", Gull 2026-11-27)
 * -------------------------------------------------------------
 * One row = one payment that clears account 2200 Accrued Production
 * Overhead. Production capitalises the overhead typed into a run into the
 * stock batches and credits 2200; nothing debited it before this model, so
 * the liability grew forever even though the bill is always paid.
 *
 * The split is Gull's Q3 answer B: pay more than accrued if the real bill
 * is bigger than the estimate.
 *   accrued_amount → Dr 2200, the part that clears the liability
 *   excess_amount  → Dr 6000, the part above the estimate (a normal expense)
 *   amount_paid    → Cr Cash/Bank, the whole payment
 *
 * Only the excess is a new expense. The rest already sits inside the item's
 * stock value, so booking it again would count the same electricity twice.
 */
import Database from 'better-sqlite3';
import AccountingService from '../services/accountingService';
import { assertCashTimeline } from '../services/cashBalanceGuard';
import { getNextSequenceNumber } from '../utils/sequence';
import { localMonthCode } from '../utils/documentNumbering';
import { roundCurrency } from '../utils/currency';

interface CreateOverheadSettlementDTO {
  settlement_date: string;
  amount: number;
  payment_method: string;
  reference_note?: string;
  created_by?: number;
}

export interface OverheadSettlementRow {
  id: number;
  settlement_no: string;
  settlement_date: string;
  amount_paid: number;
  accrued_amount: number;
  excess_amount: number;
  payment_method: string;
  reference_note: string | null;
  /** Set by `create` from the posting; the table has no such column. */
  journal_entry_id?: number;
}

/** OHS-YYMM-NNNNN from the shared atomic settings counter, so two
 * concurrent settlements cannot take the same number (EXP-05 lesson). */
function generateSettlementNo(db: Database.Database, settlementDate: string): string {
  const parsed = new Date(`${settlementDate}T00:00:00`);
  const monthCode = localMonthCode(Number.isNaN(parsed.getTime()) ? new Date() : parsed, 'YYMM');
  const nextNo = getNextSequenceNumber(db, `OHS_last_no_${monthCode}`);
  return `OHS-${monthCode}-${String(nextNo).padStart(5, '0')}`;
}

function getById(db: Database.Database, id: number): OverheadSettlementRow | undefined {
  return db.prepare(`
    SELECT id, settlement_no, settlement_date, amount_paid, accrued_amount,
           excess_amount, payment_method, reference_note
    FROM overhead_settlements WHERE id = ?
  `).get(id) as OverheadSettlementRow | undefined;
}

/**
 * Create one settlement: split the payment, write the document, post the GL
 * entry and re-check the cash timeline — all inside one transaction, so a
 * refused payment leaves no row and no journal line behind.
 */
function create(db: Database.Database, data: CreateOverheadSettlementDTO): OverheadSettlementRow {
  return db.transaction(() => {
    const payable = AccountingService.getAccountByTextCode(db, 'production_overhead_payable');
    if (!payable) {
      throw new Error('Chart of accounts is missing required account: 2200 (Accrued Production Overhead)');
    }

    // What is owed as of the payment date: a payment dated before the accrual
    // cannot clear a liability that does not exist yet on that day.
    // getAccountBalance is already signed by the account's normal side, so a
    // credit-normal liability reads positive when owed.
    const balance = AccountingService.getAccountBalance(db, payable.id, data.settlement_date);
    const owed = roundCurrency(balance.balance);
    const accrued = roundCurrency(Math.min(data.amount, Math.max(owed, 0)));
    const excess = roundCurrency(data.amount - accrued);

    const settlementNo = generateSettlementNo(db, data.settlement_date);
    const info = db.prepare(`
      INSERT INTO overhead_settlements (
        settlement_no, settlement_date, amount_paid, accrued_amount,
        excess_amount, payment_method, reference_note, created_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      settlementNo,
      data.settlement_date,
      data.amount,
      accrued,
      excess,
      data.payment_method,
      data.reference_note ?? null,
      data.created_by ?? null
    );
    const settlementId = Number(info.lastInsertRowid);

    const posted = AccountingService.postOverheadSettlementEntry(db, {
      settlementId,
      settlementNo,
      settlementDate: data.settlement_date,
      amountPaid: data.amount,
      accruedAmount: accrued,
      excessAmount: excess,
      paymentMethod: data.payment_method,
      userId: data.created_by ?? null,
    });

    // ACCT-013: the payment must not drive the cash/bank account negative on
    // this or any later day. Inside the transaction, so a refused payment
    // rolls the row and the journal lines back with it.
    assertCashTimeline(db, { paymentMethod: data.payment_method, fromDate: data.settlement_date });

    const created = getById(db, settlementId);
    if (!created) throw new Error('Overhead settlement row vanished after insert');
    return { ...created, journal_entry_id: posted.journal_entry_id };
  })();
}

const OverheadSettlementModel = { generateSettlementNo, getById, create };

export default OverheadSettlementModel;
