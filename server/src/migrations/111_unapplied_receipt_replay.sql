CREATE TABLE unapplied_receipt_replays (
  customer_id INTEGER NOT NULL REFERENCES customers(id),
  idempotency_key TEXT NOT NULL CHECK (length(idempotency_key) BETWEEN 8 AND 200),
  request_hash TEXT NOT NULL,
  payment_id INTEGER NOT NULL UNIQUE REFERENCES payments(id),
  amount DECIMAL(15,2) NOT NULL CHECK (amount > 0),
  PRIMARY KEY (customer_id, idempotency_key)
);

CREATE INDEX idx_credit_applications_customer_date
  ON credit_applications(customer_id, operation_date, id);
