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
exports.computeLineAmount = computeLineAmount;
exports.decomposeLineAmount = decomposeLineAmount;
exports.computeInvoiceTotal = computeInvoiceTotal;
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
 * Server-authoritative line amount (ACC-18 interim): the stored
 * invoice_items.amount is always round(qty × unit_price − discount) with
 * tax applied at the line boundary. discount_type 'percentage' treats
 * discount_value as a percent of the gross; 'flat' as an absolute amount.
 */
function computeLineAmount(args) {
    return decomposeLineAmount(args).amount;
}
/**
 * Decompose a line into stored amount / pre-tax net / tax
 * (report-query-integrity). The stored amount is
 * round(qty × unit_price − discount) plus tax at the line boundary;
 * net_amount + tax_amount always equals amount, which lets the tax
 * summary report tax on a tax-exclusive base instead of re-deriving
 * tax from the tax-inclusive stored amount.
 */
function decomposeLineAmount(args) {
    const gross = multiplyCurrency(args.quantity, args.unit_price);
    const discountValue = parseCurrency(args.discount_value || 0);
    let net = gross;
    if (discountValue > 0) {
        const discountAmount = args.discount_type === 'flat'
            ? roundCurrency(discountValue)
            : roundCurrency(gross * (discountValue / 100));
        net = subtractCurrency(gross, Math.min(discountAmount, gross));
    }
    const taxRate = parseCurrency(args.tax_rate || 0);
    const taxAmount = taxRate !== 0 ? roundCurrency(net * (taxRate / 100)) : 0;
    return { amount: addCurrency(net, taxAmount), netAmount: net, taxAmount };
}
/**
 * Header total = Σ of server-computed line amounts.
 */
function computeInvoiceTotal(items) {
    let total = 0;
    for (const item of items) {
        total = addCurrency(total, computeLineAmount(item));
    }
    return total;
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