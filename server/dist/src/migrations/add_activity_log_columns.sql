-- Migration to add missing columns to activity_log table
-- These columns are expected by the ActivityLogModel but were missing from the original schema

-- Add missing columns if they don't exist
ALTER TABLE activity_log ADD COLUMN log_level VARCHAR(20) DEFAULT 'INFO';
ALTER TABLE activity_log ADD COLUMN ip_address VARCHAR(45);
ALTER TABLE activity_log ADD COLUMN user_agent TEXT;
ALTER TABLE activity_log ADD COLUMN metadata TEXT;
ALTER TABLE activity_log ADD COLUMN duration_ms INTEGER;

-- Add indexes for better performance
CREATE INDEX IF NOT EXISTS idx_activity_log_created_at ON activity_log(created_at);
CREATE INDEX IF NOT EXISTS idx_activity_log_action ON activity_log(action);
CREATE INDEX IF NOT EXISTS idx_activity_log_log_level ON activity_log(log_level);