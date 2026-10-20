CREATE TEMP TABLE supplier_advance_account_guard (valid INTEGER NOT NULL CHECK (valid = 1));
INSERT INTO supplier_advance_account_guard (valid)
SELECT CASE WHEN EXISTS (
  SELECT 1 FROM chart_of_accounts WHERE code = '1330' AND (
    type <> 'asset' OR normal_balance <> 'debit' OR text_code IS NOT 'supplier_prepayments' OR is_active <> 1
  )
) OR EXISTS (
  SELECT 1 FROM chart_of_accounts WHERE text_code = 'supplier_prepayments' AND code <> '1330'
) THEN 0 ELSE 1 END;
DROP TABLE supplier_advance_account_guard;
INSERT OR IGNORE INTO chart_of_accounts (code, name, type, normal_balance, text_code)
VALUES ('1330', 'Supplier Prepayments', 'asset', 'debit', 'supplier_prepayments');

CREATE TABLE supplier_prepayments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    supplier_id INTEGER NOT NULL REFERENCES suppliers(id),
    prepay_date TEXT NOT NULL,
    amount REAL NOT NULL CHECK (amount > 0),
    payment_method TEXT NOT NULL,
    reference_no TEXT,
    notes TEXT,
    created_by INTEGER NOT NULL REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    voided_at TEXT,
    voided_by INTEGER REFERENCES users(id),
    void_reason TEXT
);
CREATE INDEX idx_supplier_prepayments_supplier ON supplier_prepayments(supplier_id);
CREATE INDEX idx_supplier_prepayments_date ON supplier_prepayments(prepay_date);
CREATE TABLE supplier_prepayment_applications (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    prepayment_id INTEGER NOT NULL REFERENCES supplier_prepayments(id),
    payment_id INTEGER NOT NULL UNIQUE REFERENCES payments(id),
    amount REAL NOT NULL CHECK (amount > 0),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_supplier_prepayment_applications_source ON supplier_prepayment_applications(prepayment_id);
