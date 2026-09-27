/**
 * TASK 33 — supplier payout writer.
 *
 * Split from PaymentRecordingService so each file stays reviewable: the
 * customer side (receipts, refunds, credit applications, allocate-later)
 * and the supplier side share only the payment INSERT, the method
 * whitelist and the closed-period guard, all of which live in
 * paymentWriterCore.
 */
import type Database from 'better-sqlite3';
import AccountingService from './accountingService';
import InvoiceModel from '../models/Invoice';
import SupplierLedgerModel from '../models/SupplierLedger';
import { parseCurrency, subtractCurrency } from '../utils/currency';
import { validateSupplierPayment } from './paymentValidation';
import { assertPaymentMethod, assertPeriodOpen, insertPaymentRow } from './paymentWriterCore';
import type { PaymentRecordingResult, SupplierPaymentInput } from './paymentRecordingTypes';

export class SupplierPaymentService {
  constructor(private readonly db: Database.Database) {}

  recordSupplierPayment(input: SupplierPaymentInput): PaymentRecordingResult {
    return this.db.transaction(() => {
      validateSupplierPayment(this.db, input);
      assertPaymentMethod(input.paymentMethod);
      assertPeriodOpen(this.db, input.paymentDate);

      const paymentNo = input.paymentNo ?? InvoiceModel.generatePaymentNoAtomic(this.db);
      const amount = parseCurrency(input.amount);

      const paymentId = insertPaymentRow(this.db, {
        paymentNo,
        paymentDate: input.paymentDate,
        amount,
        paymentMethod: input.paymentMethod,
        referenceNo: input.referenceNo,
        notes: input.notes,
        supplierId: input.supplierId,
        purchaseOrderId: singlePurchaseOrderId(input),
      });

      for (const alloc of input.allocations) {
        if (alloc.kind === 'purchase_order') {
          this.db.prepare('INSERT INTO po_allocations (payment_id, po_id, amount) VALUES (?, ?, ?)')
            .run(paymentId, alloc.id, parseCurrency(alloc.amount));
          continue;
        }
        this.db.prepare('INSERT INTO purchase_allocations (payment_id, purchase_id, amount) VALUES (?, ?, ?)')
          .run(paymentId, alloc.id, parseCurrency(alloc.amount));
      }

      this.postAccounting(paymentId, paymentNo, input, amount);
      return { paymentId, paymentNo, amount };
    })();
  }

  private postAccounting(
    paymentId: number,
    paymentNo: string,
    input: SupplierPaymentInput,
    amount: number,
  ): void {
    const openingBalance = SupplierLedgerModel.getBalance(input.supplierId, this.db);
    SupplierLedgerModel.createEntry({
      supplier_id: input.supplierId,
      transaction_date: input.paymentDate,
      transaction_type: 'PAYMENT',
      reference_no: paymentNo,
      credit: amount,
      description: `Payment against ${this.documentReferences(input).join(', ')}`,
    }, this.db);
    this.db.prepare('UPDATE suppliers SET current_balance = ? WHERE id = ?')
      .run(subtractCurrency(openingBalance, amount), input.supplierId);

    // ACC-03: Dr 2000 AP / Cr cash-per-method, and the drawer/account must
    // actually hold the money leaving the business.
    const cashCode = AccountingService._cashOrBankAccountCode(input.paymentMethod);
    const fundsAccount = AccountingService.getAccountByCode(this.db, cashCode);
    if (!fundsAccount) throw new Error(`Chart of accounts is missing required account: ${cashCode}`);
    AccountingService.assertSufficientFunds(this.db, {
      accountId: fundsAccount.id,
      amount,
      asOfDate: input.paymentDate,
      label: `supplier payment ${paymentNo}`,
    });
    AccountingService.postSupplierPaymentEntry(this.db, {
      paymentId,
      paymentNo,
      amount,
      paymentDate: input.paymentDate,
      paymentMethod: input.paymentMethod,
      userId: input.userId ?? undefined,
    });
  }

  private documentReferences(input: SupplierPaymentInput): string[] {
    return input.allocations.map((alloc) => {
      if (alloc.kind === 'purchase_order') {
        const po = this.db.prepare('SELECT po_no FROM purchase_orders WHERE id = ?').get(alloc.id) as { po_no: string } | undefined;
        return po?.po_no ?? `PO #${alloc.id}`;
      }
      const purchase = this.db.prepare('SELECT purchase_no FROM purchases WHERE id = ?').get(alloc.id) as { purchase_no: string } | undefined;
      return purchase?.purchase_no ?? `Purchase #${alloc.id}`;
    });
  }
}

/** A single-PO payout stays denormalized on the payment row for PO reports. */
function singlePurchaseOrderId(input: SupplierPaymentInput): number | null {
  if (input.allocations.length !== 1) return null;
  const only = input.allocations[0];
  return only.kind === 'purchase_order' ? only.id : null;
}
