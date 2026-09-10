-- Migration: Add custom reports table for ad-hoc report builder
-- Created: 2026-06-24

-- ============================================================
-- 1. custom_reports — store report definitions
-- ============================================================
CREATE TABLE IF NOT EXISTS custom_reports (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  name VARCHAR(100) NOT NULL,
  description TEXT,
  config TEXT NOT NULL,              -- JSON blob
  is_active BOOLEAN DEFAULT 1,
  last_run_at DATETIME,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_custom_reports_user ON custom_reports(user_id);
CREATE INDEX IF NOT EXISTS idx_custom_reports_active ON custom_reports(is_active);

-- Note: No FOREIGN KEY on user_id to allow system templates (user_id = 0)
-- Application-level validation ensures user reports have valid IDs
