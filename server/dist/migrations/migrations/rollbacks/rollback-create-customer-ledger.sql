-- Rollback: Customer ledger table
-- Reverts: create-customer-ledger.sql

DROP INDEX IF EXISTS idx_customer_ledger_reference;
DROP INDEX IF EXISTS idx_customer_ledger_type;
DROP INDEX IF EXISTS idx_customer_ledger_date;
DROP INDEX IF EXISTS idx_customer_ledger_customer;
DROP TABLE IF EXISTS customer_ledger;
