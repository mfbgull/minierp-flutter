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

-- Rebuild payments with nullable customer_id (SQLite can't ALTER a NOT NULL column)
PRAGMA foreign_keys=OFF;
BEGIN TRANSACTION;
CREATE TABLE payments_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    payment_no VARCHAR(50) UNIQUE NOT NULL,
    customer_id INTEGER,
    supplier_id INTEGER REFERENCES suppliers(id),
    invoice_id INTEGER,
    payment_date DATE NOT NULL,
    amount DECIMAL(15,2) NOT NULL,
    payment_method VARCHAR(50),
    reference_no VARCHAR(100),
    notes TEXT,
    created_by INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (customer_id) REFERENCES customers(id),
    FOREIGN KEY (supplier_id) REFERENCES suppliers(id),
    FOREIGN KEY (invoice_id) REFERENCES invoices(id),
    FOREIGN KEY (created_by) REFERENCES users(id)
);
INSERT INTO payments_new (id, payment_no, customer_id, supplier_id, payment_date, amount, payment_method, reference_no, notes, created_by, created_at)
  SELECT id, payment_no, customer_id, supplier_id, payment_date, amount, payment_method, reference_no, notes, created_by, created_at FROM payments;
DROP TABLE payments;
ALTER TABLE payments_new RENAME TO payments;
CREATE INDEX IF NOT EXISTS idx_payments_customer_id ON payments(customer_id);
CREATE INDEX IF NOT EXISTS idx_payments_date ON payments(payment_date);
COMMIT;
PRAGMA foreign_keys=ON;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_po_allocations_payment ON po_allocations(payment_id);
CREATE INDEX IF NOT EXISTS idx_po_allocations_po ON po_allocations(po_id);
