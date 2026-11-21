-- S-6: migration 127 overstates the stock_balances mirror when a live
-- reservation exists, which makes reserved units look sellable.
--
-- 127 set quantity_physical = SUM(stock_batches.quantity_remaining),
-- quantity_reserved = 0 and quantity_available to the same SUM. The runtime
-- mirror (StockMovement.syncStockBalancesExtension) instead sums the BIN rows.
-- A reservation lowers a bin's quantity_reserved and never touches
-- stock_batches.quantity_remaining, so on a database upgraded with a live
-- reservation the mirror claimed the held units were free (reserved 0,
-- available = the full on-hand quantity).
--
-- The last line of defence held: the flag-ON sale path allocates from the bin
-- rows, which 127 leaves correct, so the reserved units were not actually sold.
-- The damage is a mirror that disagreed with the bins until the next
-- reservation/purchase write refreshed it.
--
-- Fix: recompute the mirror from the bin rows for every item+warehouse the bin
-- table covers — the same sums syncStockBalancesExtension writes. This is the
-- authoritative source, so it is correct for reserved and unreserved rows alike.
-- Scoped to covered pairs only: an item+warehouse with no bin rows keeps
-- whatever 127 left, exactly as the runtime mirror leaves it.
--
-- 127 itself is untouched: it has shipped, so its behaviour stays. This
-- migration runs after it and repairs the result.
UPDATE stock_balances
SET quantity_physical = (
      SELECT COALESCE(SUM(bsl.quantity_physical), 0)
      FROM batch_stock_by_location bsl
      JOIN locations l ON bsl.location_id = l.id
      JOIN stock_batches sb ON sb.id = bsl.batch_id
      WHERE l.warehouse_id = stock_balances.warehouse_id
        AND sb.item_id = stock_balances.item_id
    ),
    quantity_reserved = (
      SELECT COALESCE(SUM(bsl.quantity_reserved), 0)
      FROM batch_stock_by_location bsl
      JOIN locations l ON bsl.location_id = l.id
      JOIN stock_batches sb ON sb.id = bsl.batch_id
      WHERE l.warehouse_id = stock_balances.warehouse_id
        AND sb.item_id = stock_balances.item_id
    ),
    quantity_available = (
      SELECT COALESCE(SUM(bsl.quantity_available), 0)
      FROM batch_stock_by_location bsl
      JOIN locations l ON l.id = bsl.location_id
      JOIN stock_batches sb ON sb.id = bsl.batch_id
      WHERE l.warehouse_id = stock_balances.warehouse_id
        AND sb.item_id = stock_balances.item_id
    ),
    last_updated = CURRENT_TIMESTAMP
WHERE EXISTS (
  SELECT 1
  FROM batch_stock_by_location bsl
  JOIN locations l ON bsl.location_id = l.id
  JOIN stock_batches sb ON sb.id = bsl.batch_id
  WHERE l.warehouse_id = stock_balances.warehouse_id
    AND sb.item_id = stock_balances.item_id
);
