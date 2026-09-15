-- Expired Stock Management — schema foundation (expired-stock plan Phase 1)
--
-- Applied once via the schema_migrations ledger (runLedgered). All statements
-- are idempotent (INSERT OR IGNORE / IF NOT EXISTS) so partial states from an
-- interrupted run stay repairable.
--
-- Layout:
--   1. GL loss accounts 7201-7204 (children of the existing 7200 Inventory
--      Shrinkage parent from add-gl-foundation.sql — no parallel 54xx family).
--   2. warehouses.is_system column + EXPIRED / DAMAGED system warehouse seeds.
--   3. DB-level delete guard for system warehouses (defense in depth — the
--      API returns a structured 400; this trigger stops direct-SQL scripts).
--   4. Indexes for the boot-task expiry sweep (expiryDetection.ts) and its
--      idempotency NOT EXISTS check.

-- ============================================================================
-- 1. GL accounts: loss sub-categories under 7200 Inventory Shrinkage
-- ============================================================================
INSERT OR IGNORE INTO chart_of_accounts (code, name, type, normal_balance, text_code, description) VALUES
    ('7201', 'Expired Goods Loss',  'expense', 'debit', 'expired_goods_loss',  'Written-off expired stock (write-off endpoint)'),
    ('7202', 'Damaged Goods Loss',  'expense', 'debit', 'damaged_goods_loss',  'Written-off damaged stock'),
    ('7203', 'Stock Shortage Loss', 'expense', 'debit', 'stock_shortage_loss', 'Physical count shortages written off'),
    ('7204', 'Obsolete Stock Loss', 'expense', 'debit', 'obsolete_stock_loss', 'Written-off obsolete stock');

-- Attach the new sub-categories to the existing 7200 parent (which already
-- absorbs generic manual ADJUSTMENT postings — that usage is unchanged).
UPDATE chart_of_accounts
SET parent_id = (SELECT id FROM chart_of_accounts WHERE code = '7200')
WHERE code IN ('7201', '7202', '7203', '7204') AND parent_id IS NULL;

-- ============================================================================
-- 2. System warehouses: is_system column + EXPIRED / DAMAGED seeds
-- ============================================================================
-- The ledger guarantees this file runs once per database, so the ALTER needs
-- no pragma guard (SQLite has no ADD COLUMN IF NOT EXISTS).
ALTER TABLE warehouses ADD COLUMN is_system BOOLEAN NOT NULL DEFAULT 0;

INSERT OR IGNORE INTO warehouses (warehouse_code, warehouse_name, is_system, is_active)
VALUES ('EXPIRED', 'Expired Stock', 1, 1),
       ('DAMAGED', 'Damaged Stock', 1, 1);

-- ============================================================================
-- 3. System warehouse delete guard (DB-level backstop)
-- ============================================================================
CREATE TRIGGER IF NOT EXISTS trg_warehouses_no_delete_system
BEFORE DELETE ON warehouses
WHEN OLD.is_system = 1
BEGIN
    SELECT RAISE(ABORT, 'Cannot delete system warehouse');
END;

-- ============================================================================
-- 4. Boot-task indexes (expiryDetection.ts)
-- ============================================================================
-- Candidate query filters expiry_date < today AND quantity_remaining > 0:
-- partial composite index matches the filter shape exactly.
CREATE INDEX IF NOT EXISTS idx_stock_batches_expiry_active
    ON stock_batches(expiry_date, quantity_remaining)
    WHERE quantity_remaining > 0;

-- Idempotency guard: NOT EXISTS on stock_movements(batch_id, movement_type)
-- for 'EXPIRY_TRANSFER' / 'WRITE_OFF' lookups.
CREATE INDEX IF NOT EXISTS idx_stock_movements_batch_type
    ON stock_movements(batch_id, movement_type);
