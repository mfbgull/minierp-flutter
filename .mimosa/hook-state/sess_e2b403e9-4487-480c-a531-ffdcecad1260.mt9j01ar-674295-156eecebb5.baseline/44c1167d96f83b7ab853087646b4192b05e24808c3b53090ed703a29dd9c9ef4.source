/**
 * Guards the loose-item branch in the invoice aggregate calculations.
 * Run with: node --test --experimental-strip-types src/utils/__tests__/invoiceCalculations.test.ts
 */

import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  calculateItemBase,
  calculateItemTotal,
  calculateSubtotal,
  calculateTax,
  calculateDiscount,
  calculateTotal,
} from '../invoiceCalculations.ts';

const packed = {
  id: 1,
  item_id: 1,
  description: 'Soap',
  quantity: 2,
  rate: 50,
  tax: 10,
  discount: { type: 'flat' as const, value: 0 },
  sale_type: 'packed' as const,
};

// ₹100 of rice at ₹150/kg → 0.667 kg. qty × rate = 100.05, but the customer pays 100.
const looseAmountDriven = {
  id: 2,
  item_id: 2,
  description: 'Rice',
  quantity: 0.667,
  rate: 150,
  amount: 100,
  tax: 0,
  discount: { type: 'flat' as const, value: 0 },
  sale_type: 'loose' as const,
  lastEditedField: 'amount' as const,
};

const looseQtyDriven = { ...looseAmountDriven, id: 3, lastEditedField: 'quantity' as const };

test('loose amount-driven lines bill the entered amount, not qty × rate', () => {
  assert.equal(calculateItemBase(looseAmountDriven), 100);
  assert.equal(calculateItemTotal(looseAmountDriven), 100);
  // qty-driven falls back to qty × rate (raw float, same as packed lines always have)
  assert.ok(Math.abs(calculateItemBase(looseQtyDriven) - 100.05) < 1e-9);
});

test('packed lines are unchanged', () => {
  assert.equal(calculateItemBase(packed), 100);
  assert.equal(calculateItemTotal(packed), 110); // + 10% tax
});

test('aggregates use the same base as the line total', () => {
  const items = [packed, looseAmountDriven];
  assert.equal(calculateSubtotal(items), 200);
  assert.equal(calculateTax(items, 'item'), 10);
  assert.equal(calculateTotal(items, 'invoice', { type: 'flat', value: 0 }), 210);
  // Sum of line totals matches subtotal + tax − discount
  const lineSum = items.reduce((s, i) => s + calculateItemTotal(i, 'item'), 0);
  assert.equal(lineSum, 210);
});

test('per-item discount applies to the loose amount', () => {
  const discounted = {
    ...looseAmountDriven,
    discount: { type: 'percentage' as const, value: 10 },
  };
  assert.equal(calculateItemTotal(discounted, 'item'), 90);
  assert.equal(calculateDiscount([discounted], 'item', { type: 'flat', value: 0 }), 10);
});
