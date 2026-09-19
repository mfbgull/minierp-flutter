import Database from 'better-sqlite3';

interface Role {
  id: number;
  role_name: string;
  description: string | null;
  is_system_role: number;
  is_active: number;
  created_at: string;
  updated_at: string;
}

interface RoleWithPermissionCount extends Role {
  permission_count: number;
}

interface Permission {
  id: number;
  permission_name: string;
  module: string;
  action: string;
  description: string;
  assigned?: number;
}

interface CreateRoleDTO {
  role_name: string;
  description?: string;
  permissions?: number[];
}

interface UpdateRoleDTO {
  role_name?: string;
  description?: string;
  is_active?: boolean;
}

function getAll(db: Database.Database): RoleWithPermissionCount[] {
  return db.prepare(`
    SELECT
      r.id, r.role_name, r.description, r.is_system_role, r.is_active,
      r.created_at, r.updated_at,
      COUNT(rp.permission_id) as permission_count
    FROM roles r
    LEFT JOIN role_permissions rp ON r.id = rp.role_id
    GROUP BY r.id
    ORDER BY r.role_name
  `).all() as RoleWithPermissionCount[];
}

function getById(db: Database.Database, id: number): Role | undefined {
  return db.prepare(`
    SELECT id, role_name, description, is_system_role, is_active, created_at, updated_at
    FROM roles WHERE id = ?
  `).get(id) as Role | undefined;
}

function getByName(db: Database.Database, name: string): Role | undefined {
  return db.prepare('SELECT id FROM roles WHERE role_name = ?').get(name) as Role | undefined;
}

function create(db: Database.Database, data: CreateRoleDTO, userId: number): Role {
  const result = db.prepare(`
    INSERT INTO roles (role_name, description, is_system_role, is_active)
    VALUES (?, ?, 0, 1)
  `).run(data.role_name, data.description || null);

  const roleId = result.lastInsertRowid as number;

  if (data.permissions && data.permissions.length > 0) {
    const stmt = db.prepare('INSERT INTO role_permissions (role_id, permission_id) VALUES (?, ?)');
    for (const permId of data.permissions) {
      stmt.run(roleId, permId);
    }
  }

  return getById(db, roleId)!;
}

function update(db: Database.Database, id: number, data: UpdateRoleDTO): Role {
  const existing = getById(db, id);
  if (!existing) throw new Error('Role not found');
  if (existing.is_system_role) throw new Error('Cannot modify system roles');

  if (data.role_name && data.role_name !== existing.role_name) {
    const nameExists = db.prepare('SELECT id FROM roles WHERE role_name = ? AND id != ?').get(data.role_name, id);
    if (nameExists) throw new Error('Role name already exists');
  }

  const updates: string[] = [];
  const values: (string | number)[] = [];

  if (data.role_name) { updates.push('role_name = ?'); values.push(data.role_name); }
  if (data.description !== undefined) { updates.push('description = ?'); values.push(data.description); }
  if (data.is_active !== undefined) { updates.push('is_active = ?'); values.push(data.is_active ? 1 : 0); }

  if (updates.length === 0) throw new Error('No fields to update');

  updates.push('updated_at = CURRENT_TIMESTAMP');
  values.push(id);

  db.prepare(`UPDATE roles SET ${updates.join(', ')} WHERE id = ?`).run(...values);

  return getById(db, id)!;
}

function deleteRole(db: Database.Database, id: number): void {
  const existing = getById(db, id);
  if (!existing) throw new Error('Role not found');
  if (existing.is_system_role) throw new Error('Cannot delete system roles');

  const userCount = db.prepare('SELECT COUNT(*) as count FROM users WHERE role_id = ?').get(id) as { count: number };
  if (userCount.count > 0) {
    throw new Error(`Cannot delete role: ${userCount.count} user(s) have this role. Reassign users first.`);
  }

  db.prepare('DELETE FROM roles WHERE id = ?').run(id);
}

function getPermissionsForRole(db: Database.Database, roleId: number): (Permission & { assigned: number })[] {
  return db.prepare(`
    SELECT
      p.id, p.permission_name, p.module, p.action, p.description,
      CASE WHEN rp.role_id IS NOT NULL THEN 1 ELSE 0 END as assigned
    FROM permissions p
    LEFT JOIN role_permissions rp ON p.id = rp.permission_id AND rp.role_id = ?
    ORDER BY p.module, p.action
  `).all(roleId) as (Permission & { assigned: number })[];
}

function updatePermissions(db: Database.Database, roleId: number, permissionIds: number[]): void {
  const existing = getById(db, roleId);
  if (!existing) throw new Error('Role not found');

  db.transaction(() => {
    db.prepare('DELETE FROM role_permissions WHERE role_id = ?').run(roleId);
    if (permissionIds.length > 0) {
      const stmt = db.prepare('INSERT INTO role_permissions (role_id, permission_id) VALUES (?, ?)');
      for (const permId of permissionIds) {
        stmt.run(roleId, permId);
      }
    }
  })();
}

function getAllPermissions(db: Database.Database): Permission[] {
  return db.prepare(`
    SELECT id, permission_name, module, action, description
    FROM permissions
    ORDER BY module, action
  `).all() as Permission[];
}

export default {
  getAll,
  getById,
  getByName,
  create,
  update,
  delete: deleteRole,
  getPermissionsForRole,
  updatePermissions,
  getAllPermissions,
};
