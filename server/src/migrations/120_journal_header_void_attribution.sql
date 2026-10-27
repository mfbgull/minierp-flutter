ALTER TABLE journal_entries ADD COLUMN voided_at TEXT;
ALTER TABLE journal_entries ADD COLUMN voided_by INTEGER REFERENCES users(id);
ALTER TABLE journal_entries ADD COLUMN void_reason TEXT;
