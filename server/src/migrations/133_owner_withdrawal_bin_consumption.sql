-- PR49 cross-review fix: a voided goods owner-withdrawal must restore the bins
-- that withdrawal actually drained, not the warehouse DEFAULT bin.
--
-- Before this table the withdrawal kept only `quantity` per line and one
-- `stock_movements` row per batch, so a void could not tell which BIN the units
-- came from. `restoreConsumption` therefore fell back to the DEFAULT bin
-- whenever the batch lived elsewhere. Reproduced: batch stocked 10 in a named
-- bin, withdraw 4, void -> batch total 10, DEFAULT bin 4, source bin 6. The 4
-- restored units sat in a bin that never held them, so selling from the source
-- bin under-reported stock and selling against DEFAULT fabricated 4 units.
--
-- This ledger records the exact per-bin draw of every goods withdrawal, in the
-- same shape as invoice_item_bin_consumption (migration 131). The void reads it
-- back and returns each quantity to the bin that lost it. Rows are deleted when
-- the withdrawal is voided, so the ledger only ever describes live withdrawals.
--
-- No backfill: a historical withdrawal recorded no draw, and its bin cannot be
-- reconstructed. The void keeps the previous DEFAULT-bin fallback when no row
-- exists, so old documents still reverse.
CREATE TABLE IF NOT EXISTS owner_withdrawal_bin_consumption (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    withdrawal_id INTEGER NOT NULL REFERENCES owner_withdrawals(id) ON DELETE CASCADE,
    batch_id INTEGER NOT NULL REFERENCES stock_batches(id),
    location_id INTEGER NOT NULL REFERENCES locations(id),
    quantity DECIMAL(15,3) NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_ow_bin_consumption_withdrawal
    ON owner_withdrawal_bin_consumption(withdrawal_id);
