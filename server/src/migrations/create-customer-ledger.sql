-- Migration: Create customer ledger table
-- This table tracks all customer transactions (invoices, payments, adjustments) for AR tracking

CREATE TABLE IF NOT EXISTS customer_ledger (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    customer_id INTEGER NOT NULL,
    transaction_date DATE NOT NULL,
    transaction_type VARCHAR(50), -- INVOICE, PAYMENT, ADJUSTMENT, OPENING_BALANCE
    reference_no VARCHAR(100),
    debit DECIMAL(15,2) DEFAULT 0,
    credit DECIMAL(15,2) DEFAULT 0,
    balance DECIMAL(15,2) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (customer_id) REFERENCES customers(id)
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_customer_ledger_customer ON customer_ledger(customer_id);
CREATE INDEX IF NOT EXISTS idx_customer_ledger_date ON customer_ledger(transaction_date);
CREATE INDEX IF NOT EXISTS idx_customer_ledger_type ON customer_ledger(transaction_type);
CREATE INDEX IF NOT EXISTS idx_customer_ledger_reference ON customer_ledger(reference_no);