-- Add credit_balance column to customers table
-- Tracks refunds/credits not yet applied or paid out to the customer
-- When a return is processed with 'credit' disposition, the returned amount
-- is added here instead of refunding cash.
ALTER TABLE customers ADD COLUMN credit_balance DECIMAL(15,2) NOT NULL DEFAULT 0;
