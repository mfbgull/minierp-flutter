-- Invoice Return rework (invoice-return-spec.md Milestone 2): the void
-- flow must undo EXACTLY what one return did — not "the invoice's returns"
-- in aggregate. Two columns make that attribution possible:
--
--   invoice_return_items.stock_movement_id
--       the restock movement the line posted (qty + cost + warehouse),
--       so voiding the return posts the precise equal-and-opposite
--       movement. A line whose restock was skipped by the existing
--       remaining-qty logic stays NULL and voiding it touches no stock.
--
--   return_settlements.voided_by
--       actor for the audit trail when a settlement is voided (the
--       header table already carries voided_by).
--
-- Additive only; no data backfill. Runs once per database.

ALTER TABLE invoice_return_items ADD COLUMN stock_movement_id INTEGER REFERENCES stock_movements(id);
ALTER TABLE return_settlements ADD COLUMN voided_by INTEGER REFERENCES users(id);

CREATE INDEX IF NOT EXISTS idx_invoice_return_items_movement ON invoice_return_items(stock_movement_id);
CREATE INDEX IF NOT EXISTS idx_return_settlements_voided    ON return_settlements(voided_at);
