-- Migration: purchase supplier + payment support
-- Adds a nullable supplier_id FK to purchases (so direct purchases can be
-- tied to a supplier record and participate in supplier payments) and
-- creates purchase_allocations — the direct-purchase analogue of
-- po_allocations — so supplier payments can be allocated against a
-- purchase (or several) the same way they are against POs.

ALTER TABLE purchases ADD COLUMN supplier_id INTEGER REFERENCES suppliers(id);

CREATE TABLE IF NOT EXISTS purchase_allocations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    payment_id INTEGER NOT NULL,
    purchase_id INTEGER NOT NULL,
    amount DECIMAL(15,2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (payment_id) REFERENCES payments(id) ON DELETE CASCADE,
    FOREIGN KEY (purchase_id) REFERENCES purchases(id)
);

CREATE INDEX IF NOT EXISTS idx_purchase_allocations_payment ON purchase_allocations(payment_id);
CREATE INDEX IF NOT EXISTS idx_purchase_allocations_purchase ON purchase_allocations(purchase_id);
CREATE INDEX IF NOT EXISTS idx_purchases_supplier_id ON purchases(supplier_id);
