-- Store-credit applications to existing invoices. One header per idempotent
-- request; draws link to it and repeat draws for the same (settlement, invoice)
-- pair are allowed, so an invoice may consume the same settlement twice.
CREATE TABLE store_credit_applications (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id INTEGER NOT NULL REFERENCES customers(id),
  application_key TEXT NOT NULL,
  request_hash TEXT NOT NULL,
  operation_date TEXT NOT NULL,
  total_amount DECIMAL(15,2) NOT NULL CHECK (total_amount > 0),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (customer_id, application_key)
);

CREATE TABLE store_credit_draws_new (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  settlement_id INTEGER NOT NULL REFERENCES return_settlements(id),
  invoice_id INTEGER NOT NULL REFERENCES invoices(id),
  application_id INTEGER REFERENCES store_credit_applications(id),
  amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO store_credit_draws_new (id, settlement_id, invoice_id, application_id, amount_minor, created_at)
  SELECT id, settlement_id, invoice_id, NULL, amount_minor, created_at FROM store_credit_draws;
DROP TABLE store_credit_draws;
ALTER TABLE store_credit_draws_new RENAME TO store_credit_draws;
CREATE INDEX idx_store_credit_draw_invoice ON store_credit_draws(invoice_id);
CREATE INDEX idx_store_credit_draw_application ON store_credit_draws(application_id);
