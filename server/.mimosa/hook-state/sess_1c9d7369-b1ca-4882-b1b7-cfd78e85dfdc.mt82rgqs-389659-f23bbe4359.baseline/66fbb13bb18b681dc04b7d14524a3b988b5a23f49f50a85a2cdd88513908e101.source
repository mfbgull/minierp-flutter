import Database from 'better-sqlite3';

interface UserRecord {
  id: number;
  username: string;
  email: string;
  password_hash: string;
  full_name?: string;
  role: string;
  is_active: number;
  created_at?: string;
}

interface UserPublic {
  id: number;
  username: string;
  email: string;
  full_name: string;
  role: string;
  is_active: number;
  created_at: string;
  updated_at: string;
}

interface UserFilters {
  role?: string;
  is_active?: string;
  search?: string;
}

interface CreateUserDTO {
  username: string;
  email: string;
  password_hash: string;
  full_name: string;
  role_id: number;
  is_active: boolean;
}

interface UpdateUserDTO {
  username?: string;
  email?: string;
  full_name?: string;
  role_id?: number;
  is_active?: boolean;
}

class UserModel {
  static findByUsername(username: string, db: Database.Database): Omit<UserRecord, 'password_hash'> & { password_hash?: string } | undefined {
    return db.prepare(`
      SELECT id, username, email, password_hash, full_name, role, is_active
      FROM users WHERE username = ? AND is_active = 1
    `).get(username) as UserRecord | undefined;
  }

  static getById(id: number, db: Database.Database): Omit<UserRecord, 'password_hash'> | undefined {
    return db.prepare(`
      SELECT id, username, email, full_name, role, is_active, created_at
      FROM users WHERE id = ?
    `).get(id) as Omit<UserRecord, 'password_hash'> | undefined;
  }

  static getPasswordHash(id: number, db: Database.Database): { id: number; password_hash: string } | undefined {
    return db.prepare('SELECT id, password_hash FROM users WHERE id = ?').get(id) as { id: number; password_hash: string } | undefined;
  }

  static updatePassword(id: number, hash: string, db: Database.Database): void {
    db.prepare('UPDATE users SET password_hash = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?').run(hash, id);
  }

  static getAll(filters: UserFilters, db: Database.Database): UserPublic[] {
    let query = `SELECT id, username, email, full_name, role, is_active, created_at, updated_at FROM users WHERE 1=1`;
    const params: (string | number)[] = [];

    if (filters.role) { query += ' AND role = ?'; params.push(filters.role); }
    if (filters.is_active !== undefined) { query += ' AND is_active = ?'; params.push(parseInt(filters.is_active, 10)); }
    if (filters.search) {
      const term = `%${filters.search}%`;
      query += ' AND (username LIKE ? OR email LIKE ? OR full_name LIKE ?)';
      params.push(term, term, term);
    }

    query += ' ORDER BY created_at DESC';
    return db.prepare(query).all(...params) as UserPublic[];
  }

  static getPublicById(id: number, db: Database.Database): UserPublic | undefined {
    return db.prepare(`
      SELECT id, username, email, full_name, role, is_active, created_at, updated_at
      FROM users WHERE id = ?
    `).get(id) as UserPublic | undefined;
  }

  static create(db: Database.Database, data: CreateUserDTO): number {
    const result = db.prepare(`
      INSERT INTO users (username, email, password_hash, full_name, role_id, is_active)
      VALUES (?, ?, ?, ?, ?, ?)
    `).run(data.username, data.email, data.password_hash, data.full_name, data.role_id, data.is_active ? 1 : 0);
    return result.lastInsertRowid as number;
  }

  static update(db: Database.Database, id: number, data: UpdateUserDTO): void {
    const updates: string[] = [];
    const values: (string | number)[] = [];

    if (data.username) { updates.push('username = ?'); values.push(data.username); }
    if (data.email) { updates.push('email = ?'); values.push(data.email); }
    if (data.full_name) { updates.push('full_name = ?'); values.push(data.full_name); }
    if (data.role_id) { updates.push('role_id = ?'); values.push(data.role_id); }
    if (data.is_active !== undefined) { updates.push('is_active = ?'); values.push(data.is_active ? 1 : 0); }

    if (updates.length === 0) throw new Error('No fields to update');

    updates.push('updated_at = CURRENT_TIMESTAMP');
    values.push(id);

    db.prepare(`UPDATE users SET ${updates.join(', ')} WHERE id = ?`).run(...values);
  }

  static softDelete(db: Database.Database, id: number): void {
    db.prepare('UPDATE users SET is_active = 0, updated_at = CURRENT_TIMESTAMP WHERE id = ?').run(id);
  }

  static usernameExists(db: Database.Database, username: string, excludeId?: number): boolean {
    const query = excludeId
      ? 'SELECT id FROM users WHERE username = ? AND id != ?'
      : 'SELECT id FROM users WHERE username = ?';
    return !!db.prepare(query).get(username, ...(excludeId ? [excludeId] : []));
  }

  static emailExists(db: Database.Database, email: string, excludeId?: number): boolean {
    const query = excludeId
      ? 'SELECT id FROM users WHERE email = ? AND id != ?'
      : 'SELECT id FROM users WHERE email = ?';
    return !!db.prepare(query).get(email, ...(excludeId ? [excludeId] : []));
  }

  static roleExists(db: Database.Database, roleId: number): boolean {
    return !!db.prepare('SELECT id FROM roles WHERE id = ?').get(roleId);
  }

  static getAdminCount(db: Database.Database): number {
    const result = db.prepare('SELECT COUNT(*) as count FROM users WHERE role = ? AND is_active = 1').get('admin') as { count: number };
    return result.count;
  }

  static getRoleName(db: Database.Database, roleId: number): string {
    const result = db.prepare('SELECT role_name FROM roles WHERE id = ?').get(roleId) as { role_name: string };
    return result.role_name;
  }

  static getRoleId(db: Database.Database, userId: number): number {
    const result = db.prepare('SELECT role_id FROM users WHERE id = ?').get(userId) as { role_id: number };
    return result.role_id;
  }
}

export default UserModel;
