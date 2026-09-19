/**
 * InvoiceReturnService — the single orchestrator for the reworked invoice
 * return flow (invoice-return-spec.md §5). Desktop and mobile controllers
 * both delegate here so the formulas, caps and dispositions cannot diverge
 * (spec §5.3 / D17).
 *
 * Ledger model (spec §7, D14):
 *   - A return posts ONE customer-ledger row: type RETURN, CREDIT = net
 *     (gross − fee), dated TODAY (back-dated returns must not rewrite the
 *     running-balance chain), reference = the RET- number.
 *   - A refund settlement posts a REFUND DEBIT (reference = refund payment
 *     no), a negative payment + negative allocation, and the Dr AR / Cr
 *     Cash-Bank GL entry.
 *   - A credit settlement converts part of the ledger credit into STORE
 *     credit: a CR-numbered CREDIT DEBIT plus customers.credit_balance.
 *     The consuming debit keeps the ledger net equal to the still-unsettled
 *     refund due, so voiding the settlement frees the cap exactly
 *     (scenario 17) and AR (GL) keeps agreeing with the customer ledger.
 *   - An adjust settlement applies the credit to another invoice as a
 *     plain payment + allocation — that is how that invoice's balance is
 *     reduced, and it needs no ledger row: the return's RETURN credit is
 *     the funding source, so a second credit row here would double count.
 *     The carryover beyond the target's balance stays as a customer ledger
 *     credit (D7).
 *
 * Money is never double counted: refund + credit + adjust together share
 * one pool bounded by the invoice-level cumulative cap (§3.4 / D18).
 */
import type Database from 'better-sqlite3';
import db from '../config/database';
import { AccountingService } from './accountingService';
import {
  computeReturnedLine,
  resolveFee,
  computePosition,
  validateAllocations,
  type FeeType,
  type InvoicePosition,
  type ReturnedLine,
} from './returnMath';
import InvoiceReturnModel, {
  type InvoiceReturnHeader,
  type ReturnSettlementRow,
} from '../models/InvoiceReturn';
import InvoiceModel from '../models/Invoice';
import PaymentModel from '../models/Payment';
import StockMovementModel from '../models/StockMovement';
import ledgerUtils from '../utils/ledgerUtils';
import { parseCurrency, roundCurrency } from '../utils/currency';
import { todayLocal } from '../utils/reportSql';
import { isFeatureEnabled } from '../utils/featureFlags';
import { logCRUD, newCorrelationId } from './activityLogger';

const {
  createLedgerEntry,
  reverseLedgerEntry,
  calculateInvoiceBalance,
  updateInvoiceStatus,
  recalcCustomerBalanceFromLedger,
} = ledgerUtils;

// ────────────────────────────────────────────────────────────────────────
// Public types
// ────────────────────────────────────────────────────────────────────────

export interface SettlementInput {
  type: 'refund' | 'credit' | 'adjust';
  amount: number;
  /** refund only: Cash | Bank | Card … (D8 — a real cash/bank account). */
  method?: string | null;
  /** adjust only: which invoice the credit settles; auto-picked when omitted (D7). */
  target_invoice_id?: number | null;
}

export interface ProcessReturnInput {
  invoiceId: number;
  items: Array<{ invoice_item_id: number; return_quantity: number }>;
  feeType?: FeeType;
  feeValue?: number;
  /** 'YYYY-MM-DD'; defaults to today (D14). */
  returnDate?: string | null;
  warehouseId?: number | null;
  reason?: string | null;
  /** New explicit settlements (spec §5.1 step 8). Omit → leave Unsettled. */
  settlements?: SettlementInput[] | null;
  userId: number;

  // Legacy aliases (spec §10 shim) — honoured only when `settlements` is
  // absent, so existing desktop/mobile clients keep working unchanged.
  disposition?: 'refund' | 'credit' | 'adjust' | null;
  adjustInvoiceIds?: number[] | null;
  deductionType?: 'fixed' | 'percentage' | 'flat' | null;
  deductionValue?: number;
}

export interface SettlementRecord {
  id: number;
  settlement_no: string;
  type: 'refund' | 'credit' | 'adjust';
  amount: number;
  method: string | null;
  reference: string | null;
  target_invoice_id: number | null;
  payment_id: number | null;
}

export interface ProcessReturnResult {
  returnId: number;
  returnNo: string;
  status: string;
  returnedAmount: number;
  feeAmount: number;
  netAmount: number;
  settledAmount: number;
  settlements: SettlementRecord[];
  position: InvoicePosition;
  // Legacy response aliases (spec §10) — the pre-rework client reads these.
  disposition?: 'refund' | 'credit' | 'adjust';
  returnAmount: number;
  deduction: number;
  netReturn: number;
  refundAmount: number;
  retainedCredit: number;
  totalItems: number;
  returnedItems: Array<{ invoice_item_id: number; item_id: number; quantity: number }>;
}
export interface ReturnDetail {
  id: number;
  return_no: string;
  return_date: string;
  reason: string | null;
  status: string;
  fee_type: string | null;
  fee_value: number;
  returned_amount: number;
  fee_amount: number;
  net_amount: number;
  settled_amount: number;
  warehouse_id: number | null;
  items: Array<{
    item_id: number;
    quantity: number;
    unit_price: number;
    tax_amount: number;
    line_amount: number;
  }>;
  settlements: Array<{
    settlement_no: string;
    type: string;
    amount: number;
    method: string | null;
    reference: string | null;
    settled_date: string;
  }>;
}

export interface TimelineEvent {
  type: 'INVOICE' | 'PAYMENT' | 'RETURN' | 'RESTOCKING_FEE' | 'SETTLEMENT';
  reference: string;
  amount: number;
  date: string;
}

/**
 * Typed API error: the controllers map `status` to the HTTP status and the
 * message is user-facing (no stack leakage, spec §5.4).
 */
export class ReturnError extends Error {
  constructor(
    public status: number,
    message: string,
  ) {
    super(message);
    this.name = 'ReturnError';
  }
}

interface PostedSettlement {
  record: SettlementRecord;
  /** amount actually applied (an adjust may be capped by the target balance). */
  appliedAmount: number;
}

// ────────────────────────────────────────────────────────────────────────
// Service
// ────────────────────────────────────────────────────────────────────────

export class InvoiceReturnService {
  // ======================================================================
  // 1. PROCESS A RETURN (spec §5.1)
  // ======================================================================

  static processReturn(input: ProcessReturnInput): ProcessReturnResult {
    if (!input.items || input.items.length === 0) {
      throw new ReturnError(400, 'Invalid request: items must be a non-empty array');
    }

    const invoice = InvoiceModel.getById(input.invoiceId, db);
    if (!invoice) throw new ReturnError(404, 'Invoice not found');
    if (invoice.status === 'Cancelled') {
      throw new ReturnError(400, 'Cannot return a cancelled invoice');
    }

    const returnDate = resolveReturnDate(input.returnDate);
    const warehouseId = resolveWarehouse(input.warehouseId);
    const feeType: FeeType = normalizeFeeType(input.feeType, input.deductionType);
    const feeValue = Number(input.feeValue ?? input.deductionValue ?? 0) || 0;

    // Legacy clients (no `settlements` array) keep their old disposition
    // semantics; new clients pass explicit settlements.
    const isLegacy = !input.settlements || input.settlements.length === 0;
    const legacyDisposition = isLegacy ? input.disposition ?? null : null;

    const txn = db.transaction(() => {
      // Fresh re-read INSIDE the transaction — the per-line returned_qty
      // guard must see concurrent writes (scenario 14's double-spend).
      const fresh = InvoiceModel.getById(input.invoiceId, db);
      if (!fresh) throw new ReturnError(404, 'Invoice not found');
      if (fresh.status === 'Cancelled') {
        throw new ReturnError(400, 'Cannot return a cancelled invoice');
      }

      // Locked books are never modified (D23). Today's date is always
      // allowed; only back-dated returns can be blocked.
      assertPeriodOpen(returnDate);

      // Validate each line and mirror it proportionally (§3.5).
      const lines: Array<ReturnedLine & { invoice_item_id: number; item_id: number }> = [];
      for (const line of input.items) {
        const row = db.prepare(
          `SELECT ii.id, ii.item_id, ii.quantity, ii.unit_price, ii.tax_rate,
                  ii.discount_type, ii.discount_value, ii.returned_qty,
                  i.item_name
           FROM invoice_items ii
           LEFT JOIN items i ON i.id = ii.item_id
           WHERE ii.invoice_id = ? AND ii.id = ?`
        ).get(input.invoiceId, Number(line.invoice_item_id)) as {
          id: number; item_id: number; quantity: number; unit_price: number;
          tax_rate: number | null; discount_type: string | null;
          discount_value: number | null; returned_qty: number | null;
          item_name: string | null;
        } | undefined;

        if (!row) {
          throw new ReturnError(400, `Invoice item ${line.invoice_item_id} not found`);
        }
        const returnQty = Number(line.return_quantity);
        if (!(returnQty > 0)) throw new ReturnError(400, 'Return quantity must be positive');

        const alreadyReturned = Number(row.returned_qty) || 0;
        const available = Number(row.quantity) - alreadyReturned;
        if (returnQty > available + 1e-9) {
          throw new ReturnError(
            400,
            `Return quantity (${returnQty}) exceeds available quantity (${available}) for item ${row.item_name ?? row.item_id}. Already returned: ${alreadyReturned}.`
          );
        }

        lines.push({
          invoice_item_id: row.id,
          item_id: row.item_id,
          ...computeReturnedLine({
            quantity: Number(row.quantity),
            unitPrice: Number(row.unit_price),
            taxRate: Number(row.tax_rate) || 0,
            discountType: row.discount_type ?? undefined,
            discountValue: Number(row.discount_value) || 0,
            returnQuantity: returnQty,
          }),
        });
      }

      const returnedGross = roundCurrency(lines.reduce((s, l) => s + l.returnedGross, 0));

      // Fee — always charged (D5), clamped to the returned value.
      const feeAmount = resolveFee({ feeType, feeValue, returnedValueGross: returnedGross });
      const netAmount = roundCurrency(returnedGross - feeAmount);

      if (!(returnedGross > 0)) {
        throw new ReturnError(400, 'Return has no monetary value');
      }

      // Monetary over-return guard (defense in depth beyond the line check).
      const currentReturned = Number(fresh.returned_amount || 0);
      const invoiceTotal = Number(fresh.total_amount);
      if (currentReturned + returnedGross > invoiceTotal + 0.01) {
        throw new ReturnError(
          400,
          `Cannot return more than the invoice total. Already returned: ${parseCurrency(currentReturned)}, this return: ${returnedGross}, invoice total: ${parseCurrency(invoiceTotal)}.`
        );
      }

      // Create the return document.
      const header = InvoiceReturnModel.createReturn(db, {
        invoice_id: input.invoiceId,
        customer_id: fresh.customer_id,
        return_date: returnDate,
        reason: input.reason ?? null,
        fee_type: feeType,
        fee_value: feeValue,
        fee_amount: feeAmount,
        returned_amount: returnedGross,
        net_amount: netAmount,
        warehouse_id: warehouseId,
        created_by: input.userId,
      });

      const returnItemIds: number[] = [];
      for (const line of lines) {
        InvoiceReturnModel.addReturnItem(db, {
          return_id: header.id,
          invoice_item_id: line.invoice_item_id,
          item_id: line.item_id,
          quantity: line.returnedQuantity,
          unit_price: roundCurrency(line.returnedGross / line.returnedQuantity),
          tax_amount: line.returnedTax,
          line_amount: line.returnedGross,
        });
        const inserted = db.prepare('SELECT last_insert_rowid() AS id').get() as { id: number };
        returnItemIds.push(inserted.id);
        // Track the returned quantity on the sale line (existing behaviour).
        db.prepare('UPDATE invoice_items SET returned_qty = returned_qty + ? WHERE id = ?')
          .run(line.returnedQuantity, line.invoice_item_id);
      }

      // Reverse stock — restocked into the chosen warehouse. The movement
      // ids are attributed to the returned lines so a later void can post
      // the exact equal-and-opposite movement.
      const movements = InvoiceModel.reverseStockForItems(
        db,
        lines.map((l) => ({
          item_id: l.item_id,
          quantity: l.returnedQuantity,
          unit_price: roundCurrency(l.returnedGross / l.returnedQuantity),
        })),
        fresh.invoice_no,
        input.userId,
        'RETURN',
        warehouseId ?? undefined,
      );
      movements.forEach((m) => {
        const idx = lines.findIndex((l) => l.item_id === m.item_id);
        if (idx >= 0) {
          InvoiceReturnModel.setStockMovementId(db, returnItemIds[idx], m.movement_id);
        }
      });

      // GL — separate journal entries (D20).
      AccountingService.postInvoiceReturnEntry(db, {
        returnId: header.id,
        invoiceNo: fresh.invoice_no,
        lines: lines.map((l) => ({ returnedNet: l.returnedNet, returnedTax: l.returnedTax })),
        entryDate: returnDate,
        userId: input.userId,
      });
      if (feeAmount > 0) {
        AccountingService.postReturnFeeEntry(db, {
          returnId: header.id,
          invoiceNo: fresh.invoice_no,
          feeAmount,
          entryDate: returnDate,
          userId: input.userId,
        });
      }
      const cogsAmount = computeReturnCogs(db, fresh.invoice_no, lines);
      if (cogsAmount > 0) {
        AccountingService.postCOGSReversalEntry(db, {
          invoiceId: input.invoiceId,
          invoiceNo: fresh.invoice_no,
          cogsAmount,
          entryDate: returnDate,
          userId: input.userId,
          referenceId: header.id,
        });
      }

      // Customer ledger: ONE RETURN credit for the net amount, dated today
      // (D14). The RET- number is the reference so a void can find this
      // exact row even with several returns on one invoice.
      createLedgerEntry(
        fresh.customer_id,
        todayLocal(),
        'RETURN',
        header.return_no,
        0,
        netAmount,
        `Return ${header.return_no} on Invoice ${fresh.invoice_no}` +
          (feeAmount > 0 ? ` (restocking fee ${feeAmount.toFixed(2)})` : '')
      );

      // Sync the invoice aggregates, then the balance/status.
      db.prepare(
        `UPDATE invoices SET returned_amount = returned_amount + ?, return_fee = return_fee + ? WHERE id = ?`
      ).run(returnedGross, feeAmount, input.invoiceId);
      calculateInvoiceBalance(input.invoiceId);
      updateInvoiceStatus(input.invoiceId);

      // Settlements.
      let posted: PostedSettlement[] = [];
      if (input.settlements && input.settlements.length > 0) {
        const position = InvoiceReturnService.getPosition(input.invoiceId);
        const remainder = roundCurrency(netAmount - Number(header.settled_amount));
        const validation = validateAllocations(
          input.settlements,
          remainder,
          position.remainingSettlementCapacity,
        );
        if (!validation.ok) {
          throw new ReturnError(400, validation.error ?? 'Invalid settlements');
        }
        posted = input.settlements.map((spec) =>
          InvoiceReturnService.applySettlement(db, {
            returnHeader: header,
            invoiceNo: fresh.invoice_no,
            customerId: fresh.customer_id,
            spec,
            userId: input.userId,
          })
        );
      }
      // Legacy shim (spec §10): a bare `disposition` (no `settlements`
      // array) keeps the pre-rework settlement semantics.
      if (!posted.length && legacyDisposition) {
        const legacyPosition = InvoiceReturnService.getPosition(input.invoiceId);
        if (legacyPosition.refundCreditDue > 0.005) {
          if (legacyDisposition === 'refund') {
            const legacyRefundSettlement = InvoiceReturnService.applyLegacyRefund(db, {
              returnHeader: header,
              invoiceNo: fresh.invoice_no,
              customerId: fresh.customer_id,
              netAmount,
              userId: input.userId,
            });
            if (legacyRefundSettlement) posted.push(legacyRefundSettlement);
          } else if (legacyDisposition === 'adjust') {
            posted.push(
              ...InvoiceReturnService.applyLegacyAdjust(db, {
                returnHeader: header,
                invoiceNo: fresh.invoice_no,
                customerId: fresh.customer_id,
                netAmount,
                userId: input.userId,
                targetInvoiceIds: input.adjustInvoiceIds,
              }),
            );
          }
          // Legacy 'credit' posts no settlement: the RETURN ledger row
          // already carries the credit (credit_offset consumes it, D16).
        }
      }
      // Legacy 'credit' and no-disposition both leave the return Unsettled
      // with the RETURN credit sitting on the customer ledger (spec §5.1
      // step 8; the credit_offset pool consumes it, D16).

      calculateInvoiceBalance(input.invoiceId);
      updateInvoiceStatus(input.invoiceId);
      recalcCustomerBalanceFromLedger(fresh.customer_id);

      const finalHeader = InvoiceReturnModel.getById(db, header.id) as InvoiceReturnHeader;
      const position = InvoiceReturnService.getPosition(input.invoiceId);
      const legacyRefund = posted.find((p) => p.record.type === 'refund');

      logCRUD(
        'INVOICE_RETURN',
        'Invoice',
        input.invoiceId,
        `Return ${header.return_no} processed for ${lines.length} item(s) on Invoice ${fresh.invoice_no}` +
          (posted.length ? ` — ${posted.length} settlement(s)` : ' — left unsettled'),
        input.userId,
        { returnId: header.id, returnedGross, feeAmount, netAmount },
        { correlationId: newCorrelationId() },
      );

      return {
        returnId: header.id,
        returnNo: header.return_no,
        status: finalHeader.status,
        returnedAmount: returnedGross,
        feeAmount,
        netAmount,
        settledAmount: Number(finalHeader.settled_amount),
        settlements: posted.map((p) => p.record),
        position,
        disposition: legacyDisposition ?? undefined,
        returnAmount: returnedGross,
        deduction: feeAmount,
        netReturn: netAmount,
        refundAmount: legacyRefund ? legacyRefund.appliedAmount : 0,
        retainedCredit: roundCurrency(
          netAmount - (legacyRefund ? legacyRefund.appliedAmount : 0)
        ),
        totalItems: lines.length,
        returnedItems: lines.map((l) => ({
          invoice_item_id: l.invoice_item_id,
          item_id: l.item_id,
          quantity: l.returnedQuantity,
        })),
      };
    });

    return txn();
  }

  // ======================================================================
  // 2. SETTLE A RETURN (spec §5.2)
  // ======================================================================

  static settleReturn(
    returnId: number,
    allocations: SettlementInput[],
    userId: number,
  ): ProcessReturnResult {
    const txn = db.transaction(() => {
      const ret = InvoiceReturnModel.getById(db, returnId);
      if (!ret) throw new ReturnError(404, 'Return not found');
      if (ret.voided_at) throw new ReturnError(400, 'Cannot settle a voided return');

      const invoice = InvoiceModel.getById(ret.invoice_id, db);
      if (!invoice) throw new ReturnError(404, 'Invoice not found');

      const position = InvoiceReturnService.getPosition(ret.invoice_id);
      const remainder = roundCurrency(Number(ret.net_amount) - Number(ret.settled_amount));
      const validation = validateAllocations(
        allocations,
        remainder,
        position.remainingSettlementCapacity,
      );
      if (!validation.ok) {
        throw new ReturnError(400, validation.error ?? 'Invalid allocations');
      }

      const posted = allocations.map((spec) =>
        InvoiceReturnService.applySettlement(db, {
          returnHeader: ret,
          invoiceNo: invoice.invoice_no,
          customerId: ret.customer_id,
          spec,
          userId,
        })
      );

      calculateInvoiceBalance(ret.invoice_id);
      updateInvoiceStatus(ret.invoice_id);
      recalcCustomerBalanceFromLedger(ret.customer_id);

      const finalHeader = InvoiceReturnModel.getById(db, returnId) as InvoiceReturnHeader;
      const refundTotal = posted.reduce(
        (s, p) => s + (p.record.type === 'refund' ? p.appliedAmount : 0),
        0,
      );

      logCRUD(
        'RETURN_SETTLE',
        'Invoice',
        ret.invoice_id,
        `Return ${ret.return_no} settled: ${posted
          .map((p) => `${p.record.type} ${p.appliedAmount.toFixed(2)}`)
          .join(', ')}`,
        userId,
        { returnId, allocations },
        { correlationId: newCorrelationId() },
      );

      return {
        returnId,
        returnNo: ret.return_no,
        status: finalHeader.status,
        returnedAmount: Number(ret.returned_amount),
        feeAmount: Number(ret.fee_amount),
        netAmount: Number(ret.net_amount),
        settledAmount: Number(finalHeader.settled_amount),
        settlements: posted.map((p) => p.record),
        position: InvoiceReturnService.getPosition(ret.invoice_id),
        returnAmount: Number(ret.returned_amount),
        deduction: Number(ret.fee_amount),
        netReturn: Number(ret.net_amount),
        refundAmount: refundTotal,
        retainedCredit: roundCurrency(Number(ret.net_amount) - refundTotal),
        totalItems: InvoiceReturnModel.getItems(db, returnId).length,
        returnedItems: InvoiceReturnModel.getItems(db, returnId).map((it) => ({
          invoice_item_id: it.invoice_item_id,
          item_id: it.item_id,
          quantity: Number(it.quantity),
        })),
      };
    });

    return txn();
  }

  // ======================================================================
  // 3. VOID A RETURN (spec §5.2 / §5.3)
  // ======================================================================

  static voidReturn(returnId: number, userId: number, reason?: string | null): void {
    const txn = db.transaction(() => {
      const ret = InvoiceReturnModel.getById(db, returnId);
      if (!ret) throw new ReturnError(404, 'Return not found');
      if (ret.voided_at) throw new ReturnError(400, 'Return is already voided');

      const invoice = InvoiceModel.getById(ret.invoice_id, db);
      if (!invoice) throw new ReturnError(404, 'Invoice not found');

      // 1. Void every active settlement (reverses each money leg).
      for (const settlement of InvoiceReturnModel.getActiveSettlements(db, returnId)) {
        InvoiceReturnService.revertSettlement(
          db,
          settlement,
          ret.customer_id,
          userId,
          reason ?? 'return voided',
        );
        InvoiceReturnModel.voidSettlement(db, settlement.id, userId);
      }

      // 2. Reverse the RETURN ledger row (append-only correction, ACC-14).
      revertLedgerByReference(db, {
        customerId: ret.customer_id,
        transactionType: 'RETURN',
        referenceNo: ret.return_no,
        reason: `void of return ${ret.return_no}`,
      });

      // 3. Void the GL groups keyed to this return. The COGS reversal
      //    shares the INVOICE_RETURN group by construction, so it is
      //    reversed with the return entry.
      AccountingService.voidJournalLinesByReference(db, 'INVOICE_RETURN', returnId, {
        voidedBy: userId,
        voidReason: reason ?? 'return voided',
      });
      AccountingService.voidJournalLinesByReference(db, 'RETURN_FEE', returnId, {
        voidedBy: userId,
        voidReason: reason ?? 'return voided',
      });

      // 4. Reverse the restock: the exact negative mirror of the movement
      //    this return posted, plus the proportional batch restore it
      //    made. Skip when the line has no attributed movement (the
      //    restock was skipped at return time, e.g. nothing left to return).
      for (const line of InvoiceReturnModel.getStockMovements(db, returnId)) {
        reverseRestock(db, {
          itemId: line.item_id,
          invoiceNo: invoice.invoice_no,
          restockMovementId: line.stock_movement_id,
          returnWarehouseId: ret.warehouse_id,
          userId,
          remarks: `Stock reversal — void of return ${ret.return_no}`,
        });
      }

      // 5. Restore the invoice aggregates and the returnable quantities.
      db.prepare(
        `UPDATE invoices
         SET returned_amount = MAX(0, returned_amount - ?),
             return_fee = MAX(0, return_fee - ?)
         WHERE id = ?`
      ).run(Number(ret.returned_amount), Number(ret.fee_amount), ret.invoice_id);

      for (const item of InvoiceReturnModel.getItems(db, returnId)) {
        db.prepare('UPDATE invoice_items SET returned_qty = MAX(0, returned_qty - ?) WHERE id = ?')
          .run(Number(item.quantity), item.invoice_item_id);
      }

      // 6. Mark the document voided and recompute downstream state.
      InvoiceReturnModel.markVoided(db, returnId, userId);
      calculateInvoiceBalance(ret.invoice_id);
      updateInvoiceStatus(ret.invoice_id);
      recalcCustomerBalanceFromLedger(ret.customer_id);

      logCRUD(
        'INVOICE_RETURN_VOID',
        'Invoice',
        ret.invoice_id,
        `Return ${ret.return_no} voided — GL, stock, ledger and settlements reversed`,
        userId,
        { returnId, reason: reason ?? null },
        { correlationId: newCorrelationId() },
      );
    });

    txn();
  }

  // ======================================================================
  // 4. VOID ONE SETTLEMENT (spec §5.2 / D24)
  // ======================================================================

  static voidSettlement(settlementId: number, userId: number, reason?: string | null): void {
    const txn = db.transaction(() => {
      const row = db.prepare('SELECT * FROM return_settlements WHERE id = ?')
        .get(settlementId) as ReturnSettlementRow | undefined;
      if (!row) throw new ReturnError(404, 'Settlement not found');
      if (row.voided_at) throw new ReturnError(400, 'Settlement is already voided');

      const ret = InvoiceReturnModel.getById(db, row.return_id);
      if (!ret) throw new ReturnError(404, 'Return not found');
      if (ret.voided_at) {
        throw new ReturnError(400, 'Cannot void a settlement of a voided return');
      }

      InvoiceReturnService.revertSettlement(
        db,
        row,
        ret.customer_id,
        userId,
        reason ?? 'settlement voided',
      );
      InvoiceReturnModel.voidSettlement(db, settlementId, userId);

      calculateInvoiceBalance(ret.invoice_id);
      updateInvoiceStatus(ret.invoice_id);
      recalcCustomerBalanceFromLedger(ret.customer_id);
      // The target invoice of an adjust may now be unpaid again.
      if (row.target_invoice_id) {
        calculateInvoiceBalance(row.target_invoice_id);
        updateInvoiceStatus(row.target_invoice_id);
      }

      logCRUD(
        'RETURN_SETTLEMENT_VOID',
        'Invoice',
        ret.invoice_id,
        `Settlement ${row.settlement_no} voided — ${row.type} of ${Number(row.amount).toFixed(2)} released back to the refund/credit due`,
        userId,
        { settlementId, returnId: ret.id },
        { correlationId: newCorrelationId() },
      );
    });

    txn();
  }

  // ======================================================================
  // 5. POSITION + PRINT DATA (spec §3.2 / §4.2 / §6.3)
  // ======================================================================

  /**
   * The authoritative position (spec §3.2). Aggregates come from the
   * invoice columns (maintained incrementally by this service, so returns
   * recorded before the return tables existed are not forgotten) plus the
   * settlement rows joined to non-voided returns.
   */
  static getPosition(invoiceId: number): InvoicePosition & { settledAmount: number } {
    const invoice = db.prepare(
      'SELECT total_amount, returned_amount, return_fee, credit_offset FROM invoices WHERE id = ?'
    ).get(invoiceId) as {
      total_amount: number; returned_amount: number | null;
      return_fee: number | null; credit_offset: number | null;
    } | undefined;
    if (!invoice) throw new ReturnError(404, 'Invoice not found');

    const paid = db.prepare(`
      SELECT COALESCE(SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END), 0) AS p
      FROM payment_allocations
      WHERE invoice_id = ? AND voided_at IS NULL
    `).get(invoiceId) as { p: number };

    const settled = db.prepare(`
      SELECT COALESCE(SUM(s.amount), 0) AS s
      FROM return_settlements s
      JOIN invoice_returns r ON r.id = s.return_id
      WHERE r.invoice_id = ? AND s.voided_at IS NULL AND r.voided_at IS NULL
    `).get(invoiceId) as { s: number };

    const position = computePosition({
      originalTotal: Number(invoice.total_amount),
      totalReturned: Number(invoice.returned_amount || 0),
      totalFees: Number(invoice.return_fee || 0),
      totalPaid: roundCurrency(Number(paid.p) + Number(invoice.credit_offset || 0)),
      totalSettled: Number(settled.s),
    });
    // The spec's §4.2 API field name for `totalSettled`.
    return { ...position, settledAmount: position.totalSettled };
  }

  /** Per-return history for the invoice detail / print payload (§6.3 3–5). */
  static getReturnDetails(invoiceId: number): ReturnDetail[] {
    const headers = db.prepare(`
      SELECT id, return_no, return_date, reason, status, fee_type, fee_value,
             returned_amount, fee_amount, net_amount, settled_amount, warehouse_id
      FROM invoice_returns
      WHERE invoice_id = ? AND voided_at IS NULL
      ORDER BY id
    `).all(invoiceId) as Omit<ReturnDetail, 'items' | 'settlements'>[];

    if (headers.length === 0) return [];

    const ids = headers.map((h) => h.id);
    const placeholders = ids.map(() => '?').join(',');
    const items = db.prepare(
      `SELECT return_id, item_id, quantity, unit_price, tax_amount, line_amount
       FROM invoice_return_items WHERE return_id IN (${placeholders}) ORDER BY id`
    ).all(...ids) as Array<ReturnDetail['items'][number] & { return_id: number }>;
    const settlements = db.prepare(
      `SELECT return_id, settlement_no, type, amount, method, reference,
              settled_date
       FROM return_settlements
       WHERE return_id IN (${placeholders}) AND voided_at IS NULL ORDER BY id`
    ).all(...ids) as Array<{
      return_id: number; settlement_no: string; type: string; amount: number;
      method: string | null; reference: string | null; settled_date: string;
    }>;
    return headers.map((h) => ({
      ...h,
      items: items
        .filter((i) => i.return_id === h.id)
        .map((i) => ({
          item_id: i.item_id,
          quantity: Number(i.quantity),
          unit_price: Number(i.unit_price),
          tax_amount: Number(i.tax_amount),
          line_amount: Number(i.line_amount),
        })),
      settlements: settlements
        .filter((s) => s.return_id === h.id)
        .map((s) => ({
          settlement_no: s.settlement_no,
          type: s.type,
          amount: Number(s.amount),
          method: s.method,
          reference: s.reference,
          settled_date: s.settled_date,
        })),
    }));
  }

  /**
   * Chronological transaction history built from persisted rows (§6.3 7):
   * invoice → payments → returns → fees → settlements. The type rank is
   * the tie-break for same-day events so INVOICE always leads and
   * SETTLEMENT always closes.
   */
  static getTimeline(invoiceId: number): TimelineEvent[] {
    const rows = db.prepare(`
      SELECT type, reference, amount, event_date FROM (
        SELECT 'INVOICE' AS type, invoice_no AS reference, total_amount AS amount,
               invoice_date AS event_date, 1 AS rank
        FROM invoices WHERE id = ?
        UNION ALL
        SELECT 'PAYMENT', p.payment_no, a.amount, p.payment_date, 2
        FROM payment_allocations a
        JOIN payments p ON p.id = a.payment_id
        WHERE a.invoice_id = ? AND a.voided_at IS NULL AND a.amount > 0
        UNION ALL
        SELECT 'RETURN', r.return_no, r.returned_amount, r.return_date, 3
        FROM invoice_returns r
        WHERE r.invoice_id = ? AND r.voided_at IS NULL
        UNION ALL
        SELECT 'RESTOCKING_FEE', r.return_no, r.fee_amount, r.return_date, 4
        FROM invoice_returns r
        WHERE r.invoice_id = ? AND r.voided_at IS NULL AND r.fee_amount > 0
        UNION ALL
        SELECT 'SETTLEMENT', s.settlement_no, s.amount, s.settled_date, 5
        FROM return_settlements s
        JOIN invoice_returns r ON r.id = s.return_id
        WHERE r.invoice_id = ? AND s.voided_at IS NULL AND r.voided_at IS NULL
      ) ORDER BY event_date, rank
    `).all(invoiceId, invoiceId, invoiceId, invoiceId, invoiceId) as Array<{
      type: TimelineEvent['type'];
      reference: string;
      amount: number;
      event_date: string;
    }>;

    return rows.map((r) => ({
      type: r.type,
      reference: r.reference,
      amount: Number(r.amount),
      date: r.event_date,
    }));
  }

  // ======================================================================
  // Internals — settlement legs
  // ======================================================================

  private static applySettlement(
    dbArg: Database.Database,
    args: {
      returnHeader: InvoiceReturnHeader;
      invoiceNo: string;
      customerId: number;
      spec: SettlementInput;
      userId: number;
    },
  ): PostedSettlement {
    const { spec, returnHeader, invoiceNo, customerId, userId } = args;
    const amount = roundCurrency(Number(spec.amount) || 0);
    if (amount <= 0) throw new ReturnError(400, 'Settlement amounts must be positive');

    if (spec.type === 'refund') {
      return InvoiceReturnService.applyRefund(dbArg, {
        returnHeader,
        invoiceNo,
        customerId,
        amount,
        method: spec.method ?? 'Cash',
        userId,
      });
    }
    if (spec.type === 'credit') {
      return InvoiceReturnService.applyCredit(dbArg, {
        returnHeader,
        invoiceNo,
        customerId,
        amount,
        userId,
      });
    }
    return InvoiceReturnService.applyAdjust(dbArg, {
      returnHeader,
      invoiceNo,
      customerId,
      amount,
      targetInvoiceId: spec.target_invoice_id ?? null,
      userId,
    });
  }

  /** REFUND: negative payment + negative allocation + REFUND debit + GL. */
  private static applyRefund(
    dbArg: Database.Database,
    args: {
      returnHeader: InvoiceReturnHeader; invoiceNo: string; customerId: number;
      amount: number; method: string; userId: number;
    },
  ): PostedSettlement {
    const today = todayLocal();
    const { userId } = args;
    const refundPaymentNo = InvoiceModel.generatePaymentNoAtomic(dbArg);

    const refundPaymentId = InvoiceModel.createPayment(
      dbArg,
      refundPaymentNo,
      args.customerId,
      today,
      -args.amount,
      args.method,
      null,
      `Refund for return ${args.returnHeader.return_no} on Invoice ${args.invoiceNo}`,
    );
    InvoiceModel.createPaymentAllocation(
      dbArg,
      refundPaymentId,
      args.returnHeader.invoice_id,
      -args.amount,
    );

    createLedgerEntry(
      args.customerId,
      today,
      'REFUND',
      refundPaymentNo,
      args.amount,
      0,
      `Refund ${refundPaymentNo} for return ${args.returnHeader.return_no} on Invoice ${args.invoiceNo}`,
    );

    // The refund leaves the till: Dr AR / Cr <Cash|Bank> (D8). Only the
    // Cash account is guarded in real time — a drawer must actually hold
    // the money being handed back. Bank/Card refunds post for external
    // reconciliation, so their balance is not blocking. A shortfall is a
    // client error (400), never a 500.
    const cashCode = AccountingService._cashOrBankAccountCode(args.method);
    const cashAccount = AccountingService.getAccountByCode(dbArg, cashCode);
    if (!cashAccount) {
      throw new ReturnError(500, `Chart of accounts is missing required account: ${cashCode}`);
    }
    if (args.method.toLowerCase() === 'cash') {
      try {
        AccountingService.assertSufficientFunds(dbArg, {
          accountId: cashAccount.id,
          amount: args.amount,
          asOfDate: today,
          label: `refund ${refundPaymentNo}`,
        });
      } catch (err: unknown) {
        throw new ReturnError(400, (err as Error).message);
      }
    }
    AccountingService.postRefundEntry(dbArg, {
      refundPaymentId,
      refundPaymentNo,
      amount: args.amount,
      refundDate: today,
      paymentMethod: args.method,
      customerId: args.customerId,
      userId,
    });

    const record = InvoiceReturnModel.createSettlement(dbArg, {
      return_id: args.returnHeader.id,
      settlement_no: refundPaymentNo,
      type: 'refund',
      amount: args.amount,
      method: args.method,
      reference: refundPaymentNo,
      payment_id: refundPaymentId,
      settled_date: today,
      created_by: userId,
    });
    return { record, appliedAmount: args.amount };
  }

  /** CREDIT: convert ledger credit into store credit (CR- number). */
  private static applyCredit(
    dbArg: Database.Database,
    args: {
      returnHeader: InvoiceReturnHeader; invoiceNo: string; customerId: number;
      amount: number; userId: number;
    },
  ): PostedSettlement {
    const today = todayLocal();
    const { userId } = args;
    const creditNo = InvoiceReturnModel.generateCreditNoAtomic(dbArg);

    // Consuming debit: the ledger credit is moved into the store-credit
    // pool. Without this row the ledger would still show the credit and
    // the cap would not free up once it has been used.
    createLedgerEntry(
      args.customerId,
      today,
      'CREDIT',
      creditNo,
      args.amount,
      0,
      `Credit note ${creditNo} from return ${args.returnHeader.return_no} on Invoice ${args.invoiceNo}`,
    );
    dbArg.prepare('UPDATE customers SET credit_balance = credit_balance + ? WHERE id = ?')
      .run(args.amount, args.customerId);

    const record = InvoiceReturnModel.createSettlement(dbArg, {
      return_id: args.returnHeader.id,
      settlement_no: creditNo,
      type: 'credit',
      amount: args.amount,
      method: null,
      reference: creditNo,
      settled_date: today,
      created_by: userId,
    });
    return { record, appliedAmount: args.amount };
  }

  /** ADJUST: apply the credit to another invoice as a payment allocation. */
  private static applyAdjust(
    dbArg: Database.Database,
    args: {
      returnHeader: InvoiceReturnHeader; invoiceNo: string; customerId: number;
      amount: number; targetInvoiceId: number | null; userId: number;
    },
  ): PostedSettlement {
    const { userId } = args;
    const today = todayLocal();

    // Auto-pick the customer's oldest unpaid invoice (D7).
    let targetId = args.targetInvoiceId;
    if (!targetId) {
      const oldest = dbArg.prepare(`
        SELECT id FROM invoices
        WHERE customer_id = ? AND status IN ('Unpaid', 'Partially Paid')
          AND balance_amount > 0 AND id <> ?
        ORDER BY invoice_date ASC, id ASC LIMIT 1
      `).get(args.customerId, args.returnHeader.invoice_id) as { id: number } | undefined;
      if (!oldest) {
        throw new ReturnError(
          400,
          'No unpaid invoice found to adjust against — use a credit settlement instead',
        );
      }
      targetId = oldest.id;
    }

    const target = dbArg.prepare(
      'SELECT id, invoice_no, balance_amount FROM invoices WHERE id = ? AND customer_id = ?'
    ).get(targetId, args.customerId) as {
      id: number; invoice_no: string; balance_amount: number;
    } | undefined;
    if (!target) throw new ReturnError(400, 'Target invoice not found for this customer');

    // The application is capped by the target's outstanding balance; the
    // carryover stays as a customer ledger credit (D7). The settlement row
    // records the full requested amount (scenario 5: the return is then
    // fully settled), so settled_amount never silently drops below net.
    const applied = roundCurrency(
      Math.min(args.amount, Math.max(0, Number(target.balance_amount))),
    );

    if (applied > 0) {
      const adjustPaymentNo = InvoiceModel.generatePaymentNoAtomic(dbArg);
      const adjustPaymentId = InvoiceModel.createPayment(
        dbArg,
        adjustPaymentNo,
        args.customerId,
        today,
        applied,
        'Credit',
        null,
        `Return credit from ${args.returnHeader.return_no} applied to Invoice ${target.invoice_no}`,
      );
      InvoiceModel.createPaymentAllocation(dbArg, adjustPaymentId, target.id, applied);
      calculateInvoiceBalance(target.id);
      updateInvoiceStatus(target.id);
    }

    const record = InvoiceReturnModel.createSettlement(dbArg, {
      return_id: args.returnHeader.id,
      settlement_no: `ADJ-${args.returnHeader.return_no}`,
      type: 'adjust',
      amount: args.amount,
      method: null,
      reference: target.invoice_no,
      target_invoice_id: target.id,
      payment_id: null,
      settled_date: today,
      created_by: userId,
    });
    return { record, appliedAmount: applied };
  }

  // ======================================================================
  // Internals — legacy dispositions (spec §10 shim)
  // ======================================================================

  /**
   * Legacy `disposition: 'refund'` — never refund more than was actually
   * collected on the invoice; the remainder stays as a ledger credit.
   */
  private static applyLegacyRefund(
    dbArg: Database.Database,
    args: {
      returnHeader: InvoiceReturnHeader; invoiceNo: string; customerId: number;
      netAmount: number; userId: number;
    },
  ): PostedSettlement | null {
    const refundable = PaymentModel.refundableOnInvoice(
      dbArg,
      args.returnHeader.invoice_id,
    );
    const amount = roundCurrency(Math.min(args.netAmount, Math.max(0, refundable)));
    if (amount <= 0) return null;
    return InvoiceReturnService.applyRefund(dbArg, {
      returnHeader: args.returnHeader,
      invoiceNo: args.invoiceNo,
      customerId: args.customerId,
      amount,
      method: 'Cash',
      userId: args.userId,
    });
  }

  /**
   * Legacy `disposition: 'adjust'` — applies the net to the customer's
   * unpaid invoices (explicit list or oldest-first), one settlement row
   * per target. The RETURN credit posted above funds every application, so
   * no extra ledger row is written here; any carryover stays on the ledger
   * as credit instead of being silently dropped.
   */
  private static applyLegacyAdjust(
    dbArg: Database.Database,
    args: {
      returnHeader: InvoiceReturnHeader; invoiceNo: string; customerId: number;
      netAmount: number; userId: number; targetInvoiceIds: number[] | null;
    },
  ): PostedSettlement[] {
    let targets = args.targetInvoiceIds ?? null;
    if (!targets || targets.length === 0) {
      targets = (dbArg.prepare(`
        SELECT id FROM invoices
        WHERE customer_id = ? AND status IN ('Unpaid', 'Partially Paid')
          AND balance_amount > 0 AND id <> ?
        ORDER BY invoice_date ASC, id ASC
      `).all(args.customerId, args.returnHeader.invoice_id) as Array<{ id: number }>)
        .map((r) => r.id);
    }
    if (targets.length === 0) {
      throw new ReturnError(400, 'No unpaid invoices found to adjust against');
    }

    const posted: PostedSettlement[] = [];
    let remaining = args.netAmount;
    for (const targetId of targets) {
      if (remaining <= 0.01) break;
      const target = dbArg.prepare(
        'SELECT id, invoice_no, balance_amount FROM invoices WHERE id = ? AND customer_id = ?'
      ).get(targetId, args.customerId) as {
        id: number; invoice_no: string; balance_amount: number;
      } | undefined;
      if (!target || Number(target.balance_amount) <= 0) continue;

      const applied = roundCurrency(Math.min(remaining, Number(target.balance_amount)));
      const adjustPaymentNo = InvoiceModel.generatePaymentNoAtomic(dbArg);
      const adjustPaymentId = InvoiceModel.createPayment(
        dbArg,
        adjustPaymentNo,
        args.customerId,
        todayLocal(),
        applied,
        'Credit',
        null,
        `Return credit from ${args.invoiceNo} applied to Invoice ${target.invoice_no}`,
      );
      InvoiceModel.createPaymentAllocation(dbArg, adjustPaymentId, target.id, applied);
      calculateInvoiceBalance(target.id);
      updateInvoiceStatus(target.id);

      posted.push({
        record: InvoiceReturnModel.createSettlement(dbArg, {
          return_id: args.returnHeader.id,
          settlement_no: `ADJ-${args.returnHeader.return_no}-${posted.length + 1}`,
          type: 'adjust',
          amount: applied,
          method: null,
          reference: target.invoice_no,
          target_invoice_id: target.id,
          payment_id: adjustPaymentId,
          settled_date: todayLocal(),
          created_by: args.userId,
        }),
        appliedAmount: applied,
      });
      remaining = roundCurrency(remaining - applied);
    }
    return posted;
  }

  // ======================================================================
  // Internals — reversal of a single settlement (used by both voids)
  // ======================================================================

  private static revertSettlement(
    dbArg: Database.Database,
    settlement: ReturnSettlementRow,
    customerId: number,
    userId: number,
    reason: string,
  ): void {
    const nowIso = new Date().toISOString();

    if (settlement.type === 'refund') {
      // Reverse the REFUND ledger row, void the negative allocation (the
      // negative payment row stays as the audit record) and void the
      // refund's GL group keyed to the payment.
      revertLedgerByReference(dbArg, {
        customerId,
        transactionType: 'REFUND',
        referenceNo: settlement.reference,
        reason,
      });
      if (settlement.payment_id) {
        dbArg.prepare(
          'UPDATE payment_allocations SET voided_at = ? WHERE payment_id = ? AND voided_at IS NULL'
        ).run(nowIso, settlement.payment_id);
        AccountingService.voidJournalLinesByReference(dbArg, 'PAYMENT', settlement.payment_id, {
          voidedBy: userId,
          voidReason: reason,
        });
      }
      return;
    }

    if (settlement.type === 'credit') {
      // Release the store credit back to the customer ledger.
      dbArg.prepare('UPDATE customers SET credit_balance = MAX(0, credit_balance - ?) WHERE id = ?')
        .run(Number(settlement.amount), customerId);
      revertLedgerByReference(dbArg, {
        customerId,
        transactionType: 'CREDIT',
        referenceNo: settlement.reference,
        reason,
      });
      return;
    }

    // adjust: drop the allocation from the target invoice (the payment row
    // stays as the audit record) and recompute its balance.
    if (settlement.payment_id) {
      dbArg.prepare(
        'UPDATE payment_allocations SET voided_at = ? WHERE payment_id = ? AND voided_at IS NULL'
      ).run(nowIso, settlement.payment_id);
    }
    if (settlement.target_invoice_id) {
      calculateInvoiceBalance(settlement.target_invoice_id);
      updateInvoiceStatus(settlement.target_invoice_id);
    }
  }
}

// ────────────────────────────────────────────────────────────────────────
// Module helpers
// ────────────────────────────────────────────────────────────────────────

function resolveReturnDate(raw?: string | null): string {
  if (!raw || !String(raw).trim()) return todayLocal();
  const value = String(raw).trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new ReturnError(400, `Invalid return_date: ${value} (expected YYYY-MM-DD)`);
  }
  return value;
}

function resolveWarehouse(raw?: number | string | null): number | null {
  if (raw === null || raw === undefined || String(raw).trim() === '') return null;
  const id = Number(raw);
  // An explicitly-provided id must be a positive integer of an existing
  // warehouse — silently falling back to the sale-origin warehouse on a
  // bad id would restock into the wrong place (legacy 400 contract).
  if (!Number.isInteger(id) || id <= 0) {
    throw new ReturnError(400, 'A valid warehouse_id is required');
  }
  const exists = db.prepare('SELECT 1 FROM warehouses WHERE id = ?').get(id);
  if (!exists) throw new ReturnError(400, `Warehouse ${id} not found`);
  return id;
}

function normalizeFeeType(
  feeType?: FeeType,
  legacyType?: string | null,
): FeeType {
  if (feeType === 'fixed' || feeType === 'percentage' || feeType === 'none') return feeType;
  if (legacyType === 'percentage') return 'percentage';
  if (legacyType === 'flat' || legacyType === 'fixed') return 'fixed';
  return 'none';
}

/** Reject a return whose date falls inside a closed accounting period (D23). */
function assertPeriodOpen(returnDate: string): void {
  const closed = db.prepare(
    `SELECT 1 FROM accounting_periods
     WHERE ? BETWEEN start_date AND end_date AND status = 'closed'
     LIMIT 1`
  ).get(returnDate) as { 1: number } | undefined;
  if (closed) {
    throw new ReturnError(
      400,
      `Cannot post a return dated ${returnDate}: the accounting period is closed`,
    );
  }
}

/**
 * COGS reversal at actual FIFO cost — the returned share of the original
 * sale movements (same proportional rule the stock reversal uses).
 */
function computeReturnCogs(
  dbArg: Database.Database,
  invoiceNo: string,
  lines: Array<{ item_id: number; returnedQuantity: number }>,
): number {
  let cogsTotal = 0;
  for (const line of lines) {
    const saleMovements = db.prepare(`
      SELECT quantity, unit_cost FROM stock_movements
      WHERE item_id = ? AND reference_docno = ? AND movement_type = 'SALE'
      ORDER BY id
    `).all(line.item_id, invoiceNo) as Array<{ quantity: number; unit_cost: number }>;

    if (saleMovements.length === 0) continue;

    const totalSold = saleMovements.reduce((sum, m) => sum + Math.abs(m.quantity), 0);
    if (totalSold <= 0) continue;
    const ratio = Math.min(line.returnedQuantity / totalSold, 1);
    for (const movement of saleMovements) {
      cogsTotal += Math.abs(movement.quantity) * Number(movement.unit_cost) * ratio;
    }
  }
  return roundCurrency(cogsTotal);
}

/** Reverse one customer_ledger row found by (type, reference) — ACC-14 style. */
function revertLedgerByReference(
  dbArg: Database.Database,
  args: {
    customerId: number;
    transactionType: string;
    referenceNo: string | null;
    reason: string;
  },
): void {
  if (!args.referenceNo) return;
  const row = dbArg.prepare(
    `SELECT id FROM customer_ledger
     WHERE customer_id = ? AND transaction_type = ? AND reference_no = ?
       AND voided = 0
     ORDER BY id DESC LIMIT 1`
  ).get(args.customerId, args.transactionType, args.referenceNo) as { id: number } | undefined;
  if (row) {
    reverseLedgerEntry('customer_ledger', row.id, args.reason);
  }
}

/**
 * Reverse the restock a return posted: the exact negative mirror movement
 * (which restores stock_balances / items.current_stock and posts its own
 * balanced inventory GL entry) plus the proportional batch restore the
 * return made, so FEFO batch quantities are exact again.
 *
 * The mirror quantity is read from the attributed movement itself, so the
 * reversal is exact even when other returns have happened since.
 */
function reverseRestock(
  dbArg: Database.Database,
  args: {
    itemId: number;
    invoiceNo: string;
    restockMovementId: number;
    returnWarehouseId: number | null;
    userId: number;
    remarks: string;
  },
): void {
  const movement = db.prepare(
    'SELECT id, quantity, unit_cost, warehouse_id FROM stock_movements WHERE id = ?'
  ).get(args.restockMovementId) as {
    id: number; quantity: number; unit_cost: number | null; warehouse_id: number;
  } | undefined;
  if (!movement) return;

  const restockQty = Number(movement.quantity);
  if (restockQty <= 0) return;

  // 1. Reverse the batch-level restore FIRST, so the movement's own
  //    syncStockBalancesExtension recomputes from corrected batch rows.
  reverseBatchRestore(dbArg, {
    itemId: args.itemId,
    invoiceNo: args.invoiceNo,
    restockQty,
    returnWarehouseId: args.returnWarehouseId,
  });

  // 2. Equal-and-opposite ADJUSTMENT movement in the same warehouse at the
  //    same cost. recordMovement posts its own balanced financial entry,
  //    which restores the inventory GL.
  StockMovementModel.recordMovement(
    {
      item_id: args.itemId,
      warehouse_id: movement.warehouse_id,
      movement_type: 'ADJUSTMENT',
      quantity: -restockQty,
      unit_cost: movement.unit_cost,
      reference_doctype: 'RETURN',
      reference_docno: args.invoiceNo,
      remarks: args.remarks,
      movement_date: todayLocal(),
    },
    args.userId,
    dbArg,
  );
}

/**
 * Undo the batch restore this return made. The return restored
 * `|saleMovementQty| * ratio` to each sold batch's DEFAULT location where
 * ratio = restockQty / totalSold — derived here from the attributed
 * movement, so it matches the original exactly.
 */
function reverseBatchRestore(
  dbArg: Database.Database,
  args: {
    itemId: number;
    invoiceNo: string;
    restockQty: number;
    returnWarehouseId: number | null;
  },
): void {
  const saleMovements = db.prepare(`
    SELECT warehouse_id, quantity, batch_id FROM stock_movements
    WHERE item_id = ? AND reference_docno = ? AND movement_type = 'SALE'
    ORDER BY id
  `).all(args.itemId, args.invoiceNo) as Array<{
    warehouse_id: number; quantity: number; batch_id: number | null;
  }>;
  if (saleMovements.length === 0) return;

  const totalSold = saleMovements.reduce((sum, m) => sum + Math.abs(m.quantity), 0);
  if (totalSold <= 0) return;
  const ratio = Math.min(args.restockQty / totalSold, 1);

  const batchFeatureOn = isFeatureEnabled(db, 'feature_batch_locations');
  for (const movement of saleMovements) {
    if (movement.batch_id === null) continue;
    const restoreQty = Math.abs(movement.quantity) * ratio;
    if (restoreQty <= 0) continue;

    if (batchFeatureOn) {
      // The return restored every batch to the chosen warehouse's DEFAULT
      // location (explicit warehouse) or to the sale movement's own
      // warehouse DEFAULT location (implicit).
      const targetWarehouseId = args.returnWarehouseId ?? movement.warehouse_id;
      const locRow = db.prepare(`
        SELECT id FROM locations WHERE warehouse_id = ? AND location_code = 'DEFAULT' LIMIT 1
      `).get(targetWarehouseId) as { id: number } | undefined;
      if (!locRow) continue;
      db.prepare(`
        UPDATE batch_stock_by_location
        SET quantity_physical = MAX(0, quantity_physical - ?),
            quantity_available = MAX(0, quantity_available - ?)
        WHERE batch_id = ? AND location_id = ?
      `).run(restoreQty, restoreQty, movement.batch_id, locRow.id);
    } else {
      db.prepare(`
        UPDATE stock_batches
        SET quantity_remaining = MAX(0, quantity_remaining - ?)
        WHERE id = ?
      `).run(restoreQty, movement.batch_id);
    }
  }
}

export default InvoiceReturnService;
