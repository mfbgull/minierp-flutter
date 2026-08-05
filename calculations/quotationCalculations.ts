import type { QuotationFormItem } from '../types';

// ============================================
// Item Row Utilities
// ============================================

export const createEmptyItemRow = (index: number): QuotationFormItem => ({
  id: Date.now() + index,
  item_id: 0,
  description: '',
  quantity: 1,
  rate: 0,
  tax: 0,
  discount: { type: 'flat', value: 0 }
});

export const padItemsToMinimum = (items: QuotationFormItem[], min = 1): QuotationFormItem[] => {
  if (items.length >= min) return items;
  const padded = [...items];
  const now = Date.now();
  for (let i = items.length; i < min; i++) {
    padded.push({
      id: now + i + 1000,
      item_id: 0,
      description: '',
      quantity: 1,
      rate: 0,
      tax: 0,
      discount: { type: 'flat', value: 0 }
    });
  }
  return padded;
};

// ============================================
// Calculations
// ============================================

export const calculateItemDiscount = (item: QuotationFormItem): number => {
  const subtotal = item.quantity * item.rate;
  if (item.discount.type === 'percentage') {
    return (subtotal * item.discount.value) / 100;
  }
  return Number(item.discount.value) || 0;
};

export const calculateItemTotal = (item: QuotationFormItem): number => {
  const subtotal = item.quantity * item.rate;
  const discount = calculateItemDiscount(item);
  const afterDiscount = subtotal - discount;
  const taxAmount = (afterDiscount * item.tax) / 100;
  return afterDiscount + taxAmount;
};

export const calculateSubtotal = (items: QuotationFormItem[]): number => {
  return items.reduce((sum, item) => sum + (item.quantity * item.rate), 0);
};

export const calculateDiscount = (items: QuotationFormItem[]): number => {
  return items.reduce((sum, item) => sum + calculateItemDiscount(item), 0);
};

export const calculateTax = (items: QuotationFormItem[]): number => {
  return items.reduce((sum, item) => {
    const subtotal = item.quantity * item.rate;
    const discount = calculateItemDiscount(item);
    const afterDiscount = subtotal - discount;
    return sum + (afterDiscount * item.tax / 100);
  }, 0);
};

export const calculateTotal = (items: QuotationFormItem[]): number => {
  return calculateSubtotal(items) - calculateDiscount(items) + calculateTax(items);
};

// ============================================
// UI Utilities
// ============================================

export { getStatusColor } from './statusColors';

// ============================================
// Field Navigation
// ============================================

export const getFieldOrder = (): readonly string[] => {
  return ['description', 'quantity', 'rate', 'discountValue', 'tax'] as const;
};

export const getNextField = (currentField: string): string | undefined => {
  const fieldOrder = getFieldOrder();
  const currentIndex = fieldOrder.indexOf(currentField);
  return fieldOrder[currentIndex + 1];
};

// ============================================
// Validation / Submission
// ============================================

export const getSellableItems = (items: Array<{ is_raw_material?: boolean | number; is_finished_good?: number; is_purchased?: number }>): Array<{ id: number; item_name: string; item_code: string; current_stock?: number; standard_selling_price?: number }> => {
  return items.filter(item =>
    !item.is_raw_material &&
    (item.is_finished_good === 1 || item.is_purchased === 1)
  ).slice(0, 10) as Array<{ id: number; item_name: string; item_code: string; current_stock?: number; standard_selling_price?: number }>;
};

export const filterFilledItems = (items: QuotationFormItem[]): QuotationFormItem[] => {
  return items.filter(item => item.item_id || item.description);
};
