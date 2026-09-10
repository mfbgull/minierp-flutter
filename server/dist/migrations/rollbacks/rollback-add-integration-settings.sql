-- Rollback: Integration settings
-- Reverts: add-integration-settings.sql

DELETE FROM settings WHERE key LIKE 'integration_%';
DELETE FROM settings WHERE key LIKE 'email_%';
DELETE FROM settings WHERE key LIKE 'sms_%';
