-- Rollback: Sales table
-- Reverts: add-sales-table.sql

DROP INDEX IF EXISTS idx_sales_customer_id;
DROP INDEX IF EXISTS idx_sales_date;
DROP INDEX IF EXISTS idx_sales_status;
DROP TABLE IF EXISTS sales;
