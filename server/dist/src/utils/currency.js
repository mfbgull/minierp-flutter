"use strict";
/**
 * Currency arithmetic utilities to avoid floating-point precision errors.
 * All financial calculations in the ERP system should use these functions.
 *
 * Uses Math.round(value * 100) / 100 to ensure 2-decimal-place precision.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.roundCurrency = roundCurrency;
exports.addCurrency = addCurrency;
exports.subtractCurrency = subtractCurrency;
exports.multiplyCurrency = multiplyCurrency;
exports.parseCurrency = parseCurrency;
function roundCurrency(value) {
    // Use the e+2 trick to avoid IEEE 754 rounding errors (e.g., 1.005 → 1.01 instead of 1.00)
    return Number(Math.round(Number(value + 'e+2')) + 'e-2');
}
function addCurrency(a, b) {
    return roundCurrency(a + b);
}
function subtractCurrency(a, b) {
    return roundCurrency(a - b);
}
function multiplyCurrency(a, b) {
    return roundCurrency(a * b);
}
/**
 * Safely parse a value to a currency number.
 * Returns 0 for null, undefined, NaN, or non-numeric strings.
 */
function parseCurrency(value) {
    if (value === null || value === undefined)
        return 0;
    const num = typeof value === 'number' ? value : parseFloat(String(value));
    return isNaN(num) ? 0 : roundCurrency(num);
}
//# sourceMappingURL=currency.js.map