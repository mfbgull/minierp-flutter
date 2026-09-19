/**
 * GL balance for the reworked invoice-return postings
 * (invoice-return-spec.md §3.5 + D20).
 *
 *   postInvoiceReturnEntry — the goods reversal:
 *     Dr Sales Returns (4100)  Σ returnedNet    (tax-EXCLUSIVE)
 *     Dr Tax Payable    (2100)  Σ returnedTax
 *     Cr AR             (1100)  Σ (net + tax)    (tax-INCLUSIVE)
 *
 *   postReturnFeeEntry — the restocking fee, as its OWN group:
 *     Dr AR (1100)  fee
 *     Cr Restocking Fee Income (4150)  fee
 *
 * The fee used to be a leg of the goods entry; it now posts separately so
 * it can be voided/reported on its own. Both groups must balance
 * individually.
 */
import db from '../config/database';
import { AccountingService, type PostedEntry } from '../services/accountingService';

const EPS = 0.01;

function groupTotals(referenceId: number): { debit: number; credit: number } {
  const row = db.prepare(`
    SELECT COALESCE(SUM(debit), 0) AS debit, COALESCE(SUM(credit), 0) AS credit
    FROM journal_lines
    WHERE reference_type = 'INVOICE_RETURN' AND reference_id = ? AND voided = 0
  `).get(referenceId) as { debit: number; credit: number };
  return { debit: Number(row.debit), credit: Number(row.credit) };
}

describe('invoice-return GL groups — goods reversal and restocking fee (spec §3.5 / D20)', () => {
  // Reference the shared test DB (already migrated by the global setup).
  const database = db;

  function post(args: {
    returnId: number;
    invoiceNo: string;
    returnedNet: number;
    returnedTax: number;
  }): PostedEntry | null {
    return AccountingService.postInvoiceReturnEntry(database, {
      returnId: args.returnId,
      invoiceNo: args.invoiceNo,
      lines: [{ returnedNet: args.returnedNet, returnedTax: args.returnedTax }],
      entryDate: '2026-09-17',
      userId: 1,
    });
  }

  function postFee(args: { returnId: number; invoiceNo: string; fee: number }): PostedEntry | null {
    return AccountingService.postReturnFeeEntry(database, {
      returnId: args.returnId,
      invoiceNo: args.invoiceNo,
      feeAmount: args.fee,
      entryDate: '2026-09-17',
      userId: 1,
    });
  }

  function feeGroupTotals(referenceId: number): { debit: number; credit: number } {
    const row = db.prepare(`
      SELECT COALESCE(SUM(debit), 0) AS debit, COALESCE(SUM(credit), 0) AS credit
      FROM journal_lines
      WHERE reference_type = 'RETURN_FEE' AND reference_id = ? AND voided = 0
    `).get(referenceId) as { debit: number; credit: number };
    return { debit: Number(row.debit), credit: Number(row.credit) };
  }

  it('no tax, no fee: Dr 4100 == Cr AR (balanced)', () => {
    const entryId = post({
      returnId: 990001,
      invoiceNo: 'TAXFIX-0001',
      returnedNet: 600,
      returnedTax: 0,
    });
    expect(entryId).not.toBeNull();
    const t = groupTotals(990001);
    expect(t.debit).toBeCloseTo(600, 2);
    expect(t.credit).toBeCloseTo(600, 2);
    expect(t.debit - t.credit).toBeLessThan(EPS);
  });

  it('tax > 0, fee == 0 — Dr 4100 + Dr 2100 == Cr AR (tax-inclusive credit)', () => {
    // Pre-rework this was imbalanced by the tax (600 + 60 debits vs 600 credit).
    const entryId = post({
      returnId: 990002,
      invoiceNo: 'TAXFIX-0002',
      returnedNet: 600,
      returnedTax: 60,
    });
    expect(entryId).not.toBeNull();
    const t = groupTotals(990002);
    expect(t.debit).toBeCloseTo(660, 2);
    expect(t.credit).toBeCloseTo(660, 2);
    expect(t.debit - t.credit).toBeLessThan(EPS);
  });

  it('tax > 0, fee > 0 — goods group balances on its own; fee posts as a separate RETURN_FEE group', () => {
    // gross 1200, tax 120, fee 120. Goods entry: Dr 1320 / Cr AR 1320.
    // The fee no longer appears in the goods group — it restores part of
    // that AR credit in its own Dr AR / Cr 4150 group.
    const entryId = post({
      returnId: 990003,
      invoiceNo: 'TAXFIX-0003',
      returnedNet: 1200,
      returnedTax: 120,
    });
    expect(entryId).not.toBeNull();
    expect(postFee({ returnId: 990003, invoiceNo: 'TAXFIX-0003', fee: 120 })).not.toBeNull();

    const t = groupTotals(990003);
    expect(t.debit).toBeCloseTo(1320, 2);   // Sales Returns 1200 + Tax Payable 120
    expect(t.credit).toBeCloseTo(1320, 2);  // AR credited tax-inclusive, fee NOT included
    expect(t.debit - t.credit).toBeLessThan(EPS);

    const f = feeGroupTotals(990003);
    expect(f.debit).toBeCloseTo(120, 2);    // Dr AR
    expect(f.credit).toBeCloseTo(120, 2);   // Cr 4150 fee income
    expect(f.debit - f.credit).toBeLessThan(EPS);
  });

  it('no tax, fee > 0 — same split: goods group net, fee group separate', () => {
    expect(post({ returnId: 990004, invoiceNo: 'TAXFIX-0004', returnedNet: 1200, returnedTax: 0 })).not.toBeNull();
    expect(postFee({ returnId: 990004, invoiceNo: 'TAXFIX-0004', fee: 120 })).not.toBeNull();

    const t = groupTotals(990004);
    expect(t.debit).toBeCloseTo(1200, 2);
    expect(t.credit).toBeCloseTo(1200, 2);
    expect(t.debit - t.credit).toBeLessThan(EPS);

    const f = feeGroupTotals(990004);
    expect(f.debit).toBeCloseTo(120, 2);
    expect(f.credit).toBeCloseTo(120, 2);
  });

  it('AR credit is tax-inclusive on tax-rated returns (the core correction)', () => {
    post({ returnId: 990005, invoiceNo: 'TAXFIX-0005', returnedNet: 600, returnedTax: 60 });
    const ar = db.prepare("SELECT id FROM chart_of_accounts WHERE code = '1100'").get() as { id: number };
    const arCredit = db.prepare(`
      SELECT COALESCE(SUM(credit), 0) AS c FROM journal_lines
      WHERE account_id = ? AND reference_type = 'INVOICE_RETURN'
        AND reference_id = 990005 AND voided = 0
    `).get(ar.id) as { c: number };
    expect(Number(arCredit.c)).toBeCloseTo(660, 2); // 600 + 60, not 600
  });
});
