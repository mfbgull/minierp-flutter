/**
 * Floating-point quantity precision regression tests.
 *
 * Covers the exact scenarios from audit finding H1:
 * - 0.3 - 0.1 = 0.2 (exact)
 * - 1.1 - 0.7 - 0.4 = 0 (multi-step)
 * - Repeated fractional purchases/sales (10x 0.1)
 * - Dust stock detection
 * - Insufficient stock edge cases
 */
import { roundQty, qtyEpsilon, qtyEquals, qtyLessThan, qtyPositive, qtyZero, parseQty } from '../utils/quantity';

describe('roundQty utility', () => {
  it('rounds 0.3 - 0.1 to exactly 0.2', () => {
    const result = roundQty(0.3 - 0.1, 3);
    expect(result).toBe(0.2);
  });

  it('rounds 1.1 - 0.7 - 0.4 to exactly 0', () => {
    const result = roundQty(1.1 - 0.7 - 0.4, 3);
    expect(result).toBe(0);
  });

  it('rounds 0.1 + 0.2 to exactly 0.3', () => {
    const result = roundQty(0.1 + 0.2, 3);
    expect(result).toBe(0.3);
  });

  it('rounds to specified precision', () => {
    expect(roundQty(1.23456, 2)).toBe(1.23);
    expect(roundQty(1.23456, 4)).toBe(1.2346);
    expect(roundQty(1.23456, 0)).toBe(1);
  });

  it('handles negative values correctly', () => {
    expect(roundQty(-0.1 + 0.2, 3)).toBe(0.1);
    // -1.1 + 0.7 + 0.4 produces -0 in IEEE 754; -0 === 0 in arithmetic
    expect(roundQty(-1.1 + 0.7 + 0.4, 3) === 0).toBe(true);
  });

  it('handles zero correctly', () => {
    expect(roundQty(0, 3)).toBe(0);
    // -0 is a JS quirk; treat as zero for stock purposes
    expect(roundQty(-0, 3) === 0).toBe(true);
  });
});

describe('qtyEpsilon', () => {
  it('returns correct epsilon for precision', () => {
    expect(qtyEpsilon(3)).toBe(0.001);
    expect(qtyEpsilon(2)).toBe(0.01);
    expect(qtyEpsilon(0)).toBe(1);
  });
});

describe('qtyEquals', () => {
  it('detects floating-point residue as equal', () => {
    const residue = 0.19999999999999998;
    expect(qtyEquals(residue, 0.2)).toBe(true);
  });

  it('detects actual differences as not equal', () => {
    expect(qtyEquals(0.1, 0.2)).toBe(false);
    expect(qtyEquals(0.2, 0.3)).toBe(false);
  });

  it('handles exact values', () => {
    expect(qtyEquals(0.2, 0.2)).toBe(true);
    expect(qtyEquals(0, 0)).toBe(true);
  });
});

describe('qtyLessThan', () => {
  it('does not reject valid stock due to residue', () => {
    const available = 0.19999999999999998;
    const required = 0.2;
    expect(qtyLessThan(available, required)).toBe(false);
  });

  it('rejects genuinely insufficient stock', () => {
    expect(qtyLessThan(0.1, 0.2)).toBe(true);
    expect(qtyLessThan(0, 0.1)).toBe(true);
  });

  it('handles exact equality', () => {
    expect(qtyLessThan(0.2, 0.2)).toBe(false);
  });
});

describe('qtyPositive', () => {
  it('treats residue as zero (not positive)', () => {
    const residue = 5.551115123125783e-17;
    expect(qtyPositive(residue)).toBe(false);
  });

  it('detects genuinely positive values', () => {
    expect(qtyPositive(0.1)).toBe(true);
    expect(qtyPositive(0.001)).toBe(true);
    expect(qtyPositive(1)).toBe(true);
  });

  it('detects zero', () => {
    expect(qtyPositive(0)).toBe(false);
    expect(qtyPositive(-0)).toBe(false);
  });
});

describe('qtyZero', () => {
  it('detects residue as zero', () => {
    const residue = 5.551115123125783e-17;
    expect(qtyZero(residue)).toBe(true);
  });

  it('detects actual zero', () => {
    expect(qtyZero(0)).toBe(true);
    expect(qtyZero(-0)).toBe(true);
  });

  it('does not treat non-zero as zero', () => {
    expect(qtyZero(0.1)).toBe(false);
    expect(qtyZero(-0.1)).toBe(false);
  });
});

describe('parseQty', () => {
  it('parses and rounds numbers', () => {
    expect(parseQty(0.1 + 0.2)).toBe(0.3);
    expect(parseQty('0.123456')).toBe(0.123);
  });

  it('handles null/undefined/NaN', () => {
    expect(parseQty(null)).toBe(0);
    expect(parseQty(undefined)).toBe(0);
    expect(parseQty('not-a-number')).toBe(0);
  });

  it('handles strings', () => {
    expect(parseQty('0.3')).toBe(0.3);
    expect(parseQty('1.23456')).toBe(1.235);
  });
});

describe('Repeated fractional operations (10x 0.1)', () => {
  it('accumulates 10x 0.1 to exactly 1.0', () => {
    let total = 0;
    for (let i = 0; i < 10; i++) {
      total = roundQty(total + 0.1, 3);
    }
    expect(total).toBe(1);
  });

  it('subtracts 10x 0.1 from 1.0 to exactly 0', () => {
    let remaining = roundQty(1.0, 3);
    for (let i = 0; i < 10; i++) {
      remaining = roundQty(remaining - 0.1, 3);
    }
    expect(remaining).toBe(0);
  });

  it('handles mixed operations without dust', () => {
    // Buy 0.3, sell 0.1, sell 0.2 → should be exactly 0
    let stock = roundQty(0.3, 3);
    stock = roundQty(stock - 0.1, 3);
    stock = roundQty(stock - 0.2, 3);
    expect(stock).toBe(0);
    expect(qtyZero(stock)).toBe(true);
  });
});

describe('Insufficient stock edge cases', () => {
  it('allows sale when stock equals required (not rejected by residue)', () => {
    // Simulate: bought 0.3, sold 0.1, remaining should be 0.2
    const stock = roundQty(0.3 - 0.1, 3);
    const required = 0.2;
    expect(qtyLessThan(stock, required)).toBe(false);
  });

  it('rejects sale when stock is genuinely less', () => {
    const stock = 0.1;
    const required = 0.2;
    expect(qtyLessThan(stock, required)).toBe(true);
  });

  it('handles edge case: have 0.2000001, sell 0.2', () => {
    const stock = roundQty(0.2000001, 3);
    const required = roundQty(0.2, 3);
    expect(qtyLessThan(stock, required)).toBe(false);
  });

  it('handles edge case: have 0.1999999, sell 0.2', () => {
    const stock = roundQty(0.1999999, 3);
    const required = roundQty(0.2, 3);
    expect(stock).toBe(0.2);
    expect(qtyLessThan(stock, required)).toBe(false);
  });
});
