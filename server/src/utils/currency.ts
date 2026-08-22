/**
 * Currency arithmetic utilities to avoid floating-point precision errors.
 * All financial calculations in the ERP system should use these functions.
 *
 * Uses Math.round(value * 100) / 100 to ensure 2-decimal-place precision.
 */

export function roundCurrency(value: number): number {
  // Use the e+2 trick to avoid IEEE 754 rounding errors (e.g., 1.005 → 1.01 instead of 1.00)
  return Number(Math.round(Number(value + 'e+2')) + 'e-2');
}

export function addCurrency(a: number, b: number): number {
  return roundCurrency(a + b);
}

export function subtractCurrency(a: number, b: number): number {
  return roundCurrency(a - b);
}

export function multiplyCurrency(a: number, b: number): number {
  return roundCurrency(a * b);
}

/**
 * Server-authoritative line amount (ACC-18 interim): the stored
 * invoice_items.amount is always round(qty × unit_price − discount) with
 * tax applied at the line boundary. discount_type 'percentage' treats
 * discount_value as a percent of the gross; 'flat' as an absolute amount.
 */
export function computeLineAmount(args: {
  quantity: number;
  unit_price: number;
  tax_rate?: number;
  discount_type?: string;
  discount_value?: number;
}): number {
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
  if (taxRate !== 0) {
    net = addCurrency(net, roundCurrency(net * (taxRate / 100)));
  }
  return net;
}

/**
 * Header total = Σ of server-computed line amounts.
 */
export function computeInvoiceTotal(items: Array<{
  quantity: number;
  unit_price: number;
  tax_rate?: number;
  discount_type?: string;
  discount_value?: number;
}>): number {
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
export function parseCurrency(value: unknown): number {
  if (value === null || value === undefined) return 0;
  const num = typeof value === 'number' ? value : parseFloat(String(value));
  return isNaN(num) ? 0 : roundCurrency(num);
}
