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
import { parseCurrency } from '../utils/currency';
import { validateSupplierPayment } from './paymentValidation';
import { assertPaymentMethod, assertPeriodOpen, insertPaymentRow } from './paymentWriterCore';
import type { PaymentRecordingResult, SupplierPaymentInput } from './paymentRecordingTypes';
import { BusinessRuleError } from '../utils/businessRuleError';

export class SupplierPaymentService {
  constructor(private readonly db: Database.Database) {}

  recordSupplierPayment(input: SupplierPaymentInput): PaymentRecordingResult {
    return this.db.transaction(() => {
      validateSupplierPayment(this.db, input);
      this.assertFunding(input);
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
        if (alloc.kind === 'supplier_bill') {
          this.db.prepare('INSERT INTO supplier_bill_allocations (payment_id, bill_id, amount) VALUES (?, ?, ?)')
            .run(paymentId, alloc.id, parseCurrency(alloc.amount));
          continue;
        }
        if (alloc.kind === 'purchase_order') {
          this.db.prepare('INSERT INTO po_allocations (payment_id, po_id, amount) VALUES (?, ?, ?)')
            .run(paymentId, alloc.id, parseCurrency(alloc.amount));
          continue;
        }
        this.db.prepare('INSERT INTO purchase_allocations (payment_id, purchase_id, amount) VALUES (?, ?, ?)')
          .run(paymentId, alloc.id, parseCurrency(alloc.amount));
      }

      if (input.supplierPrepaymentId !== undefined) {
        this.db.prepare('INSERT INTO supplier_prepayment_applications (prepayment_id, payment_id, amount) VALUES (?, ?, ?)')
          .run(input.supplierPrepaymentId, paymentId, amount);
      }
      this.postAccounting(paymentId, paymentNo, input, amount);
      return { paymentId, paymentNo, amount };
    })();
  }

  private assertFunding(input: SupplierPaymentInput): void {
    if (input.supplierPrepaymentId !== undefined) {
      if (!Number.isSafeInteger(input.supplierPrepaymentId) || input.supplierPrepaymentId <= 0 || input.paymentMethod !== 'credit') {
        throw new BusinessRuleError(400, 'Invalid supplier advance funding');
      }
      const source = this.db.prepare(`
        SELECT a.supplier_id, a.prepay_date, a.amount - COALESCE((
          SELECT SUM(x.amount) FROM supplier_prepayment_applications x
          JOIN payments p ON p.id = x.payment_id
          WHERE x.prepayment_id = a.id AND p.voided_at IS NULL
        ), 0) AS available
        FROM supplier_prepayments a WHERE a.id = ? AND a.voided_at IS NULL
      `).get(input.supplierPrepaymentId) as { supplier_id: number; prepay_date: string; available: number } | undefined;
      if (!source || source.supplier_id !== input.supplierId) throw new BusinessRuleError(400, 'Active advance not found for this supplier');
      if (input.paymentDate < source.prepay_date || parseCurrency(input.amount) > parseCurrency(source.available)) throw new BusinessRuleError(400, 'Application precedes or exceeds the supplier advance');
      AccountingService.assertPeriodNotClosed(this.db, source.prepay_date, 'Supplier advance');
    } else {
      assertPaymentMethod(input.paymentMethod);
    }
  }

  private postAccounting(
    paymentId: number,
    paymentNo: string,
    input: SupplierPaymentInput,
    amount: number,
  ): void {
    SupplierLedgerModel.createEntry({
      supplier_id: input.supplierId,
      transaction_date: input.paymentDate,
      transaction_type: 'PAYMENT',
      reference_no: paymentNo,
      credit: amount,
      description: `Payment against ${this.documentReferences(input).join(', ')}`,
    }, this.db);
    // Rebuild in insertion order: getBalance() follows transaction_date, which
    // is stale whenever an earlier-dated entry was posted after a later one.
    SupplierLedgerModel.rebuildBalances(input.supplierId, this.db);

    if (input.supplierPrepaymentId !== undefined) {
      const payable = AccountingService.getAccountByCode(this.db, '2000');
      const advance = AccountingService.getAccountByCode(this.db, '1330');
      if (!payable || !advance) throw new Error('Supplier advance accounts are missing');
      AccountingService.postEntry(this.db, {
        entry_date: input.paymentDate, reference_type: 'PAYMENT', reference_id: paymentId,
        description: `Supplier advance applied by ${paymentNo}`, created_by: input.userId,
        lines: [{ account_id: payable.id, debit: amount }, { account_id: advance.id, credit: amount }],
      });
      return;
    }

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
      if (alloc.kind === 'supplier_bill') {
        const bill = this.db.prepare('SELECT bill_no FROM supplier_bills WHERE id = ?').get(alloc.id) as { bill_no: string } | undefined;
        return bill?.bill_no ?? `Bill #${alloc.id}`;
      }
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
