-- Migration: activity_log:purge permission (audit-remediation task 4.8)
-- Purging the audit trail is a privileged, separately-auditable operation.

INSERT OR IGNORE INTO permissions (permission_name, module, action, description)
VALUES ('activity_log:purge', 'activity_log', 'purge', 'Purge old activity log entries');

INSERT OR IGNORE INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.role_name = 'Admin' AND p.permission_name = 'activity_log:purge';
