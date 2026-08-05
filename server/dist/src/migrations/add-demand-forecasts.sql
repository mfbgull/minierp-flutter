-- Migration: Add demand_forecasts table
-- Created: 2026-03-14

CREATE TABLE IF NOT EXISTS demand_forecasts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  item_id INTEGER NOT NULL,
  forecast_date DATE NOT NULL,
  period TEXT NOT NULL CHECK(period IN ('next_week', 'next_month', 'next_quarter')),
  predicted_quantity REAL NOT NULL,
  confidence_level REAL DEFAULT 0,
  trend_direction TEXT DEFAULT 'stable' CHECK(trend_direction IN ('growing', 'stable', 'declining')),
  trend_percentage REAL DEFAULT 0,
  model_type TEXT DEFAULT 'weighted_moving_average',
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (item_id) REFERENCES items(id)
);

CREATE INDEX IF NOT EXISTS idx_forecasts_item_date ON demand_forecasts(item_id, forecast_date);
CREATE INDEX IF NOT EXISTS idx_forecasts_item_period ON demand_forecasts(item_id, period);
