ALTER TABLE credit_source_consumptions RENAME TO credit_source_consumptions_precision_old;
ALTER TABLE customer_credit_sources RENAME TO customer_credit_sources_precision_old;

CREATE TABLE customer_credit_sources (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id INTEGER NOT NULL REFERENCES customers(id),
  kind TEXT NOT NULL CHECK (kind IN ('RETURN_CREDIT','UNAPPLIED_CASH')),
  origin_payment_id INTEGER,
  origin_invoice_id INTEGER,
  credited_amount DECIMAL(15,2) NOT NULL,
  consumed_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
  refunded_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
  remaining_amount DECIMAL(15,2)
    GENERATED ALWAYS AS (ROUND(credited_amount-consumed_amount-refunded_amount,2)) VIRTUAL,
  refundable_cash_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
  credited_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  voided_at TIMESTAMP,
  CONSTRAINT c_nonneg_consumed CHECK (consumed_amount>=0),
  CONSTRAINT c_refund_le_credited CHECK (refunded_amount<=credited_amount),
  CONSTRAINT c_refundable_nonneg CHECK (refundable_cash_amount>=0),
  CONSTRAINT c_refundable_le_remaining CHECK (refundable_cash_amount<=remaining_amount)
);

INSERT INTO customer_credit_sources
  (id,customer_id,kind,origin_payment_id,origin_invoice_id,credited_amount,
   consumed_amount,refunded_amount,refundable_cash_amount,credited_at,voided_at)
SELECT id,customer_id,kind,origin_payment_id,origin_invoice_id,credited_amount,
       consumed_amount,refunded_amount,refundable_cash_amount,credited_at,voided_at
FROM customer_credit_sources_precision_old;

CREATE TABLE credit_source_consumptions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  source_id INTEGER NOT NULL REFERENCES customer_credit_sources(id),
  application_id INTEGER NOT NULL REFERENCES credit_applications(id),
  kind TEXT NOT NULL CHECK (kind IN ('APPLY','REFUND')),
  invoice_id INTEGER,
  payment_id INTEGER,
  amount DECIMAL(15,2) NOT NULL CHECK (amount>0),
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  voided_at TIMESTAMP
);

INSERT INTO credit_source_consumptions
  (id,source_id,application_id,kind,invoice_id,payment_id,amount,created_at,voided_at)
SELECT id,source_id,application_id,kind,invoice_id,payment_id,amount,created_at,voided_at
FROM credit_source_consumptions_precision_old;

DROP TABLE credit_source_consumptions_precision_old;
DROP TABLE customer_credit_sources_precision_old;

CREATE INDEX idx_credit_sources_customer_live
  ON customer_credit_sources(customer_id,kind,voided_at,credited_at,id);
CREATE UNIQUE INDEX idx_unapplied_origin_payment
  ON customer_credit_sources(origin_payment_id) WHERE kind='UNAPPLIED_CASH';
CREATE INDEX idx_credit_consumptions_source_live
  ON credit_source_consumptions(source_id,voided_at);
CREATE INDEX idx_credit_consumptions_application
  ON credit_source_consumptions(application_id);
CREATE INDEX idx_credit_consumptions_invoice_live
  ON credit_source_consumptions(invoice_id,voided_at);
CREATE INDEX idx_credit_consumptions_payment
  ON credit_source_consumptions(payment_id);
