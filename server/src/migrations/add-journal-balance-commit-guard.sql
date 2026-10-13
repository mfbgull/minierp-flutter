CREATE TABLE journal_balance_zero (
  value INTEGER PRIMARY KEY CHECK (value = 0)
);
INSERT INTO journal_balance_zero (value) VALUES (0);

CREATE TABLE journal_entry_balances (
  journal_entry_id INTEGER PRIMARY KEY,
  balance_cents INTEGER NOT NULL REFERENCES journal_balance_zero(value)
    DEFERRABLE INITIALLY DEFERRED
);

INSERT INTO journal_entry_balances (journal_entry_id, balance_cents)
SELECT journal_entry_id,
       SUM(CASE WHEN voided = 0
           THEN CAST(ROUND(debit * 100) - ROUND(credit * 100) AS INTEGER)
           ELSE 0 END)
FROM journal_lines
GROUP BY journal_entry_id;

CREATE TRIGGER journal_balance_insert
AFTER INSERT ON journal_lines
BEGIN
  INSERT OR IGNORE INTO journal_balance_zero (value) VALUES (0);
  INSERT INTO journal_entry_balances (journal_entry_id, balance_cents)
  VALUES (NEW.journal_entry_id, CASE WHEN NEW.voided = 0
    THEN CAST(ROUND(NEW.debit * 100) - ROUND(NEW.credit * 100) AS INTEGER) ELSE 0 END)
  ON CONFLICT (journal_entry_id) DO UPDATE
    SET balance_cents = balance_cents + excluded.balance_cents;
END;

CREATE TRIGGER journal_balance_update
AFTER UPDATE OF journal_entry_id, debit, credit, voided ON journal_lines
BEGIN
  UPDATE journal_entry_balances
  SET balance_cents = balance_cents - CASE WHEN OLD.voided = 0
    THEN CAST(ROUND(OLD.debit * 100) - ROUND(OLD.credit * 100) AS INTEGER) ELSE 0 END
  WHERE journal_entry_id = OLD.journal_entry_id;
  INSERT INTO journal_entry_balances (journal_entry_id, balance_cents)
  VALUES (NEW.journal_entry_id, CASE WHEN NEW.voided = 0
    THEN CAST(ROUND(NEW.debit * 100) - ROUND(NEW.credit * 100) AS INTEGER) ELSE 0 END)
  ON CONFLICT (journal_entry_id) DO UPDATE
    SET balance_cents = balance_cents + excluded.balance_cents;
END;

CREATE TRIGGER journal_balance_delete
AFTER DELETE ON journal_lines
BEGIN
  UPDATE journal_entry_balances
  SET balance_cents = balance_cents - CASE WHEN OLD.voided = 0
    THEN CAST(ROUND(OLD.debit * 100) - ROUND(OLD.credit * 100) AS INTEGER) ELSE 0 END
  WHERE journal_entry_id = OLD.journal_entry_id;
END;

CREATE TRIGGER journal_balance_no_replace_insert
BEFORE INSERT ON journal_lines
WHEN EXISTS (SELECT 1 FROM journal_lines WHERE id = NEW.id)
BEGIN
  SELECT RAISE(ABORT, 'Journal lines must be updated, not replaced');
END;

CREATE TRIGGER journal_balance_no_replace_update
BEFORE UPDATE OF id ON journal_lines
WHEN NEW.id != OLD.id AND EXISTS (SELECT 1 FROM journal_lines WHERE id = NEW.id)
BEGIN
  SELECT RAISE(ABORT, 'Journal lines must be updated, not replaced');
END;
