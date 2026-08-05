-- Rollback: Performance indexes
-- Reverts: add-performance-indexes.sql

DROP INDEX IF EXISTS idx_activity_log_user_created_at;
DROP INDEX IF EXISTS idx_activity_log_entity_created_at;
DROP INDEX IF EXISTS idx_activity_log_action;
DROP INDEX IF EXISTS idx_activity_log_log_level;
DROP INDEX IF EXISTS idx_activity_log_created_at;
