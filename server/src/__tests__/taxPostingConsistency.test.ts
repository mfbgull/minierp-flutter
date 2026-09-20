/**
 * H3 — Tax Posting Must Match the Stored Invoice Tax.
 *
 * The GL Tax Payable credit on a posted invoice must equal
 * Σ invoice_items.tax_amount (the same stored columns the tax report and
 * the return math read). Before the fix, the posting path recomputed tax
 * from GROSS qty × unit_price, ignoring item discounts, header discounts
 * and per-line rounding, so every discounted invoice was mis-split
 * between Sales Revenue and Tax Payable.
 *
 * Coverage: no discount, percentage / flat item discounts, header
 * discount, multi-line rounding, full return (exact reversal) and
 * partial return (proportional), plus the GL-balance invariant.
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import {
  getAuthCookie, createItem, purchaseStock, createCustomer, createInvoice,
  processReturn, glTotalsFor, assertGlBalanced,
} from './helpers/invoiceReturnSpec';
import { glImbalances } from './helpers/accountingInvariants';
import { decomposeLineAmount, parseCurrency } from '../utils/currency';

const EPS = 0.01;

function accountCodeToId(code: string): number {
  const row = db.prepare('SELECT id FROM chart_of_accounts WHERE code = ?').get(code) as { id: number };
  return row.id;
}

/** Σ stored invoice_items.tax_amount — the authoritative invoice tax. */
function storedTax(invoiceId: number): number {
  const row = db.prepare(
    'SELECT COALESCE(SUM(tax_amount), 0) AS tax FROM invoice_items WHERE invoice_id = ?'
  ).get(invoiceId) as { tax: number };
  return parseCurrency(row.tax);
}

/**
 * Net Tax Payable credit posted against the invoice itself
 * (INVOICE group only — return debits live in their own group).
 */
function postedTaxPayableCredit(invoiceId: number): number {
  const taxId = accountCodeToId('2100');
  const row = db.prepare(`
    SELECT COALESCE(SUM(credit - debit), 0) AS net
    FROM journal_lines
    WHERE account_id = ? AND reference_type = 'INVOICE'
      AND reference_id = ? AND voided = 0
  `).get(taxId, invoiceId) as { net: number };
  return parseCurrency(row.net);
}

/** Tax Payable debited by the return group (the reversal). */
function returnedTaxDebit(returnId: number): number {
  const taxId = accountCodeToId('2100');
  const row = db.prepare(`
    SELECT COALESCE(SUM(debit), 0) AS d
    FROM journal_lines
    WHERE account_id = ? AND reference_type = 'INVOICE_RETURN'
      AND reference_id = ? AND voided = 0
  `).get(taxId, returnId) as { d: number };
  return parseCurrency(row.d);
}

/**
 * The invoice create path with an optional INVOICE-scope header
 * discount (the shared helper does not send one).
 */
async function createInvoiceWithHeaderDiscount(args: {
  customerId: number;
  itemId: number;
  lines: Array<{ quantity: number; unitPrice: number; taxRate?: number; discountType?: string; discountValue?: number }>;
  headerDiscount?: { type: string; value: number };
  invoiceDate?: string;
}): Promise<{ invoiceId: number; invoiceItemIds: number[] }> {
  const res = await request(app).post('/api/invoices')
    .set('Cookie', authCookie)
    .send({
      customer_id: args.customerId,
      invoice_date: args.invoiceDate ?? '2026-09-15',
      due_date: '2026-09-30',
      discount_scope: args.headerDiscount ? 'invoice' : undefined,
      discount_type: args.headerDiscount?.type,
      discount_value: args.headerDiscount?.value,
      items: args.lines.map((l) => ({
        item_id: args.itemId,
        quantity: l.quantity,
        unit_price: l.unitPrice,
        tax_rate: l.taxRate ?? 0,
        discount_type: l.discountType ?? 'none',
        discount_value: l.discountValue ?? 0,
      })),
    });
  if (res.status !== 201 && res.status !== 200) {
    throw new Error(`createInvoiceWithHeaderDiscount failed: ${res.status} ${JSON.stringify(res.body)}`);
  }
  const invoiceId: number = res.body.id;
  const rows = db.prepare('SELECT id FROM invoice_items WHERE invoice_id = ? ORDER BY id').all(invoiceId) as Array<{ id: number }>;
  return { invoiceId, invoiceItemIds: rows.map((r) => r.id) };
}

let authCookie = '';

describe('H3 — tax posting matches the stored invoice tax', () => {
  let itemId: number;
  let customerId: number;
  let warehouseId: number;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');

    const wh = db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number };
    warehouseId = wh.id;

    itemId = await createItem('Tax Posting Widget (H3)', authCookie);
    await purchaseStock(itemId, warehouseId, 200, 100, authCookie); // ample stock at cost 100
    customerId = await createCustomer('Tax Posting Customer (H3)', authCookie);
  });

  // ── H3 core invariant, one assertion per discount shape ──────────

  it('no discount: posted Tax Payable == stored tax (10% on 3 × 600)', async () => {
    const { invoiceId } = await createInvoice({
      customerId, itemId,
      lines: [{ quantity: 3, unitPrice: 600, taxRate: 10 }],
      invoiceDate: '2026-09-15',
    }, authCookie);

    // stored: net 1800, tax 180
    expect(storedTax(invoiceId)).toBeCloseTo(180, 2);
    expect(postedTaxPayableCredit(invoiceId)).toBeCloseTo(180, 2);
    assertGlBalanced('INVOICE', invoiceId);
  });

  it('percentage item discount: tax uses the DISCOUNTED net, not gross', async () => {
    // 2 × 1000 gross 2000, 10% item discount → net 1800, tax 10% → 180
    // (the old gross-based code posted 200 — the bug).
    const { invoiceId } = await createInvoice({
      customerId, itemId,
      lines: [{ quantity: 2, unitPrice: 1000, taxRate: 10, discountType: 'percentage', discountValue: 10 }],
      invoiceDate: '2026-09-15',
    }, authCookie);

    expect(storedTax(invoiceId)).toBeCloseTo(180, 2);
    expect(postedTaxPayableCredit(invoiceId)).toBeCloseTo(180, 2);
    expect(postedTaxPayableCredit(invoiceId)).not.toBeCloseTo(200, 2);
    assertGlBalanced('INVOICE', invoiceId);
  });

  it('flat item discount: tax uses the discounted net', async () => {
    // gross 2000, flat 500 discount → net 1500, 10% tax → 150
    const { invoiceId } = await createInvoice({
      customerId, itemId,
      lines: [{ quantity: 2, unitPrice: 1000, taxRate: 10, discountType: 'flat', discountValue: 500 }],
      invoiceDate: '2026-09-15',
    }, authCookie);

    expect(storedTax(invoiceId)).toBeCloseTo(150, 2);
    expect(postedTaxPayableCredit(invoiceId)).toBeCloseTo(150, 2);
    assertGlBalanced('INVOICE', invoiceId);
  });

  it('header discount: posted tax still equals the stored line tax', async () => {
    // 2 × 1000 @10%: line tax 200, then a 100 invoice-scope header
    // discount. Tax is NOT recomputed off the header discount — the
    // stored line tax is the truth, so the GL must match it exactly and
    // the discount lands in revenue.
    const { invoiceId } = await createInvoiceWithHeaderDiscount({
      customerId, itemId,
      lines: [{ quantity: 2, unitPrice: 1000, taxRate: 10 }],
      headerDiscount: { type: 'flat', value: 100 },
    });

    expect(storedTax(invoiceId)).toBeCloseTo(200, 2);
    expect(postedTaxPayableCredit(invoiceId)).toBeCloseTo(200, 2);
    assertGlBalanced('INVOICE', invoiceId);
  });

  it('multi-line: posted tax == Σ per-line stored tax (rounding at the line boundary)', async () => {
    // Three lines whose tax does not sum to a round number per gross:
    //   1 × 333.33 @10% → net 333.33, tax 33.33
    //   2 × 250   @10% → net 500,    tax 50
    //   1 × 99.99 @10% → net 99.99,  tax 10.00
    const lines = [
      { quantity: 1, unitPrice: 333.33, taxRate: 10 },
      { quantity: 2, unitPrice: 250, taxRate: 10 },
      { quantity: 1, unitPrice: 99.99, taxRate: 10 },
    ];
    const { invoiceId } = await createInvoiceWithHeaderDiscount({ customerId, itemId, lines });

    const expected = lines.reduce((s, l) => s + decomposeLineAmount({
      quantity: l.quantity, unit_price: l.unitPrice, tax_rate: l.taxRate,
    }).taxAmount, 0);
    expect(expected).toBeCloseTo(93.33, 2);

    expect(storedTax(invoiceId)).toBeCloseTo(expected, 2);
    expect(postedTaxPayableCredit(invoiceId)).toBeCloseTo(expected, 2);
    assertGlBalanced('INVOICE', invoiceId);
  });

  it('zero-rated invoice posts no Tax Payable line at all', async () => {
    const { invoiceId } = await createInvoice({
      customerId, itemId,
      lines: [{ quantity: 1, unitPrice: 600 }],
      invoiceDate: '2026-09-15',
    }, authCookie);

    expect(storedTax(invoiceId)).toBe(0);
    expect(postedTaxPayableCredit(invoiceId)).toBe(0);
    assertGlBalanced('INVOICE', invoiceId);
  });

  // ── Return path: reversal tax tracks the STORED tax ──────────────

  it('full return reverses the stored tax exactly', async () => {
    const { invoiceId, invoiceItemIds } = await createInvoice({
      customerId, itemId,
      lines: [{ quantity: 2, unitPrice: 1000, taxRate: 10, discountType: 'percentage', discountValue: 10 }],
      invoiceDate: '2026-09-15',
    }, authCookie);
    expect(storedTax(invoiceId)).toBeCloseTo(180, 2);

    const res = await processReturn(invoiceId, {
      invoiceItemIds, quantities: [2], feeType: 'none', warehouseId,
      returnDate: '2026-09-16',
    }, authCookie);
    expect(res.status).toBe(200);
    const returnId = res.returnId!;
    expect(returnId).toBeDefined();

    expect(returnedTaxDebit(returnId)).toBeCloseTo(180, 2);
    assertGlBalanced('INVOICE_RETURN', returnId);
  });

  it('partial return reverses tax proportionally (half the line → half the stored tax)', async () => {
    // net 1800, stored tax 180 → returning 1 of 2 units debits 90.
    const { invoiceId, invoiceItemIds } = await createInvoice({
      customerId, itemId,
      lines: [{ quantity: 2, unitPrice: 1000, taxRate: 10, discountType: 'percentage', discountValue: 10 }],
      invoiceDate: '2026-09-15',
    }, authCookie);
    expect(storedTax(invoiceId)).toBeCloseTo(180, 2);

    const res = await processReturn(invoiceId, {
      invoiceItemIds, quantities: [1], feeType: 'none', warehouseId,
      returnDate: '2026-09-16',
    }, authCookie);
    expect(res.status).toBe(200);
    const returnId = res.returnId!;

    expect(returnedTaxDebit(returnId)).toBeCloseTo(90, 2);
    assertGlBalanced('INVOICE_RETURN', returnId);
  });

  // ── Global invariant ─────────────────────────────────────────────

  it('every GL reference group still balances after these postings', () => {
    const { groups, totalDiff } = glImbalances();
    expect(groups).toEqual([]);
    expect(totalDiff).toBeLessThan(EPS);
  });
});
