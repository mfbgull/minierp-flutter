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
 * invoice_items.amount is always round(gross − discount) with tax applied
 * at the line boundary. The gross is qty × unit_price — except for loose
 * amount-driven lines, where the client sends `amount` and the entered
 * bill amount IS the business data (same trust level as qty/rate; sales
 * form flip model §5.2). discount_type 'percentage' treats discount_value
 * as a percent of the gross; 'flat' as an absolute amount.
 */
export function computeLineAmount(args: {
  quantity: number;
  unit_price: number;
  tax_rate?: number;
  discount_type?: string;
  discount_value?: number;
  amount?: number;
}): number {
  return decomposeLineAmount(args).amount;
}

/**
 * Decompose a line into stored amount / pre-tax net / tax
 * (report-query-integrity). The stored amount is
 * round(gross − discount) plus tax at the line boundary;
 * net_amount + tax_amount always equals amount, which lets the tax
 * summary report tax on a tax-exclusive base instead of re-deriving
 * tax from the tax-inclusive stored amount. A positive finite `amount`
 * overrides the qty × unit_price gross (loose amount-driven lines).
 */
export function decomposeLineAmount(args: {
  quantity: number;
  unit_price: number;
  tax_rate?: number;
  discount_type?: string;
  discount_value?: number;
  amount?: number;
}): { amount: number; netAmount: number; taxAmount: number; gross: number } {
  const override = parseCurrency(args.amount);
  const gross = override > 0
    ? roundCurrency(override)
    : multiplyCurrency(args.quantity, args.unit_price);
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
  return { amount: addCurrency(net, taxAmount), netAmount: net, taxAmount, gross };
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
 * The grand total the invoice form displays and ACC-18 validation
 * expects — Σ of server-computed line amounts MINUS an invoice-scope
 * header discount (the form applies it on the pre-tax subtotal: flat
 * value or percent of the line grosses). Item-scope discounts are
 * already inside each line's amount. Mirrors the client's
 * `calculateTotal` in invoice_calculations.dart.
 */
export function computeInvoiceGrandTotal(
  items: Parameters<typeof computeInvoiceTotal>[0],
  header?: {
    discount_scope?: string;
    discount_type?: string;
    discount_value?: number;
  }
): number {
  let subtotal = 0;
  let linesTotal = 0;
  for (const item of items) {
    const line = decomposeLineAmount(item);
    subtotal = addCurrency(subtotal, line.gross);
    linesTotal = addCurrency(linesTotal, line.amount);
  }
  if (header?.discount_scope !== 'invoice') return linesTotal;
  const discountValue = parseCurrency(header.discount_value || 0);
  if (discountValue <= 0) return linesTotal;
  const discount = header.discount_type === 'percentage'
    ? roundCurrency(subtotal * (discountValue / 100))
    : roundCurrency(discountValue);
  return subtractCurrency(linesTotal, Math.min(discount, linesTotal));
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
