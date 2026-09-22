/**
 * Invoice return math — pure functions from invoice-return-spec.md §3.
 *
 * No DB access, no I/O: every function takes plain numbers/objects and
 * returns plain numbers/objects, so it is unit-testable without HTTP
 * and reusable by both the desktop and mobile flows (spec D17).
 *
 * Conventions:
 *  - Money is rounded to the currency scale (2dp) at each boundary,
 *    mirroring server/src/utils/currency.ts::roundCurrency semantics.
 *  - Tax is ADDITIVE per the system's authoritative line math
 *    (currency.ts::decomposeLineAmount): amount = (gross − discount) + tax.
 *    Tax is never extracted from a tax-inclusive amount.
 *  - "Paid" means GROSS collections (original payment allocations +
 *    credit offsets) — refunds are NOT subtracted here; they reduce the
 *    position exactly once through the settled term of the cumulative
 *    cap (spec §3.2 "Paid" definition).
 */
import { decomposeLineAmount, roundCurrency } from '../utils/currency';

// ────────────────────────────────────────────────────────────────────
// Returned line (spec §3.5 — additive proportional mirror)
// ────────────────────────────────────────────────────────────────────

export interface ReturnedLineInput {
  quantity: number;          // original sold quantity on the line
  unitPrice: number;
  taxRate?: number;          // percent, additive
  discountType?: string;     // 'percentage' | 'flat' | 'none'
  discountValue?: number;
  returnQuantity: number;    // must be ≤ quantity (validated by caller)
}

export interface ReturnedLine {
  returnedQuantity: number;
  returnedRatio: number;
  returnedNet: number;       // tax-exclusive (Sales Returns debit basis)
  returnedTax: number;       // proportional additive tax (Tax Payable debit)
  returnedGross: number;     // net + tax — AR credit and fee base (tax-inclusive)
  /** Full-line gross the proportional split came from (H2 header-discount base). */
  lineGross: number;
}

/**
 * Mirror one invoice line proportionally: the returned share of the
 * line's net and tax, using the same decomposition rules as the sale
 * (decomposeLineAmount). Rounding is applied per component, so
 * returnedNet + returnedTax === returnedGross always holds.
 */
export function computeReturnedLine(line: ReturnedLineInput): ReturnedLine {
  const originalQty = Number(line.quantity);
  const returnQty = Number(line.returnQuantity);
  if (!(originalQty > 0)) {
    throw new Error(`computeReturnedLine: original quantity must be > 0 (got ${originalQty})`);
  }
  if (returnQty <= 0 || returnQty > originalQty + 1e-9) {
    throw new Error(
      `computeReturnedLine: returnQuantity (${returnQty}) must be > 0 and ≤ line quantity (${originalQty})`
    );
  }
  // Guard fp drift: an exact-full return snaps the ratio to 1.
  const ratio = returnQty >= originalQty - 1e-9 ? 1 : returnQty / originalQty;

  // Decompose the FULL line the same way the sale did (sale-side truth),
  // then take the returned proportion of each component. (Proportional
  // split of the decomposed parts — not a recomposition with a partial
  // qty — so per-unit discount treatment matches the sale exactly.)
  const full = decomposeLineAmount({
    quantity: originalQty,
    unit_price: line.unitPrice,
    tax_rate: line.taxRate ?? 0,
    discount_type: line.discountType,
    discount_value: line.discountValue,
  });

  const returnedNet = roundCurrency(full.netAmount * ratio);
  const returnedTax = roundCurrency(full.taxAmount * ratio);
  return {
    returnedQuantity: returnQty,
    returnedRatio: ratio,
    returnedNet,
    returnedTax,
    returnedGross: roundCurrency(returnedNet + returnedTax),
    lineGross: full.gross,
  };
}

// ────────────────────────────────────────────────────────────────────
// Invoice-scope header discount (H2)
// ────────────────────────────────────────────────────────────────────

/**
 * Give back the invoice-scope header discount proportionally (H2).
 *
 * The sale deducted the header discount from the pre-tax subtotal
 * (currency.ts::computeInvoiceGrandTotal) and the GL absorbed it into
 * revenue, so a return must deduct the same discount from the returned
 * NET — the contra-revenue (4100) side — never from tax: the tax
 * reversal must keep matching the stored invoice tax exactly (H3).
 *
 * Allocation mirrors the sale-side base exactly: the discount is spread
 * pro-rata by line gross over the WHOLE invoice, and each returned line
 * gives up its own share scaled by its returned ratio. Consequences:
 *  - a full return of every line credits exactly the invoice grand total;
 *  - a partial return gives up only its own share of the discount;
 *  - a flat discount stays a fixed total spread across all lines, so
 *    returning one line cannot consume a flat discount that belongs to
 *    the others.
 *
 * The total deduction is rounded once then re-split across the lines with
 * the largest-remainder method, so the sum of the per-line deductions is
 * exactly the rounded total (a full return closes to the cent against the
 * invoice total). Per-line deductions are floored at 0 — a pathological
 * discount can never make a return credit negative.
 */
export function allocateHeaderDiscount<T extends ReturnedLine>(
  lines: T[],
  context: {
    discount_scope?: string;
    discount_type?: string;
    discount_value?: number;
    /** Σ line gross over EVERY invoice line — the discount base the sale used. */
    invoiceSubtotal: number;
  },
): T[] {
  if (context.discount_scope !== 'invoice') return lines;
  const discountValue = roundCurrency(Number(context.discount_value ?? 0));
  const subtotal = roundCurrency(Number(context.invoiceSubtotal));
  if (!(discountValue > 0) || !(subtotal > 0) || lines.length === 0) return lines;

  const rawDiscount = context.discount_type === 'percentage'
    ? subtotal * (discountValue / 100)
    : discountValue;

  // What this request gives back in total: each line's pro-rata share of
  // the discount, scaled by its returned ratio.
  const exactTotal = lines.reduce(
    (sum, l) => sum + (rawDiscount * (l.lineGross / subtotal)) * l.returnedRatio,
    0,
  );
  // Round once, same boundary as the sale's single deduction.
  const totalToDeduct = Math.min(roundCurrency(exactTotal), roundCurrency(
    lines.reduce((s, l) => s + l.returnedNet, 0),
  ));
  if (!(totalToDeduct > 0)) return lines;

  // Largest-remainder split into cents so the parts sum to the total.
  const cents = Math.round(totalToDeduct * 100);
  const exactParts = lines.map((l) => {
    const share = (rawDiscount * (l.lineGross / subtotal)) * l.returnedRatio;
    return { line: l, exact: exactTotal > 0 ? share / exactTotal : 0 };
  });
  const floors = exactParts.map((p) => Math.floor(p.exact * cents));
  let remaining = cents - floors.reduce((a, b) => a + b, 0);
  const order = exactParts
    .map((p, i) => ({ i, frac: p.exact * cents - floors[i] }))
    .sort((a, b) => b.frac - a.frac);
  for (let k = 0; k < order.length && remaining > 0; k += 1) {
    floors[order[k].i] += 1;
    remaining -= 1;
  }

  return exactParts.map((p, i) => {
    const deduction = floors[i] / 100;
    const returnedNet = Math.max(0, roundCurrency(p.line.returnedNet - deduction));
    return {
      ...p.line,
      returnedNet,
      returnedGross: roundCurrency(returnedNet + p.line.returnedTax),
    };
  });
}

// ────────────────────────────────────────────────────────────────────
// Restocking fee (spec §3.6 / D5 — always charged, clamped)
// ────────────────────────────────────────────────────────────────────

export type FeeType = 'none' | 'fixed' | 'percentage';

export interface FeeInput {
  feeType?: FeeType;
  feeValue?: number;
  /** Tax-inclusive returned value (computeReturnedLine → returnedGross, summed). */
  returnedValueGross: number;
}

/**
 * Resolve the fee from its type/value against the tax-inclusive
 * returned value. The fee can never exceed the returned value (a
 * 5000 fixed fee on a 600 return clamps to 600; net never goes
 * negative). Always charged (D5) — the caller decides nothing here.
 */
export function resolveFee(input: FeeInput): number {
  const base = roundCurrency(input.returnedValueGross);
  const type = input.feeType ?? 'none';
  const value = Number(input.feeValue) || 0;
  if (type === 'none' || value <= 0) return 0;
  const raw = type === 'percentage' ? base * (value / 100) : value;
  return roundCurrency(Math.min(raw, base));
}

// ────────────────────────────────────────────────────────────────────
// Invoice position (spec §3.2) + cumulative settlement cap (§3.4)
// ────────────────────────────────────────────────────────────────────

export interface PositionInput {
  originalTotal: number;
  /** Σ returned gross (tax-inclusive) over non-voided returns. */
  totalReturned: number;
  /** Σ fees over non-voided returns (already resolved). */
  totalFees: number;
  /** GROSS collections: positive payment allocations + credit offsets applied. */
  totalPaid: number;
  /** Σ settled amounts over non-voided settlements of ALL types. */
  totalSettled: number;
}

export interface InvoicePosition {
  originalTotal: number;
  totalReturned: number;
  /** Remaining Invoice Value — goods the customer keeps (spec §3.1). */
  currentInvoiceValue: number;
  totalPaid: number;
  totalFees: number;
  /** Net Customer Position = paid − remaining − fees. */
  netPosition: number;
  /** Business owes customer when > 0 (else 0). */
  refundCreditDue: number;
  totalSettled: number;
  /** refundCreditDue − totalSettled, floored at 0. */
  remainingRefundDue: number;
  /** Customer owes when > 0 (else 0) — NEVER negative (D2). */
  balanceDue: number;
  /** Cumulative settlement cap remaining (§3.4), floored at 0. */
  remainingSettlementCapacity: number;
}

/**
 * The authoritative position computation (spec §3.2). Balance Due and
 * Refund/Credit Due are mutually exclusive: one of them is always 0,
 * and balanceDue is never negative (stored balance clamps to ≥ 0).
 */
export function computePosition(input: PositionInput): InvoicePosition {
  const originalTotal = roundCurrency(input.originalTotal);
  const totalReturned = roundCurrency(input.totalReturned);
  const totalFees = roundCurrency(input.totalFees);
  const totalPaid = roundCurrency(input.totalPaid);
  const totalSettled = roundCurrency(input.totalSettled);

  const currentInvoiceValue = roundCurrency(Math.max(0, originalTotal - totalReturned));
  const netPosition = roundCurrency(totalPaid - currentInvoiceValue - totalFees);

  const refundCreditDue = netPosition > 0 ? netPosition : 0;
  const balanceDue = netPosition < 0 ? roundCurrency(-netPosition) : 0;
  const remainingRefundDue = roundCurrency(Math.max(0, refundCreditDue - totalSettled));

  // Cumulative cap (§3.4): total entitlement − already settled. This is
  // the hard backend safety rule — enforced again at write time.
  const entitlement = Math.max(0, netPosition);
  const remainingSettlementCapacity = roundCurrency(Math.max(0, entitlement - totalSettled));

  return {
    originalTotal,
    totalReturned,
    currentInvoiceValue,
    totalPaid,
    totalFees,
    netPosition,
    refundCreditDue,
    totalSettled,
    remainingRefundDue,
    balanceDue,
    remainingSettlementCapacity,
  };
}

// ────────────────────────────────────────────────────────────────────
// Settlement allocation validation (spec §3.4 / D18)
// ────────────────────────────────────────────────────────────────────

export interface SettlementAllocation {
  type: 'refund' | 'credit' | 'adjust';
  amount: number;
}

export interface AllocationValidation {
  ok: boolean;
  /** Human-readable rejection reason when ok === false. */
  error?: string;
  totalRequested: number;
}

/**
 * Validate a batch of settlement allocations against (a) the return's
 * own unsettled remainder and (b) the invoice's cumulative cap. All
 * types share one pool (D18): refund + credit + adjust together must
 * fit both limits.
 */
export function validateAllocations(
  allocations: SettlementAllocation[],
  returnRemainder: number,
  remainingCapacity: number,
): AllocationValidation {
  const total = allocations.reduce((sum, a) => sum + roundCurrency(Number(a.amount) || 0), 0);
  const totalRequested = roundCurrency(total);

  if (allocations.length === 0) {
    return { ok: false, error: 'At least one settlement allocation is required', totalRequested };
  }
  for (const a of allocations) {
    const amount = roundCurrency(Number(a.amount) || 0);
    if (amount <= 0) {
      return { ok: false, error: 'Settlement amounts must be positive', totalRequested };
    }
    if (a.type !== 'refund' && a.type !== 'credit' && a.type !== 'adjust') {
      return { ok: false, error: `Unknown settlement type: ${a.type}`, totalRequested };
    }
  }
  if (totalRequested > roundCurrency(returnRemainder) + 1e-9) {
    return {
      ok: false,
      error: `Allocations (${totalRequested.toFixed(2)}) exceed the return's unsettled remainder (${roundCurrency(returnRemainder).toFixed(2)})`,
      totalRequested,
    };
  }
  if (totalRequested > roundCurrency(remainingCapacity) + 1e-9) {
    return {
      ok: false,
      error: `Allocations (${totalRequested.toFixed(2)}) exceed the invoice's remaining refund/credit entitlement (${roundCurrency(remainingCapacity).toFixed(2)})`,
      totalRequested,
    };
  }
  return { ok: true, totalRequested };
}
