-- Add credit_offset column to invoices table
-- Persists the customer credit applied to this invoice so balance
-- recalculation (calculateInvoiceBalance) includes it correctly.

ALTER TABLE invoices ADD COLUMN credit_offset DECIMAL(15,2) NOT NULL DEFAULT 0;
