-- Migration: soft-delete columns for invoices (audit-remediation task 5.1 / AUD-06)
ALTER TABLE invoices ADD COLUMN deleted_at TEXT;
ALTER TABLE invoices ADD COLUMN deleted_by INTEGER;
