/**
 * TASK 33 — payment recording contracts.
 *
 * `amount` is always POSITIVE at the boundary. The service owns the sign
 * convention for each mode: a REFUND writes a negative `payments.amount`
 * and a negative allocation (the shape the receipt, allocation and
 * position readers already expect), while the ledger debit and the GL
 * cash exit stay positive.
 */

export type CustomerPaymentMode =
  /** Customer pays down one or more invoices that already exist. */
  | 'RECEIPT'
  /**
   * Payment recorded in the same transaction that creates the invoice. The
   * invoice row is already stored as settled, so the allocation ceiling is
   * the invoice's collectible value rather than its remaining balance.
   */
  | 'INVOICE_SETTLEMENT'
  /** Money leaves the business back to the customer (return settlement). */
  | 'REFUND'
  /** Return credit applied against an invoice — no cash moves. */
  | 'CREDIT_APPLICATION';

export type PaymentAllocation = {
  readonly invoiceId: number;
  readonly amount: number;
};

export type CustomerPaymentInput = {
  readonly mode: CustomerPaymentMode;
  readonly customerId: number;
  readonly paymentDate: string;
  readonly amount: number;
  readonly paymentMethod: string;
  readonly allocations: readonly PaymentAllocation[];
  readonly referenceNo?: string | null;
  readonly notes?: string | null;
  readonly userId?: number | null;
  /** Supplied by callers that already generated a document number. */
  readonly paymentNo?: string;
  /**
   * audit-3 task 08. When present, the key is checked and claimed inside
   * this write's transaction: a retry after a lost response replays
   * `replayedPaymentId` instead of recording the money twice.
   */
  readonly idempotency?: IdempotentClaim;
};

export type SupplierPaymentAllocation = {
  readonly kind: 'purchase_order' | 'purchase';
  readonly id: number;
  readonly amount: number;
};

export type SupplierPaymentInput = {
  readonly supplierId: number;
  readonly paymentDate: string;
  readonly amount: number;
  readonly paymentMethod: string;
  readonly allocations: readonly SupplierPaymentAllocation[];
  readonly referenceNo?: string | null;
  readonly notes?: string | null;
  readonly userId?: number | null;
  readonly paymentNo?: string;
  /** audit-3 task 08 — claimed inside the supplier payment transaction. */
  readonly idempotency?: IdempotentClaim;
};

export type ExistingPaymentAllocationInput = {
  readonly paymentId: number;
  readonly customerId: number;
  readonly allocations: readonly PaymentAllocation[];
  /** audit-3 task 08 — claimed inside the allocation transaction. */
  readonly idempotency?: IdempotentClaim;
};

/** audit-3 task 08: an idempotency key plus the hash of the request it claims. */
export type IdempotentClaim = {
  readonly scope: string;
  readonly key: string;
  readonly hash: string;
};

export type PaymentRecordingResult = {
  readonly paymentId: number;
  readonly paymentNo: string;
  readonly amount: number;
};
