-- Migration: index the goods_receipt_items foreign keys (audit DB-001)
--
-- goods_receipt_items carried three FK columns and NO indexes at all --
-- `PRAGMA index_list('goods_receipt_items')` returned empty. Every parent
-- delete or update (goods_receipts ON DELETE CASCADE, purchase_order_items,
-- items) had to full-scan the goods-receipt hot path, and
-- add-missing-fk-indexes.sql did not cover this table.
--
-- Index all three FK columns: the cascade on receipt_id, and the two joins
-- the receipt path performs per line.

CREATE INDEX IF NOT EXISTS idx_goods_receipt_items_receipt_id
  ON goods_receipt_items(receipt_id);

CREATE INDEX IF NOT EXISTS idx_goods_receipt_items_po_item_id
  ON goods_receipt_items(po_item_id);

CREATE INDEX IF NOT EXISTS idx_goods_receipt_items_item_id
  ON goods_receipt_items(item_id);