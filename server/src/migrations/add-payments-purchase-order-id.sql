-- Migration: Add purchase_order_id to payments
-- Denormalized link so PO-level payment reporting can join directly on
-- payments.purchase_order_id. createSupplierPayment sets it for single-PO
-- supplier payments; multi-PO / mixed payments leave it NULL (po_allocations
-- stays authoritative for those).
ALTER TABLE payments ADD COLUMN purchase_order_id INTEGER REFERENCES purchase_orders(id);

CREATE INDEX IF NOT EXISTS idx_payments_purchase_order_id ON payments(purchase_order_id);
