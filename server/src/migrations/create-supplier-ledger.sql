-- Migration: Create supplier ledger table
-- This table tracks all supplier transactions (purchase orders, receipts, adjustments) for AP tracking

CREATE TABLE IF NOT EXISTS supplier_ledger (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    supplier_id INTEGER NOT NULL,
    transaction_date DATE NOT NULL,
    transaction_type VARCHAR(50), -- PURCHASE_ORDER, RECEIPT, PAYMENT, ADJUSTMENT, OPENING_BALANCE
    reference_no VARCHAR(100),
    debit DECIMAL(15,2) DEFAULT 0,
    credit DECIMAL(15,2) DEFAULT 0,
    balance DECIMAL(15,2) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (supplier_id) REFERENCES suppliers(id)
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_supplier_ledger_supplier ON supplier_ledger(supplier_id);
CREATE INDEX IF NOT EXISTS idx_supplier_ledger_date ON supplier_ledger(transaction_date);
CREATE INDEX IF NOT EXISTS idx_supplier_ledger_type ON supplier_ledger(transaction_type);
CREATE INDEX IF NOT EXISTS idx_supplier_ledger_reference ON supplier_ledger(reference_no);
