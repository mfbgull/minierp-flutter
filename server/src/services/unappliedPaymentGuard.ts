import type Database from 'better-sqlite3';
import { UnappliedCashError } from './unappliedCashTypes';

export function assertLegacyPaymentAllowed(db: Database.Database, paymentId: number): void {
  const supported = db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='customer_credit_sources'").get();
  if (!supported) return;
  const owned = db.prepare(`SELECT 1 FROM customer_credit_sources WHERE origin_payment_id=? AND kind='UNAPPLIED_CASH'
    UNION ALL SELECT 1 FROM credit_source_consumptions WHERE payment_id=? LIMIT 1`).get(paymentId, paymentId);
  if (owned) throw new UnappliedCashError('UNAPPLIED_OPERATION_REQUIRED', 'Use the unapplied cash operation for this payment');
}

export function assertLegacyInvoiceAllocationsAllowed(db: Database.Database, invoiceId: number): void {
  const supported = db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='credit_source_consumptions'").get();
  if (!supported) return;
  const owned = db.prepare('SELECT 1 FROM credit_source_consumptions WHERE invoice_id=? AND voided_at IS NULL LIMIT 1').get(invoiceId);
  if (owned) throw new UnappliedCashError('UNAPPLIED_ALREADY_APPLIED', 'Invoice has unapplied cash applications; reversal is blocked');
}
