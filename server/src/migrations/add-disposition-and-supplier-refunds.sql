-- Migration: refund-expected-cash
-- ---------------------------------------------------------------
-- 1. Persist the PRET-06 disposition on the return header and its
--    credit note ('credit_on_account' | 'refund_expected') so the
--    refund lifecycle knows which notes are cash-payout eligible.
--    Backfill: existing returns behaved as pure credit, so any row
--    stamped POSTED gets 'credit_on_account' (the audited default).
-- 2. supplier_refunds — cash payout against a supplier credit note.
--    Lifecycle mirrors the payment void model: POSTED | VOIDED.

ALTER TABLE purchase_returns ADD COLUMN disposition TEXT;
ALTER TABLE credit_notes ADD COLUMN disposition TEXT;

UPDATE purchase_returns SET disposition = 'credit_on_account'
WHERE disposition IS NULL AND status = 'POSTED';
UPDATE credit_notes SET disposition = 'credit_on_account'
WHERE disposition IS NULL AND status = 'POSTED';

CREATE TABLE IF NOT EXISTS supplier_refunds (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    refund_no      TEXT NOT NULL UNIQUE,            -- SR-2026-0001
    refund_date    TEXT NOT NULL,
    supplier_id    INTEGER NOT NULL REFERENCES suppliers(id),
    credit_note_id INTEGER NOT NULL REFERENCES credit_notes(id),
    return_id      INTEGER REFERENCES purchase_returns(id),
    amount         NUMERIC(15,3) NOT NULL,
    payment_method TEXT NOT NULL DEFAULT 'cash',
    reference_no   TEXT,
    status         TEXT NOT NULL DEFAULT 'POSTED',  -- 'POSTED' | 'VOIDED'
    voided_at      TEXT,
    voided_by      INTEGER REFERENCES users(id),
    voided_reason  TEXT,
    created_by     INTEGER REFERENCES users(id),
    created_at     TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_supplier_refunds_supplier ON supplier_refunds(supplier_id);
CREATE INDEX IF NOT EXISTS idx_supplier_refunds_credit_note ON supplier_refunds(credit_note_id);
CREATE INDEX IF NOT EXISTS idx_supplier_refunds_date ON supplier_refunds(refund_date);
