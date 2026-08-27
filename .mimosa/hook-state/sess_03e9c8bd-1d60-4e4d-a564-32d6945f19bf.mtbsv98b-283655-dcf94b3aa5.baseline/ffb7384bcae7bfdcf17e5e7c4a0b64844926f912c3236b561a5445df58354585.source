/**
 * V2 Invoice Calculations
 *
 * Re-exports all calculation functions from the existing invoiceCalculations
 * and adds v2-specific helpers for default state, etc.
 */

import {
  calculateItemTotal as origItemTotal,
  calculateSubtotal as origSubtotal,
  calculateTax as origTax,
  calculateDiscount as origDiscount,
  calculateTotal as origTotal,
  generateInvoiceNo as origGenNo,
} from './invoiceCalculations';

import type { InvoiceFormItem, Discount } from '../types';
import type { InvoiceV2State, InvoiceV2FormItem } from '../types/invoiceV2';

/* ── Re-exports (wrapped for v2 types) ─────────────────────────── */

// NOTE: The `as unknown as InvoiceFormItem` cast is safe because:
// InvoiceV2FormItem and InvoiceFormItem share the same shape for all
// fields used in calculations: quantity, rate, tax, discount.
// The only difference is itemId (v2) vs item_id (v1) which calculations
// never access. If either interface changes calculation-relevant fields,
// update this mapping.
export function calculateItemTotal(item: InvoiceV2FormItem, discountScope: 'item' | 'invoice' = 'item'): number {
  return origItemTotal(item as unknown as InvoiceFormItem, discountScope);
}

export function calculateSubtotal(items: InvoiceV2FormItem[]): number {
  return origSubtotal(items as unknown as InvoiceFormItem[]);
}

export function calculateTax(items: InvoiceV2FormItem[], discountScope: 'item' | 'invoice' = 'item'): number {
  return origTax(items as unknown as InvoiceFormItem[], discountScope);
}

export function calculateDiscount(
  items: InvoiceV2FormItem[],
  discountScope: 'item' | 'invoice',
  invoiceDiscount: Discount,
): number {
  return origDiscount(items as unknown as InvoiceFormItem[], discountScope, invoiceDiscount);
}

export function calculateTotal(
  items: InvoiceV2FormItem[],
  discountScope: 'item' | 'invoice',
  invoiceDiscount: Discount,
): number {
  return origTotal(items as unknown as InvoiceFormItem[], discountScope, invoiceDiscount);
}

export function generateInvoiceNo(): string {
  return origGenNo();
}

/* ── Default state factory ─────────────────────────────────────── */

export function createEmptyInvoiceV2Item(id: number = Date.now()): InvoiceV2FormItem {
  return {
    id,
    itemId: '',
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

export function createDefaultInvoiceV2State(): InvoiceV2State {
  return {
    invoiceNo: generateInvoiceNo(),
    customer: null,
    invoiceDate: new Date().toISOString().split('T')[0],
    dueDate: new Date(Date.now() + 14 * 24 * 60 * 60 * 1000).toISOString().split('T')[0],
    discountScope: 'invoice',
    discount: { type: 'flat', value: 0 },
    items: [createEmptyInvoiceV2Item()],
    notes: 'Thank you for your business. Payment is due within 14 days.',
    terms: 'Net 14 days. Late payments subject to 1.5% monthly interest.',
    source: null,
    payment: {
      recordPayment: true,
      paymentDate: new Date().toISOString().split('T')[0],
      paymentMethods: [{ id: Date.now(), method: 'Cash', amount: 1, reference_no: '' }],
      paymentNotes: '',
    },
    // Note: amount defaults to 1 instead of 0 so the invoice total auto-fills correctly
    // The actual total is synced when items change in the page
    company: {
      name: 'Mini ERP',
      email: 'support@minierp.com',
      phone: '+1 123 456 7890',
      address: '456 Enterprise Ave, BC 12345',
      taxId: 'TAX-123456789',
    },
  };
}
