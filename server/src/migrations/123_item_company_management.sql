ALTER TABLE item_companies ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1
  CHECK (is_active IN (0, 1));

ALTER TABLE items ADD COLUMN company_id INTEGER REFERENCES item_companies(id);
CREATE INDEX idx_items_company_id ON items(company_id);

INSERT INTO item_companies (company_name)
SELECT MIN(TRIM(manufacturer_name))
FROM items
WHERE manufacturer_name IS NOT NULL AND TRIM(manufacturer_name) <> ''
GROUP BY TRIM(manufacturer_name) COLLATE NOCASE
ON CONFLICT(company_name) DO NOTHING;

UPDATE items
SET company_id = (
  SELECT id FROM item_companies
  WHERE company_name = TRIM(items.manufacturer_name) COLLATE NOCASE
)
WHERE manufacturer_name IS NOT NULL AND TRIM(manufacturer_name) <> '';

CREATE TABLE item_company_suppliers (
  company_id INTEGER NOT NULL REFERENCES item_companies(id) ON DELETE CASCADE,
  supplier_id INTEGER NOT NULL REFERENCES suppliers(id),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (company_id, supplier_id)
);
CREATE INDEX idx_item_company_suppliers_supplier_id
  ON item_company_suppliers(supplier_id);
