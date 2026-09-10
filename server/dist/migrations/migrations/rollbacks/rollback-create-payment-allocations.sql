-- Rollback: Payment allocations table
-- Reverts: create-payment-allocations.sql

DROP INDEX IF EXISTS idx_payment_allocations_invoice;
DROP INDEX IF EXISTS idx_payment_allocations_payment;
DROP TABLE IF EXISTS payment_allocations;
