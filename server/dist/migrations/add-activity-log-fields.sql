-- Activity Log Enhancement Migration
-- Adds additional fields for comprehensive activity tracking

-- Add new columns to activity_log table
-- Only run if columns don't exist

-- Check and add log_level column
SELECT COUNT(*) as count FROM pragma_table_info('activity_log')
WHERE name='log_level';

-- If log_level doesn't exist, add it
ALTER TABLE activity_log ADD COLUMN log_level VARCHAR(20) DEFAULT 'INFO';
ALTER TABLE activity_log ADD COLUMN ip_address VARCHAR(45);
ALTER TABLE activity_log ADD COLUMN user_agent TEXT;
ALTER TABLE activity_log ADD COLUMN metadata TEXT; -- JSON field for extra data
ALTER TABLE activity_log ADD COLUMN duration_ms INTEGER; -- Request duration

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_activity_log_timestamp ON activity_log(timestamp);
CREATE INDEX IF NOT EXISTS idx_activity_log_user_timestamp ON activity_log(user_id, timestamp);
CREATE INDEX IF NOT EXISTS idx_activity_log_entity_timestamp ON activity_log(entity_type, entity_id, timestamp);
CREATE INDEX IF NOT EXISTS idx_activity_log_action ON activity_log(action);
