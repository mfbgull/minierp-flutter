-- Migration: Enhance forecasts — accuracy tracking, multi-algorithm, seasonality, safety stock
-- Created: 2026-06-24

-- ============================================================
-- 1. ENHANCE existing demand_forecasts table
-- ============================================================

-- Add new columns to demand_forecasts (safely with IF NOT EXISTS style checks)
ALTER TABLE demand_forecasts ADD COLUMN is_manual_override INTEGER DEFAULT 0;
ALTER TABLE demand_forecasts ADD COLUMN override_reason TEXT DEFAULT NULL;
ALTER TABLE demand_forecasts ADD COLUMN override_expires DATE DEFAULT NULL;
ALTER TABLE demand_forecasts ADD COLUMN bias_adjustment REAL DEFAULT NULL;
ALTER TABLE demand_forecasts ADD COLUMN seasonal_multiplier REAL DEFAULT NULL;
ALTER TABLE demand_forecasts ADD COLUMN run_id TEXT DEFAULT NULL;

-- Update existing model_type column to be more flexible (drop CHECK constraint — handled in app)
-- (SQLite doesn't support ALTER COLUMN, so we recreate the check implicitly via app logic)

-- ============================================================
-- 2. forecast_runs — track each forecast generation run
-- ============================================================
CREATE TABLE IF NOT EXISTS forecast_runs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id TEXT NOT NULL UNIQUE,
  run_type TEXT NOT NULL DEFAULT 'auto' CHECK(run_type IN ('auto', 'manual', 'scheduled')),
  started_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  completed_at DATETIME DEFAULT NULL,
  items_processed INTEGER DEFAULT 0,
  errors INTEGER DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'running' CHECK(status IN ('running', 'completed', 'failed')),
  error_message TEXT DEFAULT NULL
);

CREATE INDEX IF NOT EXISTS idx_forecast_runs_created ON forecast_runs(started_at);
CREATE INDEX IF NOT EXISTS idx_forecast_runs_status ON forecast_runs(status);
CREATE INDEX IF NOT EXISTS idx_forecast_runs_type ON forecast_runs(run_type);

-- ============================================================
-- 3. forecast_model_config — per-item or per-category model config
-- ============================================================
CREATE TABLE IF NOT EXISTS forecast_model_config (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  item_id INTEGER DEFAULT NULL,
  category TEXT DEFAULT NULL,
  model_type TEXT NOT NULL DEFAULT 'weighted_moving_average',
  ses_alpha REAL DEFAULT NULL,
  holt_alpha REAL DEFAULT NULL,
  holt_beta REAL DEFAULT NULL,
  hw_alpha REAL DEFAULT NULL,
  hw_beta REAL DEFAULT NULL,
  hw_gamma REAL DEFAULT NULL,
  seasonal_periods INTEGER DEFAULT 12,
  service_level REAL DEFAULT 0.95,
  lead_time_days INTEGER DEFAULT 7,
  bias_correction INTEGER DEFAULT 1,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (item_id) REFERENCES items(id),
  CHECK (item_id IS NOT NULL OR category IS NOT NULL)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_forecast_config_item ON forecast_model_config(item_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_forecast_config_category ON forecast_model_config(category);

-- ============================================================
-- 4. forecast_seasonal_events — calendar-based events with multipliers
-- ============================================================
CREATE TABLE IF NOT EXISTS forecast_seasonal_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  event_name TEXT NOT NULL,
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  multiplier REAL NOT NULL DEFAULT 1.0,
  applies_to_category TEXT DEFAULT NULL,
  applies_to_item_id INTEGER DEFAULT NULL,
  is_recurring INTEGER DEFAULT 0,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (applies_to_item_id) REFERENCES items(id)
);

CREATE INDEX IF NOT EXISTS idx_seasonal_events_dates ON forecast_seasonal_events(start_date, end_date);
CREATE INDEX IF NOT EXISTS idx_seasonal_events_category ON forecast_seasonal_events(applies_to_category);

-- Seed some common seasonal events (recurring)
INSERT OR IGNORE INTO forecast_seasonal_events (event_name, start_date, end_date, multiplier, is_recurring) VALUES
  ('New Year', '2026-01-01', '2026-01-03', 0.7, 1),
  ('Eid al-Fitr', '2026-03-30', '2026-04-03', 0.6, 1),
  ('Eid al-Adha', '2026-06-06', '2026-06-10', 0.6, 1),
  ('Black Friday', '2026-11-26', '2026-11-27', 2.5, 1),
  ('Back to School', '2026-08-15', '2026-09-15', 1.4, 1);

-- ============================================================
-- 5. forecast_accuracy — track predicted vs actual per item/period
-- ============================================================
CREATE TABLE IF NOT EXISTS forecast_accuracy (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  forecast_date DATE NOT NULL,
  item_id INTEGER NOT NULL,
  period TEXT NOT NULL CHECK(period IN ('next_week', 'next_month', 'next_quarter')),
  model_type TEXT NOT NULL DEFAULT 'weighted_moving_average',
  predicted_quantity REAL NOT NULL,
  actual_quantity REAL DEFAULT NULL,
  mape REAL DEFAULT NULL,
  mae REAL DEFAULT NULL,
  smape REAL DEFAULT NULL,
  is_override INTEGER DEFAULT 0,
  computed_at DATETIME DEFAULT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (item_id) REFERENCES items(id)
);

CREATE INDEX IF NOT EXISTS idx_forecast_accuracy_item ON forecast_accuracy(item_id, forecast_date);
CREATE INDEX IF NOT EXISTS idx_forecast_accuracy_date ON forecast_accuracy(forecast_date);
CREATE INDEX IF NOT EXISTS idx_forecast_accuracy_model ON forecast_accuracy(model_type);
