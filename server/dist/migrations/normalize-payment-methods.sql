-- Migration: normalize payment methods (financial-audit-p0-remediation task 1.4 / CASH-02)
-- Blank/NULL payment methods default to 'Cash'; column becomes NOT NULL so
-- unclassified values can never re-enter the cash math silently.

UPDATE payments SET payment_method = 'Cash' WHERE payment_method IS NULL OR TRIM(payment_method) = '';
UPDATE expenses SET payment_method = 'Cash' WHERE payment_method IS NULL OR TRIM(payment_method) = '';

-- Enforce NOT NULL DEFAULT 'Cash' on payments.payment_method. SQLite cannot
-- ALTER a column to NOT NULL in place, so rebuild the table from its live
-- column list (the audit-remediation pattern: never hand-maintain a copy
-- list). The CHECK-free rebuild keeps every constraint/index re-created.
CREATE TABLE payments_nn (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  payment_no VARCHAR(50) UNIQUE NOT NULL,
  customer_id INTEGER,
  supplier_id INTEGER REFERENCES suppliers(id),
  invoice_id INTEGER,
  payment_date DATE NOT NULL,
  amount DECIMAL(15,2) NOT NULL,
  payment_method VARCHAR(50) NOT NULL DEFAULT 'Cash',
  reference_no VARCHAR(100),
  notes TEXT,
  purchase_order_id INTEGER REFERENCES purchase_orders(id),
  created_by INTEGER,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (customer_id) REFERENCES customers(id),
  FOREIGN KEY (supplier_id) REFERENCES suppliers(id),
  FOREIGN KEY (invoice_id) REFERENCES invoices(id),
  FOREIGN KEY (purchase_order_id) REFERENCES purchase_orders(id),
  FOREIGN KEY (created_by) REFERENCES users(id)
);
INSERT INTO payments_nn (id, payment_no, customer_id, supplier_id, invoice_id, payment_date, amount, payment_method, reference_no, notes, purchase_order_id, created_by, created_at)
  SELECT id, payment_no, customer_id, supplier_id, invoice_id, payment_date, amount, payment_method, reference_no, notes, purchase_order_id, created_by, created_at FROM payments;
DROP TABLE payments;
ALTER TABLE payments_nn RENAME TO payments;
CREATE INDEX IF NOT EXISTS idx_payments_customer_id ON payments(customer_id);
CREATE INDEX IF NOT EXISTS idx_payments_supplier_id ON payments(supplier_id);
CREATE INDEX IF NOT EXISTS idx_payments_date ON payments(payment_date);
CREATE INDEX IF NOT EXISTS idx_payments_purchase_order_id ON payments(purchase_order_id);
