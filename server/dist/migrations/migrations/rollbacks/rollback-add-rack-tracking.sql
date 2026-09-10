-- Rollback: Rack tracking
-- Reverts: add-rack-tracking.sql

ALTER TABLE stock_balances DROP COLUMN IF EXISTS rack_location;
ALTER TABLE stock_movements DROP COLUMN IF EXISTS rack_location;
