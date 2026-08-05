"use strict";
/**
 * CustomReport Model
 * CRUD operations for saved custom report definitions.
 */
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const database_1 = __importDefault(require("../config/database"));
/** System user ID used for shared report templates */
const SYSTEM_USER_ID = 0;
// ── CRUD ─────────────────────────────────────────────────────
function findByUser(userId) {
    // TODO: Add LIMIT/OFFSET pagination once users have 100+ reports
    return database_1.default.prepare(`
    SELECT * FROM custom_reports
    WHERE user_id = ?
    ORDER BY updated_at DESC
  `).all(userId);
}
function findById(id, userId) {
    return database_1.default.prepare(`
    SELECT * FROM custom_reports
    WHERE id = ? AND user_id = ?
  `).get(id, userId);
}
function create(data) {
    const result = database_1.default.prepare(`
    INSERT INTO custom_reports (user_id, name, description, config)
    VALUES (?, ?, ?, ?)
  `).run(data.user_id, data.name, data.description || null, JSON.stringify(data.config));
    return database_1.default.prepare('SELECT * FROM custom_reports WHERE id = ?').get(result.lastInsertRowid);
}
function update(id, userId, data) {
    const sets = [];
    const params = [];
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
    if (sets.length === 0)
        return false;
    sets.push("updated_at = CURRENT_TIMESTAMP");
    params.push(id, userId);
    const result = database_1.default.prepare(`
    UPDATE custom_reports SET ${sets.join(', ')}
    WHERE id = ? AND user_id = ?
  `).run(...params);
    return result.changes > 0;
}
function remove(id, userId) {
    const result = database_1.default.prepare('DELETE FROM custom_reports WHERE id = ? AND user_id = ?').run(id, userId);
    return result.changes > 0;
}
function duplicate(id, userId) {
    const original = findById(id, userId);
    if (!original)
        return null;
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
function markRun(id) {
    database_1.default.prepare("UPDATE custom_reports SET last_run_at = CURRENT_TIMESTAMP WHERE id = ?").run(id);
}
function getTemplates() {
    return database_1.default.prepare(`
    SELECT * FROM custom_reports
    WHERE user_id = ?
    ORDER BY name ASC
  `).all(SYSTEM_USER_ID);
}
function createTemplate(data) {
    const existing = database_1.default.prepare(`
    SELECT id FROM custom_reports
    WHERE user_id = ? AND name = ?
  `).get(SYSTEM_USER_ID, data.name);
    if (existing) {
        // Overwrite existing template with same name
        database_1.default.prepare(`
      UPDATE custom_reports
      SET config = ?, description = ?, updated_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `).run(JSON.stringify(data.config), data.description || null, existing.id);
        return database_1.default.prepare('SELECT * FROM custom_reports WHERE id = ?').get(existing.id);
    }
    return create({
        user_id: SYSTEM_USER_ID,
        name: data.name,
        description: data.description,
        config: data.config,
    });
}
exports.default = {
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
//# sourceMappingURL=CustomReport.js.map