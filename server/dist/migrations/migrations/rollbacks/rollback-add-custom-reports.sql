-- Rollback: Remove custom reports table
-- Reverses migration add-custom-reports.sql

DROP TABLE IF EXISTS custom_reports;

-- Indexes are dropped automatically with the table in SQLite
