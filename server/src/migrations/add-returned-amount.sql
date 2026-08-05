-- Add returned_amount column to invoices table
-- Tracks the total value of items returned against an invoice
ALTER TABLE invoices ADD COLUMN returned_amount DECIMAL(15,2) NOT NULL DEFAULT 0;
