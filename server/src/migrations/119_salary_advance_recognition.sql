CREATE TABLE salary_advance_recognitions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  advance_id INTEGER NOT NULL REFERENCES salary_payments(id),
  payment_id INTEGER NOT NULL REFERENCES salary_payments(id),
  amount_minor INTEGER NOT NULL CHECK(amount_minor > 0),
  voided_at TEXT,
  UNIQUE(advance_id,payment_id)
);
CREATE INDEX idx_salary_recognition_payment ON salary_advance_recognitions(payment_id,voided_at);
