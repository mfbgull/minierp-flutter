/** Pure unit check of the H2 header-discount allocation (no app import). */
import { computeReturnedLine, allocateHeaderDiscount } from '../services/returnMath';

describe('allocateHeaderDiscount (pure math)', () => {
  const line = (q: number, up: number, rq: number) =>
    computeReturnedLine({ quantity: q, unitPrice: up, returnQuantity: rq });

  it('no invoice-scope discount: lines unchanged', () => {
    const l = [line(2, 500, 1)];
    expect(allocateHeaderDiscount(l, { discount_scope: 'item', discount_value: 10, invoiceSubtotal: 1000 }))
      .toEqual(l);
  });

  it('full return of a discounted line credits the grand total', () => {
    const out = allocateHeaderDiscount([line(2, 500, 2)], {
      discount_scope: 'invoice', discount_type: 'percentage', discount_value: 10, invoiceSubtotal: 1000,
    });
    expect(out[0].returnedGross).toBeCloseTo(900, 2);
  });

  it('partial return gives back only its own share', () => {
    const out = allocateHeaderDiscount([line(2, 500, 1)], {
      discount_scope: 'invoice', discount_type: 'percentage', discount_value: 10, invoiceSubtotal: 1000,
    });
    expect(out[0].returnedGross).toBeCloseTo(450, 2);
  });

  it('flat discount is shared across lines, never consumed by the first', () => {
    const out = allocateHeaderDiscount([line(1, 500, 1), line(1, 500, 1)], {
      discount_scope: 'invoice', discount_type: 'flat', discount_value: 100, invoiceSubtotal: 1000,
    });
    expect(out[0].returnedGross).toBeCloseTo(450, 2);
    expect(out[1].returnedGross).toBeCloseTo(450, 2);
  });

  it('multi-line flat discount sums exactly to the grand total (no cent drift)', () => {
    const out = allocateHeaderDiscount(
      [line(1, 500, 1), line(1, 300, 1), line(1, 200, 1)],
      { discount_scope: 'invoice', discount_type: 'flat', discount_value: 100, invoiceSubtotal: 1000 },
    );
    const sum = out.reduce((s, l) => s + l.returnedGross, 0);
    expect(Math.round(sum * 100) / 100).toBe(900);
  });

  it('tax is never reduced — only the net absorbs the discount', () => {
    const full = computeReturnedLine({ quantity: 2, unitPrice: 500, taxRate: 10, returnQuantity: 2 });
    const out = allocateHeaderDiscount([full], {
      discount_scope: 'invoice', discount_type: 'flat', discount_value: 100, invoiceSubtotal: 1000,
    });
    expect(out[0].returnedTax).toBeCloseTo(full.returnedTax, 2); // 100
    expect(out[0].returnedNet).toBeCloseTo(900, 2);
    expect(out[0].returnedGross).toBeCloseTo(1000, 2);
  });

  it('never produces a negative return credit', () => {
    const out = allocateHeaderDiscount([line(1, 500, 1)], {
      discount_scope: 'invoice', discount_type: 'percentage', discount_value: 200, invoiceSubtotal: 500,
    });
    expect(out[0].returnedNet).toBeGreaterThanOrEqual(0);
    expect(out[0].returnedGross).toBeGreaterThanOrEqual(0);
  });
});
