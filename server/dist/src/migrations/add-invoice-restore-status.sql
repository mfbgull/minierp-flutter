-- Migration: preserve the invoice's pre-delete status so the restore
-- endpoint (undo pattern, SHORTCOMINGS-FIX 4.2/4.4) can bring the
-- invoice back exactly as it was before the soft-delete.
ALTER TABLE invoices ADD COLUMN deleted_from_status TEXT;