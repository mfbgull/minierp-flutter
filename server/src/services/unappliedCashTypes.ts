export class UnappliedCashError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly status: 400 | 404 | 409 = 409,
    readonly blockedBy: readonly { sourceId: number; consumed: number; invoices: number[] }[] = [],
  ) {
    super(message);
    this.name = 'UnappliedCashError';
  }
}

export interface ReceiveUnappliedCashInput {
  customerId: number;
  amount: number;
  date: string;
  paymentMethod: string;
}

export interface ApplyUnappliedCashInput {
  customerId: number;
  date: string;
  applicationKey: string;
  allocations: readonly { invoiceId: number; amount: number }[];
}

export interface RefundUnappliedCashInput extends ReceiveUnappliedCashInput {
  applicationKey: string;
}

export interface UnappliedCashResult {
  paymentId: number | null;
  applicationId: number | null;
  amount: number;
}
