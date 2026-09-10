-- Rollback: Roles and permissions
-- Reverts: add-roles-permissions.sql

DROP INDEX IF EXISTS idx_permissions_module;
DROP INDEX IF EXISTS idx_role_permissions_permission;
DROP INDEX IF EXISTS idx_role_permissions_role;
DROP INDEX IF EXISTS idx_users_role_id;

ALTER TABLE users DROP COLUMN IF EXISTS role_id;

DROP TABLE IF EXISTS role_permissions;
DROP TABLE IF EXISTS permissions;
DROP TABLE IF EXISTS roles;
