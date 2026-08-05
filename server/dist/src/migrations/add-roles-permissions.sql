-- ============================================
-- Roles and Permissions Schema
-- ============================================

-- Roles table (replaces simple role string in users)
CREATE TABLE IF NOT EXISTS roles (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    role_name VARCHAR(50) UNIQUE NOT NULL,
    description TEXT,
    is_system_role BOOLEAN DEFAULT 0, -- System roles (Admin, User) cannot be deleted
    is_active BOOLEAN DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Permissions table
CREATE TABLE IF NOT EXISTS permissions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    permission_name VARCHAR(100) UNIQUE NOT NULL,
    module VARCHAR(50) NOT NULL, -- e.g., 'users', 'inventory', 'sales', 'purchases', etc.
    action VARCHAR(20) NOT NULL, -- 'read', 'create', 'update', 'delete', 'approve', etc.
    description TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Role-Permission mapping table
CREATE TABLE IF NOT EXISTS role_permissions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    role_id INTEGER NOT NULL,
    permission_id INTEGER NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE,
    FOREIGN KEY (permission_id) REFERENCES permissions(id) ON DELETE CASCADE,
    UNIQUE(role_id, permission_id)
);

-- Update users table to use role_id instead of role string
ALTER TABLE users ADD COLUMN role_id INTEGER REFERENCES roles(id);

-- Migrate existing role strings to role_id
-- First, create default roles
INSERT OR IGNORE INTO roles (role_name, description, is_system_role, is_active) 
VALUES 
    ('Admin', 'System administrator with full access to all modules', 1, 1),
    ('User', 'Standard user with limited access', 1, 1);

-- Update users to use role_id based on their current role string
UPDATE users SET role_id = (SELECT id FROM roles WHERE role_name = 'Admin') WHERE role = 'admin';
UPDATE users SET role_id = (SELECT id FROM roles WHERE role_name = 'User') WHERE role = 'user';

-- Set role_id to Admin for any users without a role_id (fallback)
UPDATE users SET role_id = (SELECT id FROM roles WHERE role_name = 'Admin') WHERE role_id IS NULL;

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_users_role_id ON users(role_id);
CREATE INDEX IF NOT EXISTS idx_role_permissions_role ON role_permissions(role_id);
CREATE INDEX IF NOT EXISTS idx_role_permissions_permission ON role_permissions(permission_id);
CREATE INDEX IF NOT EXISTS idx_permissions_module ON permissions(module);
