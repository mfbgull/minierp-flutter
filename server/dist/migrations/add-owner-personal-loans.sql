-- Owner Personal Loans Migration
-- Personal loan tracker for the owner — purely record-keeping.
-- No GL entries, no chart_of_accounts seeds, no accounting impact.
-- Completely independent of business data (sales, purchases, invoices, etc.).
--
-- Idempotent: safe to re-run on every server start.

-- ============================================================================
-- 1. owner_personal_loan_borrowers
--    Reusable borrower list. Optional link to customers/suppliers is purely
--    cosmetic (shows a badge in the UI). No business logic dependency.
-- ============================================================================

CREATE TABLE IF NOT EXISTS owner_personal_loan_borrowers (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    name            VARCHAR(200) NOT NULL,              -- borrower name
    phone           VARCHAR(50),                        -- optional phone number
    linked_type     TEXT CHECK (linked_type IS NULL OR linked_type IN ('customer', 'supplier')),
    linked_id       INTEGER,                            -- FK to customers(id) or suppliers(id)
    is_active       INTEGER NOT NULL DEFAULT 1,          -- soft-delete: 0 = deactivated
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(name, linked_type, linked_id)
);

CREATE INDEX IF NOT EXISTS idx_own_loan_borrowers_name ON owner_personal_loan_borrowers(name);
CREATE INDEX IF NOT EXISTS idx_own_loan_borrowers_active ON owner_personal_loan_borrowers(is_active);

-- ============================================================================
-- 2. owner_personal_loans
--    The owner's personal loan records. No journal_entry_id, no GL impact.
--    Doc numbers via generateDocNo(db, 'PL') → PL-2026-0001 format.
-- ============================================================================

CREATE TABLE IF NOT EXISTS owner_personal_loans (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    loan_no         VARCHAR(50) UNIQUE NOT NULL,        -- auto-generated: PL-2026-0001
    borrower_name   VARCHAR(200) NOT NULL,              -- free-text borrower name (snapshot)
    borrower_id     INTEGER,                            -- nullable FK to owner_personal_loan_borrowers(id)
    borrower_type   TEXT CHECK (borrower_type IS NULL OR borrower_type IN ('customer', 'supplier')),
    -- 'customer' | 'supplier' | null (snapshot)
    amount          DECIMAL(15,2) NOT NULL CHECK (amount > 0),  -- total loan amount given
    balance         DECIMAL(15,2) NOT NULL,             -- remaining balance (= amount - repaid)
    currency        VARCHAR(3) DEFAULT 'PKR',           -- ISO 4217 currency code
    loan_date       DATE NOT NULL,                      -- date loan was given
    due_date        DATE,                               -- optional — informational only
    purpose         VARCHAR(100),                       -- e.g. "Medical", "Family", "Personal"
    status          VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'partial', 'settled', 'written_off')),
    notes           TEXT,
    created_by      INTEGER REFERENCES users(id),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_own_personal_loans_borrower ON owner_personal_loans(borrower_name);
CREATE INDEX IF NOT EXISTS idx_own_personal_loans_status ON owner_personal_loans(status);
CREATE INDEX IF NOT EXISTS idx_own_personal_loans_date ON owner_personal_loans(loan_date);

-- ============================================================================
-- 3. owner_personal_loan_repayments
--    Individual repayments received from borrowers.
--    No ON DELETE CASCADE — backend rejects loan deletion when repayments exist.
-- ============================================================================

CREATE TABLE IF NOT EXISTS owner_personal_loan_repayments (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    loan_id         INTEGER NOT NULL REFERENCES owner_personal_loans(id),
    amount          DECIMAL(15,2) NOT NULL CHECK (amount > 0),  -- repayment amount received
    payment_date    DATE NOT NULL,                      -- date repayment was received
    notes           TEXT,
    created_by      INTEGER REFERENCES users(id),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_own_loan_repayments_loan ON owner_personal_loan_repayments(loan_id);
CREATE INDEX IF NOT EXISTS idx_own_loan_repayments_date ON owner_personal_loan_repayments(payment_date);
