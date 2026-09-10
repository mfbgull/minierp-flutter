-- Migration: Add Accounts Receivable fields to customers table
-- This migration adds fields needed for customer credit management and AR tracking

-- Add credit management fields to customers table
ALTER TABLE customers ADD COLUMN credit_limit DECIMAL(15,2) DEFAULT 0;
ALTER TABLE customers ADD COLUMN current_balance DECIMAL(15,2) DEFAULT 0;
ALTER TABLE customers ADD COLUMN opening_balance DECIMAL(15,2) DEFAULT 0;
ALTER TABLE customers ADD COLUMN payment_terms_days INTEGER DEFAULT 14;

-- Verify that invoice fields are properly initialized (if not already set)
-- Ensure invoices table has proper defaults for paid_amount and balance_amount
UPDATE invoices SET paid_amount = 0 WHERE paid_amount IS NULL;
UPDATE invoices SET balance_amount = total_amount WHERE balance_amount IS NULL;

-- Update existing invoices to have proper balance_amount if it's 0 but total_amount exists
UPDATE invoices SET balance_amount = total_amount WHERE balance_amount = 0 AND total_amount > 0;