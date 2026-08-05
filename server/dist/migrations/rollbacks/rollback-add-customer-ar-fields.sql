-- Rollback: Customer AR fields
-- Reverts: add-customer-ar-fields.sql

ALTER TABLE customers DROP COLUMN IF EXISTS credit_limit;
ALTER TABLE customers DROP COLUMN IF EXISTS current_balance;
ALTER TABLE customers DROP COLUMN IF EXISTS opening_balance;
ALTER TABLE customers DROP COLUMN IF EXISTS payment_terms_days;
