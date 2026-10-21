import type Database from 'better-sqlite3';
import { BusinessRuleError } from '../utils/businessRuleError';

/**
 * ACCT-006 — the inbound side of the inventory transaction-date rule.
 *
 * An inventory movement carries THREE different dates and conflating them is
 * what allowed financially incorrect documents:
 *
 *   - the DOCUMENT date the user typed (purchase_date, goods-receipt date, ...)
 *   - the INVENTORY-EFFECTIVE date the movement is recorded against
 *     (stock_movements.movement_date)
 *   - the RECORD-CREATION timestamp (stock_movements.created_at)
 *
 * The first two are held equal and both are constrained; the third is left
 * alone and is what the ledger already trusts for ordering ties.
 *
 * THE INBOUND RULE
 * A backdated RECEIPT is only dangerous when it would slip a new batch in
 * FRONT of a batch that a posted document has already consumed — that
 * silently reorders FIFO and restates COGS the ledger has already booked.
 *
 * Rejecting every retroactive receipt instead would be wrong: recording a
 * supplier invoice that arrived late, against stock nobody has sold yet,
 * changes no posted history and is ordinary wholesale trading. So the test
 * is "does this reorder something already consumed", not "is this the
 * earliest date".
 *
 * The outbound side of ACCT-006 — a sale may not consume stock received
 * after its own date, and a backdated sale may not drive historical stock
 * negative — is enforced in the consumption path itself, by the `asOf` filter
 * in `StockMovement.consumeFromOldestBatches`, not by a separate guard.
 * See `docs/INVENTORY-EFFECTIVE-DATES.md` for the full rationale and the
 * end-to-end coverage.
 *
 * Same-day transactions are permitted (`<=` is inclusive) because a purchase
 * and a sale on one date is normal wholesale trading.
 */
export interface EffectiveDateCheck {
  itemId: number;
  warehouseId: number;
  /** The date the movement will be recorded against (YYYY-MM-DD). */
  effectiveDate: string;
  /** Human name of the document, used in the error message. */
  documentLabel?: string;
  /** Return the latest known movement date instead of throwing. */
  probeOnly?: boolean;
}

/**
 * Rejects a backdated inbound movement that would reorder FIFO beneath a
 * batch already partly consumed by a posted document.
 *
 * Per item AND warehouse rather than per item globally: two warehouses hold
 * independent stock, so a movement in one does not constrain the other. The
 * caller is inside its own write transaction, so a rejection rolls the whole
 * document back rather than leaving it half-written.
 */
export function assertInboundDateNotRetroactive(
  db: Database.Database,
  check: EffectiveDateCheck,
): void {
  const { itemId, warehouseId, effectiveDate } = check;
  if (check.probeOnly === true) return;

  const consumedAhead = db
    .prepare(
      `SELECT id, batch_no, received_date FROM stock_batches
       WHERE item_id = ? AND warehouse_id = ?
         AND received_date > ?
         AND quantity_remaining < quantity_original
       LIMIT 1`,
    )
    .get(itemId, warehouseId, effectiveDate) as
    | { id: number; batch_no: string; received_date: string }
    | undefined;

  if (!consumedAhead) return;

  const label = check.documentLabel ?? 'This receipt';
  throw retroactiveError(
    db,
    itemId,
    effectiveDate,
    consumedAhead.received_date,
    `${label} — batch ${consumedAhead.batch_no} (received ${consumedAhead.received_date}) has already ` +
      `been partly consumed by a posted document, so a batch dated ${effectiveDate} would take ` +
      `precedence over it under FIFO and restate cost of goods already booked`,
  );
}

function retroactiveError(
  db: Database.Database,
  itemId: number,
  effectiveDate: string,
  latest: string,
  label?: string,
): BusinessRuleError {
  const name = (
    db.prepare('SELECT item_name FROM items WHERE id = ?').get(itemId) as
      | { item_name: string }
      | undefined
  )?.item_name ?? `item ${itemId}`;

  return new BusinessRuleError(
    400,
    `${label ?? 'This transaction'} is dated ${effectiveDate}, but stock movements for "${name}" are already ` +
      `recorded up to ${latest}. A movement cannot be dated before one that has already been posted: it would ` +
      `change quantities, batch allocation and COGS that are already on the books. Record it with a date of ` +
      `${latest} or later.`,
  );
}
