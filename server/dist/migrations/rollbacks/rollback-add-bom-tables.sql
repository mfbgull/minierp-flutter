-- Rollback: BOM tables
-- Reverts: add-bom-tables.sql

DROP INDEX IF EXISTS idx_bom_items_bom;
DROP INDEX IF EXISTS idx_bom_items_item;
DROP INDEX IF EXISTS idx_boms_item;
DROP INDEX IF EXISTS idx_boms_is_active;

DROP TABLE IF EXISTS bom_items;
DROP TABLE IF EXISTS boms;
