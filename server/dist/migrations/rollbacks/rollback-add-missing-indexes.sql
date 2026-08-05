-- Rollback: Missing indexes
-- Reverts: add-missing-indexes.sql

DROP INDEX IF EXISTS idx_payment_allocations_payment;
DROP INDEX IF EXISTS idx_payment_allocations_invoice;
DROP INDEX IF EXISTS idx_customer_ledger_reference;
DROP INDEX IF EXISTS idx_supplier_ledger_supplier;
