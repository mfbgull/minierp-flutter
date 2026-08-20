-- ============================================
-- Override Sale Column
-- Migration: add-override-sale-column.sql
-- Date: 2026-08-21
-- ============================================

-- Flag invoices created via the expired-batch override flow
ALTER TABLE invoices ADD COLUMN override_sale INTEGER DEFAULT 0;
