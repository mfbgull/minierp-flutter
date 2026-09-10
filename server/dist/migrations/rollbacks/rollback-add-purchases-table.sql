-- Rollback: Purchases table
-- Reverts: add-purchases-table.sql

DROP INDEX IF EXISTS idx_purchases_supplier_id;
DROP INDEX IF EXISTS idx_purchases_date;
DROP INDEX IF EXISTS idx_purchases_status;
DROP TABLE IF EXISTS purchases;
DROP TABLE IF EXISTS purchase_items;
