/**
 * V2 Invoice Creation — Types
 *
 * Domain-specific types for the invoice creation modal.
 * Reuses Discount, PaymentMethodEntry, and InvoiceSubmitData from types/index.ts.
 */

import type { Discount, PaymentMethodEntry, PriceHistory, SaleType } from './index';

/* ── Customer ──────────────────────────────────────────────────── */

export interface InvoiceV2Customer {
  id: number;
  name: string;
  code?: string;
  email: string;
  phone: string;
  address: string;
  balance: number;
  creditLimit: number;
  creditUtilization: number;
}

/* ── Items ──────────────────────────────────────────────────────── */

export interface InvoiceV2FormItem {
  /** Local temp ID (Date.now()) */
  id: number;
  /** Selected inventory item ID (empty string if not yet selected) */
  itemId: number | string;
  description: string;
  quantity: number;
  rate: number;
  tax: number;
  discount: Discount;
  /** 'packed' (qty drives amount) or 'loose' (bidirectional). Defaults to packed. */
  sale_type?: SaleType;
  /** Explicit line amount — authoritative only for loose amount-driven lines. */
  amount?: number;
  /** Which field the user last edited, driving loose recalculation. */
  lastEditedField?: 'quantity' | 'amount' | null;
  qty_decimal_precision?: number;
  rounding_step?: number | null;
}

/* ── Payment ────────────────────────────────────────────────────── */

export interface InvoiceV2Payment {
  recordPayment: boolean;
  paymentDate: string;
  paymentMethods: PaymentMethodEntry[];
  paymentNotes: string;
}

/* ── Source document tracking ───────────────────────────────────── */

export interface InvoiceV2Source {
  type: 'quotation' | 'so';
  id: number;
  reference: string; // e.g. "Q-2026-001"
}

/* ── Company info ───────────────────────────────────────────────── */

export interface InvoiceV2Company {
  name: string;
  email: string;
  phone: string;
  address: string;
  taxId?: string;
}

/* ── Form state ──────────────────────────────────────────────────── */

export interface InvoiceV2State {
  invoiceNo: string;
  customer: InvoiceV2Customer | null;
  invoiceDate: string;
  dueDate: string;
  discountScope: 'item' | 'invoice';
  discount: Discount;
  items: InvoiceV2FormItem[];
  notes: string;
  terms: string;
  source: InvoiceV2Source | null;
  payment: InvoiceV2Payment;
  company: InvoiceV2Company;
}

/* ── Cell navigation ───────────────────────────────────────────── */

export type CellColumn =
  | 'description'
  | 'quantity'
  | 'rate'
  | 'discountValue'
  | 'tax'
  | 'amount'
  | 'delete';

export interface CellPosition {
  /** Index in the items array */
  row: number;
  /** Column identifier */
  col: CellColumn;
}

/* ── Props for modal components ────────────────────────────────── */

export interface InvoiceV2ModalProps {
  isOpen: boolean;
  onClose: () => void;
  /** Called after a successful save so the parent can handle navigation */
  onCreated: (invoiceId: number, invoiceNo: string) => void;
  /** Optional source document pre-fill params */
  source?: InvoiceV2Source | null;
  /** Optional edit mode params */
  editInvoiceId?: number;
}

export interface InvoiceV2HeaderProps {
  invoiceNo: string;
  source: InvoiceV2Source | null;
  onClose: () => void;
}

export interface InvoiceV2CustomerPanelProps {
  /** Currently selected customer, or null */
  customer: InvoiceV2Customer | null;
  /** All customers from API */
  customers: Array<{
    id: number;
    customer_name: string;
    customer_code?: string;
    email?: string;
    phone?: string;
    billing_address?: string;
    credit_limit?: number;
  }>;
  loading: boolean;
  onSelect: (customer: InvoiceV2Customer) => void;
  formatCurrency: (amount: number | string | null | undefined) => string;
}

export interface InvoiceV2ItemsGridProps {
  items: InvoiceV2FormItem[];
  discountScope: 'item' | 'invoice';
  /** Inventory items for the searchable description dropdown */
  inventoryItems: Array<{
    id: number;
    item_name: string;
    item_code: string;
    current_stock?: number;
    standard_selling_price?: number;
    is_raw_material?: boolean | number;
    is_finished_good?: boolean | number;
    is_purchased?: boolean | number;
    is_manufactured?: boolean | number;
    sale_type?: SaleType;
    qty_decimal_precision?: number;
    rounding_step?: number | null;
  }>;
  onUpdateItem: (id: number, field: string, value: unknown) => void;
  onRemoveItem: (id: number) => void;
  onAddNewItem: () => number;
  onUpdateDiscountScope?: (scope: 'item' | 'invoice') => void;
  formatCurrency: (amount: number | string | null | undefined) => string;
  calculateItemTotal: (item: InvoiceV2FormItem) => number;
  getCurrencySymbol: () => string;
}

export interface InvoiceV2TotalsPanelProps {
  items: InvoiceV2FormItem[];
  discountScope: 'item' | 'invoice';
  discount: Discount;
  notes: string;
  terms: string;
  onUpdateDiscount: (discount: Discount) => void;
  onUpdateNotes: (notes: string) => void;
  onUpdateTerms: (terms: string) => void;
  formatCurrency: (amount: number | string | null | undefined) => string;
  getCurrencySymbol: () => string;
  calculateSubtotal: () => number;
  calculateTax: () => number;
  calculateDiscount: () => number;
  calculateTotal: () => number;
}

export interface InvoiceV2PaymentSectionProps {
  payment: InvoiceV2Payment;
  totalAmount: number;
  onUpdatePayment: (payment: Partial<InvoiceV2Payment>) => void;
  onAddPaymentMethod: () => void;
  onRemovePaymentMethod: (id: number) => void;
  onUpdatePaymentMethod: (id: number, field: string, value: string) => void;
  formatCurrency: (amount: number | string | null | undefined) => string;
}

export interface InvoiceV2FooterProps {
  isSaving: boolean;
  isEditMode: boolean;
  onCreateAndView: () => void;
  onCreateAndNew: () => void;
  onCancel: () => void;
}
