-- ============================================
-- Item Expiry Date Tracking
-- Migration: add-item-expiry-tracking.sql
-- Date: 2026-08-20
-- ============================================
-- Adds per-batch expiry dates, FEFO support,
-- batch halt mechanism, and invoice expiry notes.

-- ── Items: expiry opt-in and threshold ──────
-- has_expiry: whether this item tracks expiry dates (0 = skip all expiry logic)
-- near_expiry_threshold_days: configurable per-item (default 30)
ALTER TABLE items ADD COLUMN has_expiry BOOLEAN DEFAULT 0;
ALTER TABLE items ADD COLUMN near_expiry_threshold_days INTEGER DEFAULT 30;

-- ── Stock Batches: expiry date and halt ─────
-- expiry_date: the expiry date of this batch (NULL = no expiry)
-- halted: whether this batch is excluded from FEFO consumption
-- halted_reason: free-text reason why the batch was halted
ALTER TABLE stock_batches ADD COLUMN expiry_date DATE;
ALTER TABLE stock_batches ADD COLUMN halted BOOLEAN DEFAULT 0;
ALTER TABLE stock_batches ADD COLUMN halted_reason TEXT;

-- ── Purchase Order Items: expiry date ───────
-- Flows into stock_batches.expiry_date at goods receipt time
ALTER TABLE purchase_order_items ADD COLUMN expiry_date DATE;

-- ── Productions: expiry date for output ─────
-- For produced items that have expiry tracking
ALTER TABLE productions ADD COLUMN expiry_date DATE;

-- ── Invoice Items: denormalized expiry info ─
-- Preserved even if batch data changes
ALTER TABLE invoice_items ADD COLUMN expiry_date DATE;
ALTER TABLE invoice_items ADD COLUMN is_expired_at_sale BOOLEAN DEFAULT 0;

-- ── Invoices: system-generated expiry notes ─
-- Separate from user-editable notes field
ALTER TABLE invoices ADD COLUMN expiry_notes TEXT;

-- ── Invoices: override sale flag ─────────────
-- Indicates invoice was created using expired-batch override flow
ALTER TABLE invoices ADD COLUMN override_sale INTEGER DEFAULT 0;

-- ── Indexes ─────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_stock_batches_expiry ON stock_batches(expiry_date) WHERE expiry_date IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_stock_batches_halted ON stock_batches(halted) WHERE halted = 1;
CREATE INDEX IF NOT EXISTS idx_items_has_expiry ON items(has_expiry);
