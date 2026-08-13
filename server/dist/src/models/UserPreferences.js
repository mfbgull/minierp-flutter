"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getForUser = getForUser;
exports.updateForUser = updateForUser;
function isWeekStart(value) {
    return value === 'monday' || value === 'saturday' || value === 'sunday';
}
/** Fresh server defaults — an absent row means these (spec §6.1 backfill). */
function defaultPreferences() {
    return { weekStart: 'monday', defaultRange: null, presets: [] };
}
/**
 * Parses a stored row defensively — a corrupt JSON blob or an unknown
 * week-start falls back to the default for that field, never throws.
 */
function parseRow(row) {
    let defaultRange = null;
    try {
        const parsed = row.default_range ? JSON.parse(row.default_range) : null;
        if (parsed &&
            typeof parsed === 'object' &&
            typeof parsed.from === 'string' &&
            typeof parsed.to === 'string') {
            defaultRange = { from: parsed.from, to: parsed.to };
        }
    }
    catch {
        /* corrupt → null */
    }
    let presets = [];
    try {
        const parsed = JSON.parse(row.presets);
        if (Array.isArray(parsed)) {
            presets = parsed.filter((p) => p !== null &&
                typeof p === 'object' &&
                typeof p.id === 'string' &&
                typeof p.name === 'string' &&
                typeof p.from === 'string' &&
                typeof p.to === 'string');
        }
    }
    catch {
        /* corrupt → [] */
    }
    return {
        weekStart: isWeekStart(row.week_start) ? row.week_start : 'monday',
        defaultRange,
        presets,
    };
}
/** The current preferences for [userId] — server defaults when no row exists. */
function getForUser(db, userId) {
    const row = db
        .prepare('SELECT week_start, default_range, presets FROM user_preferences WHERE user_id = ?')
        .get(userId);
    return row ? parseRow(row) : defaultPreferences();
}
/**
 * Upserts a partial update for [userId] (single statement = atomic) and
 * returns the merged preferences. Fields not present in [partial] keep
 * their current value.
 */
function updateForUser(db, userId, partial) {
    const current = getForUser(db, userId);
    const next = {
        weekStart: partial.weekStart ?? current.weekStart,
        defaultRange: partial.defaultRange !== undefined ? partial.defaultRange : current.defaultRange,
        presets: partial.presets ?? current.presets,
    };
    db.prepare(`
    INSERT INTO user_preferences (user_id, week_start, default_range, presets, updated_at)
    VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
    ON CONFLICT(user_id) DO UPDATE SET
      week_start = excluded.week_start,
      default_range = excluded.default_range,
      presets = excluded.presets,
      updated_at = CURRENT_TIMESTAMP
  `).run(userId, next.weekStart, next.defaultRange ? JSON.stringify(next.defaultRange) : null, JSON.stringify(next.presets));
    return next;
}
//# sourceMappingURL=UserPreferences.js.map