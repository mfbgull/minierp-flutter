-- Add returned_quantity column to purchases table
-- Tracks the cumulative quantity returned against a direct purchase
ALTER TABLE purchases ADD COLUMN returned_quantity DECIMAL(15,3) NOT NULL DEFAULT 0;

-- Add returned_quantity column to purchase_order_items table
-- Tracks the cumulative quantity returned against a PO line item
ALTER TABLE purchase_order_items ADD COLUMN returned_quantity DECIMAL(15,3) NOT NULL DEFAULT 0;

-- Index for efficient querying of returns
CREATE INDEX IF NOT EXISTS idx_purchases_returned_quantity ON purchases(returned_quantity);
CREATE INDEX IF NOT EXISTS idx_po_items_returned_quantity ON purchase_order_items(returned_quantity);

-- Index for finding return-related stock movements efficiently
CREATE INDEX IF NOT EXISTS idx_stock_movements_return_ref ON stock_movements(reference_doctype, reference_docno);
