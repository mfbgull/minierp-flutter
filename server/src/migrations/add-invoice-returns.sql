-- Invoice Returns — first-class return documents
-- (invoice-return-spec.md §4.1 / Milestone 1)
--
-- Creates the return document tables that make returns real, linked
-- transactions instead of stock-movement reconstructions:
--   invoice_returns       — one row per return event (RET- number)
--   invoice_return_items  — the returned lines at original sale price
--   return_settlements    — refund/credit/adjust allocations (CR- number)
--
-- No legacy backfill (spec D11): rows only exist for returns processed
-- after this change. Idempotent: safe to re-run on every start.

-- ============================================================================
-- 1. invoice_returns: return header
-- ============================================================================
CREATE TABLE IF NOT EXISTS invoice_returns (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    return_no       TEXT NOT NULL UNIQUE,               -- RET-0926-00001
    invoice_id      INTEGER NOT NULL REFERENCES invoices(id),
    customer_id     INTEGER NOT NULL REFERENCES customers(id),
    return_date     TEXT NOT NULL,                      -- user-pickable (spec D14)
    reason          TEXT,
    status          TEXT NOT NULL DEFAULT 'Unsettled'
                    CHECK (status IN ('Unsettled', 'Settled', 'Voided')),
    fee_type        TEXT CHECK (fee_type IN ('none', 'fixed', 'percentage')),
    fee_value       REAL NOT NULL DEFAULT 0,            -- 10 (percent) or 150 (fixed)
    fee_amount      REAL NOT NULL DEFAULT 0,            -- resolved amount
    returned_amount REAL NOT NULL DEFAULT 0,            -- tax-inclusive gross returned value
    net_amount      REAL NOT NULL DEFAULT 0,            -- returned_amount − fee_amount
    settled_amount  REAL NOT NULL DEFAULT 0,            -- Σ allocations (≤ net_amount)
    warehouse_id    INTEGER,                            -- restock warehouse
    created_by      INTEGER NOT NULL REFERENCES users(id),
    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
    voided_at       TEXT,
    voided_by       INTEGER REFERENCES users(id),
    CHECK (fee_amount >= 0 AND returned_amount >= 0 AND settled_amount >= 0)
);

CREATE INDEX IF NOT EXISTS idx_invoice_returns_invoice  ON invoice_returns(invoice_id);
CREATE INDEX IF NOT EXISTS idx_invoice_returns_customer ON invoice_returns(customer_id);
CREATE INDEX IF NOT EXISTS idx_invoice_returns_date     ON invoice_returns(return_date);

-- ============================================================================
-- 2. invoice_return_items: returned lines (original sale price preserved)
-- ============================================================================
CREATE TABLE IF NOT EXISTS invoice_return_items (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    return_id       INTEGER NOT NULL REFERENCES invoice_returns(id),
    invoice_item_id INTEGER NOT NULL REFERENCES invoice_items(id),
    item_id         INTEGER NOT NULL,
    quantity        REAL NOT NULL CHECK (quantity > 0),  -- ≤ sold − already returned (enforced in service)
    unit_price      REAL NOT NULL,                       -- original sale price
    tax_amount      REAL NOT NULL DEFAULT 0,             -- proportional mirror (spec §3.5, additive)
    line_amount     REAL NOT NULL CHECK (line_amount >= 0),  -- net of item discount, incl. tax
    UNIQUE (return_id, invoice_item_id)
);

CREATE INDEX IF NOT EXISTS idx_invoice_return_items_return ON invoice_return_items(return_id);
CREATE INDEX IF NOT EXISTS idx_invoice_return_items_item   ON invoice_return_items(item_id);

-- ============================================================================
-- 3. return_settlements: what happened to the net amount (no double-count)
-- ============================================================================
CREATE TABLE IF NOT EXISTS return_settlements (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    return_id         INTEGER NOT NULL REFERENCES invoice_returns(id),
    settlement_no     TEXT NOT NULL UNIQUE,             -- CR-… / payment no / ADJ ref
    type              TEXT NOT NULL CHECK (type IN ('refund', 'credit', 'adjust')),
    amount            REAL NOT NULL CHECK (amount > 0),
    method            TEXT,                             -- refund only: Cash | Bank | Card …
    reference         TEXT,                             -- payment no / target invoice no
    target_invoice_id INTEGER,                          -- adjust only
    payment_id        INTEGER,                          -- links to payments row (refund/adjust)
    settled_date      TEXT NOT NULL,
    created_by        INTEGER NOT NULL REFERENCES users(id),
    created_at        TEXT NOT NULL DEFAULT (datetime('now')),
    voided_at         TEXT
);

CREATE INDEX IF NOT EXISTS idx_return_settlements_return  ON return_settlements(return_id);
CREATE INDEX IF NOT EXISTS idx_return_settlements_invoice ON return_settlements(target_invoice_id);
CREATE INDEX IF NOT EXISTS idx_return_settlements_payment ON return_settlements(payment_id);
