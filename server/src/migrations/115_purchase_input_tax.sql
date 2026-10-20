ALTER TABLE purchases ADD COLUMN input_tax_amount REAL NOT NULL DEFAULT 0 CHECK (input_tax_amount >= 0);
ALTER TABLE purchase_returns ADD COLUMN input_tax_amount REAL NOT NULL DEFAULT 0 CHECK (input_tax_amount >= 0);
ALTER TABLE purchase_return_items ADD COLUMN input_tax_amount REAL NOT NULL DEFAULT 0 CHECK (input_tax_amount >= 0);

CREATE TABLE purchase_submission_items (
  root_purchase_id INTEGER NOT NULL REFERENCES purchases(id),
  purchase_id INTEGER NOT NULL UNIQUE REFERENCES purchases(id),
  line_index INTEGER NOT NULL CHECK (line_index >= 0),
  PRIMARY KEY (root_purchase_id, line_index)
);

CREATE VIEW direct_purchase_payables AS
SELECT p.id, ROUND(p.total_cost + p.input_tax_amount, 2) AS total_payable,
  COALESCE((SELECT SUM(r.total_amount) FROM purchase_returns r
    WHERE r.source_type = 'PURCHASE' AND r.source_id = p.id AND r.status = 'POSTED'), 0) AS returned_amount,
  COALESCE((SELECT SUM(a.amount) FROM purchase_allocations a
    WHERE a.purchase_id = p.id AND a.voided_at IS NULL), 0) AS paid_amount
FROM purchases p;

CREATE VIEW purchase_order_payables AS
SELECT po.id, po.total_amount AS total_payable,
  COALESCE((SELECT SUM(r.total_amount) FROM purchase_returns r
    WHERE r.source_type = 'PURCHASE_ORDER' AND r.source_id = po.id AND r.status = 'POSTED'), 0) AS returned_amount,
  COALESCE((SELECT SUM(a.amount) FROM po_allocations a
    WHERE a.po_id = po.id AND a.voided_at IS NULL), 0) AS paid_amount
FROM purchase_orders po;
