-- Stock Adjustment Financial Posting Migration
-- Adds financial tracking columns to stock_movements and creates journal_entries table
-- Enables P&L impact for inventory shrinkage (removal) and corrections (additions)

-- Journal entries table for double-entry-style posting
-- MUST be created BEFORE adding FK reference in stock_movements
CREATE TABLE IF NOT EXISTS journal_entries (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    reference_type  TEXT NOT NULL,
    reference_id    INTEGER NOT NULL,
    entry_date      DATE NOT NULL,
    description     TEXT,
    debit_account   TEXT NOT NULL,
    credit_account  TEXT NOT NULL,
    amount          DECIMAL(15,4) NOT NULL,
    created_by      INTEGER REFERENCES users(id),
    voided          BOOLEAN DEFAULT FALSE,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Index for looking up journal entries by reference
CREATE INDEX IF NOT EXISTS idx_journal_entries_reference
    ON journal_entries(reference_type, reference_id);

-- Index for date-range queries (P&L reports)
CREATE INDEX IF NOT EXISTS idx_journal_entries_date
    ON journal_entries(entry_date);

-- Index for account queries
CREATE INDEX IF NOT EXISTS idx_journal_entries_accounts
    ON journal_entries(debit_account, credit_account, voided);

-- Add financial columns to stock_movements (safe ALTER TABLE with IF NOT EXISTS pattern)
ALTER TABLE stock_movements ADD COLUMN financial_value DECIMAL(15,4) DEFAULT 0;
ALTER TABLE stock_movements ADD COLUMN financial_posted BOOLEAN DEFAULT FALSE;
ALTER TABLE stock_movements ADD COLUMN journal_entry_id INTEGER REFERENCES journal_entries(id);
