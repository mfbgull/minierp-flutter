import type Database from 'better-sqlite3';
import AccountingService from './accountingService';
import InvoiceModel from '../models/Invoice';
import ledgerUtils from '../utils/ledgerUtils';
import { UnappliedCashError } from './unappliedCashTypes';
import { recordStoreCreditDraws } from './storeCreditOwnership';
import { roundCurrency, toMinorUnits } from '../utils/currency';
import { hashRequestPayload, claimIdempotencyKey, beginIdempotentWrite, IdempotencyConflictError } from '../utils/idempotency';
import { documentDate } from '../middleware/validation';

export interface StoreCreditApplyInput {
  customerId: number;
  date: string;
  applicationKey: string;
  userId: number | null;
  allocations: readonly { invoiceId: number; amount: number }[];
}

export interface StoreCreditApplyResult {
  applicationId: number;
  amount: number;
}

function positiveAmount(value: number): number {
  if (!Number.isFinite(value) || value <= 0 || !Number.isSafeInteger(toMinorUnits(value))) {
    throw new UnappliedCashError('INVALID_AMOUNT', 'Amount must be finite and positive', 400);
  }
  const normalized = roundCurrency(value);
  if (normalized <= 0) throw new UnappliedCashError('INVALID_AMOUNT', 'Amount must be at least 0.01', 400);
  return normalized;
}

/**
 * Applies a customer's store-credit pool (customers.credit_balance, sourced
 * from invoice returns) to existing invoices. Mirrors the credit-offset leg of
 * InvoiceCreationService: FIFO settlement draws, Dr 1110 / Cr 1100 journal,
 * CREDIT ledger row, invoice credit_offset and balance updates.
 */
export class StoreCreditApplicationService {
  constructor(private readonly db: Database.Database) {}

  apply(input: StoreCreditApplyInput): StoreCreditApplyResult {
    if (!Number.isSafeInteger(input.customerId) || input.customerId <= 0) {
      throw new UnappliedCashError('INVALID_ID', 'Expected a positive integer ID', 400);
    }
    if (!documentDate('Operation date').safeParse(input.date).success) {
      throw new UnappliedCashError('INVALID_DATE', 'Operation date must be a real YYYY-MM-DD date', 400);
    }
    const key = input.applicationKey;
    if (typeof key !== 'string' || key.trim().length < 8 || key.length > 200 || key !== key.trim()) {
      throw new UnappliedCashError('INVALID_APPLICATION_KEY', 'Application key must be 8..200 characters without surrounding whitespace', 400);
    }
    if (!input.allocations.length) throw new UnappliedCashError('INVALID_ALLOCATION', 'At least one invoice is required', 400);
    const amounts = new Map<number, number>();
    for (const allocation of input.allocations) {
      if (!Number.isSafeInteger(allocation.invoiceId) || allocation.invoiceId <= 0) {
        throw new UnappliedCashError('INVALID_ID', 'Expected a positive integer ID', 400);
      }
      amounts.set(allocation.invoiceId, (amounts.get(allocation.invoiceId) ?? 0) + toMinorUnits(positiveAmount(allocation.amount)));
    }
    const allocations = [...amounts].sort(([left], [right]) => left - right)
      .map(([invoiceId, minor]) => ({ invoiceId, amount: positiveAmount(minor / 100) }));
    const amount = positiveAmount(allocations.reduce((sum, a) => sum + toMinorUnits(a.amount), 0) / 100);
    const requestHash = hashRequestPayload({ customerId: input.customerId, date: input.date, allocations });

    return this.db.transaction(() => {
      this.beginReplayGuard(`${input.customerId}:${key}`, requestHash);
      const existing = this.db.prepare<[number, string], { id: number; request_hash: string; total_amount: number }>(
        'SELECT id, request_hash, total_amount FROM store_credit_applications WHERE customer_id=? AND application_key=?')
        .get(input.customerId, key);
      if (existing) {
        if (existing.request_hash !== requestHash) throw new UnappliedCashError('IDEMPOTENCY_CONFLICT', 'Application key was used for another payload', 409);
        return { applicationId: existing.id, amount: existing.total_amount };
      }

      this.period(input.date);
      const customer = this.db.prepare<[number], { current_balance: number; credit_balance: number }>(
        'SELECT current_balance, COALESCE(credit_balance, 0) AS credit_balance FROM customers WHERE id=?').get(input.customerId);
      if (!customer) throw new UnappliedCashError('CUSTOMER_NOT_FOUND', 'Customer not found', 404);

      for (const allocation of allocations) {
        const invoice = this.db.prepare<[number], { invoice_no: string; customer_id: number; status: string; invoice_date: string; balance_amount: number }>(
          'SELECT invoice_no, customer_id, status, invoice_date, balance_amount FROM invoices WHERE id=?').get(allocation.invoiceId);
        if (!invoice) throw new UnappliedCashError('INVOICE_NOT_FOUND', 'Invoice not found', 404);
        if (Number(invoice.customer_id) !== input.customerId) {
          throw new UnappliedCashError('INVALID_ALLOCATION', `Invoice ${allocation.invoiceId} does not belong to this customer`, 400);
        }
        if (['Cancelled', 'Deleted'].includes(invoice.status) || invoice.invoice_date > input.date) {
          throw new UnappliedCashError('INVALID_INVOICE', 'Invoice is cancelled or dated after application', 400);
        }
        if (toMinorUnits(allocation.amount) > toMinorUnits(invoice.balance_amount)) {
          throw new UnappliedCashError('INVOICE_OVERALLOCATION', 'Allocation exceeds invoice balance', 400);
        }
      }
      if (toMinorUnits(amount) > toMinorUnits(customer.credit_balance)) {
        throw new UnappliedCashError('INSUFFICIENT_STORE_CREDIT', 'Application exceeds the available store credit pool', 400);
      }

      const applicationId = Number(this.db.prepare(
        'INSERT INTO store_credit_applications (customer_id, application_key, request_hash, operation_date, total_amount) VALUES (?,?,?,?,?)')
        .run(input.customerId, key, requestHash, input.date, amount).lastInsertRowid);

      for (const allocation of allocations) {
        const invoiceNo = (this.db.prepare<[number], { invoice_no: string }>('SELECT invoice_no FROM invoices WHERE id=?')
          .get(allocation.invoiceId) as { invoice_no: string }).invoice_no;
        AccountingService.postCreditOffsetEntry(this.db, {
          invoiceId: allocation.invoiceId, invoiceNo, amount: allocation.amount,
          invoiceDate: input.date, customerId: input.customerId, userId: input.userId ?? undefined,
        });
        const changed = this.db.prepare(
          'UPDATE invoices SET credit_offset=ROUND(COALESCE(credit_offset,0)+?,2) WHERE id=? AND ROUND(balance_amount*100)>=?'
        ).run(allocation.amount, allocation.invoiceId, toMinorUnits(allocation.amount));
        if (changed.changes !== 1) throw new UnappliedCashError('INVOICE_OVERALLOCATION', 'Invoice balance changed concurrently', 409);
        recordStoreCreditDraws(this.db, input.customerId, allocation.invoiceId, allocation.amount, applicationId);
        ledgerUtils.calculateInvoiceBalance(allocation.invoiceId, this.db);
        ledgerUtils.updateInvoiceStatus(allocation.invoiceId, this.db);
        InvoiceModel.createLedgerEntry(this.db, input.customerId, 'CREDIT', `CREDIT-${invoiceNo}`, input.date, 0, allocation.amount,
          `Store credit applied to Invoice ${invoiceNo}`);
        this.db.prepare('UPDATE customers SET current_balance=ROUND(current_balance-?,2) WHERE id=?').run(allocation.amount, input.customerId);
      }

      this.db.prepare('UPDATE customers SET credit_balance=MAX(0, COALESCE(credit_balance,0)-?) WHERE id=?').run(amount, input.customerId);
      claimIdempotencyKey(this.db, 'store_credit.apply', `${input.customerId}:${key}`, requestHash, applicationId);
      return { applicationId, amount };
    }).immediate();
  }

  private beginReplayGuard(composedKey: string, requestHash: string): void {
    try {
      beginIdempotentWrite(this.db, 'store_credit.apply', composedKey, requestHash);
    } catch (error) {
      if (!(error instanceof IdempotencyConflictError)) throw error;
      throw new UnappliedCashError('IDEMPOTENCY_CONFLICT', error.message, 409);
    }
  }

  private period(date: string): void {
    const closed = this.db.prepare("SELECT 1 FROM accounting_periods WHERE status='closed' AND start_date<=? AND end_date>=?").get(date, date);
    if (closed) throw new UnappliedCashError('PERIOD_CLOSED', 'Operation date is in a closed accounting period', 400);
    AccountingService.assertPeriodNotClosed(this.db, date, 'Store credit application');
  }
}
