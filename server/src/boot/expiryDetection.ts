import Database from 'better-sqlite3';
import logger from '../utils/logger';
import StockMovementModel from '../models/StockMovement';

/**
 * Expiry Detection Boot Task (expired-stock plan Phase 2).
 *
 * Runs on server startup AFTER migrations (which seed the EXPIRED system
 * warehouse via add-expired-stock.sql) and BEFORE app.listen — so no
 * request can observe a half-swept valuation.
 *
 * Behavior:
 *  - Finds batches with expiry_date < today, quantity_remaining > 0, not
 *    already at the EXPIRED warehouse, and with no prior EXPIRY_TRANSFER
 *    movement (idempotency — safe to run on every boot).
 *  - Moves each via StockMovementModel.recordExpiryTransfer: the shared
 *    paired-leg transfer used by the write-off endpoint's auto-transfer
 *    path. Balances, mirror batches, and location layers are synced inside
 *    that helper — nothing here updates balances or batches by hand.
 *  - Transaction scope: ONE transaction PER BATCH. A single bad batch
 *    (constraint violation, orphaned row) cannot roll back the rest of the
 *    sweep; per-batch failures are logged and the batch is retried on the
 *    next boot automatically (the idempotency filter hasn't fired for it).
 *
 * Audit actor: movements are recorded with created_by = NULL and a
 * 'source=SYSTEM' remark (applied inside recordExpiryTransfer) — the boot
 * sweep is system-initiated and must not borrow an arbitrary admin's id.
 *
 * Failure policy: a missing EXPIRED warehouse throws (migration bug — fail
 * loud); per-batch errors are logged and skipped. Either way boot continues
 * — never block serving on expiry detection.
 */
export function runExpiryDetection(db: Database.Database): {
  candidates: number;
  moved: number;
  failed: number;
  failures: Array<{ batchId: number; batchNo: string; reason: string }>;
} {
  logger.info('Running expiry detection on startup...');

  const today = new Date().toISOString().split('T')[0];

  // 1. Resolve the destination warehouse by CODE — never a hardcoded id.
  //    Throwing is intentional: the Phase 1 migration guarantees this row,
  //    so its absence is a boot-blocking setup bug, not a runtime condition.
  const expiredWarehouse = db.prepare(
    `SELECT id FROM warehouses WHERE warehouse_code = 'EXPIRED' AND is_active = 1`
  ).get() as { id: number } | undefined;
  if (!expiredWarehouse) {
    throw new Error(
      "System warehouse 'EXPIRED' not found — add-expired-stock.sql migration did not run. " +
      'Expiry detection cannot proceed.'
    );
  }
  const expiredWarehouseId = expiredWarehouse.id;

  // 2. Candidate query (uses idx_stock_batches_expiry_active +
  //    idx_stock_movements_batch_type, both created by the Phase 1 migration).
  //    Replaces the old invalid `status NOT IN (...)` filter — batch status
  //    is derived, not stored; idempotency comes from the movement ledger.
  const candidates = db.prepare(`
    SELECT sb.id, sb.batch_no, sb.item_id, sb.warehouse_id,
           sb.quantity_remaining, sb.unit_cost, sb.expiry_date
    FROM stock_batches sb
    WHERE sb.expiry_date < ?
      AND sb.quantity_remaining > 0
      AND sb.warehouse_id <> ?
      AND NOT EXISTS (
        SELECT 1 FROM stock_movements sm
        WHERE sm.batch_id = sb.id AND sm.movement_type = 'EXPIRY_TRANSFER'
      )
    ORDER BY sb.expiry_date ASC
  `).all(today, expiredWarehouseId) as Array<{
    id: number;
    batch_no: string;
    item_id: number;
    warehouse_id: number;
    quantity_remaining: number;
    unit_cost: number | null;
    expiry_date: string | null;
  }>;

  logger.info(`Expiry detection: ${candidates.length} expired batch(es) to move to 'EXPIRED'`);

  // 3. Per-batch transaction scope: one failure must not roll back the sweep.
  let moved = 0;
  const failures: Array<{ batchId: number; batchNo: string; reason: string }> = [];
  for (const batch of candidates) {
    try {
      StockMovementModel.recordExpiryTransfer(
        {
          batchId: batch.id,
          toWarehouseId: expiredWarehouseId,
          remarks: `Expiry transfer: batch ${batch.batch_no} expired on ${batch.expiry_date ?? 'unknown'}`,
        },
        null, // system actor: created_by NULL + source=SYSTEM remark
        db
      );
      moved++;
      logger.info(
        `Expiry detection: moved batch ${batch.batch_no} (${Number(batch.quantity_remaining)} unit(s), ` +
        `expired ${batch.expiry_date ?? 'unknown'}) to 'EXPIRED' warehouse`
      );
    } catch (err) {
      const reason = err instanceof Error ? err.message : String(err);
      failures.push({ batchId: batch.id, batchNo: batch.batch_no, reason });
      logger.error(
        `Expiry detection: batch ${batch.batch_no} (id=${batch.id}) failed and will retry on next boot: ${reason}`
      );
    }
  }

  logger.info(
    `Expiry detection complete: ${moved} moved, ${failures.length} failed, ` +
    `${candidates.length - moved - failures.length} skipped`
  );

  return { candidates: candidates.length, moved, failed: failures.length, failures };
}
