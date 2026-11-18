-- S-1 decision B: one reservation may cover MULTIPLE bins.
--
-- stock_reservations kept a single (batch_id, location_id) pair, so a
-- reservation could only ever name one bin. Gull's decision: a reservation
-- may allocate its quantity across several bins, while the invoice line still
-- carries ONE durable reservation_id.
--
-- This child table holds one row per (reservation, bin) allocation. The
-- parent's batch_id/location_id stay for the single-bin legacy shape and are
-- NULL for a multi-bin reservation. quantity_reserved on the parent is the
-- total across children.
--
-- No backfill of existing rows: a single-bin reservation keeps working from
-- its parent columns; the code writes a child row lazily on consume/release
-- when one is missing, so historical rows need no rewrite at migration time.

CREATE TABLE IF NOT EXISTS stock_reservation_bins (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    reservation_id INTEGER NOT NULL REFERENCES stock_reservations(id) ON DELETE CASCADE,
    batch_id INTEGER NOT NULL REFERENCES stock_batches(id),
    location_id INTEGER NOT NULL REFERENCES locations(id),
    quantity_reserved DECIMAL(15,3) NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_reservation_bins_res ON stock_reservation_bins(reservation_id);
CREATE INDEX IF NOT EXISTS idx_reservation_bins_bin ON stock_reservation_bins(batch_id, location_id);
