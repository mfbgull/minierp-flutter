-- Migration: Add missing indexes for payment allocations, ledger, and supplier ledger
-- These indexes are critical for financial query performance

-- Payment allocation indexes (heavily queried during invoice balance calculations)
CREATE INDEX IF NOT EXISTS idx_payment_allocations_payment ON payment_allocations(payment_id);
CREATE INDEX IF NOT EXISTS idx_payment_allocations_invoice ON payment_allocations(invoice_id);

-- Customer ledger indexes
CREATE INDEX IF NOT EXISTS idx_customer_ledger_reference ON customer_ledger(reference_no);

-- Supplier ledger indexes
CREATE INDEX IF NOT EXISTS idx_supplier_ledger_supplier ON supplier_ledger(supplier_id);

-- Analyze to update query planner statistics
ANALYZE payment_allocations;
ANALYZE customer_ledger;
ANALYZE supplier_ledger;
