/**
 * One-time repair of historical header discounts (H2: persist the invoice
 * header discount).
 *
 * createInvoice used to read the invoice-scope discount from the request
 * and use it to compute the grand total, but never forwarded it to the
 * model. Those invoices therefore carry `discount_value = 0` on a total
 * that was already discounted — so the return path (which allocates
 * credit from the stored header discount) had no discount to give back:
 * a discounted line returned more credit than the customer was charged,
 * and a full return tripped the over-return guard against the undiscounted
 * line sum.
 *
 * The discount is recoverable: the grand total is always
 * Σ stored line amounts − the header discount, so the flat discount is
 * exactly the gap between them. The repair writes it back as a FLAT
 * discount (the type that reproduces the stored total to the cent — the
 * original percentage is not recoverable and is not needed, since the
 * return allocation only uses the resolved flat amount).
 *
 * Idempotent: repaired rows leave `discount_value > 0`, so they no longer
 * match the predicate. Invoices with no gap (no header discount was ever
 * applied) are left untouched. Cancelled invoices are excluded — they can
 * no longer be returned, and their stored total is already reversed.
 */
import type Database from 'better-sqlite3';
import { parseCurrency } from '../utils/currency';
import logger from '../utils/logger';

interface GapRow {
  id: number;
  invoice_no: string;
  lines_total: number;
  total_amount: number;
}

export function runBackfillInvoiceHeaderDiscount(db: Database.Database): void {
  // Only live invoices whose header discount is missing while the stored
  // total is smaller than the (tax-inclusive) line sum. discount_scope is
  // 'invoice' for every legacy row — it is the model default — so the
  // zero-value predicate is what pins the pre-H2 population.
  const rows = db.prepare(`
    SELECT i.id,
           i.invoice_no,
           COALESCE((SELECT SUM(ii.amount)
                     FROM invoice_items ii
                     WHERE ii.invoice_id = i.id), 0) AS lines_total,
           i.total_amount
    FROM invoices i
    WHERE i.deleted_at IS NULL
      AND i.status <> 'Cancelled'
      AND i.discount_scope = 'invoice'
      AND COALESCE(i.discount_value, 0) = 0
      AND i.total_amount > 0
  `).all() as GapRow[];

  let repaired = 0;
  let skipped = 0;

  for (const row of rows) {
    const linesTotal = parseCurrency(row.lines_total);
    const total = parseCurrency(row.total_amount);
    const gap = parseCurrency(linesTotal - total);
    if (!(gap > 0.005)) {
      skipped += 1;
      continue;
    }
    // A flat discount of exactly the gap reproduces the stored total,
    // which is what the return allocation and the grand-total check use.
    db.prepare(
      `UPDATE invoices SET discount_type = 'flat', discount_value = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?`
    ).run(gap, row.id);
    repaired += 1;
  }

  logger.info(
    `[backfill-invoice-header-discount] header discount recovered on ${repaired} invoice(s), ${skipped} needed no repair`,
  );
}
