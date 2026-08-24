-- Migration: Add supplier payment support
-- Adds supplier_id to payments, creates po_allocations table, and makes
-- customer_id nullable so outgoing supplier payments can be recorded.

-- Add supplier_id to payments (nullable, for outgoing supplier payments)
ALTER TABLE payments ADD COLUMN supplier_id INTEGER REFERENCES suppliers(id);

-- Create PO allocations table for supplier payment allocations
CREATE TABLE IF NOT EXISTS po_allocations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    payment_id INTEGER NOT NULL,
    po_id INTEGER NOT NULL,
    amount DECIMAL(15,2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (payment_id) REFERENCES payments(id) ON DELETE CASCADE,
    FOREIGN KEY (po_id) REFERENCES purchase_orders(id)
);

-- NOTE: payments table rebuild moved to fn.runPaymentsCustomerNullableRebuild
-- (ledger step; preserves invoice_id and restores foreign_keys in finally).

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_po_allocations_payment ON po_allocations(payment_id);
CREATE INDEX IF NOT EXISTS idx_po_allocations_po ON po_allocations(po_id);
