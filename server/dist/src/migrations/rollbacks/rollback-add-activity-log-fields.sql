-- Rollback: Activity log fields
-- Reverts: add-activity-log-fields.sql

ALTER TABLE activity_log DROP COLUMN IF EXISTS log_level;
ALTER TABLE activity_log DROP COLUMN IF EXISTS ip_address;
ALTER TABLE activity_log DROP COLUMN IF EXISTS user_agent;
ALTER TABLE activity_log DROP COLUMN IF EXISTS metadata;
ALTER TABLE activity_log DROP COLUMN IF EXISTS duration_ms;
