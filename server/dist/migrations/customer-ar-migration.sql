-- Main Migration Script for Customer AR Module
-- This script applies all customer AR related migrations in the correct order

-- First, add the new fields to existing customers table
ALTER TABLE customers ADD COLUMN credit_limit DECIMAL(15,2) DEFAULT 0;
ALTER TABLE customers ADD COLUMN current_balance DECIMAL(15,2) DEFAULT 0;
ALTER TABLE customers ADD COLUMN opening_balance DECIMAL(15,2) DEFAULT 0;
ALTER TABLE customers ADD COLUMN payment_terms_days INTEGER DEFAULT 14;

-- Create the customer ledger table
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

-- Create the payment allocations table
CREATE TABLE IF NOT EXISTS payment_allocations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    payment_id INTEGER NOT NULL,
    invoice_id INTEGER NOT NULL,
    amount DECIMAL(15,2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (payment_id) REFERENCES payments(id) ON DELETE CASCADE,
    FOREIGN KEY (invoice_id) REFERENCES invoices(id)
);

-- Ensure invoices table has proper defaults and update existing records
UPDATE invoices SET paid_amount = 0 WHERE paid_amount IS NULL;
UPDATE invoices SET balance_amount = total_amount WHERE balance_amount IS NULL;
UPDATE invoices SET balance_amount = total_amount WHERE balance_amount = 0 AND total_amount > 0;

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_customer_ledger_customer ON customer_ledger(customer_id);
CREATE INDEX IF NOT EXISTS idx_customer_ledger_date ON customer_ledger(transaction_date);
CREATE INDEX IF NOT EXISTS idx_customer_ledger_type ON customer_ledger(transaction_type);
CREATE INDEX IF NOT EXISTS idx_customer_ledger_reference ON customer_ledger(reference_no);

CREATE INDEX IF NOT EXISTS idx_payment_allocations_payment ON payment_allocations(payment_id);
CREATE INDEX IF NOT EXISTS idx_payment_allocations_invoice ON payment_allocations(invoice_id);

-- Update customer current balances based on existing invoices
-- This ensures existing customers have correct AR balances
UPDATE customers SET current_balance = (
    SELECT COALESCE(SUM(balance_amount), 0) 
    FROM invoices 
    WHERE invoices.customer_id = customers.id 
    AND invoices.status IN ('Unpaid', 'Partially Paid', 'Overdue')
);