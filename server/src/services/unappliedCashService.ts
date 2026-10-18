import type Database from 'better-sqlite3';
import type { ReceiveUnappliedCashInput, ApplyUnappliedCashInput, RefundUnappliedCashInput, UnappliedCashResult } from './unappliedCashTypes';
import { UnappliedCashError } from './unappliedCashTypes';
import AccountingService from './accountingService';
import InvoiceModel from '../models/Invoice';
import ledgerUtils from '../utils/ledgerUtils';
import { roundCurrency, toMinorUnits } from '../utils/currency';
import { hashRequestPayload, claimIdempotencyKey, beginIdempotentWrite, IdempotencyConflictError } from '../utils/idempotency';
import { documentDate } from '../middleware/validation';
import { assertPaymentMethod, insertPaymentRow } from './paymentWriterCore';
import { assertInvoiceAllocation, InvoiceAllocationError } from './paymentValidation';
import { assertCashTimeline } from './cashBalanceGuard';
import { BusinessRuleError } from '../utils/businessRuleError';

interface CashSource {
  id: number;
  origin_payment_id: number;
  remaining_amount: number;
  refundable_cash_amount: number;
  refunded_amount: number;
  receipt_amount: number;
  allocated_amount: number;
}

function positiveAmount(value: number): number {
  if (!Number.isFinite(value) || value <= 0 || !Number.isSafeInteger(toMinorUnits(value))) {
    throw new UnappliedCashError('INVALID_AMOUNT', 'Amount must be finite and positive', 400);
  }
  const normalized = roundCurrency(value);
  if (normalized <= 0) throw new UnappliedCashError('INVALID_AMOUNT', 'Amount must be at least 0.01', 400);
  return normalized;
}

function assertId(value: number): void {
  if (!Number.isSafeInteger(value) || value <= 0) throw new UnappliedCashError('INVALID_ID', 'Expected a positive integer ID', 400);
}

export class UnappliedCashService {
  constructor(private readonly db: Database.Database) {}

  receive(input: ReceiveUnappliedCashInput): UnappliedCashResult & { paymentId: number } {
    const amount = positiveAmount(input.amount);
    this.validate(input.customerId, input.date, input.paymentMethod ?? '');
    return this.db.transaction(() => {
      this.period(input.date);
      const customer = this.customer(input.customerId);
      if (customer.current_balance < 0) throw new UnappliedCashError('CUSTOMER_ALREADY_IN_CREDIT', 'Customer is already in credit');
      const paymentId = this.payment(input, amount, 'UNAPPLIED_RECEIPT');
      this.db.prepare(`INSERT INTO customer_credit_sources
        (customer_id,kind,origin_payment_id,credited_amount,refundable_cash_amount,credited_at)
        VALUES (?,'UNAPPLIED_CASH',?,?,?,?)`).run(input.customerId, paymentId, amount, amount, input.date);
      this.post(input.date, 'UNAPPLIED_RECEIPT', paymentId, amount,
        AccountingService._cashOrBankAccountCode(input.paymentMethod), '2110');
      return { paymentId, applicationId: null, amount };
    }).immediate();
  }

  apply(input: ApplyUnappliedCashInput): UnappliedCashResult {
    this.validate(input.customerId, input.date);
    this.key(input.applicationKey);
    if (!input.allocations.length) throw new UnappliedCashError('INVALID_ALLOCATION', 'At least one invoice is required', 400);
    const amounts = new Map<number, number>();
    for (const allocation of input.allocations) {
      assertId(allocation.invoiceId);
      amounts.set(allocation.invoiceId, (amounts.get(allocation.invoiceId) ?? 0) + toMinorUnits(positiveAmount(allocation.amount)));
    }
    const allocations = [...amounts].sort(([left], [right]) => left - right).map(([invoiceId, minor]) => ({ invoiceId, amount: positiveAmount(minor / 100) }));
    const amount = positiveAmount(allocations.reduce((sum, allocation) => sum + toMinorUnits(allocation.amount), 0) / 100);
    const requestHash = hashRequestPayload({ customerId: input.customerId, date: input.date, allocations });
    return this.db.transaction(() => {
      const replay = this.replay(input.customerId, 'APPLY', input.applicationKey, requestHash);
      if (replay) return replay;
      this.period(input.date);
      this.customer(input.customerId);
      for (const allocation of allocations) {
        const invoice = this.db.prepare<[number], { invoice_date: string; status: string; balance_amount: number }>(
          'SELECT invoice_date,status,balance_amount FROM invoices WHERE id=?').get(allocation.invoiceId);
        if (!invoice) throw new UnappliedCashError('INVOICE_NOT_FOUND', 'Invoice not found', 404);
        if (['Cancelled', 'Deleted'].includes(invoice.status) || invoice.invoice_date > input.date) {
          throw new UnappliedCashError('INVALID_INVOICE', 'Invoice is cancelled or dated after application');
        }
        try { assertInvoiceAllocation(this.db, input.customerId, allocation); }
        catch (error) {
          if (!(error instanceof InvoiceAllocationError)) throw error;
          throw new UnappliedCashError('INVALID_ALLOCATION', error.message);
        }
        if (toMinorUnits(allocation.amount) > toMinorUnits(invoice.balance_amount)) {
          throw new UnappliedCashError('INVOICE_OVERALLOCATION', 'Allocation exceeds invoice balance');
        }
      }
      const applicationId = this.application(input.customerId, 'APPLY', input.applicationKey, requestHash, input.date, amount, null);
      for (const allocation of allocations) {
        this.draw(input.customerId, input.date, allocation.amount, 'APPLY', applicationId, allocation.invoiceId, null);
        ledgerUtils.calculateInvoiceBalance(allocation.invoiceId, this.db);
        ledgerUtils.updateInvoiceStatus(allocation.invoiceId, this.db);
      }
      ledgerUtils.createLedgerEntry(input.customerId, input.date, 'PAYMENT', `UNAPPLIED-APPLY-${applicationId}`, 0, amount,
        'Unapplied cash applied to invoices', this.db);
      this.db.prepare('UPDATE customers SET current_balance=ROUND(current_balance-?,2) WHERE id=?').run(amount, input.customerId);
      this.post(input.date, 'UNAPPLIED_APPLY', applicationId, amount, '2110', '1100');
      claimIdempotencyKey(this.db, 'unapplied_cash.apply', `${input.customerId}:${input.applicationKey}`, requestHash, applicationId);
      return { applicationId, paymentId: null, amount };
    }).immediate();
  }

  refund(input: RefundUnappliedCashInput): UnappliedCashResult {
    const amount = positiveAmount(input.amount);
    this.validate(input.customerId, input.date, input.paymentMethod ?? '');
    this.key(input.applicationKey);
    const requestHash = hashRequestPayload({ ...input, amount });
    return this.db.transaction(() => {
      const replay = this.replay(input.customerId, 'REFUND', input.applicationKey, requestHash);
      if (replay) return replay;
      this.period(input.date);
      this.customer(input.customerId);
      const paymentId = this.payment(input, -amount, 'REFUND');
      const applicationId = this.application(input.customerId, 'REFUND', input.applicationKey, requestHash, input.date, amount, paymentId);
      this.draw(input.customerId, input.date, amount, 'REFUND', applicationId, null, paymentId);
      this.post(input.date, 'UNAPPLIED_REFUND', paymentId, amount, '2110', AccountingService._cashOrBankAccountCode(input.paymentMethod));
      this.cashTimeline(input.paymentMethod, input.date);
      claimIdempotencyKey(this.db, 'unapplied_cash.refund', `${input.customerId}:${input.applicationKey}`, requestHash, applicationId);
      return { applicationId, paymentId, amount };
    }).immediate();
  }

  reverse(paymentId: number, attribution?: { voidedBy?: number | null; voidReason?: string }): void {
    assertId(paymentId);
    this.db.transaction(() => {
      const receipt = this.db.prepare<[number], { customer_id: number; payment_date: string; payment_method: string; voided_at: string | null }>(
        "SELECT customer_id,payment_date,payment_method,voided_at FROM payments WHERE id=? AND payment_kind='UNAPPLIED_RECEIPT'").get(paymentId);
      if (!receipt) throw new UnappliedCashError('RECEIPT_NOT_FOUND', 'Unapplied receipt not found', 404);
      if (receipt.voided_at) throw new UnappliedCashError('ALREADY_VOIDED', 'Receipt is already voided');
      this.period(receipt.payment_date);
      const sources = this.db.prepare<[number], { id: number; consumed_amount: number; refunded_amount: number }>(
        "SELECT id,consumed_amount,refunded_amount FROM customer_credit_sources WHERE origin_payment_id=? AND kind='UNAPPLIED_CASH' AND voided_at IS NULL").all(paymentId);
      if (sources.length !== 1) throw new UnappliedCashError('INVALID_SOURCE', 'Receipt source is missing or ambiguous');
      const blockedBy = sources.flatMap(source => {
        const draws = this.db.prepare<[number], { invoice_id: number | null }>(
          'SELECT invoice_id FROM credit_source_consumptions WHERE source_id=? AND voided_at IS NULL').all(source.id);
        return source.consumed_amount > 0 || source.refunded_amount > 0 || draws.length > 0
          ? [{ sourceId: source.id, consumed: source.consumed_amount, invoices: [...new Set(draws.flatMap(draw => draw.invoice_id === null ? [] : [draw.invoice_id]))] }]
          : [];
      });
      if (blockedBy.length) throw new UnappliedCashError('UNAPPLIED_ALREADY_APPLIED', 'Receipt has applied or refunded dependencies', 409, blockedBy);
      const changed = AccountingService.voidJournalLinesByReference(this.db, 'UNAPPLIED_RECEIPT', paymentId, attribution);
      if (changed !== 2) throw new UnappliedCashError('INVALID_JOURNAL', 'Receipt journal is missing or inconsistent');
      this.db.prepare(`UPDATE journal_entries SET voided=1 WHERE reference_type='UNAPPLIED_RECEIPT' AND reference_id=? AND voided=0`).run(paymentId);
      this.db.prepare(`UPDATE customer_credit_sources SET voided_at=CURRENT_TIMESTAMP WHERE origin_payment_id=? AND kind='UNAPPLIED_CASH'`).run(paymentId);
      this.db.prepare('UPDATE payments SET voided_at=CURRENT_TIMESTAMP,voided_by=?,void_reason=? WHERE id=?')
        .run(attribution?.voidedBy ?? null, attribution?.voidReason ?? null, paymentId);
      this.cashTimeline(receipt.payment_method, receipt.payment_date);
      ledgerUtils.rebuildLedgerBalances(receipt.customer_id, this.db);
    }).immediate();
  }

  private validate(customerId: number, date: string, method?: string): void {
    assertId(customerId);
    if (!documentDate('Operation date').safeParse(date).success) {
      throw new UnappliedCashError('INVALID_DATE', 'Operation date must be a real YYYY-MM-DD date', 400);
    }
    if (method !== undefined) {
      try { assertPaymentMethod(method); }
      catch { throw new UnappliedCashError('INVALID_PAYMENT_METHOD', 'Invalid payment method', 400); }
    }
  }

  private customer(customerId: number): { current_balance: number } {
    const customer = this.db.prepare<[number], { current_balance: number }>('SELECT current_balance FROM customers WHERE id=?').get(customerId);
    if (!customer) throw new UnappliedCashError('CUSTOMER_NOT_FOUND', 'Customer not found', 404);
    return customer;
  }

  private period(date: string): void {
    const closed = this.db.prepare('SELECT 1 FROM accounting_periods WHERE status=\'closed\' AND start_date<=? AND end_date>=?').get(date, date);
    if (closed) throw new UnappliedCashError('PERIOD_CLOSED', 'Operation date is in a closed accounting period');
    AccountingService.assertPeriodNotClosed(this.db, date, 'Unapplied cash');
  }

  private key(key: string): void {
    if (typeof key !== 'string' || key.trim().length < 8 || key.length > 200 || key !== key.trim()) {
      throw new UnappliedCashError('INVALID_APPLICATION_KEY', 'Application key must be 8..200 characters without surrounding whitespace', 400);
    }
  }

  private payment(input: ReceiveUnappliedCashInput, amount: number, kind: 'UNAPPLIED_RECEIPT' | 'REFUND'): number {
    const paymentId = insertPaymentRow(this.db, {
      paymentNo: InvoiceModel.generatePaymentNoAtomic(this.db), customerId: input.customerId,
      paymentDate: input.date, amount, paymentMethod: input.paymentMethod,
    });
    this.db.prepare('UPDATE payments SET payment_kind=? WHERE id=?').run(kind, paymentId);
    return paymentId;
  }

  private replay(customerId: number, operation: 'APPLY' | 'REFUND', key: string, hash: string): UnappliedCashResult | null {
    try { beginIdempotentWrite(this.db, operation === 'APPLY' ? 'unapplied_cash.apply' : 'unapplied_cash.refund', `${customerId}:${key}`, hash); }
    catch (error) {
      if (!(error instanceof IdempotencyConflictError)) throw error;
      throw new UnappliedCashError('IDEMPOTENCY_CONFLICT', error.message);
    }
    const existing = this.db.prepare<[number, string, string], { id: number; request_hash: string | null; total_amount: number; payment_id: number | null }>(
      'SELECT id,request_hash,total_amount,payment_id FROM credit_applications WHERE customer_id=? AND operation=? AND application_key=?').get(customerId, operation, key);
    if (!existing) return null;
    if (existing.request_hash !== hash) throw new UnappliedCashError('IDEMPOTENCY_CONFLICT', 'Application key was used for another payload');
    return { applicationId: existing.id, paymentId: existing.payment_id, amount: existing.total_amount };
  }

  private application(customerId: number, operation: string, key: string, hash: string, date: string, amount: number, paymentId: number | null): number {
    return Number(this.db.prepare(`INSERT INTO credit_applications
      (customer_id,operation,application_key,request_hash,operation_date,total_amount,payment_id) VALUES (?,?,?,?,?,?,?)`)
      .run(customerId, operation, key, hash, date, amount, paymentId).lastInsertRowid);
  }

  private draw(customerId: number, date: string, amount: number, kind: 'APPLY' | 'REFUND', applicationId: number, invoiceId: number | null, paymentId: number | null): void {
    const sources = this.db.prepare<[number, string], CashSource>(`SELECT source.id,source.origin_payment_id,
      source.remaining_amount,source.refundable_cash_amount,source.refunded_amount,receipt.amount receipt_amount,
      (SELECT COALESCE(SUM(amount),0) FROM payment_allocations WHERE payment_id=receipt.id AND voided_at IS NULL) allocated_amount
      FROM customer_credit_sources source JOIN payments receipt ON receipt.id=source.origin_payment_id
      WHERE source.customer_id=? AND source.kind='UNAPPLIED_CASH' AND source.voided_at IS NULL
      AND receipt.customer_id=source.customer_id AND receipt.payment_kind='UNAPPLIED_RECEIPT'
      AND receipt.voided_at IS NULL AND receipt.payment_date<=? AND receipt.amount>0
      AND source.remaining_amount>0 AND source.refundable_cash_amount>0
      ORDER BY source.credited_at,source.id`).all(customerId, date);
    let needed = toMinorUnits(amount);
    for (const source of sources) {
      if (needed === 0) break;
      const capacity = Math.min(toMinorUnits(source.remaining_amount), toMinorUnits(source.refundable_cash_amount),
        toMinorUnits(source.receipt_amount) - toMinorUnits(source.allocated_amount) - toMinorUnits(source.refunded_amount));
      if (capacity <= 0) continue;
      const drawn = Math.min(needed, capacity) / 100;
      const update = kind === 'APPLY'
        ? this.db.prepare(`UPDATE customer_credit_sources SET consumed_amount=ROUND(consumed_amount+?,2),refundable_cash_amount=ROUND(refundable_cash_amount-?,2)
            WHERE id=? AND voided_at IS NULL AND ROUND(remaining_amount*100)>=? AND ROUND(refundable_cash_amount*100)>=?`)
        : this.db.prepare(`UPDATE customer_credit_sources SET refunded_amount=ROUND(refunded_amount+?,2),refundable_cash_amount=ROUND(refundable_cash_amount-?,2)
            WHERE id=? AND voided_at IS NULL AND ROUND(remaining_amount*100)>=? AND ROUND(refundable_cash_amount*100)>=?`);
      const changed = update.run(drawn, drawn, source.id, toMinorUnits(drawn), toMinorUnits(drawn));
      if (changed.changes !== 1) throw new UnappliedCashError('SOURCE_CONFLICT', 'Source capacity changed');
      this.db.prepare(`INSERT INTO credit_source_consumptions (source_id,application_id,kind,invoice_id,payment_id,amount)
        VALUES (?,?,?,?,?,?)`).run(source.id, applicationId, kind, invoiceId, paymentId ?? source.origin_payment_id, drawn);
      if (kind === 'APPLY') this.db.prepare('INSERT INTO payment_allocations (payment_id,invoice_id,amount) VALUES (?,?,?)').run(source.origin_payment_id, invoiceId, drawn);
      needed -= toMinorUnits(drawn);
    }
    if (needed > 0) throw new UnappliedCashError('INSUFFICIENT_UNAPPLIED_CASH', 'Insufficient available unapplied cash');
  }

  private post(date: string, reference: string, referenceId: number, amount: number, debitCode: string, creditCode: string): void {
    const debit = AccountingService.getAccountByCode(this.db, debitCode);
    const credit = AccountingService.getAccountByCode(this.db, creditCode);
    if (!debit?.is_active || !credit?.is_active) throw new UnappliedCashError('MISSING_ACCOUNT', 'Required accounting account is missing or inactive');
    AccountingService.postEntry(this.db, {
      entry_date: date, description: reference, reference_type: reference, reference_id: referenceId,
      lines: [{ account_id: debit.id, debit: amount }, { account_id: credit.id, credit: amount }],
    });
  }

  private cashTimeline(method: string, date: string): void {
    try { assertCashTimeline(this.db, { paymentMethod: method, fromDate: date }); }
    catch (error) {
      if (!(error instanceof BusinessRuleError)) throw error;
      throw new UnappliedCashError('INSUFFICIENT_CASH', error.message);
    }
  }
}
