CREATE TEMP TABLE input_tax_account_guard (valid INTEGER NOT NULL CHECK (valid = 1));
INSERT INTO input_tax_account_guard (valid)
SELECT CASE WHEN EXISTS (
  SELECT 1 FROM chart_of_accounts WHERE code = '1320' AND (
    type <> 'asset' OR normal_balance <> 'debit' OR text_code IS NOT 'recoverable_input_tax' OR is_active <> 1
  )
) OR EXISTS (
  SELECT 1 FROM chart_of_accounts WHERE text_code = 'recoverable_input_tax' AND code <> '1320'
) THEN 0 ELSE 1 END;
DROP TABLE input_tax_account_guard;
INSERT OR IGNORE INTO chart_of_accounts (code, name, type, normal_balance, text_code)
VALUES ('1320', 'Recoverable Input Tax', 'asset', 'debit', 'recoverable_input_tax');

CREATE TABLE supplier_bills (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    supplier_id INTEGER NOT NULL REFERENCES suppliers(id),
    bill_no TEXT NOT NULL,
    bill_date TEXT NOT NULL,
    due_date TEXT,
    description TEXT NOT NULL,
    net_amount REAL NOT NULL CHECK (net_amount > 0),
    input_tax_amount REAL NOT NULL DEFAULT 0 CHECK (input_tax_amount >= 0),
    total_amount REAL NOT NULL CHECK (total_amount > 0),
    created_by INTEGER NOT NULL REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    voided_at TEXT,
    voided_by INTEGER REFERENCES users(id),
    void_reason TEXT
);
CREATE UNIQUE INDEX idx_supplier_bills_active_number ON supplier_bills(supplier_id, bill_no) WHERE voided_at IS NULL;
CREATE INDEX idx_supplier_bills_date ON supplier_bills(bill_date);
CREATE TABLE supplier_bill_allocations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    payment_id INTEGER NOT NULL REFERENCES payments(id),
    bill_id INTEGER NOT NULL REFERENCES supplier_bills(id),
    amount REAL NOT NULL CHECK (amount > 0),
    voided_at TEXT,
    UNIQUE (payment_id, bill_id)
);
CREATE INDEX idx_supplier_bill_allocations_bill ON supplier_bill_allocations(bill_id);
