/**
 * H2 — Persist invoice header discount + notes, and make returns give the
 * discount back.
 *
 * Before the fix, `createInvoice` read `notes` and the invoice-scope
 * discount fields from the request and used them to compute the grand
 * total, but never forwarded them to `InvoiceModel.createInvoice`. The
 * invoice row therefore stored `discount_value = 0` and lost its notes,
 * so the return path — which allocates credit from the stored header
 * discount — had no discount to give back: a discounted line returned
 * more credit than the customer was ever charged for it.
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import {
  getAuthCookie, createItem, purchaseStock, createCustomer,
  processReturn, getInvoiceRow,
} from './helpers/invoiceReturnSpec';
import { glImbalances } from './helpers/accountingInvariants';
import { parseCurrency } from '../utils/currency';

const EPS = 0.01;

function invoiceRow(invoiceId: number): {
  total_amount: number; discount_scope: string; discount_type: string;
  discount_value: number; notes: string | null;
} {
  return db.prepare(
    'SELECT total_amount, discount_scope, discount_type, discount_value, notes FROM invoices WHERE id = ?'
  ).get(invoiceId) as {
    total_amount: number; discount_scope: string; discount_type: string;
    discount_value: number; notes: string | null;
  };
}

/**
 * Customer ledger net for THIS invoice only (debits − credits): the
 * invoice's own INVOICE row plus its RETURN rows. Voided excluded.
 * Scoped per invoice so the assertion is not polluted by the other
 * invoices this file creates for the same shared customer.
 */
function invoiceLedgerNet(invoiceId: number): number {
  const row = db.prepare(`
    SELECT COALESCE(SUM(debit - credit), 0) AS net
    FROM customer_ledger
    WHERE voided = 0 AND (
      reference_no = (SELECT invoice_no FROM invoices WHERE id = ?)
      OR reference_no IN (SELECT return_no FROM invoice_returns WHERE invoice_id = ?)
    )
  `).get(invoiceId, invoiceId) as { net: number };
  return parseCurrency(row.net);
}

/** Σ posted return credits for one invoice. */
function returnsCredited(invoiceId: number): number {
  const row = db.prepare(
    'SELECT COALESCE(SUM(returned_amount), 0) AS s FROM invoice_returns WHERE invoice_id = ? AND voided_at IS NULL'
  ).get(invoiceId) as { s: number };
  return parseCurrency(row.s);
}

interface DiscountedLine {
  quantity: number;
  unitPrice: number;
  taxRate?: number;
}

interface DiscountedInvoiceArgs {
  customerId: number;
  itemId: number;
  lines: DiscountedLine[];
  header?: { type: 'percentage' | 'flat'; value: number };
  notes?: string;
  invoiceDate?: string;
}

async function createDiscountedInvoice(
  args: DiscountedInvoiceArgs,
): Promise<{ invoiceId: number; invoiceItemIds: number[] }> {
  const res = await request(app).post('/api/invoices')
    .set('Cookie', authCookie)
    .send({
      customer_id: args.customerId,
      invoice_date: args.invoiceDate ?? '2026-09-15',
      due_date: '2026-09-30',
      notes: args.notes,
      discount_scope: args.header ? 'invoice' : undefined,
      discount_type: args.header?.type,
      discount_value: args.header?.value,
      items: args.lines.map((l) => ({
        item_id: args.itemId,
        quantity: l.quantity,
        unit_price: l.unitPrice,
        tax_rate: l.taxRate ?? 0,
        discount_type: 'none',
        discount_value: 0,
      })),
    });
  if (res.status !== 201 && res.status !== 200) {
    throw new Error(`createDiscountedInvoice failed: ${res.status} ${JSON.stringify(res.body)}`);
  }
  const invoiceId: number = res.body.id;
  const rows = db.prepare('SELECT id FROM invoice_items WHERE invoice_id = ? ORDER BY id')
    .all(invoiceId) as Array<{ id: number }>;
  return { invoiceId, invoiceItemIds: rows.map((r) => r.id) };
}

let authCookie = '';

describe('H2 — header discount + notes persist and returns give them back', () => {
  let itemId: number;
  let customerId: number;
  let warehouseId: number;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');
    const wh = db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number };
    warehouseId = wh.id;
    itemId = await createItem('Header Discount Widget (H2)', authCookie);
    await purchaseStock(itemId, warehouseId, 400, 100, authCookie);
    customerId = await createCustomer('Header Discount Customer (H2)', authCookie);
  });

  // ── Persistence (the bug) ─────────────────────────────────────────
  it('persists a percentage header discount and the notes', async () => {
    const { invoiceId } = await createDiscountedInvoice({
      customerId, itemId,
      lines: [{ quantity: 2, unitPrice: 500 }],
      header: { type: 'percentage', value: 10 },
      notes: 'Loyalty 10% off — H2',
    });
    const row = invoiceRow(invoiceId);
    expect(row.discount_scope).toBe('invoice');
    expect(row.discount_type).toBe('percentage');
    expect(row.discount_value).toBe(10);
    expect(row.notes).toBe('Loyalty 10% off — H2');
    // Grand total = Σ lines (1000) − 10% of the subtotal (100) = 900.
    expect(row.total_amount).toBeCloseTo(900, 2);
  });

  it('persists a flat header discount', async () => {
    const { invoiceId } = await createDiscountedInvoice({
      customerId, itemId,
      lines: [{ quantity: 2, unitPrice: 500 }],
      header: { type: 'flat', value: 100 },
    });
    const row = invoiceRow(invoiceId);
    expect(row.discount_type).toBe('flat');
    expect(row.discount_value).toBe(100);
    expect(row.total_amount).toBeCloseTo(900, 2);
  });

  it('defaults to no header discount and keeps notes null when absent', async () => {
    const { invoiceId } = await createDiscountedInvoice({
      customerId, itemId,
      lines: [{ quantity: 1, unitPrice: 500 }],
    });
    const row = invoiceRow(invoiceId);
    expect(row.discount_value).toBe(0);
    expect(row.total_amount).toBeCloseTo(500, 2);
    expect(row.notes).toBeNull();
  });

  it('survives an invoice update: notes and the discount are re-persisted', async () => {
    const { invoiceId, invoiceItemIds } = await createDiscountedInvoice({
      customerId, itemId,
      lines: [{ quantity: 2, unitPrice: 500 }],
      header: { type: 'flat', value: 100 },
      notes: 'before update',
    });
    const res = await request(app).put(`/api/invoices/${invoiceId}`)
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId,
        invoice_date: '2026-09-15',
        due_date: '2026-09-30',
        notes: 'after update',
        discount_scope: 'invoice',
        discount_type: 'percentage',
        discount_value: 20,
        items: [{
          item_id: itemId,
          quantity: 2,
          unit_price: 500,
          tax_rate: 0,
          discount_type: 'none',
          discount_value: 0,
        }],
      });
    expect(res.status).toBe(200);
    const row = invoiceRow(invoiceId);
    expect(row.discount_type).toBe('percentage');
    expect(row.discount_value).toBe(20);
    expect(row.notes).toBe('after update');
    expect(row.total_amount).toBeCloseTo(800, 2); // 1000 − 20%
    expect(invoiceItemIds.length).toBeGreaterThan(0);
  });

  // ── Returns after a header discount ───────────────────────────────
  it('full return after a header discount credits the DISCOUNTED total, not the gross', async () => {
    // 2 × 500 = 1000 gross, 10% header discount → the customer paid 900.
    const { invoiceId, invoiceItemIds } = await createDiscountedInvoice({
      customerId, itemId,
      lines: [{ quantity: 2, unitPrice: 500 }],
      header: { type: 'percentage', value: 10 },
    });
    expect(invoiceRow(invoiceId).total_amount).toBeCloseTo(900, 2);
    const res = await processReturn(invoiceId, {
      invoiceItemIds, quantities: [2], feeType: 'none', warehouseId,
      returnDate: '2026-09-16',
    }, authCookie);
    expect(res.status).toBe(200);
    // The return credit is 900 — NOT 1000 (the pre-fix behaviour).
    expect(returnsCredited(invoiceId)).toBeCloseTo(900, 2);
    expect(returnsCredited(invoiceId)).not.toBeCloseTo(1000, 2);
    const row = getInvoiceRow(invoiceId);
    expect(row.returned_amount).toBeCloseTo(900, 2);
    // Nothing is owed either way after a full return of a fully-paid... it
    // was unpaid, so the customer owes 0 and is credited 900.
    expect(Math.abs(invoiceLedgerNet(invoiceId))).toBeLessThan(EPS);
    expect(glImbalances().groups).toEqual([]);
  });

  it('partial return after a header discount gives back only its own share', async () => {
    // 2 × 500 = 1000 gross, 10% off → paid 900. Each unit's discounted
    // share is 450.
    const { invoiceId, invoiceItemIds } = await createDiscountedInvoice({
      customerId, itemId,
      lines: [{ quantity: 2, unitPrice: 500 }],
      header: { type: 'percentage', value: 10 },
    });
    const res = await processReturn(invoiceId, {
      invoiceItemIds, quantities: [1], feeType: 'none', warehouseId,
      returnDate: '2026-09-16',
    }, authCookie);
    expect(res.status).toBe(200);
    expect(returnsCredited(invoiceId)).toBeCloseTo(450, 2);
    expect(returnsCredited(invoiceId)).not.toBeCloseTo(500, 2);
    // The remaining unit still returns its discounted 450 — the two
    // partial returns close exactly on the invoice total.
    const res2 = await processReturn(invoiceId, {
      invoiceItemIds, quantities: [1], feeType: 'none', warehouseId,
      returnDate: '2026-09-17',
    }, authCookie);
    expect(res2.status).toBe(200);
    expect(returnsCredited(invoiceId)).toBeCloseTo(900, 2);
    expect(Math.abs(invoiceLedgerNet(invoiceId))).toBeLessThan(EPS);
    expect(glImbalances().groups).toEqual([]);
  });

  it('a flat header discount is shared across lines, not consumed by the first return', async () => {
    // Two lines, 500 gross each; flat 100 off → paid 900. Each line's
    // share of the discount is 50, so each returns 450.
    const { invoiceId, invoiceItemIds } = await createDiscountedInvoice({
      customerId, itemId,
      lines: [{ quantity: 1, unitPrice: 500 }, { quantity: 1, unitPrice: 500 }],
      header: { type: 'flat', value: 100 },
    });
    expect(invoiceItemIds).toHaveLength(2);
    const res = await processReturn(invoiceId, {
      invoiceItemIds: [invoiceItemIds[0]], quantities: [1], feeType: 'none', warehouseId,
      returnDate: '2026-09-16',
    }, authCookie);
    expect(res.status).toBe(200);
    expect(returnsCredited(invoiceId)).toBeCloseTo(450, 2);
    const res2 = await processReturn(invoiceId, {
      invoiceItemIds: [invoiceItemIds[1]], quantities: [1], feeType: 'none', warehouseId,
      returnDate: '2026-09-17',
    }, authCookie);
    expect(res2.status).toBe(200);
    expect(returnsCredited(invoiceId)).toBeCloseTo(900, 2);
    expect(glImbalances().groups).toEqual([]);
  });

  it('multi-line invoice with a header discount: full return closes on the grand total', async () => {
    // 500 + 300 + 200 = 1000 gross, flat 100 off → paid 900.
    const { invoiceId, invoiceItemIds } = await createDiscountedInvoice({
      customerId, itemId,
      lines: [{ quantity: 1, unitPrice: 500 }, { quantity: 1, unitPrice: 300 }, { quantity: 1, unitPrice: 200 }],
      header: { type: 'flat', value: 100 },
    });
    expect(invoiceRow(invoiceId).total_amount).toBeCloseTo(900, 2);
    const res = await processReturn(invoiceId, {
      invoiceItemIds, quantities: [1, 1, 1], feeType: 'none', warehouseId,
      returnDate: '2026-09-16',
    }, authCookie);
    expect(res.status).toBe(200);
    // Per-line credits (450 + 270 + 180) must sum to the grand total.
    expect(returnsCredited(invoiceId)).toBeCloseTo(900, 2);
    const items = db.prepare(
      'SELECT line_amount FROM invoice_return_items ri JOIN invoice_returns r ON r.id = ri.return_id '
      + 'WHERE r.invoice_id = ? AND r.voided_at IS NULL ORDER BY ri.id'
    ).all(invoiceId) as Array<{ line_amount: number }>;
    expect(items.reduce((s, i) => s + parseCurrency(i.line_amount), 0)).toBeCloseTo(900, 2);
    expect(Math.abs(invoiceLedgerNet(invoiceId))).toBeLessThan(EPS);
    expect(glImbalances().groups).toEqual([]);
  });

  it('header discount with tax: the tax reversal still matches the stored tax', async () => {
    // 2 × 500 @10% tax → lines 1100 (incl. 100 tax); flat 100 header
    // discount → grand total 1000. The discount comes out of revenue,
    // never out of tax.
    const { invoiceId, invoiceItemIds } = await createDiscountedInvoice({
      customerId, itemId,
      lines: [{ quantity: 2, unitPrice: 500, taxRate: 10 }],
      header: { type: 'flat', value: 100 },
    });
    expect(invoiceRow(invoiceId).total_amount).toBeCloseTo(1000, 2);
    const res = await processReturn(invoiceId, {
      invoiceItemIds, quantities: [2], feeType: 'none', warehouseId,
      returnDate: '2026-09-16',
    }, authCookie);
    expect(res.status).toBe(200);
    expect(returnsCredited(invoiceId)).toBeCloseTo(1000, 2);
    const taxRow = db.prepare(
      'SELECT COALESCE(SUM(tax_amount), 0) AS s FROM invoice_return_items ri '
      + 'JOIN invoice_returns r ON r.id = ri.return_id WHERE r.invoice_id = ? AND r.voided_at IS NULL'
    ).get(invoiceId) as { s: number };
    expect(parseCurrency(taxRow.s)).toBeCloseTo(100, 2);
    expect(glImbalances().groups).toEqual([]);
  });

  // ── Entitlement guard (step 7) ─────────────────────────────────────
  it('total return credits can never exceed the invoice total', async () => {
    const { invoiceId, invoiceItemIds } = await createDiscountedInvoice({
      customerId, itemId,
      lines: [{ quantity: 3, unitPrice: 500 }],
      header: { type: 'percentage', value: 10 },
    });
    expect(invoiceRow(invoiceId).total_amount).toBeCloseTo(1350, 2); // 1500 − 150
    // Return everything.
    const res = await processReturn(invoiceId, {
      invoiceItemIds, quantities: [3], feeType: 'none', warehouseId,
      returnDate: '2026-09-16',
    }, authCookie);
    expect(res.status).toBe(200);
    expect(returnsCredited(invoiceId)).toBeCloseTo(1350, 2);
    // The over-return guard rejects anything beyond the entitlement.
    const row = getInvoiceRow(invoiceId);
    expect(row.returned_amount).toBeLessThanOrEqual(row.total_amount + EPS);
    expect(row.returned_amount).toBeCloseTo(row.total_amount, 2);
  });

  it('every GL reference group still balances after the discounted returns', () => {
    const { groups, totalDiff } = glImbalances();
    expect(groups).toEqual([]);
    expect(totalDiff).toBeLessThan(EPS);
  });
});
