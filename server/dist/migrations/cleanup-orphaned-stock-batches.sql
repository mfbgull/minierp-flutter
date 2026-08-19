-- cleanup-orphaned-stock-batches.sql
-- Removes orphaned stock_batches that reference deleted purchases or
-- have invalid data. Nullifies dangling batch_id references in
-- stock_movements first to avoid FK violations.
--
-- Idempotent: safe to run on every server start. No-op when no
-- orphaned rows exist.

-- 1. Nullify dangling batch_id in stock_movements for batches about to be deleted
UPDATE stock_movements
SET batch_id = NULL
WHERE batch_id IN (
  SELECT sb.id FROM stock_batches sb
  WHERE (sb.source_type = 'PURCHASE'
         AND sb.source_id > 0
         AND NOT EXISTS (SELECT 1 FROM purchases WHERE id = sb.source_id)
         AND NOT EXISTS (SELECT 1 FROM goods_receipt_items WHERE id = sb.source_id))
     OR sb.unit_cost <= 0
     OR sb.quantity_original <= 0
);

-- 2. Delete orphaned batches:
--    a) PURCHASE batches whose source purchase/receipt was deleted
--    b) Zero cost or zero/negative quantity (bad test data)
DELETE FROM stock_batches
WHERE (source_type = 'PURCHASE'
       AND source_id > 0
       AND NOT EXISTS (SELECT 1 FROM purchases WHERE id = source_id)
       AND NOT EXISTS (SELECT 1 FROM goods_receipt_items WHERE id = source_id))
   OR unit_cost <= 0
   OR quantity_original <= 0;
