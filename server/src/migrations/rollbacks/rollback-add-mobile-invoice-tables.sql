-- Rollback: Mobile invoice tables
-- Reverts: add-mobile-invoice-tables.sql

DROP INDEX IF EXISTS idx_tax_rates_is_active;
DROP INDEX IF EXISTS idx_mobile_invoices_customer;
DROP INDEX IF EXISTS idx_mobile_invoices_date;
DROP INDEX IF EXISTS idx_mobile_invoice_items_invoice;

DROP TABLE IF EXISTS mobile_invoice_items;
DROP TABLE IF EXISTS mobile_invoices;
DROP TABLE IF EXISTS tax_rates;
