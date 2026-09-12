/**
 * Backfill batch_stock_by_location from existing stock_batches.
 * Idempotent: skips rows that already exist.
 * Run once after add-batch-location-model migration.
 */

import Database from 'better-sqlite3';

export function runBackfillBatchLocations(db: Database.Database): number {
  // 1. Ensure all batches have a location row
  const insert = db.prepare(`
    INSERT OR IGNORE INTO batch_stock_by_location (batch_id, location_id, quantity_physical, quantity_reserved, quantity_available)
    SELECT sb.id,
           COALESCE(
             (SELECT id FROM locations WHERE warehouse_id = sb.warehouse_id LIMIT 1),
             (SELECT id FROM locations LIMIT 1)
           ),
           sb.quantity_remaining,
           0,
           sb.quantity_remaining
    FROM stock_batches sb
    WHERE NOT EXISTS (
      SELECT 1 FROM batch_stock_by_location bsl WHERE bsl.batch_id = sb.id
    )
  `);

  const result = insert.run();
  const inserted = result.changes;

  // 2. Backfill stock_balances extension columns from current state
  // quantity_physical = sum of quantity_physical in batch_stock_by_location per (item, warehouse via location)
  // quantity_available = sum of quantity_available
  // quantity_reserved = sum of quantity_reserved
  db.exec(`
    UPDATE stock_balances SET
      quantity_physical = COALESCE((
        SELECT SUM(bsl.quantity_physical)
        FROM batch_stock_by_location bsl
        JOIN locations l ON bsl.location_id = l.id
        WHERE l.warehouse_id = stock_balances.warehouse_id
          AND EXISTS (
            SELECT 1 FROM stock_batches sb
            WHERE sb.id = bsl.batch_id AND sb.item_id = stock_balances.item_id
          )
      ), 0),
      quantity_reserved = COALESCE((
        SELECT SUM(bsl.quantity_reserved)
        FROM batch_stock_by_location bsl
        JOIN locations l ON bsl.location_id = l.id
        WHERE l.warehouse_id = stock_balances.warehouse_id
          AND EXISTS (
            SELECT 1 FROM stock_batches sb
            WHERE sb.id = bsl.batch_id AND sb.item_id = stock_balances.item_id
          )
      ), 0),
      quantity_available = COALESCE((
        SELECT SUM(bsl.quantity_available)
        FROM batch_stock_by_location bsl
        JOIN locations l ON bsl.location_id = l.id
        WHERE l.warehouse_id = stock_balances.warehouse_id
          AND EXISTS (
            SELECT 1 FROM stock_batches sb
            WHERE sb.id = bsl.batch_id AND sb.item_id = stock_balances.item_id
          )
      ), 0)
  `);

  return inserted;
}
