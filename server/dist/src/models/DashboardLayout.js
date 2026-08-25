"use strict";
/**
 * DashboardLayout Model
 * CRUD operations for per-user customizable dashboard layouts.
 *
 * Each user can have multiple named layouts. Exactly one layout can be active
 * (is_active = 1) per user. The `blocks` column stores a JSON array of
 * DashboardBlock configurations.
 *
 * @see dashboard-customization-spec.md §4 — Data Model
 */
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const database_1 = __importDefault(require("../config/database"));
// ═══════════════════════════════════════════════════════════════
//  HELPERS
// ═══════════════════════════════════════════════════════════════
/** Parse a raw DB row into a typed DashboardLayout object */
function parseRow(row) {
    return {
        ...row,
        blocks: JSON.parse(row.blocks),
        is_active: row.is_active === 1,
    };
}
// ═══════════════════════════════════════════════════════════════
//  CRUD
// ═══════════════════════════════════════════════════════════════
/**
 * Get the active layout for a user.
 * Returns null if the user has no saved layout.
 */
function getActiveLayout(userId) {
    const row = database_1.default.prepare(`
    SELECT * FROM dashboard_layouts
    WHERE user_id = ? AND is_active = 1
    ORDER BY updated_at DESC
    LIMIT 1
  `).get(userId);
    if (!row)
        return null;
    return parseRow(row);
}
/**
 * Get a layout by ID, scoped to the given user.
 */
function getLayoutById(id, userId) {
    const row = database_1.default.prepare(`
    SELECT * FROM dashboard_layouts
    WHERE id = ? AND user_id = ?
  `).get(id, userId);
    if (!row)
        return null;
    return parseRow(row);
}
/**
 * Create a new layout for a user.
 * If `is_active` is true (default), any other active layouts for this user
 * are deactivated first.
 */
function createLayout(data, isActive = true) {
    if (isActive) {
        deactivateAll(data.user_id);
    }
    const result = database_1.default.prepare(`
    INSERT INTO dashboard_layouts (user_id, layout_name, blocks, is_active)
    VALUES (?, ?, ?, ?)
  `).run(data.user_id, data.layout_name, JSON.stringify(data.blocks), isActive ? 1 : 0);
    const row = database_1.default.prepare('SELECT * FROM dashboard_layouts WHERE id = ?')
        .get(result.lastInsertRowid);
    return parseRow(row);
}
/**
 * Update an existing layout's blocks and/or name.
 * Always updates `updated_at`.
 * Returns true if a row was updated.
 */
function updateLayout(id, userId, data) {
    const sets = [];
    const params = [];
    if (data.blocks !== undefined) {
        sets.push('blocks = ?');
        params.push(JSON.stringify(data.blocks));
    }
    if (data.layout_name !== undefined) {
        sets.push('layout_name = ?');
        params.push(data.layout_name);
    }
    if (sets.length === 0)
        return false;
    sets.push("updated_at = datetime('now')");
    params.push(id, userId);
    const result = database_1.default.prepare(`
    UPDATE dashboard_layouts SET ${sets.join(', ')}
    WHERE id = ? AND user_id = ?
  `).run(...params);
    return result.changes > 0;
}
/**
 * Rename a layout. Convenience wrapper around updateLayout.
 */
function renameLayout(id, userId, name) {
    return updateLayout(id, userId, { layout_name: name });
}
/**
 * Delete a layout by ID, scoped to the given user.
 * Returns true if a row was deleted.
 */
function deleteLayout(id, userId) {
    const result = database_1.default.prepare('DELETE FROM dashboard_layouts WHERE id = ? AND user_id = ?')
        .run(id, userId);
    return result.changes > 0;
}
/**
 * List all layouts for a user, ordered by most recently updated first.
 */
function listLayouts(userId) {
    const rows = database_1.default.prepare(`
    SELECT * FROM dashboard_layouts
    WHERE user_id = ?
    ORDER BY updated_at DESC
  `).all(userId);
    return rows.map(parseRow);
}
/**
 * Set a layout as the active layout for a user.
 * This deactivates all other layouts and activates the specified one.
 * Returns true if the layout was found and updated.
 */
function setActiveLayout(id, userId) {
    // First check the layout belongs to this user
    const layout = database_1.default.prepare('SELECT id FROM dashboard_layouts WHERE id = ? AND user_id = ?')
        .get(id, userId);
    if (!layout)
        return false;
    // Deactivate all layouts for this user
    database_1.default.prepare('UPDATE dashboard_layouts SET is_active = 0, updated_at = datetime(\'now\') WHERE user_id = ?')
        .run(userId);
    // Activate the target layout
    database_1.default.prepare('UPDATE dashboard_layouts SET is_active = 1, updated_at = datetime(\'now\') WHERE id = ?')
        .run(id);
    return true;
}
/**
 * Deactivate all layouts for a user (used internally before setting a new active one).
 */
function deactivateAll(userId) {
    database_1.default.prepare("UPDATE dashboard_layouts SET is_active = 0 WHERE user_id = ?")
        .run(userId);
}
/**
 * Duplicate a layout with "(Copy)" appended to the name.
 * Returns the new layout or null if the original was not found.
 */
function duplicateLayout(id, userId) {
    const original = getLayoutById(id, userId);
    if (!original)
        return null;
    const suffix = ' (Copy)';
    const maxNameLen = 100;
    let copyName = `${original.layout_name}${suffix}`;
    if (copyName.length > maxNameLen) {
        copyName = `${original.layout_name.slice(0, maxNameLen - suffix.length)}${suffix}`;
    }
    return createLayout({
        user_id: userId,
        layout_name: copyName,
        blocks: original.blocks,
    }, false); // Duplicated layouts are not automatically active
}
exports.default = {
    getActiveLayout,
    getLayoutById,
    createLayout,
    updateLayout,
    renameLayout,
    deleteLayout,
    listLayouts,
    setActiveLayout,
    duplicateLayout,
};
