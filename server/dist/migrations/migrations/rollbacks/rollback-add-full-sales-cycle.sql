-- Rollback: Full sales cycle
-- Reverts: add-full-sales-cycle.sql

DROP INDEX IF EXISTS idx_sales_orders_status;
DROP INDEX IF EXISTS idx_sales_orders_customer;
DROP INDEX IF EXISTS idx_quotation_items_quotation;
DROP INDEX IF EXISTS idx_quotations_customer;
DROP INDEX IF EXISTS idx_quotations_status;

ALTER TABLE invoices DROP COLUMN IF EXISTS source_type;
ALTER TABLE invoices DROP COLUMN IF EXISTS quotation_id;
ALTER TABLE invoices DROP COLUMN IF EXISTS customer_name;

ALTER TABLE sales_orders DROP COLUMN IF EXISTS source_type;
ALTER TABLE sales_orders DROP COLUMN IF EXISTS source_id;
ALTER TABLE sales_orders DROP COLUMN IF EXISTS customer_name;

DROP TABLE IF EXISTS quotation_items;
DROP TABLE IF EXISTS quotations;
