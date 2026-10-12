-- Migration: cap a return's settled_amount at its net_amount (audit RET-008)
--
-- `invoice_returns` shipped with a FLOOR only:
--   CHECK (fee_amount >= 0 AND returned_amount >= 0 AND settled_amount >= 0)
-- and nothing above. `settled_amount` is "Σ allocations", so a return could be
-- settled above what the business actually owes the customer.
--
-- The ceiling is `net_amount` (= returned_amount − fee_amount), NOT
-- returned_amount: the restocking fee is money the customer keeps, so it must
-- never be payable back out. The column's own comment in add-invoice-returns.sql
-- already documented the intent as "Σ allocations (≤ net_amount)", and
-- InvoiceReturn.ts:248 flips the header to 'Settled' on
-- `settled_amount >= net_amount`. The audit ledger words this as
-- "exceeds the return's returned_amount", which with a non-zero fee would
-- permit a refund larger than the net obligation — the exact defect class
-- this constraint exists to prevent.
--
-- Implemented as a trigger rather than a CHECK: SQLite cannot add a CHECK to an
-- existing table, and the ceiling needs the 12-step table rebuild (FK off,
-- copy, drop, rename, recreate three indexes). A trigger is added in place,
-- so existing installs get the guard with no data movement and no window where
-- the table is unguarded. The existing floor CHECK is untouched.

CREATE TRIGGER IF NOT EXISTS trg_invoice_returns_settled_ceiling
BEFORE INSERT ON invoice_returns
WHEN NEW.settled_amount > NEW.net_amount
BEGIN
    SELECT RAISE(ABORT, 'settled_amount cannot exceed net_amount (returned_amount − fee_amount)');
END;

CREATE TRIGGER IF NOT EXISTS trg_invoice_returns_settled_ceiling_update
BEFORE UPDATE OF settled_amount, net_amount, returned_amount, fee_amount ON invoice_returns
WHEN NEW.settled_amount > NEW.net_amount
BEGIN
    SELECT RAISE(ABORT, 'settled_amount cannot exceed net_amount (returned_amount − fee_amount)');
END;