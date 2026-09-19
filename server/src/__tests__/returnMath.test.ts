/**
 * Unit tests for the pure return math (invoice-return-spec.md §3,
 * Milestone 1 step 1.3). No DB, no HTTP.
 */
import {
  computeReturnedLine, resolveFee, computePosition, validateAllocations,
} from '../services/returnMath';

describe('returnMath — computeReturnedLine (additive tax mirror, §3.5)', () => {
  it('no tax, no discount: net == gross, tax 0', () => {
    const r = computeReturnedLine({ quantity: 3, unitPrice: 600, returnQuantity: 2 });
    expect(r.returnedRatio).toBeCloseTo(2 / 3, 9);
    expect(r.returnedNet).toBeCloseTo(1200, 2);
    expect(r.returnedTax).toBeCloseTo(0, 2);
    expect(r.returnedGross).toBeCloseTo(1200, 2);
  });

  it('spec §3.5 reconciliation: 3 @ 600 + 10% additive tax, return 2 → net 1200, tax 120, gross 1320', () => {
    const r = computeReturnedLine({ quantity: 3, unitPrice: 600, taxRate: 10, returnQuantity: 2 });
    expect(r.returnedNet).toBeCloseTo(1200, 2);
    expect(r.returnedTax).toBeCloseTo(120, 2);
    expect(r.returnedGross).toBeCloseTo(1320, 2);
    expect(r.returnedNet + r.returnedTax).toBeCloseTo(r.returnedGross, 2);
  });

  it('full return snaps ratio to 1 (fp-drift guard)', () => {
    const r = computeReturnedLine({ quantity: 3, unitPrice: 600, taxRate: 10, returnQuantity: 3 });
    expect(r.returnedRatio).toBe(1);
    expect(r.returnedGross).toBeCloseTo(1980, 2);
  });

  it('percentage discount is mirrored proportionally', () => {
    // 2 @ 500 − 10% → net 900, tax 90 (10%), amount 990. Return 1 of 2 → half.
    const r = computeReturnedLine({
      quantity: 2, unitPrice: 500, taxRate: 10,
      discountType: 'percentage', discountValue: 10, returnQuantity: 1,
    });
    expect(r.returnedNet).toBeCloseTo(450, 2);
    expect(r.returnedTax).toBeCloseTo(45, 2);
    expect(r.returnedGross).toBeCloseTo(495, 2);
  });

  it('flat discount is mirrored proportionally', () => {
    // 4 @ 300 − flat 100 → net 1100 (300 gross each, flat 100 on the line).
    const r = computeReturnedLine({
      quantity: 4, unitPrice: 300, discountType: 'flat', discountValue: 100, returnQuantity: 2,
    });
    expect(r.returnedNet).toBeCloseTo(550, 2); // (1200 − 100) × 1/2
    expect(r.returnedGross).toBeCloseTo(550, 2);
  });

  it('rejects over-return and non-positive quantities', () => {
    expect(() => computeReturnedLine({ quantity: 3, unitPrice: 600, returnQuantity: 4 })).toThrow();
    expect(() => computeReturnedLine({ quantity: 3, unitPrice: 600, returnQuantity: 0 })).toThrow();
  });
});

describe('returnMath — resolveFee (§3.6 / D5)', () => {
  it('none → 0 regardless of value', () => {
    expect(resolveFee({ feeType: 'none', feeValue: 100, returnedValueGross: 1200 })).toBe(0);
  });

  it('percentage: 10% of tax-inclusive 1200 → 120', () => {
    expect(resolveFee({ feeType: 'percentage', feeValue: 10, returnedValueGross: 1200 })).toBeCloseTo(120, 2);
  });

  it('fixed: 150 → 150', () => {
    expect(resolveFee({ feeType: 'fixed', feeValue: 150, returnedValueGross: 1200 })).toBeCloseTo(150, 2);
  });

  it('clamps to the returned value (fixed 5000 on 600 → 600, never negative net)', () => {
    expect(resolveFee({ feeType: 'fixed', feeValue: 5000, returnedValueGross: 600 })).toBeCloseTo(600, 2);
  });

  it('percentage > 100% clamps too', () => {
    expect(resolveFee({ feeType: 'percentage', feeValue: 250, returnedValueGross: 600 })).toBeCloseTo(600, 2);
  });

  it('zero/missing value → 0 (fee policy belongs to the caller, not the math)', () => {
    expect(resolveFee({ feeType: 'fixed', feeValue: 0, returnedValueGross: 1200 })).toBe(0);
    expect(resolveFee({ returnedValueGross: 1200 })).toBe(0);
  });
});

describe('returnMath — computePosition (§3.2 worked examples)', () => {
  it('fully paid, partial return: due 1080, balance 0', () => {
    const p = computePosition({
      originalTotal: 1800, totalReturned: 1200, totalFees: 120,
      totalPaid: 1800, totalSettled: 0,
    });
    expect(p.currentInvoiceValue).toBeCloseTo(600, 2);
    expect(p.refundCreditDue).toBeCloseTo(1080, 2);
    expect(p.balanceDue).toBe(0);
    expect(p.remainingRefundDue).toBeCloseTo(1080, 2);
    expect(p.remainingSettlementCapacity).toBeCloseTo(1080, 2);
  });

  it('partially paid (1000), fee 200: refund due 200, balance 0', () => {
    const p = computePosition({
      originalTotal: 1800, totalReturned: 1200, totalFees: 200,
      totalPaid: 1000, totalSettled: 0,
    });
    expect(p.refundCreditDue).toBeCloseTo(200, 2);
    expect(p.balanceDue).toBe(0);
  });

  it('underpaid (500), fee 200: balance 300, refund due 0 (never negative, D2)', () => {
    const p = computePosition({
      originalTotal: 1800, totalReturned: 1200, totalFees: 200,
      totalPaid: 500, totalSettled: 0,
    });
    expect(p.refundCreditDue).toBe(0);
    expect(p.balanceDue).toBeCloseTo(300, 2);
    expect(p.remainingSettlementCapacity).toBe(0);
  });

  it('unpaid with fee (D5): balance = remaining + fee (1300)', () => {
    // User's D25 example: return 600 of 1800, fee 100 → remaining 1200 + fee 100.
    const p = computePosition({
      originalTotal: 1800, totalReturned: 600, totalFees: 100,
      totalPaid: 0, totalSettled: 0,
    });
    expect(p.currentInvoiceValue).toBeCloseTo(1200, 2);
    expect(p.refundCreditDue).toBe(0);
    expect(p.balanceDue).toBeCloseTo(1300, 2);
  });

  it('unpaid FULL return with fee: balance = fee only (100)', () => {
    const p = computePosition({
      originalTotal: 1800, totalReturned: 1800, totalFees: 100,
      totalPaid: 0, totalSettled: 0,
    });
    expect(p.currentInvoiceValue).toBe(0);
    expect(p.balanceDue).toBeCloseTo(100, 2);
  });

  it('settled amounts reduce remaining due and capacity but never the gross due', () => {
    const p = computePosition({
      originalTotal: 1800, totalReturned: 1200, totalFees: 120,
      totalPaid: 1800, totalSettled: 1080,
    });
    expect(p.refundCreditDue).toBeCloseTo(1080, 2);   // gross due unchanged
    expect(p.remainingRefundDue).toBe(0);             // settled
    expect(p.remainingSettlementCapacity).toBe(0);    // cap consumed
  });
});

describe('returnMath — validateAllocations (§3.4 / D18)', () => {
  const mix = [
    { type: 'refund' as const, amount: 600 },
    { type: 'credit' as const, amount: 480 },
  ];

  it('mixed types within both limits are ok (600 + 480 = 1080)', () => {
    const v = validateAllocations(mix, 1080, 1080);
    expect(v.ok).toBe(true);
    expect(v.totalRequested).toBeCloseTo(1080, 2);
  });

  it('rejects when total exceeds the return remainder', () => {
    const v = validateAllocations(mix, 1000, 5000);
    expect(v.ok).toBe(false);
    expect(v.error).toMatch(/remainder/i);
  });

  it('rejects when total exceeds the invoice cumulative cap (hard rule §3.4)', () => {
    const v = validateAllocations(mix, 5000, 1000);
    expect(v.ok).toBe(false);
    expect(v.error).toMatch(/entitlement/i);
  });

  it('rejects cross-type double-count: refund+credit+adjust vs entitlement 1200', () => {
    const v = validateAllocations([
      { type: 'refund', amount: 600 },
      { type: 'credit', amount: 600 },
      { type: 'adjust', amount: 600 },
    ], 5000, 1200);
    expect(v.ok).toBe(false);
  });

  it('rejects empty, non-positive, and unknown types', () => {
    expect(validateAllocations([], 100, 100).ok).toBe(false);
    expect(validateAllocations([{ type: 'credit', amount: 0 }], 100, 100).ok).toBe(false);
    expect(validateAllocations([{ type: 'gift' as never, amount: 50 }], 100, 100).ok).toBe(false);
  });
});
