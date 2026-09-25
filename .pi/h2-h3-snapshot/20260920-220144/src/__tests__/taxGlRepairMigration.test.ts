/**
 * H3 data-repair — backfillInvoiceTaxGl.
 *
 * Simulates historical drift (the GL split posted from gross instead of
 * the discounted-net stored tax), then asserts the repair moves only the
 * Revenue ↔ Tax Payable split by the delta, keeps every group balanced,
 * stays idempotent, and leaves excluded documents alone.
 */
import db from '../config/database';
import { runBackfillInvoiceTaxGl } from '../migrations/backfillInvoiceTaxGl';
import {
  getAuthCookie, createItem, purchaseStock, createCustomer, createInvoice,
} from './helpers/invoiceReturnSpec';
import { glImbalances } from './helpers/accountingInvariants';
import { parseCurrency } from '../utils/currency';

function accountId(code: string): number {
  return (db.prepare('SELECT id FROM chart_of_accounts WHERE code = ?').get(code) as { id: number }).id;
}

/** A discounted invoice: net 1800, stored tax 180 (gross was 2000). */
async function seedDiscountedInvoice(
  customerId: number, itemId: number, authCookie: string,
): Promise<number> {
  const { invoiceId } = await createInvoice({
    customerId, itemId,
    lines: [{ quantity: 2, unitPrice: 1000, taxRate: 10, discountType: 'percentage', discountValue: 10 }],
    invoiceDate: '2026-09-15',
  }, authCookie);
  const row = db.prepare(
    'SELECT COALESCE(SUM(tax_amount), 0) AS tax FROM invoice_items WHERE invoice_id = ?'
  ).get(invoiceId) as { tax: number };
  expect(parseCurrency(row.tax)).toBeCloseTo(180, 2);
  return invoiceId;
}

/** Net Tax Payable credit attributable to the invoice (INVOICE + INVOICE_TAX_FIX). */
function netTaxPayableCredit(invoiceId: number): number {
  const taxId = accountId('2100');
  const row = db.prepare(`
    SELECT COALESCE(SUM(credit - debit), 0) AS net
    FROM journal_lines
    WHERE account_id = ? AND reference_id = ?
      AND reference_type IN ('INVOICE', 'INVOICE_TAX_FIX') AND voided = 0
  `).get(taxId, invoiceId) as { net: number };
  return parseCurrency(row.net);
}

function correctionRows(invoiceId: number): Array<{ debit: number; credit: number }> {
  return db.prepare(`
    SELECT debit, credit
    FROM journal_lines
    WHERE reference_type = 'INVOICE_TAX_FIX' AND reference_id = ? AND voided = 0
  `).all(invoiceId) as Array<{ debit: number; credit: number }>;
}

/**
 * Corrupt the live INVOICE group into the OLD buggy shape: Tax Payable
 * credited with gross-based `badTax` and Revenue absorbing the rest.
 */
function corruptToGrossTax(invoiceId: number, badTax: number): void {
  const taxId = accountId('2100');
  const revId = accountId('4000');
  const total = parseCurrency(
    (db.prepare('SELECT total_amount FROM invoices WHERE id = ?').get(invoiceId) as { total_amount: number }).total_amount
  );
  db.prepare(`
    UPDATE journal_lines SET credit = ? WHERE reference_type = 'INVOICE'
      AND reference_id = ? AND account_id = ? AND voided = 0
  `).run(badTax, invoiceId, taxId);
  db.prepare(`
    UPDATE journal_lines SET credit = ? WHERE reference_type = 'INVOICE'
      AND reference_id = ? AND account_id = ? AND voided = 0
  `).run(parseCurrency(total - badTax), invoiceId, revId);
}

describe('H3 repair migration — backfillInvoiceTaxGl', () => {
  let authCookie: string;
  let itemId: number;
  let customerId: number;
  let warehouseId: number;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');
    const wh = db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number };
    warehouseId = wh.id;
    itemId = await createItem('Tax Repair Widget (H3)', authCookie);
    await purchaseStock(itemId, warehouseId, 200, 100, authCookie);
    customerId = await createCustomer('Tax Repair Customer (H3)', authCookie);
  });

  it('over-posted tax: moves the delta from Tax Payable back to Revenue', async () => {
    const invoiceId = await seedDiscountedInvoice(customerId, itemId, authCookie);
    // The historical bug posted gross tax 200 instead of the stored 180.
    corruptToGrossTax(invoiceId, 200);
    expect(netTaxPayableCredit(invoiceId)).toBeCloseTo(200, 2);

    runBackfillInvoiceTaxGl(db);

    // Net Tax Payable credit is now exactly the stored tax.
    expect(netTaxPayableCredit(invoiceId)).toBeCloseTo(180, 2);
    // The correction debited 2100 and credited 4000 by 20.
    const rows = correctionRows(invoiceId);
    expect(rows).toHaveLength(2);
    expect(rows.find((r) => r.debit > 0)!.debit).toBeCloseTo(20, 2);
    expect(rows.find((r) => r.credit > 0)!.credit).toBeCloseTo(20, 2);
    // AR was never touched.
    const arId = accountId('1100');
    const ar = db.prepare(`
      SELECT COALESCE(SUM(debit - credit), 0) AS net FROM journal_lines
      WHERE account_id = ? AND reference_type = 'INVOICE' AND reference_id = ? AND voided = 0
    `).get(arId, invoiceId) as { net: number };
    expect(parseCurrency(ar.net)).toBeCloseTo(1980, 2); // 1800 net + 180 tax
    // GL still balances everywhere.
    expect(glImbalances().groups).toEqual([]);
  });

  it('under-posted tax: moves the delta from Revenue into Tax Payable', async () => {
    const invoiceId = await seedDiscountedInvoice(customerId, itemId, authCookie);
    // Legacy 2-line posting: no Tax Payable line at all, all revenue.
    corruptToGrossTax(invoiceId, 0);
    expect(netTaxPayableCredit(invoiceId)).toBeCloseTo(0, 2);

    runBackfillInvoiceTaxGl(db);

    expect(netTaxPayableCredit(invoiceId)).toBeCloseTo(180, 2);
    const rows = correctionRows(invoiceId);
    expect(rows).toHaveLength(2);
    expect(rows.find((r) => r.credit > 0)!.credit).toBeCloseTo(180, 2);
    expect(glImbalances().groups).toEqual([]);
  });

  it('is idempotent: a second run posts nothing new', async () => {
    const invoiceId = await seedDiscountedInvoice(customerId, itemId, authCookie);
    corruptToGrossTax(invoiceId, 200);
    runBackfillInvoiceTaxGl(db);
    const afterFirst = correctionRows(invoiceId).length;

    runBackfillInvoiceTaxGl(db);
    expect(correctionRows(invoiceId).length).toBe(afterFirst);
    expect(netTaxPayableCredit(invoiceId)).toBeCloseTo(180, 2);
  });

  it('already-matching invoices are left alone', async () => {
    const invoiceId = await seedDiscountedInvoice(customerId, itemId, authCookie);
    // No corruption — the correct posting already matches the stored tax.
    runBackfillInvoiceTaxGl(db);
    expect(correctionRows(invoiceId)).toHaveLength(0);
    expect(netTaxPayableCredit(invoiceId)).toBeCloseTo(180, 2);
  });

  it('cancelled invoices are not repaired', async () => {
    const invoiceId = await seedDiscountedInvoice(customerId, itemId, authCookie);
    corruptToGrossTax(invoiceId, 200);

    // Cancel: voids the INVOICE group (reversal-rules C1/C4).
    db.prepare('UPDATE invoices SET status = ? WHERE id = ?').run('Cancelled', invoiceId);
    db.prepare(`
      UPDATE journal_lines SET voided = 1, void_reason = ?
      WHERE reference_type = 'INVOICE' AND reference_id = ? AND voided = 0
    `).run('cancelled', invoiceId);

    runBackfillInvoiceTaxGl(db);
    expect(correctionRows(invoiceId)).toHaveLength(0);
  });

  it('invoices never posted to the GL are not repaired', async () => {
    const invoiceId = await seedDiscountedInvoice(customerId, itemId, authCookie);
    // Wipe the GL group entirely — as if predating live posting.
    db.prepare(`
      UPDATE journal_lines SET voided = 1, void_reason = ?
      WHERE reference_type = 'INVOICE' AND reference_id = ? AND voided = 0
    `).run('never posted', invoiceId);

    runBackfillInvoiceTaxGl(db);
    expect(correctionRows(invoiceId)).toHaveLength(0);
  });
});
