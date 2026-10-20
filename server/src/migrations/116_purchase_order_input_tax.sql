ALTER TABLE purchase_order_items ADD COLUMN input_tax_amount REAL NOT NULL DEFAULT 0 CHECK (input_tax_amount >= 0);
ALTER TABLE goods_receipt_items ADD COLUMN input_tax_amount REAL NOT NULL DEFAULT 0 CHECK (input_tax_amount >= 0);
