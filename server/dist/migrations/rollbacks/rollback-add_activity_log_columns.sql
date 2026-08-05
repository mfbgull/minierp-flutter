-- Rollback: Activity log columns
-- Reverts: add_activity_log_columns.sql

DROP INDEX IF EXISTS idx_activity_log_log_level;
DROP INDEX IF EXISTS idx_activity_log_action;
DROP INDEX IF EXISTS idx_activity_log_created_at;

ALTER TABLE activity_log DROP COLUMN IF EXISTS log_level;
ALTER TABLE activity_log DROP COLUMN IF EXISTS ip_address;
ALTER TABLE activity_log DROP COLUMN IF EXISTS user_agent;
ALTER TABLE activity_log DROP COLUMN IF EXISTS metadata;
ALTER TABLE activity_log DROP COLUMN IF EXISTS duration_ms;
