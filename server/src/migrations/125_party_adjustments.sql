CREATE TABLE parties (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  display_name TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE customers ADD COLUMN party_id INTEGER REFERENCES parties(id);
ALTER TABLE suppliers ADD COLUMN party_id INTEGER REFERENCES parties(id);
ALTER TABLE invoices ADD COLUMN adjusted_amount REAL NOT NULL DEFAULT 0;
INSERT INTO parties (id, display_name) SELECT id, customer_name FROM customers;
UPDATE customers SET party_id = id;
INSERT INTO parties (id, display_name)
SELECT id + COALESCE((SELECT MAX(id) FROM customers), 0), supplier_name FROM suppliers;
UPDATE suppliers SET party_id = id + COALESCE((SELECT MAX(id) FROM customers), 0);
CREATE UNIQUE INDEX customers_party_id ON customers(party_id);
CREATE UNIQUE INDEX suppliers_party_id ON suppliers(party_id);
CREATE TRIGGER customers_create_party AFTER INSERT ON customers WHEN NEW.party_id IS NULL BEGIN
  INSERT INTO parties(display_name) VALUES (NEW.customer_name);
  UPDATE customers SET party_id = last_insert_rowid() WHERE id = NEW.id;
END;
CREATE TRIGGER suppliers_create_party AFTER INSERT ON suppliers WHEN NEW.party_id IS NULL BEGIN
  INSERT INTO parties(display_name) VALUES (NEW.supplier_name);
  UPDATE suppliers SET party_id = last_insert_rowid() WHERE id = NEW.id;
END;
CREATE TABLE party_identity_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  party_id INTEGER NOT NULL REFERENCES parties(id),
  customer_id INTEGER REFERENCES customers(id),
  supplier_id INTEGER REFERENCES suppliers(id),
  action TEXT NOT NULL,
  previous_party_id INTEGER REFERENCES parties(id),
  created_by INTEGER NOT NULL REFERENCES users(id),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX party_identity_events_party ON party_identity_events(party_id, id);
CREATE TABLE party_adjustments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  adjustment_no TEXT NOT NULL UNIQUE,
  party_id INTEGER NOT NULL REFERENCES parties(id),
  customer_id INTEGER NOT NULL REFERENCES customers(id),
  supplier_id INTEGER NOT NULL REFERENCES suppliers(id),
  adjustment_date TEXT NOT NULL,
  amount REAL NOT NULL CHECK(amount > 0),
  notes TEXT,
  status TEXT NOT NULL DEFAULT 'posted' CHECK(status IN ('posted', 'reversed')),
  created_by INTEGER NOT NULL REFERENCES users(id),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  reversed_by INTEGER REFERENCES users(id),
  reversed_at TEXT,
  reversal_date TEXT,
  reversal_reason TEXT,
  CHECK((status = 'posted' AND reversal_date IS NULL) OR
        (status = 'reversed' AND reversal_date IS NOT NULL AND reversed_by IS NOT NULL))
);
CREATE INDEX party_adjustments_party_date ON party_adjustments(party_id, adjustment_date, id);
CREATE INDEX party_adjustments_status_date ON party_adjustments(status, adjustment_date);
CREATE TABLE party_adjustment_receivables (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  adjustment_id INTEGER NOT NULL REFERENCES party_adjustments(id),
  invoice_id INTEGER NOT NULL REFERENCES invoices(id),
  amount REAL NOT NULL CHECK(amount > 0),
  UNIQUE(adjustment_id, invoice_id)
);
CREATE INDEX party_adjustment_receivables_invoice ON party_adjustment_receivables(invoice_id, adjustment_id);
CREATE TABLE party_adjustment_payables (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  adjustment_id INTEGER NOT NULL REFERENCES party_adjustments(id),
  purchase_id INTEGER REFERENCES purchases(id),
  purchase_order_id INTEGER REFERENCES purchase_orders(id),
  bill_id INTEGER REFERENCES supplier_bills(id),
  amount REAL NOT NULL CHECK(amount > 0),
  CHECK((purchase_id IS NOT NULL) + (purchase_order_id IS NOT NULL) + (bill_id IS NOT NULL) = 1),
  UNIQUE(adjustment_id, purchase_id),
  UNIQUE(adjustment_id, purchase_order_id),
  UNIQUE(adjustment_id, bill_id)
);
CREATE INDEX party_adjustment_payables_purchase ON party_adjustment_payables(purchase_id, adjustment_id);
CREATE INDEX party_adjustment_payables_po ON party_adjustment_payables(purchase_order_id, adjustment_id);
CREATE INDEX party_adjustment_payables_bill ON party_adjustment_payables(bill_id, adjustment_id);

DROP VIEW direct_purchase_payables;
CREATE VIEW direct_purchase_payables AS
SELECT totals.*, ROUND(paid_amount + adjusted_amount, 2) AS settled_amount FROM (
  SELECT p.id, ROUND(p.total_cost + p.input_tax_amount, 2) AS total_payable,
    COALESCE((SELECT SUM(r.total_amount) FROM purchase_returns r
      WHERE r.source_type = 'PURCHASE' AND r.source_id = p.id AND r.status = 'POSTED'), 0) AS returned_amount,
    COALESCE((SELECT SUM(a.amount) FROM purchase_allocations a
      WHERE a.purchase_id = p.id AND a.voided_at IS NULL), 0) AS paid_amount,
    COALESCE((SELECT SUM(a.amount) FROM party_adjustment_payables a JOIN party_adjustments j ON j.id = a.adjustment_id
      WHERE a.purchase_id = p.id AND j.status = 'posted'), 0) AS adjusted_amount
  FROM purchases p
) totals;
DROP VIEW purchase_order_payables;
CREATE VIEW purchase_order_payables AS
SELECT totals.*, ROUND(paid_amount + adjusted_amount, 2) AS settled_amount FROM (
  SELECT po.id, po.total_amount AS total_payable,
    COALESCE((SELECT SUM(r.total_amount) FROM purchase_returns r
      WHERE r.source_type = 'PURCHASE_ORDER' AND r.source_id = po.id AND r.status = 'POSTED'), 0) AS returned_amount,
    COALESCE((SELECT SUM(a.amount) FROM po_allocations a
      WHERE a.po_id = po.id AND a.voided_at IS NULL), 0) AS paid_amount,
    COALESCE((SELECT SUM(a.amount) FROM party_adjustment_payables a JOIN party_adjustments j ON j.id = a.adjustment_id
      WHERE a.purchase_order_id = po.id AND j.status = 'posted'), 0) AS adjusted_amount
  FROM purchase_orders po
) totals;

INSERT OR IGNORE INTO permissions(permission_name,module,action,description) VALUES
 ('parties:read','parties','read','View customer and supplier roles and balances'),
 ('parties:link','parties','link','Link customer and supplier identities'),
 ('party_adjustments:read','party_adjustments','read','View noncash balance adjustments'),
 ('party_adjustments:create','party_adjustments','create','Post noncash balance adjustments'),
 ('party_adjustments:reverse','party_adjustments','reverse','Reverse noncash balance adjustments');
INSERT OR IGNORE INTO role_permissions(role_id,permission_id)
SELECT r.id,p.id FROM roles r CROSS JOIN permissions p
WHERE r.role_name='Admin' AND p.module IN ('parties','party_adjustments');
