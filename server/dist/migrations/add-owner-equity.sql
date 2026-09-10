-- Owner Capital & Withdrawals Migration
--
-- 1. Equity hierarchy children of 3000 Owner's Equity:
--      3200 Owner Capital  (equity, credit-normal) — owner cash contributions
--      3300 Owner Drawings (equity, debit-normal)  — cash/goods taken by owner
--    Runtime code resolves these by text_code ('owner_capital' /
--    'owner_drawings'), never by literal code; database.ts runs a hard
--    post-apply assertion so an unexpected occupant of either slot fails
--    the boot instead of silently mis-posting.
-- 2. Transaction tables. Deletes are SOFT (status 'voided' + attribution);
--    journal_lines keep their own void flags via voidJournalLinesByReference.
--
-- Idempotent: safe to re-run on every server start.

-- ============================================================================
-- 1. Equity accounts
-- ============================================================================
INSERT OR IGNORE INTO chart_of_accounts (code, name, type, normal_balance, parent_id, text_code, description) VALUES
    ('3200', 'Owner Capital',  'equity', 'credit',
     (SELECT id FROM chart_of_accounts WHERE code = '3000'),
     'owner_capital',  'Cash contributed by the owner'),
    ('3300', 'Owner Drawings', 'equity', 'debit',
     (SELECT id FROM chart_of_accounts WHERE code = '3000'),
     'owner_drawings', 'Cash/goods taken by the owner (contra-equity)');

-- ============================================================================
-- 2. owner_capital
-- ============================================================================
CREATE TABLE IF NOT EXISTS owner_capital (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    capital_no      VARCHAR(50) UNIQUE NOT NULL,
    capital_date    DATE NOT NULL,
    amount          DECIMAL(15,2) NOT NULL CHECK (amount > 0),
    payment_method  VARCHAR(50),
    note            TEXT,
    status          VARCHAR(20) NOT NULL DEFAULT 'posted' CHECK (status IN ('posted','voided')),
    voided_at       TIMESTAMP,
    voided_by       INTEGER REFERENCES users(id),
    void_reason     TEXT,
    created_by      INTEGER REFERENCES users(id),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_owner_capital_date ON owner_capital(capital_date);

-- ============================================================================
-- 3. owner_withdrawals (+ user-entered item lines)
--    `amount` is ALWAYS system-calculated: user input for kind='cash',
--    Σ(batch consumption cost) for kind='goods'. The goods form never
--    accepts a client amount.
-- ============================================================================
CREATE TABLE IF NOT EXISTS owner_withdrawals (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    withdrawal_no    VARCHAR(50) UNIQUE NOT NULL,
    withdrawal_date  DATE NOT NULL,
    kind             VARCHAR(10) NOT NULL CHECK (kind IN ('cash','goods')),
    amount           DECIMAL(15,2) NOT NULL DEFAULT 0 CHECK (amount >= 0),
    payment_method   VARCHAR(50),
    note             TEXT,
    status           VARCHAR(20) NOT NULL DEFAULT 'posted' CHECK (status IN ('posted','voided')),
    voided_at        TIMESTAMP,
    voided_by        INTEGER REFERENCES users(id),
    void_reason      TEXT,
    created_by       INTEGER REFERENCES users(id),
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CHECK (kind != 'cash' OR amount > 0)
);

CREATE TABLE IF NOT EXISTS owner_withdrawal_items (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    withdrawal_id  INTEGER NOT NULL REFERENCES owner_withdrawals(id) ON DELETE CASCADE,
    item_id        INTEGER NOT NULL REFERENCES items(id),
    warehouse_id   INTEGER NOT NULL REFERENCES warehouses(id),
    quantity       DECIMAL(15,3) NOT NULL CHECK (quantity > 0)
);

CREATE INDEX IF NOT EXISTS idx_owner_withdrawals_date ON owner_withdrawals(withdrawal_date);
CREATE INDEX IF NOT EXISTS idx_owner_withdrawal_items_withdrawal ON owner_withdrawal_items(withdrawal_id);
