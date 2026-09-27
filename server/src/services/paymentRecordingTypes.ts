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
};

export type ExistingPaymentAllocationInput = {
  readonly paymentId: number;
  readonly customerId: number;
  readonly allocations: readonly PaymentAllocation[];
};

export type PaymentRecordingResult = {
  readonly paymentId: number;
  readonly paymentNo: string;
  readonly amount: number;
};
