-- Migration: soft-delete columns for customers and items (SHORTCOMINGS-FIX 4.2)
-- Adds deleted_at / deleted_by so DELETE sets a timestamp instead of
-- removing the row, and a restore endpoint can revert it.
ALTER TABLE customers ADD COLUMN deleted_at TEXT;
ALTER TABLE customers ADD COLUMN deleted_by INTEGER;
ALTER TABLE items ADD COLUMN deleted_at TEXT;
ALTER TABLE items ADD COLUMN deleted_by INTEGER;
