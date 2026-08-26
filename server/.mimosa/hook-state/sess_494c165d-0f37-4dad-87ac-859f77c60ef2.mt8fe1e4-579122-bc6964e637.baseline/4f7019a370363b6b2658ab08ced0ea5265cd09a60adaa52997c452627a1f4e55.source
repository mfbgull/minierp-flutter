/**
 * One-time backfill of invoice_items.net_amount / tax_amount
 * (report-query-integrity). Runs after add-invoice-item-tax-columns.sql.
 *
 * Every current writer stores `amount` as round(qty × price − discount)
 * with tax added at the line boundary (computeLineAmount), so a row is
 * decomposed by re-deriving that prediction from its own columns:
 *
 *   predicted = round(afterDiscount × (1 + rate/100))
 *   → match:  tax = round(afterDiscount × rate/100), net = amount − tax
 *   no match (legacy gross-stored rows): net = amount,
 *            tax = round(amount × rate/100) — flagged for review
 *
 * Unresolvable rows keep the inclusive interpretation and are logged —
 * nothing is silently guessed differently from what is stored.
 */
import type Database from 'better-sqlite3';
import logger from '../utils/logger';

interface LineRow {
  id: number;
  quantity: number;
  unit_price: number;
  amount: number;
  tax_rate: number;
  discount_type: string | null;
  discount_value: number;
}

const r2 = (v: number): number => Math.round(v * 100) / 100;
const tol = (amount: number): number => Math.max(0.01, Math.abs(amount) * 0.001);

export function runBackfillInvoiceItemTax(db: Database.Database): void {
  const lines = db.prepare(`
    SELECT id, quantity, unit_price, amount, tax_rate, discount_type, COALESCE(discount_value, 0) as discount_value
    FROM invoice_items WHERE tax_amount = 0 AND net_amount = 0
  `).all() as LineRow[];

  const update = db.prepare(
    `UPDATE invoice_items SET net_amount = ?, tax_amount = ? WHERE id = ?`
  );

  const review: string[] = [];
  let updated = 0;

  const run = (): void => {
    for (const l of lines) {
      const gross = r2(l.quantity * l.unit_price);
      const dv = r2(l.discount_value || 0);
      let afterDiscount = gross;
      if (dv > 0) {
        const disc = l.discount_type === 'flat' ? r2(dv) : r2(gross * (dv / 100));
        afterDiscount = r2(gross - Math.min(disc, gross));
      }
      const rate = l.tax_rate || 0;

      // Zero-amount lines have nothing to decompose.
      if (r2(l.amount) === 0) { update.run(0, 0, l.id); continue; }

      const predictedInclusive = r2(afterDiscount * (1 + rate / 100));
      if (Math.abs(r2(l.amount) - predictedInclusive) <= tol(l.amount)) {
        const tax = r2(afterDiscount * (rate / 100));
        update.run(r2(l.amount - tax), tax, l.id);
        updated += 1;
        continue;
      }

      // Legacy exclusive/gross-stored row: amount never contained tax.
      const taxExclusive = r2(r2(l.amount) * (rate / 100));
      update.run(r2(l.amount), taxExclusive, l.id);
      updated += 1;
      review.push(
        `invoice_item #${l.id}: stored ${l.amount} matches neither inclusive ` +
        `${predictedInclusive} nor gross ${gross} — treated as tax-exclusive base`
      );
    }
  };

  db.transaction(run)();
  logger.info(`[backfill-item-tax] decomposed ${updated} line(s); ${review.length} need review`);
  for (const item of review) logger.warn(`[backfill-item-tax] review: ${item}`);
}
