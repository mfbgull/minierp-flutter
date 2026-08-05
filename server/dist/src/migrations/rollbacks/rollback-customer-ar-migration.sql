-- Rollback: Customer AR module (composite migration)
-- Reverts: customer-ar-migration.sql
-- Note: This is a composite migration. Individual components have separate rollbacks.

DROP INDEX IF EXISTS idx_payment_allocations_invoice;
DROP INDEX IF EXISTS idx_payment_allocations_payment;
DROP INDEX IF EXISTS idx_customer_ledger_reference;
DROP INDEX IF EXISTS idx_customer_ledger_type;
DROP INDEX IF EXISTS idx_customer_ledger_date;
DROP INDEX IF EXISTS idx_customer_ledger_customer;

DROP TABLE IF EXISTS payment_allocations;
DROP TABLE IF EXISTS customer_ledger;

ALTER TABLE customers DROP COLUMN IF EXISTS credit_limit;
ALTER TABLE customers DROP COLUMN IF EXISTS current_balance;
ALTER TABLE customers DROP COLUMN IF EXISTS opening_balance;
ALTER TABLE customers DROP COLUMN IF EXISTS payment_terms_days;
