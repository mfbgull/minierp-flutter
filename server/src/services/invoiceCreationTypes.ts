import type { InvoiceStatus } from '../types';

export type InvoiceCreationSource = 'DIRECT' | 'MOBILE' | 'POS' | 'SALES_ORDER';

export type InvoiceCreationItem = {
  readonly item_id: number;
  readonly quantity: number;
  readonly unit_price: number;
  readonly tax_rate?: number;
  readonly discount_type?: 'none' | 'percentage' | 'flat';
  readonly discount_value?: number;
  readonly warehouse_id?: number;
  readonly amount?: number;
};

export type InvoiceCreationPayment = {
  readonly amount: number;
  readonly payment_date?: string;
  readonly payment_method?: string;
  readonly reference_no?: string;
  readonly notes?: string;
};

export type InvoiceCreationIdempotency = {
  readonly scope: string;
  readonly key: string;
  readonly hash: string;
};

export type InvoiceCreationInput = {
  readonly source: InvoiceCreationSource;
  readonly userId: number;
  readonly customerId: number;
  readonly customerName?: string;
  readonly invoiceNo?: string;
  readonly invoiceDate: string;
  readonly dueDate?: string | null;
  readonly status?: InvoiceStatus;
  readonly soId?: number;
  readonly quotationId?: number;
  readonly notes?: string;
  readonly terms?: string;
  readonly warehouseId?: number;
  readonly items: readonly InvoiceCreationItem[];
  readonly discountScope?: 'item' | 'invoice';
  readonly discountType?: 'flat' | 'percentage';
  readonly discountValue?: number;
  readonly totalAmount?: number;
  readonly recordPayment?: boolean;
  readonly payment?: InvoiceCreationPayment;
  /**
   * N payment legs for a split settlement. Present (even as `[]`) selects
   * the multi-leg path; absent keeps the single `payment` field, which is
   * what every existing caller sends.
   */
  readonly payments?: readonly InvoiceCreationPayment[];
  readonly creditOffset?: number;
  readonly draftId?: number;
  readonly afterCreate?: (invoiceId: number, invoiceNo: string) => void;
  readonly idempotency?: InvoiceCreationIdempotency;
};

export type InvoiceCreationItemResult = {
  readonly itemId: number;
  readonly quantity: number;
  readonly unitPrice: number;
  readonly amount: number;
  readonly warehouseId: number;
  readonly batchIds: readonly (number | null)[];
};

export type InvoiceCreationResult = {
  readonly invoiceId: number;
  readonly invoiceNo: string;
  readonly totalAmount: number;
  readonly paidAmount: number;
  readonly balanceAmount: number;
  readonly taxAmount: number;
  readonly cogsAmount: number;
  readonly paymentId: number | null;
  readonly paymentNo: string | null;
  readonly replayed: boolean;
  readonly items: readonly InvoiceCreationItemResult[];
};
