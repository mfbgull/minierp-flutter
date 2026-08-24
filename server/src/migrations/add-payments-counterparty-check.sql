-- Migration: enforce exactly-one-counterparty on payments
-- (financial-audit-p0-remediation task 2.3 / PAY-09).
--
-- Rebuilds `payments` adding CHECK ((customer_id IS NULL) <> (supplier_id IS NULL)).
-- The column list below mirrors the end state of the programmatic
-- customer_id-nullable rebuild in config/database.ts. Live data is clean
-- (every row has exactly one counterparty). foreign_keys MUST be OFF for the DROP:
-- with it ON, dropping `payments` cascades po_allocations/payment_allocations
-- (the exact PAY-06 class of data loss this change exists to prevent).
--
-- The ledgered runner wraps SQL-file migrations in a transaction; PRAGMA
-- foreign_keys is a no-op inside one, so the runner's { noTxn: true } option
-- is what makes the OFF/ON effective. See config/database.ts registration.

CREATE TABLE payments_xor (
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
    CHECK ((customer_id IS NULL) <> (supplier_id IS NULL)),
    FOREIGN KEY (customer_id) REFERENCES customers(id),
    FOREIGN KEY (supplier_id) REFERENCES suppliers(id),
    FOREIGN KEY (invoice_id) REFERENCES invoices(id),
    FOREIGN KEY (purchase_order_id) REFERENCES purchase_orders(id),
    FOREIGN KEY (created_by) REFERENCES users(id)
);

INSERT INTO payments_xor (id, payment_no, customer_id, supplier_id, invoice_id, payment_date, amount, payment_method, reference_no, notes, purchase_order_id, created_by, created_at)
  SELECT id, payment_no, customer_id, supplier_id, invoice_id, payment_date, amount, payment_method, reference_no, notes, purchase_order_id, created_by, created_at FROM payments;

DROP TABLE payments;
ALTER TABLE payments_xor RENAME TO payments;

CREATE INDEX IF NOT EXISTS idx_payments_customer_id ON payments(customer_id);
CREATE INDEX IF NOT EXISTS idx_payments_supplier_id ON payments(supplier_id);
CREATE INDEX IF NOT EXISTS idx_payments_date ON payments(payment_date);
CREATE INDEX IF NOT EXISTS idx_payments_purchase_order_id ON payments(purchase_order_id);
