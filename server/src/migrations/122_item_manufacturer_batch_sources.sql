ALTER TABLE items ADD COLUMN manufacturer_name TEXT
  CHECK (manufacturer_name IS NULL OR length(trim(manufacturer_name)) BETWEEN 1 AND 200);
CREATE INDEX idx_items_manufacturer_name ON items(manufacturer_name);

-- Provenance only: a transfer keeps its existing quantity and cost layer.
-- NULL source_batch_id explicitly represents unbatched / unknown stock.
CREATE TABLE stock_batch_sources (
  id INTEGER PRIMARY KEY,
  batch_id INTEGER NOT NULL REFERENCES stock_batches(id) ON DELETE CASCADE,
  source_batch_id INTEGER REFERENCES stock_batches(id),
  quantity REAL NOT NULL CHECK(quantity > 0),
  CHECK(source_batch_id IS NULL OR batch_id <> source_batch_id)
);
CREATE INDEX idx_stock_batch_sources_batch ON stock_batch_sources(batch_id);
CREATE INDEX idx_stock_batch_sources_source ON stock_batch_sources(source_batch_id);

-- These historical transfers moved exactly one named batch. General FIFO
-- transfers may have combined suppliers; their first batch alone is not proof.
INSERT INTO stock_batch_sources(batch_id, source_batch_id, quantity)
SELECT b.id, m.batch_id, b.quantity_original
FROM stock_batches b
JOIN stock_movements m ON m.id = b.source_id
JOIN stock_batches original ON original.id = m.batch_id AND original.item_id = b.item_id
WHERE b.source_type = 'TRANSFER'
  AND m.movement_type IN ('EXPIRY_TRANSFER', 'DAMAGE_TRANSFER')
  AND m.quantity < 0 AND b.quantity_original > 0
  AND b.id <> original.id;
