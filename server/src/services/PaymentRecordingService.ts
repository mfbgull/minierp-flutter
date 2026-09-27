/**
 * TASK 33 — the single authoritative writer for customer money.
 *
 * Every customer-side payment path (payments API, invoice-time settlement,
 * POS, mobile, sales-order conversion, return refund, return credit
 * application, return adjustment, allocate-later) records through this
 * service, so validation, allocation, cash-account resolution, the customer
 * ledger, the GL, the closed-period guard and the document number are
 * decided in exactly one place. Supplier payouts live in
 * SupplierPaymentService.
 *
 * All writes run inside one `better-sqlite3` transaction. Callers that are
 * already inside a transaction (invoice creation, return settlement) nest as
 * a savepoint, so a rejection still rolls the whole outer operation back.
 */
import type Database from 'better-sqlite3';
import AccountingService from './accountingService';
import InvoiceModel from '../models/Invoice';
import ledgerUtils from '../utils/ledgerUtils';
import { parseCurrency, subtractCurrency } from '../utils/currency';
import { validateCustomerPayment } from './paymentValidation';
import { assertPaymentMethod, assertPeriodOpen, insertPaymentRow } from './paymentWriterCore';
import type {
  CustomerPaymentInput,
  ExistingPaymentAllocationInput,
  PaymentAllocation,
  PaymentRecordingResult,
} from './paymentRecordingTypes';

export class PaymentRecordingService {
  constructor(private readonly db: Database.Database) {}

  recordCustomerPayment(input: CustomerPaymentInput): PaymentRecordingResult {
    return this.db.transaction(() => {
      validateCustomerPayment(this.db, input);
      // CREDIT_APPLICATION moves no cash: its stored method is the "Credit"
      // marker, not a cash account, so the cash whitelist must not apply.
      if (input.mode !== 'CREDIT_APPLICATION') assertPaymentMethod(input.paymentMethod);
      assertPeriodOpen(this.db, input.paymentDate);

      const paymentNo = input.paymentNo ?? InvoiceModel.generatePaymentNoAtomic(this.db);
      const isRefund = input.mode === 'REFUND';
      const signedAmount = isRefund ? -parseCurrency(input.amount) : parseCurrency(input.amount);

      const paymentId = insertPaymentRow(this.db, {
        paymentNo,
        paymentDate: input.paymentDate,
        amount: signedAmount,
        paymentMethod: input.paymentMethod,
        referenceNo: input.referenceNo,
        notes: input.notes,
        customerId: input.customerId,
      });

      // A refund is a correction against an already-settled invoice, so it
      // must not re-drive that invoice's paid/balance columns.
      this.insertAllocations(paymentId, input.allocations, isRefund ? -1 : 1, !isRefund);
      this.postAccounting(paymentId, paymentNo, input, signedAmount);

      return { paymentId, paymentNo, amount: signedAmount };
    })();
  }

  /** Attach allocations to a payment that was recorded without them. */
  allocateExistingPayment(input: ExistingPaymentAllocationInput): void {
    if (input.allocations.length === 0) throw new Error('At least one allocation is required');

    this.db.transaction(() => {
      const payment = this.db.prepare('SELECT amount, customer_id FROM payments WHERE id = ?')
        .get(input.paymentId) as { amount: number; customer_id: number | null } | undefined;
      if (!payment) throw new Error('Payment not found');
      if (Number(payment.customer_id) !== Number(input.customerId)) {
        throw new Error("Invoice does not belong to this payment's customer");
      }

      const live = this.db.prepare(`
        SELECT COALESCE(SUM(amount), 0) AS total FROM payment_allocations
        WHERE payment_id = ? AND voided_at IS NULL
      `).get(input.paymentId) as { total: number };
      const unallocated = subtractCurrency(parseCurrency(payment.amount), parseCurrency(live.total));

      let allocated = 0;
      for (const alloc of input.allocations) {
        allocated += this.assertInvoiceAllocation(input.customerId, alloc);
      }
      if (Math.abs(allocated - unallocated) > 0.01) {
        throw new Error(
          `Allocations total (${allocated.toFixed(2)}) must equal the unallocated remainder (${unallocated.toFixed(2)})`,
        );
      }

      this.insertAllocations(input.paymentId, input.allocations, 1, true);
    })();
  }

  private insertAllocations(
    paymentId: number,
    allocations: readonly PaymentAllocation[],
    sign: 1 | -1,
    refreshInvoiceBalances: boolean,
  ): void {
    const insert = this.db.prepare('INSERT INTO payment_allocations (payment_id, invoice_id, amount) VALUES (?, ?, ?)');
    const touched = new Set<number>();
    for (const alloc of allocations) {
      insert.run(paymentId, alloc.invoiceId, sign * parseCurrency(alloc.amount));
      touched.add(alloc.invoiceId);
    }
    if (!refreshInvoiceBalances) return;
    for (const invoiceId of touched) {
      ledgerUtils.calculateInvoiceBalance(invoiceId, this.db);
      ledgerUtils.updateInvoiceStatus(invoiceId, this.db);
    }
  }

  private assertInvoiceAllocation(customerId: number, alloc: PaymentAllocation): number {
    const amount = parseCurrency(alloc.amount);
    if (!(amount > 0)) {
      throw new Error(`Allocation amount for invoice ${alloc.invoiceId} must be greater than 0`);
    }
    const invoice = this.db.prepare('SELECT id, customer_id, balance_amount FROM invoices WHERE id = ?')
      .get(alloc.invoiceId) as { id: number; customer_id: number; balance_amount: number } | undefined;
    if (!invoice) throw new Error(`Invoice ${alloc.invoiceId} not found`);
    if (Number(invoice.customer_id) !== Number(customerId)) {
      throw new Error(`Invoice ${alloc.invoiceId} does not belong to this payment's customer`);
    }
    if (amount > parseCurrency(invoice.balance_amount) + 0.01) {
      throw new Error(
        `Allocation (${amount.toFixed(2)}) exceeds invoice ${alloc.invoiceId} balance (${parseCurrency(invoice.balance_amount).toFixed(2)})`,
      );
    }
    return amount;
  }

  private postAccounting(
    paymentId: number,
    paymentNo: string,
    input: CustomerPaymentInput,
    signedAmount: number,
  ): void {
    const amount = Math.abs(signedAmount);

    if (input.mode === 'CREDIT_APPLICATION') {
      // No cash and no ledger row: the return already credited the ledger.
      // What was missing is the AR side — Dr 1110 / Cr 1100 per invoice.
      for (const alloc of input.allocations) {
        AccountingService.postCreditOffsetEntry(this.db, {
          invoiceId: alloc.invoiceId,
          invoiceNo: this.invoiceNumbers([alloc.invoiceId])[0],
          amount: parseCurrency(alloc.amount),
          invoiceDate: input.paymentDate,
          customerId: input.customerId,
          userId: input.userId ?? undefined,
        });
      }
      return;
    }

    if (input.mode === 'REFUND') {
      ledgerUtils.createLedgerEntry(
        input.customerId, input.paymentDate, 'REFUND', paymentNo, amount, 0,
        `Refund ${paymentNo} for ${this.invoiceNumbers(input.allocations.map((a) => a.invoiceId)).join(', ')}`,
        this.db,
      );
      this.guardCashForRefund(paymentNo, input.paymentMethod, amount, input.paymentDate);
      AccountingService.postRefundEntry(this.db, {
        refundPaymentId: paymentId,
        refundPaymentNo: paymentNo,
        amount,
        refundDate: input.paymentDate,
        paymentMethod: input.paymentMethod,
        customerId: input.customerId,
        userId: input.userId ?? undefined,
      });
      return;
    }

    ledgerUtils.createLedgerEntry(
      input.customerId, input.paymentDate, 'PAYMENT', paymentNo, 0, amount,
      `Payment against ${this.invoiceNumbers(input.allocations.map((a) => a.invoiceId)).join(', ')}`,
      this.db,
    );
    AccountingService.postPaymentEntry(this.db, {
      paymentId,
      paymentNo,
      amount,
      paymentDate: input.paymentDate,
      paymentMethod: input.paymentMethod,
      customerId: input.customerId,
      userId: input.userId ?? undefined,
    });
    ledgerUtils.recalcCustomerBalanceFromLedger(input.customerId, this.db);
  }

  /**
   * A cash refund leaves the till, so the drawer must hold the money being
   * handed back. Bank/card refunds post for external reconciliation and are
   * not blocked.
   */
  private guardCashForRefund(paymentNo: string, method: string, amount: number, asOfDate: string): void {
    if (method.toLowerCase() !== 'cash') return;
    const cashCode = AccountingService._cashOrBankAccountCode(method);
    const cash = AccountingService.getAccountByCode(this.db, cashCode);
    if (!cash) throw new Error(`Chart of accounts is missing required account: ${cashCode}`);
    AccountingService.assertSufficientFunds(this.db, {
      accountId: cash.id,
      amount,
      asOfDate,
      label: `refund ${paymentNo}`,
    });
  }

  private invoiceNumbers(invoiceIds: readonly number[]): string[] {
    return invoiceIds.map((invoiceId) => {
      const row = this.db.prepare('SELECT invoice_no FROM invoices WHERE id = ?').get(invoiceId) as { invoice_no: string } | undefined;
      return row?.invoice_no ?? `Invoice #${invoiceId}`;
    });
  }
}
