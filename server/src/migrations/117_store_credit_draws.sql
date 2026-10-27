-- Source ownership for new store-credit applications. Do not infer or rewrite
-- historical financial allocations whose provenance was never recorded.
CREATE TABLE store_credit_draws (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  settlement_id INTEGER NOT NULL REFERENCES return_settlements(id),
  invoice_id INTEGER NOT NULL REFERENCES invoices(id),
  amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (settlement_id, invoice_id)
);
CREATE INDEX idx_store_credit_draw_invoice ON store_credit_draws(invoice_id);
