-- Rollback: Missing FK indexes
-- Reverts: add-missing-fk-indexes.sql

DROP INDEX IF EXISTS idx_invoices_so_id;
DROP INDEX IF EXISTS idx_invoices_customer_id;
DROP INDEX IF EXISTS idx_payments_customer_id;
DROP INDEX IF EXISTS idx_payments_invoice_id;
