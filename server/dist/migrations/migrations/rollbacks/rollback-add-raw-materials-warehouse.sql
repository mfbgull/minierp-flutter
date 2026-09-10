-- Rollback: Raw materials warehouse
-- Reverts: add-raw-materials-warehouse.sql

DROP INDEX IF EXISTS idx_productions_raw_materials_warehouse;
ALTER TABLE productions DROP COLUMN IF EXISTS raw_materials_warehouse_id;
