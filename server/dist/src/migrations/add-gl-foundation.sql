-- GL Foundation Migration
-- Adds the chart of accounts, multi-line journal entries, and
-- accounting periods. This is the schema upgrade that makes the
-- new (real) trial balance and balance sheet possible.
--
-- Pre-existing single-debit-single-credit entries in journal_entries
-- (TEXT account codes) are kept untouched. New postings can use
-- either old or new style; the report code UNIONs the two sources.
--
-- Idempotent: safe to re-run on every server start.

-- ============================================================================
-- 1. chart_of_accounts: the canonical account list
-- ============================================================================
CREATE TABLE IF NOT EXISTS chart_of_accounts (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    code            TEXT UNIQUE NOT NULL,           -- e.g. '1100', '4000'
    name            TEXT NOT NULL,                  -- e.g. 'Accounts Receivable'
    type            TEXT NOT NULL,                  -- asset | liability | equity | revenue | expense
    normal_balance  TEXT NOT NULL CHECK (normal_balance IN ('debit','credit')),
    parent_id       INTEGER REFERENCES chart_of_accounts(id),  -- for hierarchies
    text_code       TEXT,                           -- legacy text code for joining old journal_entries
    is_active       BOOLEAN DEFAULT TRUE,
    description     TEXT,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_coa_code ON chart_of_accounts(code);
CREATE INDEX IF NOT EXISTS idx_coa_type ON chart_of_accounts(type);
CREATE INDEX IF NOT EXISTS idx_coa_text_code ON chart_of_accounts(text_code);

-- Seed the standard 14 accounts. Uses INSERT OR IGNORE so re-runs are safe
-- and a user who has added custom accounts is not overwritten.
INSERT OR IGNORE INTO chart_of_accounts (code, name, type, normal_balance, text_code, description) VALUES
    ('1000', 'Cash',                          'asset',     'debit',  'cash',                   'On-hand cash'),
    ('1010', 'Bank',                          'asset',     'debit',  'bank',                   'Bank balances'),
    ('1100', 'Accounts Receivable',           'asset',     'debit',  'accounts_receivable',    'Customer balances'),
    ('1200', 'Inventory Asset',               'asset',     'debit',  'inventory_asset',        'On-hand inventory at cost'),
    ('2000', 'Accounts Payable',              'liability', 'credit', 'accounts_payable',       'Supplier balances'),
    ('2100', 'Tax Payable',                   'liability', 'credit', 'tax_payable',            'Sales tax collected'),
    ('3000', 'Owner''s Equity',               'equity',    'credit', 'owners_equity',          'Capital contributions'),
    ('3100', 'Retained Earnings',             'equity',    'credit', 'opening_retained_earnings', 'Cumulative profit/loss carried forward'),
    ('4000', 'Sales Revenue',                 'revenue',   'credit',  'sales_revenue',          'Revenue from invoices and POS'),
    ('4100', 'Sales Returns',                 'revenue',   'debit',   'sales_returns',          'Contra-revenue: returned/credited sales'),
    ('4150', 'Restocking Fee Income',         'revenue',   'credit',   'restocking_fee_income', 'Fees charged on returned items'),
    ('5000', 'Cost of Goods Sold',            'expense',   'debit',  'cogs',                   'Cost of items sold'),
    ('6000', 'Operating Expenses',            'expense',   'debit',  'operating_expenses',     'General operating costs'),
    ('6100', 'Wages & Salaries',              'expense',   'debit',  'wages_salaries',         'Payroll'),
    ('7000', 'Production Clearing',           'expense',   'debit',  'production_clearing',    'Clearing account for production cost flow'),
    ('7100', 'Inventory Correction',          'expense',   'debit',  'inventory_correction',   'Adjustments adding to inventory'),
    ('7200', 'Inventory Shrinkage',           'expense',   'debit',  'inventory_shrinkage',    'Losses / removals from inventory');

-- ============================================================================
-- 2. journal_lines: multi-line journal entry lines (the new canonical table)
-- ============================================================================
CREATE TABLE IF NOT EXISTS journal_lines (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    journal_entry_id INTEGER NOT NULL,             -- logical grouping; no FK to journal_entries since that table may be missing for fresh installs
    account_id      INTEGER NOT NULL REFERENCES chart_of_accounts(id),
    debit           DECIMAL(15,4) NOT NULL DEFAULT 0,
    credit          DECIMAL(15,4) NOT NULL DEFAULT 0,
    description     TEXT,
    line_date       DATE NOT NULL,
    reference_type  TEXT,
    reference_id    INTEGER,
    voided          BOOLEAN DEFAULT FALSE,
    created_by      INTEGER REFERENCES users(id),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CHECK (debit = 0 OR credit = 0),               -- a line is either debit or credit, not both
    CHECK (debit >= 0 AND credit >= 0)
);

CREATE INDEX IF NOT EXISTS idx_journal_lines_account ON journal_lines(account_id);
CREATE INDEX IF NOT EXISTS idx_journal_lines_date ON journal_lines(line_date);
CREATE INDEX IF NOT EXISTS idx_journal_lines_entry ON journal_lines(journal_entry_id);
CREATE INDEX IF NOT EXISTS idx_journal_lines_reference ON journal_lines(reference_type, reference_id);

-- ============================================================================
-- 3. accounting_periods: fiscal period open/close
-- ============================================================================
CREATE TABLE IF NOT EXISTS accounting_periods (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    period_name     TEXT UNIQUE NOT NULL,          -- e.g. '2026-01', 'FY2026-Q2'
    start_date      DATE NOT NULL,
    end_date        DATE NOT NULL,
    status          TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','closed')),
    closed_at       TIMESTAMP,
    closed_by       INTEGER REFERENCES users(id),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_periods_dates ON accounting_periods(start_date, end_date);
CREATE INDEX IF NOT EXISTS idx_periods_status ON accounting_periods(status);

-- ============================================================================
-- 4. Auto-open the current month if no period is open
-- ============================================================================
-- Idempotent: if any open period exists, this does nothing. Otherwise
-- it opens the calendar month containing today. Users can close
-- periods manually or via the accounting service.
INSERT INTO accounting_periods (period_name, start_date, end_date, status)
SELECT
    strftime('%Y-%m', 'now') AS period_name,
    date('now', 'start of month') AS start_date,
    date('now', 'start of month', '+1 month', '-1 day') AS end_date,
    'open' AS status
WHERE NOT EXISTS (
    SELECT 1 FROM accounting_periods WHERE status = 'open'
);
