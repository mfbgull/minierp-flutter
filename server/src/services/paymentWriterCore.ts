/**
 * TASK 33 — write primitives shared by the customer and supplier payment
 * services: the document-number-independent payment INSERT, the
 * cash-method whitelist and the closed-period guard.
 */
import type Database from 'better-sqlite3';
import AccountingService from './accountingService';
import { isValidPaymentMethod } from './cashService';
import { PAYMENT_METHODS_HINT } from './paymentValidation';

export type PaymentRowInput = {
  readonly paymentNo: string;
  readonly paymentDate: string;
  readonly amount: number;
  readonly paymentMethod: string;
  readonly referenceNo?: string | null;
  readonly notes?: string | null;
  readonly customerId?: number;
  readonly supplierId?: number;
  readonly purchaseOrderId?: number | null;
};

export function assertPaymentMethod(method: string | undefined): void {
  if (!isValidPaymentMethod(method)) {
    throw new Error(`Invalid payment_method "${method ?? ''}" — ${PAYMENT_METHODS_HINT}`);
  }
}

/** H6: a closed period must not gain new money movements, only lose them. */
export function assertPeriodOpen(db: Database.Database, paymentDate: string): void {
  AccountingService.assertPeriodNotClosed(db, paymentDate, 'Payment');
}

export function insertPaymentRow(db: Database.Database, row: PaymentRowInput): number {
  const result = db.prepare(`
    INSERT INTO payments (
      payment_no, customer_id, supplier_id, payment_date, amount,
      payment_method, reference_no, notes, purchase_order_id
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    row.paymentNo,
    row.customerId ?? null,
    row.supplierId ?? null,
    row.paymentDate,
    row.amount,
    row.paymentMethod,
    row.referenceNo ?? '',
    row.notes ?? '',
    row.purchaseOrderId ?? null,
  );
  return result.lastInsertRowid as number;
}
