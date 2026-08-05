/**
 * Sales Order calculations — all pure functions, no React imports.
 */

import type { SOFormItem } from '../types';

const FIELD_ORDER: readonly string[] = ['name', 'quantity', 'unitPrice', 'discountValue', 'taxRate'];

export function getFieldOrder(): readonly string[] {
  return FIELD_ORDER;
}

export function getNextField(field: string): string | undefined {
  const index = FIELD_ORDER.indexOf(field);
  return FIELD_ORDER[index + 1];
}

export function createEmptyItemRow(index: number): SOFormItem {
  return {
    id: Date.now() + index,
    item_id: '',
    name: '',
    quantity: 1,
    unitPrice: 0,
    taxRate: 0,
    discount: { type: 'flat', value: 0 },
  };
}

export function padItemsToMinimum(items: SOFormItem[], min = 1): SOFormItem[] {
  if (items.length >= min) return items;
  const padded = [...items];
  const now = Date.now();
  for (let i = items.length; i < min; i++) {
    padded.push({
      id: now + i + 1000,
      item_id: '',
      name: '',
      quantity: 1,
      unitPrice: 0,
      taxRate: 0,
      discount: { type: 'flat', value: 0 },
    });
  }
  return padded;
}

export function calculateItemDiscount(item: SOFormItem): number {
  const subtotal = (item.quantity || 0) * (item.unitPrice || 0);
  if (item.discount?.type === 'percentage') {
    return (subtotal * (item.discount.value || 0)) / 100;
  }
  return Number(item.discount?.value) || 0;
}

export function calculateItemTotal(item: SOFormItem): number {
  const subtotal = (item.quantity || 0) * (item.unitPrice || 0);
  const discount = calculateItemDiscount(item);
  const afterDiscount = subtotal - discount;
  const taxAmount = (afterDiscount * (item.taxRate || 0)) / 100;
  return afterDiscount + taxAmount;
}

export function calculateSubtotal(items: SOFormItem[]): number {
  return items.reduce((sum, item) => sum + (item.quantity || 0) * (item.unitPrice || 0), 0);
}

export function calculateDiscount(items: SOFormItem[]): number {
  return items.reduce((sum, item) => sum + calculateItemDiscount(item), 0);
}

export function calculateTax(items: SOFormItem[]): number {
  return items.reduce((sum, item) => {
    const subtotal = (item.quantity || 0) * (item.unitPrice || 0);
    const discount = calculateItemDiscount(item);
    const afterDiscount = subtotal - discount;
    return sum + (afterDiscount * (item.taxRate || 0)) / 100;
  }, 0);
}

export function calculateTotal(items: SOFormItem[]): number {
  return calculateSubtotal(items) - calculateDiscount(items) + calculateTax(items);
}

export { getStatusColor } from './statusColors';
