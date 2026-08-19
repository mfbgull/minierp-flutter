-- Migration: purchase returns redesign (Phase 1)
-- ---------------------------------------------------------------
-- Creates the first-class return documents the redesign is built on:
--   - purchase_returns      (one row per return header)
--   - purchase_return_items (one row per returned source line)
--   - credit_notes          (supplier credit document per return)
-- plus a nullable FK on stock_movements so each return's movement(s)
-- point back at their header (mirrors the journal_entry_id pattern).
--
-- The legacy backfill (see config/database.ts → runPurchaseReturnsBackfill)
-- materializes purchase_returns/purchase_return_items rows from the old
-- negative return movements; this file only creates the schema.
--
-- Idempotent: safe to re-run on every server start (CREATE IF NOT EXISTS
-- + guarded ALTER, mirroring add-gl-foundation.sql).

-- ============================================================================
-- 1. purchase_returns — return header (source of truth for a return)
-- ============================================================================
CREATE TABLE IF NOT EXISTS purchase_returns (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    return_no      TEXT NOT NULL UNIQUE,           -- PR-2026-0001
    return_date    TEXT NOT NULL,                  -- user-selectable, YYYY-MM-DD
    return_type    TEXT NOT NULL,                  -- 'PURCHASE_RETURN' | 'PO_RETURN'
    source_type    TEXT NOT NULL,                  -- 'PURCHASE' | 'PURCHASE_ORDER'
    source_id      INTEGER,                        -- purchases.id | purchase_orders.id (nullable: legacy source docs may have been deleted)
    source_no      TEXT NOT NULL,                  -- denormalized doc number
    warehouse_id   INTEGER NOT NULL,               -- restock target (user-selectable)
    reason         TEXT,
    status         TEXT NOT NULL DEFAULT 'POSTED', -- 'POSTED' | 'VOIDED'
    total_qty      NUMERIC(15,3) NOT NULL,
    total_amount   NUMERIC(15,3) NOT NULL,
    credit_note_id INTEGER REFERENCES credit_notes(id),  -- NULL until credit posted
    voided_at      TEXT,
    voided_by      INTEGER REFERENCES users(id),
    voided_reason  TEXT,
    created_by     INTEGER REFERENCES users(id),
    created_at     TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_purchase_returns_date ON purchase_returns(return_date);
CREATE INDEX IF NOT EXISTS idx_purchase_returns_status ON purchase_returns(status);
CREATE INDEX IF NOT EXISTS idx_purchase_returns_source ON purchase_returns(source_type, source_id);
CREATE INDEX IF NOT EXISTS idx_purchase_returns_warehouse ON purchase_returns(warehouse_id);
CREATE INDEX IF NOT EXISTS idx_purchase_returns_created_by ON purchase_returns(created_by);

-- ============================================================================
-- 2. purchase_return_items — one row per returned source line
-- ============================================================================
CREATE TABLE IF NOT EXISTS purchase_return_items (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    purchase_return_id INTEGER NOT NULL REFERENCES purchase_returns(id),
    source_item_id    INTEGER,                     -- purchases.id | purchase_order_items.id (nullable: legacy source lines may have been deleted)
    item_id           INTEGER NOT NULL REFERENCES items(id),
    item_name         TEXT NOT NULL,               -- denormalized
    unit_cost         NUMERIC(15,3) NOT NULL,
    quantity          NUMERIC(15,3) NOT NULL,      -- positive magnitude
    amount            NUMERIC(15,3) NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_purchase_return_items_return ON purchase_return_items(purchase_return_id);
CREATE INDEX IF NOT EXISTS idx_purchase_return_items_item ON purchase_return_items(item_id);

-- ============================================================================
-- 3. credit_notes — supplier credit document (1:1 with a return)
-- ============================================================================
-- supplier_id is nullable: direct purchases only store supplier_name (no
-- FK), so the credit note resolves the supplier by name when possible and
-- otherwise posts the document without a supplier link.
CREATE TABLE IF NOT EXISTS credit_notes (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    credit_no    TEXT NOT NULL UNIQUE,             -- CN-2026-0001
    credit_date  TEXT NOT NULL,
    supplier_id  INTEGER REFERENCES suppliers(id),
    source_type  TEXT NOT NULL,                    -- 'PURCHASE_RETURN'
    source_id    INTEGER NOT NULL,                 -- purchase_returns.id
    amount       NUMERIC(15,3) NOT NULL,
    status       TEXT NOT NULL DEFAULT 'POSTED',   -- 'POSTED' | 'VOIDED'
    posted_by    INTEGER REFERENCES users(id),
    posted_at    TEXT NOT NULL DEFAULT (datetime('now')),
    voided_at    TEXT,
    voided_by    INTEGER REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_credit_notes_source ON credit_notes(source_type, source_id);
CREATE INDEX IF NOT EXISTS idx_credit_notes_supplier ON credit_notes(supplier_id);
CREATE INDEX IF NOT EXISTS idx_credit_notes_date ON credit_notes(credit_date);

-- ============================================================================
-- 4. stock_movements.purchase_return_id — back-link movements to their header
-- ============================================================================
-- Guarded: only added when missing (fresh DBs from init.sql don't have it).
ALTER TABLE stock_movements ADD COLUMN purchase_return_id INTEGER REFERENCES purchase_returns(id);

CREATE INDEX IF NOT EXISTS idx_stock_movements_purchase_return ON stock_movements(purchase_return_id);
