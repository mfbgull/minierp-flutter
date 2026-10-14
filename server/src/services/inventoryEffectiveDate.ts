import type Database from 'better-sqlite3';
import { BusinessRuleError } from '../utils/businessRuleError';

/**
 * ACCT-006 (Option A) — safe inventory transaction dates.
 *
 * An inventory movement carries THREE different dates and conflating them is
 * what allowed financially incorrect documents:
 *
 *   - the DOCUMENT date the user typed (invoice_date, purchase_date, ...)
 *   - the INVENTORY-EFFECTIVE date the movement is recorded against
 *     (stock_movements.movement_date)
 *   - the RECORD-CREATION timestamp (stock_movements.created_at)
 *
 * Under Option A the first two are held equal and both are constrained; the
 * third is left alone and is what the ledger already trusts for ordering
 * ties.
 *
 * THE RULE
 * A newly recorded inventory movement may not be effective earlier than the
 * latest movement already recorded for that item in that warehouse.
 *
 * Why that one rule is enough for Option A: the ledger is append-only, so
 * `MAX(movement_date)` is the last point in the recorded history at which
 * stock was known-good. Dating anything before it would mean inventing a past
 * in which quantities, FIFO order or expiry differed from what was posted,
 * and the system cannot prove the alternative without reconstructing history
 * (Option B). When history cannot be proven, the transaction is rejected
 * rather than guessed at.
 *
 * What it prevents, concretely:
 *   D1 — a sale consuming a batch received after the sale's own date
 *   D3 — a backdated sale driving historical stock negative
 *   D4 — a backdated receipt reordering FIFO beneath an already-posted sale
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

export interface EffectiveDateResult {
  /** Latest existing movement date, or null when the item has no history. */
  latestMovementDate: string | null;
}

/**
 * Rejects when [effectiveDate] precedes the latest recorded movement for the
 * item in that warehouse.
 *
 * Per item AND warehouse rather than per item globally: two warehouses hold
 * independent stock, so a movement in one does not constrain the other. A
 * sale that draws lines from several warehouses is checked line by line, and
 * the caller is inside its own write transaction, so a rejection rolls the
 * whole document back rather than leaving it half-written.
 */
export function assertInventoryDateNotRetroactive(
  db: Database.Database,
  check: EffectiveDateCheck,
): EffectiveDateResult {
  const { itemId, warehouseId, effectiveDate } = check;

  const row = db
    .prepare(
      `SELECT MAX(movement_date) AS latest
       FROM stock_movements
       WHERE item_id = ? AND warehouse_id = ?`,
    )
    .get(itemId, warehouseId) as { latest: string | null } | undefined;

  const latest = row?.latest ?? null;
  if (latest === null || effectiveDate >= latest) {
    return { latestMovementDate: latest };
  }

  if (check.probeOnly === true) return { latestMovementDate: latest };

  throw retroactiveError(db, itemId, effectiveDate, latest, check.documentLabel);
}

/**
 * Outbound side (sale, production consumption, transfer out, owner
 * withdrawal): stock cannot leave before it arrived, so any movement dated
 * after this one means the historical quantity was already settled.
 */
export function assertOutboundDateNotRetroactive(
  db: Database.Database,
  check: EffectiveDateCheck,
): void {
  assertInventoryDateNotRetroactive(db, check);
}

/**
 * Inbound side (purchase, goods receipt, production output, transfer in).
 *
 * A backdated RECEIPT is only dangerous when it would slip a new batch in
 * FRONT of a batch that a posted document has already consumed — that
 * silently reorders FIFO and restates COGS the ledger has already booked.
 *
 * Rejecting every retroactive receipt instead would be wrong: recording a
 * supplier invoice that arrived late, against stock nobody has sold yet,
 * changes no posted history and is ordinary wholesale trading. So the test
 * is "does this reorder something already consumed", not "is this the
 * earliest date".
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

/**
 * Convenience wrapper for callers that touch several lines. Collects the
 * FIRST violation and throws, so the user sees one clear reason rather than
 * a list. Must be called inside the caller's write transaction.
 */
export function assertLinesNotRetroactive(
  db: Database.Database,
  lines: Array<{ itemId: number; warehouseId: number }>,
  effectiveDate: string,
  documentLabel?: string,
): void {
  for (const line of lines) {
    assertInventoryDateNotRetroactive(db, {
      itemId: line.itemId,
      warehouseId: line.warehouseId,
      effectiveDate,
      documentLabel,
    });
  }
}