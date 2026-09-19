/**
 * CustomReport Model
 * CRUD operations for saved custom report definitions.
 */

import db from '../config/database';

/** System user ID used for shared report templates */
const SYSTEM_USER_ID = 0;

export interface CustomReportRow {
  id: number;
  user_id: number;
  name: string;
  description: string | null;
  config: string; // JSON blob
  is_active: number;
  last_run_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface CreateReportDTO {
  user_id: number;
  name: string;
  description?: string;
  config: object;
}

export interface UpdateReportDTO {
  name?: string;
  description?: string;
  config?: object;
}

// ── CRUD ─────────────────────────────────────────────────────

function findByUser(userId: number): CustomReportRow[] {
  // TODO: Add LIMIT/OFFSET pagination once users have 100+ reports
  return db.prepare(`
    SELECT * FROM custom_reports
    WHERE user_id = ?
    ORDER BY updated_at DESC
  `).all(userId) as CustomReportRow[];
}

function findById(id: number, userId: number): CustomReportRow | undefined {
  return db.prepare(`
    SELECT * FROM custom_reports
    WHERE id = ? AND user_id = ?
  `).get(id, userId) as CustomReportRow | undefined;
}

function create(data: CreateReportDTO): CustomReportRow {
  const result = db.prepare(`
    INSERT INTO custom_reports (user_id, name, description, config)
    VALUES (?, ?, ?, ?)
  `).run(
    data.user_id,
    data.name,
    data.description || null,
    JSON.stringify(data.config)
  );

  return db.prepare('SELECT * FROM custom_reports WHERE id = ?').get(result.lastInsertRowid) as CustomReportRow;
}

function update(id: number, userId: number, data: UpdateReportDTO): boolean {
  const sets: string[] = [];
  const params: any[] = [];

  if (data.name !== undefined) {
    sets.push('name = ?');
    params.push(data.name);
  }
  if (data.description !== undefined) {
    sets.push('description = ?');
    params.push(data.description);
  }
  if (data.config !== undefined) {
    sets.push('config = ?');
    params.push(JSON.stringify(data.config));
  }

  if (sets.length === 0) return false;

  sets.push("updated_at = CURRENT_TIMESTAMP");
  params.push(id, userId);

  const result = db.prepare(`
    UPDATE custom_reports SET ${sets.join(', ')}
    WHERE id = ? AND user_id = ?
  `).run(...params);

  return result.changes > 0;
}

function remove(id: number, userId: number): boolean {
  const result = db.prepare('DELETE FROM custom_reports WHERE id = ? AND user_id = ?').run(id, userId);
  return result.changes > 0;
}

function duplicate(id: number, userId: number): CustomReportRow | null {
  const original = findById(id, userId);
  if (!original) return null;

  // Truncate name with appended ' (Copy)' to stay within VARCHAR(100)
  const suffix = ' (Copy)';
  const maxNameLen = 100;
  let copyName = `${original.name}${suffix}`;
  if (copyName.length > maxNameLen) {
    copyName = `${original.name.slice(0, maxNameLen - suffix.length)}${suffix}`;
  }

  return create({
    user_id: userId,
    name: copyName,
    description: original.description,
    config: JSON.parse(original.config),
  });
}

function markRun(id: number): void {
  db.prepare("UPDATE custom_reports SET last_run_at = CURRENT_TIMESTAMP WHERE id = ?").run(id);
}

function getTemplates(): CustomReportRow[] {
  return db.prepare(`
    SELECT * FROM custom_reports
    WHERE user_id = ?
    ORDER BY name ASC
  `).all(SYSTEM_USER_ID) as CustomReportRow[];
}

function createTemplate(data: { name: string; description?: string; config: object }): CustomReportRow {
  const existing = db.prepare(`
    SELECT id FROM custom_reports
    WHERE user_id = ? AND name = ?
  `).get(SYSTEM_USER_ID, data.name) as { id: number } | undefined;

  if (existing) {
    // Overwrite existing template with same name
    db.prepare(`
      UPDATE custom_reports
      SET config = ?, description = ?, updated_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `).run(JSON.stringify(data.config), data.description || null, existing.id);

    return db.prepare('SELECT * FROM custom_reports WHERE id = ?').get(existing.id) as CustomReportRow;
  }

  return create({
    user_id: SYSTEM_USER_ID,
    name: data.name,
    description: data.description,
    config: data.config,
  });
}

export default {
  findByUser,
  findById,
  create,
  update,
  remove,
  duplicate,
  markRun,
  getTemplates,
  createTemplate,
};
