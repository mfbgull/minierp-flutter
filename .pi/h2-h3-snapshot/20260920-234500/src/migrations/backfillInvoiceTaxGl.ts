/**
 * One-time repair of historical GL tax drift (H3: tax posting must match
 * the stored invoice tax).
 *
 * postInvoiceEntry used to receive a tax amount recomputed from GROSS
 * line amounts (qty × unit_price × rate/100), which ignored item
 * discounts and per-line rounding. invoice_items.tax_amount — the stored
 * tax the reports and the return math read — is computed on the
 * DISCOUNTED NET (currency.ts::decomposeLineAmount). Every posted
 * discounted invoice therefore carried a Tax Payable credit that did not
 * match its stored tax.
 *
 * The AR debit was always correct (the tax-inclusive invoice total), so
 * the repair is surgical: only the split between Sales Revenue (4000)
 * and Tax Payable (2100) moves by the delta. For each invoice with a
 * live INVOICE revenue posting:
 *
 *   storedTax = Σ invoice_items.tax_amount            (authoritative)
 *   postedTax = net Tax Payable credit on the INVOICE group
 *               (+ any prior INVOICE_TAX_FIX correction)
 *   delta     = storedTax − postedTax
 *
 *   delta > 0 → Dr 4000 / Cr 2100  delta   (tax was under-posted)
 *   delta < 0 → Dr 2100 / Cr 4000 |delta|  (tax was over-posted)
 *
 * Posted as a balanced entry of its own reference type INVOICE_TAX_FIX,
 * keyed to the invoice, dated as the ORIGINAL invoice date so the
 * corrected figures land in the period that was wrong. It never touches
 * AR, COGS, payments, returns, or the subledger.
 *
 * Excluded by construction: cancelled invoices (cancellation voids the
 * INVOICE GL group), invoices never posted to the GL, and invoices whose
 * tax already matches. Idempotent: the correction is folded into
 * postedTax, so a second run finds delta == 0 and posts nothing.
 */
import type Database from 'better-sqlite3';
import { AccountingService } from '../services/accountingService';
import { parseCurrency } from '../utils/currency';
import logger from '../utils/logger';

interface DriftRow {
  id: number;
  invoice_no: string;
  invoice_date: string;
  stored_tax: number;
  posted_tax: number;
}

export function runBackfillInvoiceTaxGl(db: Database.Database): void {
  const revenue = AccountingService.getAccountByCode(db, '4000');
  const taxPayable = AccountingService.getAccountByCode(db, '2100');
  if (!revenue || !taxPayable) {
    logger.warn('[backfill-invoice-tax-gl] chart of accounts missing 4000/2100 — skipped');
    return;
  }

  // Only invoices with a live INVOICE Sales Revenue credit — i.e. a real
  // revenue posting whose split can be wrong. Cancelled invoices have
  // their INVOICE group voided, and never-posted invoices have no rows,
  // so both fall out of this predicate.
  const rows = db.prepare(`
    SELECT i.id,
           i.invoice_no,
           i.invoice_date,
           COALESCE((SELECT SUM(ii.tax_amount)
                     FROM invoice_items ii WHERE ii.invoice_id = i.id), 0) AS stored_tax,
           COALESCE((SELECT SUM(CASE WHEN jl.account_id = ?
                                     THEN jl.credit - jl.debit ELSE 0 END)
                     FROM journal_lines jl
                     WHERE jl.reference_type IN ('INVOICE', 'INVOICE_TAX_FIX')
                       AND jl.reference_id = i.id
                       AND jl.voided = 0), 0) AS posted_tax
    FROM invoices i
    WHERE i.total_amount > 0
      AND EXISTS (SELECT 1 FROM journal_lines jl
                  WHERE jl.reference_type = 'INVOICE'
                    AND jl.reference_id = i.id
                    AND jl.voided = 0
                    AND jl.account_id = ?
                    AND jl.credit > 0)
  `).all(taxPayable.id, revenue.id) as DriftRow[];

  let repaired = 0;
  let skipped = 0;
  const notes: string[] = [];

  const post = (row: DriftRow, delta: number): void => {
    const abs = parseCurrency(Math.abs(delta));
    // delta > 0: tax was UNDER-posted → move revenue into tax payable.
    // delta < 0: tax was OVER-posted → move tax payable back into revenue.
    const debitAccountId = delta > 0 ? revenue.id : taxPayable.id;
    const creditAccountId = delta > 0 ? taxPayable.id : revenue.id;
    AccountingService.postEntry(db, {
      entry_date: row.invoice_date,
      description:
        `Tax split correction for invoice ${row.invoice_no} — ` +
        `posted tax ${parseCurrency(row.posted_tax).toFixed(2)} → stored tax ` +
        `${parseCurrency(row.stored_tax).toFixed(2)} (delta ${delta > 0 ? '+' : ''}${abs.toFixed(2)}); ` +
        `AR unchanged`,
      reference_type: 'INVOICE_TAX_FIX',
      reference_id: row.id,
      created_by: null,
      lines: [
        { account_id: debitAccountId, debit: abs, description: `Tax correction for ${row.invoice_no}` },
        { account_id: creditAccountId, credit: abs, description: `Tax correction for ${row.invoice_no}` },
      ],
    });
    repaired += 1;
    notes.push(
      `invoice ${row.invoice_no} (#${row.id}): posted ${parseCurrency(row.posted_tax).toFixed(2)} ` +
      `vs stored ${parseCurrency(row.stored_tax).toFixed(2)} — corrected ${abs.toFixed(2)}`
    );
  };

  const run = (): void => {
    for (const row of rows) {
      const stored = parseCurrency(row.stored_tax);
      const posted = parseCurrency(row.posted_tax);
      const delta = Math.round((stored - posted) * 100) / 100;
      if (Math.abs(delta) <= 0.01) {
        skipped += 1;
        continue;
      }
      post(row, delta);
    }
  };

  db.transaction(run)();
  logger.info(
    `[backfill-invoice-tax-gl] repaired ${repaired} invoice(s); ${skipped} already matched`
  );
  for (const note of notes) logger.warn(`[backfill-invoice-tax-gl] ${note}`);
}
