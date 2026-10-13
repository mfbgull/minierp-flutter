-- D5 / AUTHZ-001: permission codes that guard routes but were never seeded.
--
-- A code that guards a route but is absent from the permissions table cannot be
-- granted to any role, so the route is unreachable for non-admins and the roles
-- screen offers nothing to assign. These 17 codes are seeded so they become
-- grantable through the UI.
--
-- inventory:write is deliberately NOT seeded here: D5 retires it in favour of
-- the already-seeded inventory:update, and the three stockBatches route guards
-- are renamed to match.
--
-- activity_log:purge is deliberately NOT seeded here: add-activity-log-purge-permission.sql
-- already seeds it.
--
-- Grants: D5 says "grant none by default", so no role is handed these codes.
-- The one exception is the Admin role, which seedDefaultPermissions grants every
-- permission to. That grant only fires on a role with no permissions at all, so
-- an existing installation keeps its existing grants and would lose access to
-- these routes; granting Admin explicitly here preserves the invariant that Admin
-- can reach everything.
--
-- Idempotent: safe to re-run on every server start.

INSERT OR IGNORE INTO permissions (permission_name, module, action, description) VALUES
  ('accounting:update',  'accounting',  'update',  'Update chart of accounts and accounting settings'),
  ('admin:read',         'admin',       'read',    'View backups and system administration'),
  ('admin:create',       'admin',       'create',  'Create backups and system administration resources'),
  ('admin:delete',       'admin',       'delete',  'Delete backups and system administration resources'),
  ('dashboard:create',   'dashboard',   'create',  'Create dashboard layouts'),
  ('dashboard:update',   'dashboard',   'update',  'Update dashboard layouts'),
  ('dashboard:delete',   'dashboard',   'delete',  'Delete dashboard layouts'),
  ('expenses:delete',    'expenses',    'delete',  'Delete expenses'),
  ('forecasts:delete',   'forecasts',   'delete',  'Delete demand forecasts'),
  ('invoices:void',      'invoices',    'void',    'Void invoices'),
  ('owner_equity:read',  'owner_equity','read',    'View owner equity accounts'),
  ('owner_equity:create','owner_equity','create',  'Record owner capital and withdrawals'),
  ('owner_equity:edit',  'owner_equity','edit',    'Update owner capital and withdrawals'),
  ('owner_equity:delete','owner_equity','delete',  'Void owner capital and withdrawals'),
  ('reports:create',     'reports',     'create',  'Create custom reports'),
  ('reports:update',     'reports',     'update',  'Update custom reports'),
  ('reports:delete',     'reports',     'delete',  'Delete custom reports');

-- Keep the Admin role able to reach every guarded route.
INSERT OR IGNORE INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
WHERE r.role_name = 'Admin'
  AND p.permission_name IN (
    'accounting:update', 'admin:read', 'admin:create', 'admin:delete',
    'dashboard:create', 'dashboard:update', 'dashboard:delete', 'expenses:delete',
    'forecasts:delete', 'invoices:void', 'owner_equity:read', 'owner_equity:create',
    'owner_equity:edit', 'owner_equity:delete', 'reports:create', 'reports:update',
    'reports:delete'
  );
