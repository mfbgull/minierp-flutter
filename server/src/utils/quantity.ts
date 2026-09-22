/**
 * Quantity arithmetic utilities to avoid IEEE 754 floating-point residue.
 *
 * SQLite stores DECIMAL(15,3) as REAL, so operations like 0.3 - 0.1
 * produce 0.19999999999999998 instead of 0.2. This causes valid sales
 * to fail insufficient-stock checks.
 *
 * DESIGN:
 * - Internal calculations use 3-decimal precision (matching DB DECIMAL(15,3))
 * - Per-item `qty_decimal_precision` is for DISPLAY only, not calculations
 * - ALL stock quantity writes and comparisons must go through roundQty()
 *
 * ANTI-PATTERNS ELIMINATED:
 * - No arbitrary epsilon values (1e-9, 0.001) for comparisons
 * - No string conversion tricks (Number(v + 'e+2'))
 * - No inconsistent Math.round(v * 100) / 100 patterns
 */

/** Default precision for stock quantities (matches DB DECIMAL(15,3)) */
const DEFAULT_QTY_PRECISION = 3;

/**
 * Round a quantity value to the specified decimal places.
 *
 * Uses Math.round(factor * value) / factor for IEEE 754-safe rounding.
 *
 * @param value - The quantity to round
 * @param precision - Number of decimal places (default: 3)
 * @returns Rounded value
 *
 * @example
 * roundQty(0.3 - 0.1, 3)   // → 0.2 (not 0.19999999999999998)
 * roundQty(1.1 - 0.7 - 0.4, 3) // → 0 (not -5.551115123125783e-17)
 * roundQty(0.123456, 2)    // → 0.12
 */
export function roundQty(value: number, precision: number = DEFAULT_QTY_PRECISION): number {
  const factor = Math.pow(10, precision);
  return Math.round(value * factor) / factor;
}

/**
 * Comparison tolerance based on precision.
 *
 * Use this instead of arbitrary epsilon values when you MUST compare
 * unrounded values (e.g., reading directly from DB without roundQty).
 *
 * PREFERRED PATTERN: roundQty(a) === roundQty(b)
 * FALLBACK PATTERN: Math.abs(a - b) < qtyEpsilon(precision)
 *
 * @param precision - Number of decimal places (default: 3)
 * @returns Smallest distinguishable difference at this precision
 *
 * @example
 * qtyEpsilon(3) // → 0.001
 * qtyEpsilon(2) // → 0.01
 */
export function qtyEpsilon(precision: number = DEFAULT_QTY_PRECISION): number {
  return Math.pow(10, -precision);
}

/**
 * Parse a quantity value from unknown input, rounded to precision.
 *
 * Safely handles null, undefined, NaN, strings, and numbers.
 * Returns 0 for invalid inputs.
 *
 * @param value - Raw quantity value
 * @param precision - Number of decimal places (default: 3)
 * @returns Rounded quantity or 0
 */
export function parseQty(value: unknown, precision: number = DEFAULT_QTY_PRECISION): number {
  if (value === null || value === undefined) return 0;
  const num = typeof value === 'number' ? value : parseFloat(String(value));
  return isNaN(num) ? 0 : roundQty(num, precision);
}

/**
 * Assert two quantities are equal within precision tolerance.
 *
 * Use for stock balance checks, validation, and test assertions.
 *
 * @param a - First quantity
 * @param b - Second quantity
 * @param precision - Number of decimal places (default: 3)
 * @returns true if quantities are equal at this precision
 *
 * @example
 * qtyEquals(0.3 - 0.1, 0.2)  // → true
 * qtyEquals(0.19999999999999998, 0.2) // → true
 */
export function qtyEquals(a: number, b: number, precision: number = DEFAULT_QTY_PRECISION): boolean {
  return roundQty(a, precision) === roundQty(b, precision);
}

/**
 * Check if quantity A is strictly less than quantity B, with precision.
 *
 * Use instead of `a < b` for stock availability checks.
 *
 * @param a - Available quantity
 * @param b - Required quantity
 * @param precision - Number of decimal places (default: 3)
 * @returns true if a < b at this precision
 *
 * @example
 * qtyLessThan(0.19999999999999998, 0.2) // → false (stock is sufficient)
 * qtyLessThan(0.1, 0.2) // → true (stock is insufficient)
 */
export function qtyLessThan(a: number, b: number, precision: number = DEFAULT_QTY_PRECISION): boolean {
  return roundQty(a, precision) < roundQty(b, precision);
}

/**
 * Check if quantity A is less than or equal to quantity B, with precision.
 *
 * @param a - Available quantity
 * @param b - Required quantity
 * @param precision - Number of decimal places (default: 3)
 * @returns true if a <= b at this precision
 */
export function qtyLessThanOrEqual(a: number, b: number, precision: number = DEFAULT_QTY_PRECISION): boolean {
  return roundQty(a, precision) <= roundQty(b, precision);
}

/**
 * Check if quantity is positive (greater than zero) at precision.
 *
 * @param value - Quantity to check
 * @param precision - Number of decimal places (default: 3)
 * @returns true if value > 0 at this precision
 */
export function qtyPositive(value: number, precision: number = DEFAULT_QTY_PRECISION): boolean {
  return roundQty(value, precision) > 0;
}

/**
 * Check if quantity is zero at precision.
 *
 * @param value - Quantity to check
 * @param precision - Number of decimal places (default: 3)
 * @returns true if value === 0 at this precision
 */
export function qtyZero(value: number, precision: number = DEFAULT_QTY_PRECISION): boolean {
  return roundQty(value, precision) === 0;
}
