"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
class UserModel {
    static findByUsername(username, db) {
        return db.prepare(`
      SELECT id, username, email, password_hash, full_name, role, is_active
      FROM users WHERE username = ? AND is_active = 1
    `).get(username);
    }
    static getById(id, db) {
        return db.prepare(`
      SELECT id, username, email, full_name, role, is_active, created_at
      FROM users WHERE id = ?
    `).get(id);
    }
    static getPasswordHash(id, db) {
        return db.prepare('SELECT id, password_hash FROM users WHERE id = ?').get(id);
    }
    static updatePassword(id, hash, db) {
        db.prepare('UPDATE users SET password_hash = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?').run(hash, id);
    }
    static getAll(filters, db) {
        let query = `SELECT id, username, email, full_name, role, is_active, created_at, updated_at FROM users WHERE 1=1`;
        const params = [];
        if (filters.role) {
            query += ' AND role = ?';
            params.push(filters.role);
        }
        if (filters.is_active !== undefined) {
            query += ' AND is_active = ?';
            params.push(parseInt(filters.is_active, 10));
        }
        if (filters.search) {
            const term = `%${filters.search}%`;
            query += ' AND (username LIKE ? OR email LIKE ? OR full_name LIKE ?)';
            params.push(term, term, term);
        }
        query += ' ORDER BY created_at DESC';
        return db.prepare(query).all(...params);
    }
    static getPublicById(id, db) {
        return db.prepare(`
      SELECT id, username, email, full_name, role, is_active, created_at, updated_at
      FROM users WHERE id = ?
    `).get(id);
    }
    static create(db, data) {
        const result = db.prepare(`
      INSERT INTO users (username, email, password_hash, full_name, role_id, is_active)
      VALUES (?, ?, ?, ?, ?, ?)
    `).run(data.username, data.email, data.password_hash, data.full_name, data.role_id, data.is_active ? 1 : 0);
        return result.lastInsertRowid;
    }
    static update(db, id, data) {
        const updates = [];
        const values = [];
        if (data.username) {
            updates.push('username = ?');
            values.push(data.username);
        }
        if (data.email) {
            updates.push('email = ?');
            values.push(data.email);
        }
        if (data.full_name) {
            updates.push('full_name = ?');
            values.push(data.full_name);
        }
        if (data.role_id) {
            updates.push('role_id = ?');
            values.push(data.role_id);
        }
        if (data.is_active !== undefined) {
            updates.push('is_active = ?');
            values.push(data.is_active ? 1 : 0);
        }
        if (updates.length === 0)
            throw new Error('No fields to update');
        updates.push('updated_at = CURRENT_TIMESTAMP');
        values.push(id);
        db.prepare(`UPDATE users SET ${updates.join(', ')} WHERE id = ?`).run(...values);
    }
    static softDelete(db, id) {
        db.prepare('UPDATE users SET is_active = 0, updated_at = CURRENT_TIMESTAMP WHERE id = ?').run(id);
    }
    static usernameExists(db, username, excludeId) {
        const query = excludeId
            ? 'SELECT id FROM users WHERE username = ? AND id != ?'
            : 'SELECT id FROM users WHERE username = ?';
        return !!db.prepare(query).get(username, ...(excludeId ? [excludeId] : []));
    }
    static emailExists(db, email, excludeId) {
        const query = excludeId
            ? 'SELECT id FROM users WHERE email = ? AND id != ?'
            : 'SELECT id FROM users WHERE email = ?';
        return !!db.prepare(query).get(email, ...(excludeId ? [excludeId] : []));
    }
    static roleExists(db, roleId) {
        return !!db.prepare('SELECT id FROM roles WHERE id = ?').get(roleId);
    }
    static getAdminCount(db) {
        const result = db.prepare('SELECT COUNT(*) as count FROM users WHERE role = ? AND is_active = 1').get('admin');
        return result.count;
    }
    static getRoleName(db, roleId) {
        const result = db.prepare('SELECT role_name FROM roles WHERE id = ?').get(roleId);
        return result.role_name;
    }
    static getRoleId(db, userId) {
        const result = db.prepare('SELECT role_id FROM users WHERE id = ?').get(userId);
        return result.role_id;
    }
}
exports.default = UserModel;
//# sourceMappingURL=User.js.map