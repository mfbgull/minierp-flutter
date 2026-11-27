-- D30 — Settle overhead (Gull, 2026-11-27)
--
-- Production capitalises the overhead typed into a run into the stock
-- batches and credits 2200 Accrued Production Overhead. Nothing debited
-- 2200, so the liability grew forever even though the bill is always paid.
--
-- This table holds the payment documents that clear it. Each row is one
-- settlement and carries the split Gull chose (Q3 answer B):
--   accrued_amount -> Dr 2200, the part that clears the liability
--   excess_amount  -> Dr 6000, the part above the estimate, booked as a
--                     normal expense (the cost is already inside the item's
--                     stock value, so only the excess is a new expense)
-- The whole amount_paid leaves Cash/Bank.
--
-- Idempotent: safe to re-run on every server start.

CREATE TABLE IF NOT EXISTS overhead_settlements (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    settlement_no VARCHAR(50) NOT NULL UNIQUE,
    settlement_date DATE NOT NULL,
    amount_paid DECIMAL(15,2) NOT NULL CHECK (amount_paid > 0),
    accrued_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
    excess_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
    payment_method VARCHAR(50) NOT NULL,
    reference_note VARCHAR(200),
    created_by INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (created_by) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_overhead_settlements_date
    ON overhead_settlements (settlement_date);
