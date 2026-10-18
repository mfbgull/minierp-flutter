ALTER TABLE credit_applications ADD COLUMN request_hash TEXT;
ALTER TABLE credit_applications ADD COLUMN operation_date TEXT;
ALTER TABLE credit_applications ADD COLUMN payment_id INTEGER REFERENCES payments(id);
CREATE UNIQUE INDEX idx_unapplied_origin_payment
  ON customer_credit_sources(origin_payment_id)
  WHERE kind = 'UNAPPLIED_CASH';
