-- Rollback: Enhance forecasts
-- Reverts: enhance-forecasts.sql

-- Drop new tables (order matters for FK constraints)
DROP TABLE IF EXISTS forecast_accuracy;
DROP TABLE IF EXISTS forecast_seasonal_events;
DROP TABLE IF EXISTS forecast_model_config;
DROP TABLE IF EXISTS forecast_runs;

-- Revert demand_forecasts column additions
-- SQLite doesn't support DROP COLUMN in older versions, 
-- but we can ignore the extra columns (they won't break anything)
-- The app code will handle the columns being present but unused
