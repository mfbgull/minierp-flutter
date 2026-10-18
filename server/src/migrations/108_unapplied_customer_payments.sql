CREATE TEMP TABLE unapplied_credit_migration_guard (
  valid INTEGER NOT NULL CHECK (valid = 1)
);

INSERT INTO unapplied_credit_migration_guard (valid)
SELECT CASE WHEN EXISTS (
  SELECT 1 FROM chart_of_accounts
  WHERE code = '2110' AND (
    type <> 'liability' OR normal_balance <> 'credit'
    OR text_code IS NOT 'unapplied_customer_payments' OR is_active <> 1
  )
) OR EXISTS (
  SELECT 1 FROM chart_of_accounts
  WHERE text_code = 'unapplied_customer_payments' AND code <> '2110'
) THEN 0 ELSE 1 END;

INSERT INTO unapplied_credit_migration_guard (valid)
SELECT 0 FROM customer_ledger
WHERE COALESCE(voided, 0) = 0 AND reversed_by IS NULL
GROUP BY customer_id
HAVING ROUND(SUM(CASE WHEN transaction_type = 'CREDIT_OFFSET' AND credit > 0
                     THEN credit ELSE 0 END) * 100)
     > ROUND(SUM(CASE WHEN transaction_type = 'RETURN' AND credit > 0
                     THEN credit ELSE 0 END) * 100);

DROP TABLE unapplied_credit_migration_guard;

INSERT INTO chart_of_accounts (code, name, type, normal_balance, text_code)
VALUES ('2110', 'Unapplied Customer Payments', 'liability', 'credit',
        'unapplied_customer_payments')
ON CONFLICT(code) DO NOTHING;

CREATE TABLE customer_credit_sources (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id INTEGER NOT NULL REFERENCES customers(id),
  kind TEXT NOT NULL CHECK (kind IN ('RETURN_CREDIT', 'UNAPPLIED_CASH')),
  origin_payment_id INTEGER,
  origin_invoice_id INTEGER,
  credited_amount DECIMAL(15,2) NOT NULL,
  consumed_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
  refunded_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
  remaining_amount DECIMAL(15,2)
    GENERATED ALWAYS AS (credited_amount - consumed_amount - refunded_amount) VIRTUAL,
  refundable_cash_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
  credited_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  voided_at TIMESTAMP,
  CONSTRAINT c_nonneg_consumed CHECK (consumed_amount >= 0),
  CONSTRAINT c_refund_le_credited CHECK (refunded_amount <= credited_amount),
  CONSTRAINT c_refundable_nonneg CHECK (refundable_cash_amount >= 0),
  CONSTRAINT c_refundable_le_remaining CHECK (refundable_cash_amount <= remaining_amount)
);

CREATE TABLE credit_applications (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  application_key TEXT NOT NULL,
  customer_id INTEGER NOT NULL REFERENCES customers(id),
  operation TEXT NOT NULL CHECK (operation IN ('APPLY', 'REFUND')),
  total_amount DECIMAL(15,2) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE credit_source_consumptions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  source_id INTEGER NOT NULL REFERENCES customer_credit_sources(id),
  application_id INTEGER NOT NULL REFERENCES credit_applications(id),
  kind TEXT NOT NULL CHECK (kind IN ('APPLY', 'REFUND')),
  invoice_id INTEGER,
  payment_id INTEGER,
  amount DECIMAL(15,2) NOT NULL CHECK (amount > 0),
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  voided_at TIMESTAMP
);

CREATE INDEX idx_credit_sources_customer_live
  ON customer_credit_sources (customer_id, kind, voided_at, credited_at, id);
CREATE INDEX idx_credit_consumptions_source_live
  ON credit_source_consumptions (source_id, voided_at);
CREATE INDEX idx_credit_consumptions_application
  ON credit_source_consumptions (application_id);
CREATE UNIQUE INDEX idx_credit_applications_key
  ON credit_applications (customer_id, operation, application_key);

ALTER TABLE payments ADD COLUMN payment_kind TEXT NOT NULL DEFAULT 'RECEIPT'
  CHECK (payment_kind IN ('RECEIPT', 'UNAPPLIED_RECEIPT', 'REFUND', 'CREDIT_APPLICATION'));

WITH ret AS (
  SELECT ledger.customer_id, ledger.credit, ledger.created_at,
         COALESCE(SUM(ledger.credit) OVER (
           PARTITION BY ledger.customer_id
           ORDER BY COALESCE(ledger.created_at, ledger.id), ledger.id
           ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) AS cum_before
  FROM customer_ledger ledger
  WHERE ledger.transaction_type = 'RETURN' AND ledger.credit > 0
    AND COALESCE(ledger.voided, 0) = 0 AND ledger.reversed_by IS NULL
), cons AS (
  SELECT customer_id, SUM(credit) consumed FROM customer_ledger
  WHERE transaction_type = 'CREDIT_OFFSET' AND credit > 0
    AND COALESCE(voided, 0) = 0 AND reversed_by IS NULL
  GROUP BY customer_id
)
INSERT INTO customer_credit_sources (
  customer_id, kind, credited_amount, consumed_amount,
  refundable_cash_amount, credited_at, origin_invoice_id
)
SELECT ret.customer_id, 'RETURN_CREDIT', ret.credit,
       MAX(0, MIN(ret.credit, COALESCE(cons.consumed, 0) - ret.cum_before)),
       0, COALESCE(ret.created_at, CURRENT_TIMESTAMP), NULL
FROM ret LEFT JOIN cons ON cons.customer_id = ret.customer_id;
