import Database from 'better-sqlite3';

export type BatchStatus = 'ACTIVE' | 'BLOCKED' | 'QUARANTINED' | 'EXPIRED' | 'DAMAGED' | 'REJECTED';

export function getEffectiveBatchStatus(
  db: Database.Database,
  batchId: number,
  locationId?: number
): BatchStatus {
  const batch = db.prepare(`
    SELECT sb.halted, sb.halted_reason, sb.expiry_date,
           bsl.status_override, bsl.quantity_available
    FROM stock_batches sb
    LEFT JOIN batch_stock_by_location bsl ON sb.id = bsl.batch_id
      AND bsl.location_id = ?
    WHERE sb.id = ?
  `).get(locationId ?? null, batchId) as {
    halted: number | null;
    halted_reason: string | null;
    expiry_date: string | null;
    status_override: string | null;
    quantity_available: number;
  } | undefined;

  if (!batch) {
    throw new Error(`Batch ${batchId} not found`);
  }

  // 1. EXPIRED cannot be overridden
  if (batch.expiry_date && batch.expiry_date < new Date().toISOString().split('T')[0]) {
    return 'EXPIRED';
  }

  // 2. Explicit override takes precedence (except EXPIRED above)
  const override = batch.status_override;
  if (override && override !== 'EXPIRED') {
    return override as BatchStatus;
  }

  // 3. Derived from business rules
  if (batch.halted === 1) {
    return 'BLOCKED';
  }

  if (batch.quantity_available <= 0) {
    return 'REJECTED';
  }

  return 'ACTIVE';
}

export function setBatchStatusOverride(
  db: Database.Database,
  batchId: number,
  locationId: number,
  statusOverride: BatchStatus | null
): void {
  if (statusOverride === 'EXPIRED') {
    throw new Error('EXPIRED status cannot be set as override — it is derived from expiry_date');
  }

  db.prepare(`
    UPDATE batch_stock_by_location
    SET status_override = ?
    WHERE batch_id = ? AND location_id = ?
  `).run(statusOverride ?? null, batchId, locationId);
}

export function isBatchAllocatable(
  db: Database.Database,
  batchId: number,
  locationId?: number
): boolean {
  const status = getEffectiveBatchStatus(db, batchId, locationId);
  return status === 'ACTIVE';
}
