-- Migration: PRET-002 supplier refund claims
-- ---------------------------------------------------------------
-- One claim object per expected supplier refund: EXPECTED → PARTIAL →
-- RECEIVED (or CANCELLED). Cash moves only when a refund receipt
-- (REFUND_RECEIPT) posts — claim creation posts no GL at all.
--
-- 1. supplier_refund_claims — the expected→received lifecycle.
-- 2. refund_receipt_allocations — which receipts settled which claim.
-- 3. Account 7300 Refund Write-offs — short-pay write-off expense leg
--    (Dr 7300 / Cr AP), with the write-off reason stored on the claim.
-- 4. supplier_refunds.credit_note_id becomes nullable — receipts can
--    settle a standalone claim that has no credit note (overpayment,
--    price compensation). FK-off table rebuild, managed transaction.
-- 5. Backfill: every POSTED refund_expected return with a POSTED credit
--    note gets a claim; already-issued live refunds seed received_amount.

CREATE TABLE IF NOT EXISTS supplier_refund_claims (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    claim_no           TEXT NOT NULL UNIQUE,              -- SRC-202611-0001
    supplier_id        INTEGER NOT NULL REFERENCES suppliers(id),
    return_id          INTEGER REFERENCES purchase_returns(id),
    credit_note_id     INTEGER REFERENCES credit_notes(id),
    claim_date         TEXT NOT NULL,
    amount             NUMERIC(15,3) NOT NULL,            -- expected total
    received_amount    NUMERIC(15,3) NOT NULL DEFAULT 0,
    written_off_amount NUMERIC(15,3) NOT NULL DEFAULT 0,
    status             TEXT NOT NULL DEFAULT 'EXPECTED'
                       CHECK (status IN ('EXPECTED','PARTIAL','RECEIVED','CANCELLED')),
    reason             TEXT,
    created_by         INTEGER REFERENCES users(id),
    created_at         TEXT NOT NULL DEFAULT (datetime('now')),
    cancelled_at       TEXT,
    cancelled_by       INTEGER REFERENCES users(id),
    cancel_reason      TEXT,
    written_off_at     TEXT,
    written_off_by     INTEGER REFERENCES users(id),
    written_off_reason TEXT
);

CREATE INDEX IF NOT EXISTS idx_refund_claims_supplier ON supplier_refund_claims(supplier_id);
CREATE INDEX IF NOT EXISTS idx_refund_claims_return ON supplier_refund_claims(return_id);
CREATE INDEX IF NOT EXISTS idx_refund_claims_note ON supplier_refund_claims(credit_note_id);
CREATE INDEX IF NOT EXISTS idx_refund_claims_status ON supplier_refund_claims(status);

CREATE TABLE IF NOT EXISTS refund_receipt_allocations (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    receipt_id INTEGER NOT NULL REFERENCES supplier_refunds(id),
    claim_id   INTEGER NOT NULL REFERENCES supplier_refund_claims(id),
    amount     NUMERIC(15,3) NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_refund_alloc_receipt ON refund_receipt_allocations(receipt_id);
CREATE INDEX IF NOT EXISTS idx_refund_alloc_claim ON refund_receipt_allocations(claim_id);

-- Write-off expense account (short-paid refund claims).
INSERT OR IGNORE INTO chart_of_accounts (code, name, type, normal_balance, text_code, description)
VALUES ('7300', 'Refund Write-offs', 'expense', 'debit', 'refund_write_offs',
        'Supplier refund receivable written off as uncollectible');

-- Backfill: a claim for every POSTED refund_expected return whose credit
-- note is still POSTED. Already-issued live refunds seed received_amount so
-- the claim reflects what has actually been collected. Legacy rows keep
-- their behaviour; the claim only adds tracking. Skips notes with no
-- resolvable supplier (claims require one).
INSERT INTO supplier_refund_claims
  (claim_no, supplier_id, return_id, credit_note_id, claim_date, amount,
   received_amount, status, reason, created_by)
SELECT
  'SRC-LEGACY-' || pr.id,
  cn.supplier_id,
  pr.id,
  cn.id,
  pr.return_date,
  cn.amount,
  COALESCE(rf.paid, 0),
  CASE
    WHEN COALESCE(rf.paid, 0) >= cn.amount - 0.005 THEN 'RECEIVED'
    WHEN COALESCE(rf.paid, 0) > 0.005 THEN 'PARTIAL'
    ELSE 'EXPECTED'
  END,
  'Backfilled from return ' || pr.return_no,
  pr.created_by
FROM purchase_returns pr
JOIN credit_notes cn ON cn.id = pr.credit_note_id
LEFT JOIN (
  SELECT return_id, SUM(amount) AS paid
  FROM supplier_refunds
  WHERE status = 'POSTED'
  GROUP BY return_id
) rf ON rf.return_id = pr.id
WHERE pr.disposition = 'refund_expected'
  AND pr.status = 'POSTED'
  AND cn.status = 'POSTED'
  AND cn.supplier_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM supplier_refund_claims c WHERE c.return_id = pr.id);
