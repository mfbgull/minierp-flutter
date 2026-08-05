/**
 * Invoice line calculation — packed vs loose items. Pure functions, no React.
 *
 * packed: Quantity drives Amount (Amount = qty × rate), as it always has.
 * loose:  bidirectional — whichever of Quantity/Amount the user last edited drives the other.
 */

export type SaleType = 'packed' | 'loose';

export interface CalcItemLineError {
  code: 'ZERO_RATE' | 'ZERO_QUANTITY';
  severity: 'error' | 'warning';
  message: string;
}

export interface CalcItemLineInput {
  sale_type?: SaleType;
  quantity?: number;
  amount?: number;
  rate?: number;
  /** Decimal places allowed on quantity. Defaults to 0 (whole units). */
  qty_decimal_precision?: number;
  /** Explicit step overriding the one derived from qty_decimal_precision. */
  rounding_step?: number | null;
  lastEditedField?: 'quantity' | 'amount' | null;
}

export interface CalcItemLineResult {
  quantity: number;
  amount: number;
  error?: CalcItemLineError;
}

/** Decimal places in a step value, e.g. 0.001 → 3, 0.5 → 1, 1 → 0. */
function stepDecimals(step: number): number {
  const s = String(step);
  const dot = s.indexOf('.');
  return dot === -1 ? 0 : s.length - dot - 1;
}

/** Round to the nearest multiple of `step` (0.001, 0.5, 1, ...). */
export function roundToStep(value: number, step: number): number {
  if (!step || step <= 0) return value;
  const rounded = Math.round(value / step) * step;
  // Re-fix decimals: float division reintroduces noise (0.667000000000001)
  return parseFloat(rounded.toFixed(stepDecimals(step) + 2));
}

function round2(value: number): number {
  return parseFloat((Math.round(value * 100) / 100).toFixed(2));
}

export function calcItemLine(input: CalcItemLineInput): CalcItemLineResult {
  const quantity = input.quantity || 0;
  const amount = input.amount || 0;
  const rate = input.rate || 0;

  if ((input.sale_type || 'packed') === 'packed') {
    return { quantity, amount: round2(quantity * rate) };
  }

  const step =
    input.rounding_step != null && input.rounding_step > 0
      ? input.rounding_step
      : Math.pow(10, -(input.qty_decimal_precision || 0));

  if (input.lastEditedField === 'amount') {
    if (rate <= 0) {
      return {
        quantity,
        amount,
        error: { code: 'ZERO_RATE', severity: 'error', message: 'Rate must be greater than 0' },
      };
    }
    const derivedQty = roundToStep(amount / rate, step);
    if (amount > 0 && derivedQty === 0) {
      return {
        quantity: derivedQty,
        amount,
        error: {
          code: 'ZERO_QUANTITY',
          severity: 'warning',
          message: 'Amount results in zero quantity',
        },
      };
    }
    return { quantity: derivedQty, amount };
  }

  if (input.lastEditedField === 'quantity') {
    return { quantity, amount: round2(quantity * rate) };
  }

  // Fresh row — nothing driven yet
  return { quantity, amount };
}

export interface LineFieldPatch {
  quantity: number;
  amount: number;
  rate: number;
  lastEditedField: 'quantity' | 'amount' | null;
}

/**
 * Build the patch for a quantity/rate/amount edit on a line.
 * Editing Quantity or Amount makes it the driver; editing Rate keeps the
 * existing driver fixed and recomputes the other side.
 * Shared by both invoice grids so their behaviour cannot drift.
 */
export function applyLineFieldUpdate(
  item: CalcItemLineInput,
  field: 'quantity' | 'rate' | 'amount',
  value: number,
): LineFieldPatch {
  const lastEditedField =
    field === 'rate' ? item.lastEditedField ?? 'quantity' : field;

  const result = calcItemLine({
    sale_type: item.sale_type,
    quantity: field === 'quantity' ? value : item.quantity,
    amount: field === 'amount' ? value : item.amount,
    rate: field === 'rate' ? value : item.rate,
    qty_decimal_precision: item.qty_decimal_precision,
    rounding_step: item.rounding_step,
    lastEditedField,
  });

  return {
    quantity: result.quantity,
    amount: result.amount,
    rate: field === 'rate' ? value : item.rate || 0,
    lastEditedField: item.sale_type === 'loose' ? lastEditedField : null,
  };
}

/**
 * Inline validation for a rendered line: re-runs the calculation to surface
 * the zero-rate error / zero-quantity warning without extra component state.
 */
export function lineIssue(input: CalcItemLineInput): CalcItemLineError | undefined {
  if (input.sale_type !== 'loose') return undefined;
  if (!(input.amount && input.amount > 0)) return undefined;
  return calcItemLine({ ...input, lastEditedField: 'amount' }).error;
}
