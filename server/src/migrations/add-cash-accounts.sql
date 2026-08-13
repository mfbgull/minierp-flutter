-- Cash Accounts + Reconciliation Migration
--
-- 1. Adds Easypaisa / JazzCash / UPaisa chart-of-accounts entries so
--    payments posted through those methods hit their own GL account
--    instead of being lumped into 1010 Bank.
-- 2. Creates the cash_reconciliations table — the end-of-day
--    reconciliation store. One row per (date, account) holding the
--    expected (book) balance, the counted balance and the variance so
--    the cash-in-drawer check is auditable over time.
--
-- Idempotent: safe to re-run on every server start.

-- ============================================================================
-- 1. Wallet accounts (INSERT OR IGNORE so re-runs never clobber edits)
-- ============================================================================
INSERT OR IGNORE INTO chart_of_accounts (code, name, type, normal_balance, text_code, description) VALUES
    ('1020', 'Easypaisa / Mobile Wallet', 'asset', 'debit', 'easypaisa', 'Easypaisa / mobile wallet balances'),
    ('1030', 'JazzCash',                  'asset', 'debit', 'jazzcash',  'JazzCash wallet balances'),
    ('1040', 'UPaisa',                    'asset', 'debit', 'upaisa',    'UPaisa wallet balances');

-- ============================================================================
-- 2. End-of-day cash reconciliation records
-- ============================================================================
CREATE TABLE IF NOT EXISTS cash_reconciliations (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    reconciliation_date DATE NOT NULL,
    account_key         TEXT NOT NULL,   -- 'cash' | 'bank' | 'easypaisa' | 'jazzcash' | 'upaisa'
    account_name        TEXT NOT NULL,
    expected_balance    DECIMAL(15,2) NOT NULL DEFAULT 0,  -- book balance snapshot at save time
    counted_balance     DECIMAL(15,2),                     -- NULL until the day is counted
    variance            DECIMAL(15,2),                     -- counted - expected (NULL until counted)
    notes               TEXT,
    reconciled_by       INTEGER REFERENCES users(id),
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(reconciliation_date, account_key)
);

CREATE INDEX IF NOT EXISTS idx_cash_reconciliations_date ON cash_reconciliations(reconciliation_date);
