-- S-1 fix (GLM re-review HIGH): a void must restore the bins THAT invoice line
-- drained, not the reservation's whole original allocation.
--
-- Before this table, invoice_items carried only a total `quantity`. When one
-- reservation backed several invoices (e.g. sell 4 from b1, then 2 from b2),
-- voiding the second invoice could not tell which bins it had taken, so the
-- reopen restored the reservation's full original allocation and
-- over-reserved - or hit a 409 when the other bin no longer had the physical
-- stock to reserve.
--
-- This ledger records the exact per-bin draw of every invoice line that
-- consumed a reservation. A void reads it back and reverses precisely those
-- amounts. Rows are deleted when the invoice line is voided, so the ledger
-- only ever describes live sales.
--
-- No backfill: historical invoice lines predate the S-1 reservation link, so
-- they have no reservation-backed bin draw to reconstruct. The void path
-- falls back to the previous quantity-based reopen when no row exists.
CREATE TABLE IF NOT EXISTS invoice_item_bin_consumption (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    invoice_item_id INTEGER NOT NULL REFERENCES invoice_items(id) ON DELETE CASCADE,
    batch_id INTEGER NOT NULL REFERENCES stock_batches(id),
    location_id INTEGER NOT NULL REFERENCES locations(id),
    quantity DECIMAL(15,3) NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_invoice_item_bin_consumption_item ON invoice_item_bin_consumption(invoice_item_id);
