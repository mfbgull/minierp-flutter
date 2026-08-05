-- Rollback: Item locations
-- Reverts: add-item-locations.sql

DROP INDEX IF EXISTS idx_item_locations_item;
DROP INDEX IF EXISTS idx_item_locations_warehouse;
DROP TABLE IF EXISTS item_locations;
