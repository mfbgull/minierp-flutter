/**
 * Invoice calculations — all pure functions, no React imports.
 * Extracted from SalesInvoicePage.jsx for testability.
 */

import type { InvoiceFormItem, Discount, InvoiceFormState } from '../types';

/* ── Item-level calculations ────────────────────────────────────── */

/**
 * Calculate the discount amount for a single item, given the discountScope.
 */
export function calculateItemBase(item: InvoiceFormItem): number {
  // Loose lines where the user typed the Amount use it verbatim —
  // qty × rate would differ by the quantity rounding.
  if (item.sale_type === 'loose' && item.lastEditedField === 'amount') {
    return item.amount || 0;
  }
  return (item.quantity || 0) * (item.rate || 0);
}

/**
 * Calculate the discount amount for a single item, given the discountScope.
 */
export function calculateItemDiscount(item: InvoiceFormItem): number {
  const subtotal = calculateItemBase(item);
  if (item.discount?.type === 'percentage') {
    return (subtotal * (item.discount.value || 0)) / 100;
  }
  return item.discount?.value || 0;
}

/**
 * Calculate the total for a single item (subtotal − discount + tax).
 */
export function calculateItemTotal(item: InvoiceFormItem, discountScope: 'item' | 'invoice' = 'item'): number {
  const subtotal = calculateItemBase(item);
  const discount = discountScope === 'item' ? calculateItemDiscount(item) : 0;
  const afterDiscount = subtotal - discount;
  const taxAmount = (afterDiscount * (item.tax || 0)) / 100;
  return afterDiscount + taxAmount;
}

/* ── Aggregate calculations ─────────────────────────────────────── */

/**
 * Calculate the subtotal (sum of qty × rate for all items).
 */
export function calculateSubtotal(items: InvoiceFormItem[]): number {
  return items.reduce((sum, item) => sum + calculateItemBase(item), 0);
}

/**
 * Calculate total tax across all items.
 */
export function calculateTax(items: InvoiceFormItem[], discountScope: 'item' | 'invoice' = 'item'): number {
  return items.reduce((sum, item) => {
    const subtotal = calculateItemBase(item);
    const discount = discountScope === 'item' ? calculateItemDiscount(item) : 0;
    const afterDiscount = subtotal - discount;
    return sum + (afterDiscount * (item.tax || 0)) / 100;
  }, 0);
}

/**
 * Calculate total discount across all items (or invoice-level discount).
 */
export function calculateDiscount(
  items: InvoiceFormItem[],
  discountScope: 'item' | 'invoice',
  invoiceDiscount: Discount,
): number {
  if (discountScope === 'item') {
    return items.reduce((sum, item) => sum + calculateItemDiscount(item), 0);
  }
  const subtotal = calculateSubtotal(items);
  if (invoiceDiscount.type === 'percentage') {
    return (subtotal * (invoiceDiscount.value || 0)) / 100;
  }
  return invoiceDiscount.value || 0;
}

/**
 * Calculate the grand total (subtotal + tax − discount).
 */
export function calculateTotal(
  items: InvoiceFormItem[],
  discountScope: 'item' | 'invoice',
  invoiceDiscount: Discount,
): number {
  return calculateSubtotal(items) + calculateTax(items, discountScope) - calculateDiscount(items, discountScope, invoiceDiscount);
}

/* ── Field navigation ───────────────────────────────────────────── */

const FIELD_ORDER_ITEM = ['description', 'quantity', 'rate', 'discountValue', 'tax', 'amount'] as const;
const FIELD_ORDER_INVOICE = ['description', 'quantity', 'rate', 'tax', 'amount'] as const;

export function getFieldOrder(discountScope: 'item' | 'invoice'): readonly string[] {
  return discountScope === 'item' ? FIELD_ORDER_ITEM : FIELD_ORDER_INVOICE;
}

export function getNextField(field: string, discountScope: 'item' | 'invoice'): string | undefined {
  const order = getFieldOrder(discountScope);
  const currentIndex = order.indexOf(field);
  return order[currentIndex + 1];
}

/* ── Item helpers ───────────────────────────────────────────────── */

export function createEmptyItemRow(index: number): InvoiceFormItem {
  return {
    id: Date.now() + index,
    item_id: '',
    description: '',
    quantity: 1,
    rate: 0,
    tax: 0,
    discount: { type: 'flat', value: 0 },
    sale_type: 'packed',
    amount: 0,
    lastEditedField: null,
    qty_decimal_precision: 0,
    rounding_step: null,
  };
}

export function padItemsToMinimum(items: InvoiceFormItem[], min = 1): InvoiceFormItem[] {
  if (items.length >= min) return items;
  const padded = [...items];
  const now = Date.now();
  for (let i = items.length; i < min; i++) {
    padded.push({
      id: now + i + 1000,
      item_id: '',
      description: '',
      quantity: 0,
      rate: 0,
      tax: 0,
      discount: { type: 'flat', value: 0 },
      sale_type: 'packed',
      amount: 0,
      lastEditedField: null,
      qty_decimal_precision: 0,
      rounding_step: null,
    });
  }
  return padded;
}

/* ── Status helpers ─────────────────────────────────────────────── */

// .ts extension so Node's test runner can load this module directly (Vite handles it too)
export { getStatusColor } from './statusColors.ts';

export function getExpectedStatus(
  invoiceId: string | undefined,
  recordPayment: boolean,
  paymentMethods: Array<{ amount: number }>,
  items: InvoiceFormItem[],
  discountScope: 'item' | 'invoice',
  invoiceDiscount: Discount,
  currentStatus?: string,
): string {
  if (!invoiceId) {
    if (recordPayment) {
      const total = calculateTotal(items, discountScope, invoiceDiscount);
      const paymentAmount = paymentMethods.reduce((sum, m) => sum + (parseFloat(String(m.amount)) || 0), 0);
      if (paymentAmount >= total) return 'Paid';
      if (paymentAmount > 0) return 'Partially Paid';
    }
    return 'Unpaid';
  }
  return currentStatus || 'Unpaid';
}

/* ── Invoice number generation ──────────────────────────────────── */

export function generateInvoiceNo(): string {
  return `INV-${new Date().getFullYear()}-${String(Date.now() % 1000000).padStart(6, '0')}`;
}

/* ── Default invoice state ──────────────────────────────────────── */

export function createDefaultInvoice(): InvoiceFormState {
  return {
    invoice_no: generateInvoiceNo(),
    status: 'Unpaid',
    invoice_date: new Date().toISOString().split('T')[0],
    due_date: new Date(Date.now() + 14 * 24 * 60 * 60 * 1000).toISOString().split('T')[0],
    customer_id: '',
    customer_name: '',
    customer_email: '',
    customer_phone: '',
    customer_address: '',
    discountScope: 'invoice',
    discount: { type: 'flat', value: 0 },
    items: Array.from({ length: 1 }, (_, i) => createEmptyItemRow(i)),
    notes: 'Thank you for your business. Payment is due within 14 days.',
    terms: 'Net 14 days. Late payments subject to 1.5% monthly interest.',
    created_by: null,
    company: {
      name: 'Mini ERP',
      email: 'support@minierp.com',
      phone: '+1 123 456 7890',
      address: '456 Enterprise Ave, BC 12345',
      taxId: 'TAX-123456789',
    },
    payment: {
      record_payment: true,
      payment_date: new Date().toISOString().split('T')[0],
      payment_amount: 0,
      payment_method: 'Cash',
      reference_no: '',
      payment_notes: '',
    },
    paymentMethods: [{ id: Date.now(), method: 'Cash', amount: 0, reference_no: '' }],
  };
}
