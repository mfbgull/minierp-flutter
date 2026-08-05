"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
function getAll(db) {
    return db.prepare(`
    SELECT
      r.id, r.role_name, r.description, r.is_system_role, r.is_active,
      r.created_at, r.updated_at,
      COUNT(rp.permission_id) as permission_count
    FROM roles r
    LEFT JOIN role_permissions rp ON r.id = rp.role_id
    GROUP BY r.id
    ORDER BY r.role_name
  `).all();
}
function getById(db, id) {
    return db.prepare(`
    SELECT id, role_name, description, is_system_role, is_active, created_at, updated_at
    FROM roles WHERE id = ?
  `).get(id);
}
function getByName(db, name) {
    return db.prepare('SELECT id FROM roles WHERE role_name = ?').get(name);
}
function create(db, data, userId) {
    const result = db.prepare(`
    INSERT INTO roles (role_name, description, is_system_role, is_active)
    VALUES (?, ?, 0, 1)
  `).run(data.role_name, data.description || null);
    const roleId = result.lastInsertRowid;
    if (data.permissions && data.permissions.length > 0) {
        const stmt = db.prepare('INSERT INTO role_permissions (role_id, permission_id) VALUES (?, ?)');
        for (const permId of data.permissions) {
            stmt.run(roleId, permId);
        }
    }
    return getById(db, roleId);
}
function update(db, id, data) {
    const existing = getById(db, id);
    if (!existing)
        throw new Error('Role not found');
    if (existing.is_system_role)
        throw new Error('Cannot modify system roles');
    if (data.role_name && data.role_name !== existing.role_name) {
        const nameExists = db.prepare('SELECT id FROM roles WHERE role_name = ? AND id != ?').get(data.role_name, id);
        if (nameExists)
            throw new Error('Role name already exists');
    }
    const updates = [];
    const values = [];
    if (data.role_name) {
        updates.push('role_name = ?');
        values.push(data.role_name);
    }
    if (data.description !== undefined) {
        updates.push('description = ?');
        values.push(data.description);
    }
    if (data.is_active !== undefined) {
        updates.push('is_active = ?');
        values.push(data.is_active ? 1 : 0);
    }
    if (updates.length === 0)
        throw new Error('No fields to update');
    updates.push('updated_at = CURRENT_TIMESTAMP');
    values.push(id);
    db.prepare(`UPDATE roles SET ${updates.join(', ')} WHERE id = ?`).run(...values);
    return getById(db, id);
}
function deleteRole(db, id) {
    const existing = getById(db, id);
    if (!existing)
        throw new Error('Role not found');
    if (existing.is_system_role)
        throw new Error('Cannot delete system roles');
    const userCount = db.prepare('SELECT COUNT(*) as count FROM users WHERE role_id = ?').get(id);
    if (userCount.count > 0) {
        throw new Error(`Cannot delete role: ${userCount.count} user(s) have this role. Reassign users first.`);
    }
    db.prepare('DELETE FROM roles WHERE id = ?').run(id);
}
function getPermissionsForRole(db, roleId) {
    return db.prepare(`
    SELECT
      p.id, p.permission_name, p.module, p.action, p.description,
      CASE WHEN rp.role_id IS NOT NULL THEN 1 ELSE 0 END as assigned
    FROM permissions p
    LEFT JOIN role_permissions rp ON p.id = rp.permission_id AND rp.role_id = ?
    ORDER BY p.module, p.action
  `).all(roleId);
}
function updatePermissions(db, roleId, permissionIds) {
    const existing = getById(db, roleId);
    if (!existing)
        throw new Error('Role not found');
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
function getAllPermissions(db) {
    return db.prepare(`
    SELECT id, permission_name, module, action, description
    FROM permissions
    ORDER BY module, action
  `).all();
}
exports.default = {
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
//# sourceMappingURL=Role.js.map