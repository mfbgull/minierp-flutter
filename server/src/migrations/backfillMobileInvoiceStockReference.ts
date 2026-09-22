/**
 * TASK 17 — normalize the mobile-invoice stock-movement reference.
 *
 * MobileInvoice.submitInvoice keyed its SALE stock movements to the
 * numeric invoice ID (`reference_docno = '42'`), while every reversal
 * consumer resolves them by invoice NUMBER — InvoiceModel.reverseStockForItems
 * (cancel / delete / update / return), the soft-delete restore endpoint and
 * the return-history report joins all read `reference_docno = invoice_no`.
 * The lookup found nothing, so cancelling a mobile invoice logged
 * "[BatchReversal] No SALE movements found for item …", never wrote the
 * ADJUSTMENT restore, and left stock permanently reduced while the GL void
 * and the CANCELLATION ledger credit had already run.
 *
 * Step 1 rewrites the historical reference to the invoice number — the same
 * string the fixed write path now emits — so returns on those legacy
 * invoices restock correctly. It is precisely scoped to the mobile path:
 * recordBatchMovement prefixes remarks with "Batch: ", whereas the desktop
 * invoice and POS paths write "Sold via Invoice …" / "POS Sale: …" directly
 * (and use reference_doctype 'INVOICE'/'POS' with the doc number already).
 *
 * Step 2 repairs the stock of invoices cancelled while the bug was live:
 * their GL and customer-ledger reversal completed at cancel time, but the
 * batch restore never ran, so physical stock is understated against a GL
 * that shows no reduction. The repair applies exactly the stock leg the
 * fixed cancel would have produced. Idempotence: the INVOICE_CANCEL
 * movement is the "cancel already reversed its stock" marker, so each
 * invoice is repaired at most once, and a DB fixed before this migration
 * matches neither predicate.
 */
import type Database from 'better-sqlite3';
import logger from '../utils/logger';
import InvoiceModel from '../models/Invoice';

// The mobile write path is the only one that routes SALE movements through
// StockMovementModel.recordBatchMovement, which prefixes the remarks with
// "Batch: …". Desktop/POS SALE movements carry their own "Sold via Invoice …"
// / "POS Sale: …" remarks, so matching on that prefix pins the population
// without touching them. The literal is inlined at each use site (no
// module-level constant): config/database.ts imports this module, which
// imports models/Invoice, which imports config/database — a module-scope
// const is still in its temporal dead zone when boot runs this function.

export function runBackfillMobileInvoiceStockReference(db: Database.Database): void {
  // ── Step 1: reference_docno = invoice ID → invoice number ────────────
  // CAST to INTEGER resolves a pure-numeric reference; the EXISTS guard
  // both excludes non-numeric references (CAST('INV-5') = 0, never an id)
  // and skips rows already carrying the invoice number, so re-running this
  // migration after the fix is a no-op.
  const rekeyed = db.prepare(`
    UPDATE stock_movements
    SET reference_docno = (
      SELECT i.invoice_no FROM invoices i
      WHERE i.id = CAST(stock_movements.reference_docno AS INTEGER)
    )
    WHERE reference_doctype = 'INVOICE'
      AND movement_type = 'SALE'
      AND remarks LIKE ?
      AND reference_docno GLOB '[0-9]*'
      AND reference_docno NOT GLOB '*[^0-9]*'
      AND EXISTS (
        SELECT 1 FROM invoices i
        WHERE i.id = CAST(stock_movements.reference_docno AS INTEGER)
          AND i.invoice_no IS NOT NULL
          AND i.invoice_no <> ''
          AND i.invoice_no <> stock_movements.reference_docno
      )
  `).run('Batch: %').changes;

  // ── Step 2: restore stock for invoices cancelled under the old key ───
  // Status 'Cancelled' + SALE movements present + no INVOICE_CANCEL
  // movement == "the cancel reversal found no SALE movements to restore".
  const cancelled = db.prepare(`
    SELECT i.id, i.invoice_no, i.created_by
    FROM invoices i
    WHERE i.status = 'Cancelled'
      AND EXISTS (
        SELECT 1 FROM stock_movements sm
        WHERE sm.reference_doctype = 'INVOICE'
          AND sm.movement_type = 'SALE'
          AND sm.reference_docno = i.invoice_no
          AND sm.remarks LIKE ?
      )
      AND NOT EXISTS (
        SELECT 1 FROM stock_movements sm
        WHERE sm.reference_doctype = 'INVOICE_CANCEL'
          AND sm.reference_docno = i.invoice_no
      )
  `).all('Batch: %') as Array<{ id: number; invoice_no: string; created_by: number | null }>;

  let repaired = 0;
  let skipped = 0;
  for (const inv of cancelled) {
    const items = InvoiceModel.getInvoiceItemsForStockReverse(db, inv.id);
    if (items.length === 0) continue;
    // Each invoice's repair is its own savepoint: a batch that can no
    // longer accept the restore (consumed past the sale by later
    // documents, a merged item, …) must never abort the boot — the
    // reference rewrite in step 1 still leaves that invoice's future
    // reversals correct.
    try {
      // Attribute the repair to the invoice's original actor (the
      // movement and its stock-adjustment GL entry carry created_by);
      // user 1 is the seeded-admin fallback for legacy rows with none.
      db.transaction(() =>
        InvoiceModel.reverseStockForItems(
          db,
          items,
          inv.invoice_no,
          inv.created_by ?? 1,
          'INVOICE_CANCEL',
        ),
      )();
      repaired += 1;
    } catch (repairError) {
      skipped += 1;
      logger.warn(
        `[task17] could not restore stock on cancelled invoice ${inv.invoice_no}: ${(repairError as Error).message}`
      );
    }
  }

  if (rekeyed > 0 || repaired > 0 || skipped > 0) {
    logger.info(
      `[task17] mobile invoice stock reference: re-keyed ${rekeyed} SALE movement(s) to invoice_no; restored stock on ${repaired} cancelled invoice(s)${skipped ? `; skipped ${skipped}` : ''}`
    );
  }
}
