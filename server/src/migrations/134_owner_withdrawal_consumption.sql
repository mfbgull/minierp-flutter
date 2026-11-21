-- Owner-withdrawal edit/void fix: a re-posted withdrawal must be reversed from
-- its ACTIVE consumption, not from its whole movement history.
--
-- Before this table an edit restored stock with compensating inbound movement
-- rows and left the superseded outbound rows in place. The reversal then
-- replayed EVERY outbound row, so the second edit tried to restore 4 + 5 = 9
-- units into a batch of 10 that held 5. The INV-21 CHECK
-- `quantity_remaining <= quantity_original` rejected the UPDATE, the whole
-- transaction rolled back, and PUT returned 500. A void after one edit failed
-- the same way and left the withdrawal posted.
--
-- This ledger records exactly one lot per live consumption of the document:
-- the batch (NULL for the legacy unbatched bucket), the units taken, and the
-- unit cost. Every re-post replaces it; void deletes it. restoreConsumption
-- reads it first and falls back to the movement history only when a document
-- predates this table.
--
-- No backfill: a historical document has no recorded lot, and its active lines
-- cannot be distinguished from superseded ones. Those keep the previous
-- history-based reversal, and draw rows written before this migration keep a
-- NULL consumption_id.
--
-- KNOWN LIMITATIONS (pre-134 documents only; the fallback reads movement
-- history and nothing else):
--   1. A document EDITED before this migration keeps its superseded outbound
--      rows, so the fallback reverses their sum. Void can then add back more
--      than the batch holds and fail INV-21 (HTTP 500). A further edit after
--      the upgrade fails the same way or over-restores.
--   2. A document posted after 133 but before this migration has bin draw rows
--      with a NULL consumption_id. The fallback ignores them and restores to
--      the warehouse DEFAULT bin instead of the named bin that lost the units.
--      Totals stay right, so the void returns 200 with stock in the wrong bin.
-- Accepted 2026-11-21, not repaired: no production deployment predates this
-- migration and the dev database is disposable test data. Documents created or
-- edited under this migration always have a lot, so neither applies to them.
CREATE TABLE IF NOT EXISTS owner_withdrawal_consumption (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    withdrawal_id INTEGER NOT NULL REFERENCES owner_withdrawals(id) ON DELETE CASCADE,
    batch_id INTEGER REFERENCES stock_batches(id),
    item_id INTEGER NOT NULL REFERENCES items(id),
    warehouse_id INTEGER NOT NULL REFERENCES warehouses(id),
    quantity DECIMAL(15,3) NOT NULL,
    unit_cost DECIMAL(15,4),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_ow_consumption_withdrawal
    ON owner_withdrawal_consumption(withdrawal_id);

-- The lot the draw belongs to. Two lines drawing one batch are two lots, each
-- with its own bins; without this the reversal read the batch's whole draw per
-- lot and restored it twice (batch 10, bin 17).
ALTER TABLE owner_withdrawal_bin_consumption
    ADD COLUMN consumption_id INTEGER REFERENCES owner_withdrawal_consumption(id);
