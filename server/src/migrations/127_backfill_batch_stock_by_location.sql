-- BUG-013: backfill batch_stock_by_location from stock_batches.
--
-- The batch-location model (add-batch-location-model.sql) created the table and
-- its triggers but never filled it. Batches bought while the feature flag was
-- off got no location row, so flipping the flag on made every sell read
-- sellable stock 0 from batch_stock_by_location — a stock-amnesia switch.
--
-- This backfill gives every existing batch one DEFAULT-location row carrying its
-- remaining quantity, so the two sources agree before the flag is ever turned
-- on. A batch with no remaining quantity still gets its row (0), so the sources
-- agree on "nothing left" as well as on a positive number.
--
-- Idempotent: a batch that already has a location row is skipped, so a re-run
-- changes nothing. New batches are kept in step by
-- StockMovement.syncBatchStockByLocationForNewBatch, which now writes a row
-- regardless of the flag.

-- A warehouse created after the original migration has no DEFAULT location, so
-- the backfill below would have nothing to join to. Seed the missing ones first
-- (Warehouse.create now does this at write time; this repairs older rows).
INSERT INTO locations (warehouse_id, location_code, location_name)
SELECT w.id, 'DEFAULT', w.warehouse_name
FROM warehouses w
WHERE NOT EXISTS (
  SELECT 1 FROM locations l
  WHERE l.warehouse_id = w.id AND l.location_code = 'DEFAULT'
);

INSERT INTO batch_stock_by_location
  (batch_id, location_id, quantity_physical, quantity_reserved, quantity_available)
SELECT
  sb.id,
  l.id,
  sb.quantity_remaining,
  0,
  sb.quantity_remaining
FROM stock_batches sb
JOIN locations l
  ON l.warehouse_id = sb.warehouse_id
 AND l.location_code = 'DEFAULT'
WHERE NOT EXISTS (
  SELECT 1 FROM batch_stock_by_location bsl
  WHERE bsl.batch_id = sb.id
    AND bsl.location_id = l.id
);

-- Repair rows that exist but carry the wrong quantity. A half-migrated install
-- can hold a stale row (physical 0 while the batch still has stock). The insert
-- above skips those, because it only fills missing rows, so without this the
-- mixed state would survive the migration: the flag-on read walks
-- batch_stock_by_location and would under-report that batch's stock. Set any
-- DEFAULT-location row back to the batch's real remaining quantity.
--
-- Only the DEFAULT location is touched, and only its physical/available pair.
-- Reserved quantity is left alone: it belongs to a live reservation, not to the
-- batch's on-hand count, and the trigger recomputes quantity_available from it.
UPDATE batch_stock_by_location
SET quantity_physical = (
      SELECT sb.quantity_remaining FROM stock_batches sb WHERE sb.id = batch_stock_by_location.batch_id
    ),
    updated_at = CURRENT_TIMESTAMP
WHERE location_id IN (
  SELECT l.id FROM locations l WHERE l.location_code = 'DEFAULT'
)
AND batch_id IN (SELECT id FROM stock_batches)
AND quantity_physical <> (
      SELECT sb.quantity_remaining FROM stock_batches sb WHERE sb.id = batch_stock_by_location.batch_id
    )
AND quantity_reserved = 0;

-- Second half of BUG-013. The flag-on read path
-- (resolveAvailableQuantity) reads stock_balances.quantity_available, not the
-- location table. That column is maintained by
-- StockMovement.syncStockBalancesExtension, which was also gated on the flag,
-- so on an existing database it stayed 0. Backfilling only
-- batch_stock_by_location is therefore not enough: the sale is still refused
-- with "sellable stock 0". Bring quantity_available (and the physical and
-- reserved mirrors) up to the real batch totals now.
UPDATE stock_balances
SET quantity_physical = (
      SELECT COALESCE(SUM(sb.quantity_remaining), 0)
      FROM stock_batches sb
      WHERE sb.item_id = stock_balances.item_id
        AND sb.warehouse_id = stock_balances.warehouse_id
    ),
    quantity_reserved = 0,
    quantity_available = (
      SELECT COALESCE(SUM(sb.quantity_remaining), 0)
      FROM stock_batches sb
      WHERE sb.item_id = stock_balances.item_id
        AND sb.warehouse_id = stock_balances.warehouse_id
    ),
    last_updated = CURRENT_TIMESTAMP
WHERE EXISTS (
  SELECT 1 FROM stock_batches sb
  WHERE sb.item_id = stock_balances.item_id
    AND sb.warehouse_id = stock_balances.warehouse_id
);
