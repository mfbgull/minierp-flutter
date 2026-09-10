-- Rollback: Demand forecasts
-- Reverts: add-demand-forecasts.sql

DROP INDEX IF EXISTS idx_demand_forecasts_item;
DROP INDEX IF EXISTS idx_demand_forecasts_date;
DROP TABLE IF EXISTS demand_forecasts;
