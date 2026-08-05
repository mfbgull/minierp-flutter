/**
 * Run with: node --test --experimental-strip-types src/utils/__tests__/invoiceLineCalc.test.ts
 * (from the client/ directory — no test framework dependency needed)
 */

import assert from 'node:assert/strict';
import { test } from 'node:test';

import { roundToStep, calcItemLine, applyLineFieldUpdate, lineIssue } from '../invoiceLineCalc.ts';

test('roundToStep', () => {
  assert.equal(roundToStep(0.6666, 0.001), 0.667);
  assert.equal(roundToStep(1.234, 0.01), 1.23);
  assert.equal(roundToStep(2.6, 1), 3);
  assert.equal(roundToStep(1.2, 0.5), 1);
  assert.equal(roundToStep(5, 0), 5); // no step → passthrough
});

test('packed items: quantity drives amount', () => {
  assert.deepEqual(calcItemLine({ sale_type: 'packed', quantity: 5, rate: 150 }), {
    quantity: 5,
    amount: 750,
  });
  assert.deepEqual(calcItemLine({ sale_type: 'packed', quantity: 3, rate: 10.33 }), {
    quantity: 3,
    amount: 30.99,
  });
  // sale_type omitted defaults to packed
  assert.deepEqual(calcItemLine({ quantity: 2, rate: 4 }), { quantity: 2, amount: 8 });
});

test('loose: amount drives quantity', () => {
  assert.deepEqual(
    calcItemLine({
      sale_type: 'loose',
      amount: 100,
      rate: 150,
      lastEditedField: 'amount',
      qty_decimal_precision: 3,
    }),
    { quantity: 0.667, amount: 100 },
  );
});

test('loose: amount with zero rate errors', () => {
  const res = calcItemLine({
    sale_type: 'loose',
    amount: 100,
    rate: 0,
    lastEditedField: 'amount',
    qty_decimal_precision: 3,
  });
  assert.equal(res.error?.code, 'ZERO_RATE');
  assert.equal(res.error?.severity, 'error');
});

test('loose: amount too small warns about zero quantity', () => {
  const res = calcItemLine({
    sale_type: 'loose',
    amount: 1,
    rate: 150,
    lastEditedField: 'amount',
    qty_decimal_precision: 1,
  });
  assert.equal(res.quantity, 0);
  assert.equal(res.error?.code, 'ZERO_QUANTITY');
  assert.equal(res.error?.severity, 'warning');
});

test('loose: quantity drives amount', () => {
  assert.deepEqual(
    calcItemLine({ sale_type: 'loose', quantity: 5, rate: 150, lastEditedField: 'quantity' }),
    { quantity: 5, amount: 750 },
  );
});

test('loose: rate change keeps the driver fixed', () => {
  // amount-driven → quantity recomputed
  assert.deepEqual(
    calcItemLine({
      sale_type: 'loose',
      amount: 100,
      rate: 200,
      lastEditedField: 'amount',
      qty_decimal_precision: 3,
    }),
    { quantity: 0.5, amount: 100 },
  );
  // quantity-driven → amount recomputed
  assert.deepEqual(
    calcItemLine({ sale_type: 'loose', quantity: 2, rate: 200, lastEditedField: 'quantity' }),
    { quantity: 2, amount: 400 },
  );
});

test('loose: fresh row is a no-op', () => {
  assert.deepEqual(
    calcItemLine({ sale_type: 'loose', quantity: 0, amount: 0, rate: 150, lastEditedField: null }),
    { quantity: 0, amount: 0 },
  );
});

test('applyLineFieldUpdate: editing a field makes it the driver', () => {
  const loose = { sale_type: 'loose' as const, qty_decimal_precision: 3, rate: 150 };

  assert.deepEqual(applyLineFieldUpdate(loose, 'amount', 100), {
    quantity: 0.667,
    amount: 100,
    rate: 150,
    lastEditedField: 'amount',
  });
  assert.deepEqual(applyLineFieldUpdate(loose, 'quantity', 2), {
    quantity: 2,
    amount: 300,
    rate: 150,
    lastEditedField: 'quantity',
  });
});

test('applyLineFieldUpdate: rate edit keeps the existing driver', () => {
  const amountDriven = {
    sale_type: 'loose' as const,
    qty_decimal_precision: 3,
    rate: 150,
    amount: 100,
    quantity: 0.667,
    lastEditedField: 'amount' as const,
  };
  assert.deepEqual(applyLineFieldUpdate(amountDriven, 'rate', 200), {
    quantity: 0.5,
    amount: 100,
    rate: 200,
    lastEditedField: 'amount',
  });
});

test('applyLineFieldUpdate: packed lines never set a driver', () => {
  const packed = { sale_type: 'packed' as const, rate: 10, quantity: 3 };
  assert.deepEqual(applyLineFieldUpdate(packed, 'quantity', 4), {
    quantity: 4,
    amount: 40,
    rate: 10,
    lastEditedField: null,
  });
});

test('lineIssue: only flags loose lines with a positive amount', () => {
  assert.equal(lineIssue({ sale_type: 'packed', amount: 100, rate: 0 }), undefined);
  assert.equal(lineIssue({ sale_type: 'loose', amount: 0, rate: 0 }), undefined);
  assert.equal(lineIssue({ sale_type: 'loose', amount: 100, rate: 0 })?.code, 'ZERO_RATE');
  assert.equal(
    lineIssue({ sale_type: 'loose', amount: 1, rate: 150, qty_decimal_precision: 1 })?.code,
    'ZERO_QUANTITY',
  );
});

test('loose: explicit rounding_step overrides precision', () => {
  assert.deepEqual(
    calcItemLine({
      sale_type: 'loose',
      amount: 100,
      rate: 150,
      lastEditedField: 'amount',
      qty_decimal_precision: 3,
      rounding_step: 0.5,
    }),
    { quantity: 0.5, amount: 100 },
  );
});
