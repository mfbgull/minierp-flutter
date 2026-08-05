-- Loose item support: items sold by weight/volume where the rupee amount drives quantity.
-- Existing rows become 'packed' with integer quantities — behaviour unchanged.
ALTER TABLE items ADD COLUMN sale_type TEXT NOT NULL DEFAULT 'packed' CHECK(sale_type IN ('packed','loose'));
ALTER TABLE items ADD COLUMN qty_decimal_precision INTEGER NOT NULL DEFAULT 0;
ALTER TABLE items ADD COLUMN rounding_step REAL DEFAULT NULL;
