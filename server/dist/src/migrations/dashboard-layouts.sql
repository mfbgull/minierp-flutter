-- Migration: Dashboard layouts — per-user customizable dashboard block layouts
-- Created: 2026-06-24
--
-- This table stores user-defined dashboard layouts. Each user can have multiple
-- named layouts, with exactly one active at a time. The `blocks` column stores
-- a JSON array of DashboardBlock configurations (block type, position, size,
-- visibility, and block-specific config).

CREATE TABLE IF NOT EXISTS dashboard_layouts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  layout_name TEXT DEFAULT 'Default',
  blocks TEXT NOT NULL DEFAULT '[]',
  is_active INTEGER DEFAULT 1,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  UNIQUE(user_id, layout_name)
);

CREATE INDEX IF NOT EXISTS idx_dashboard_layouts_user_id ON dashboard_layouts(user_id);
CREATE INDEX IF NOT EXISTS idx_dashboard_layouts_active ON dashboard_layouts(is_active);
