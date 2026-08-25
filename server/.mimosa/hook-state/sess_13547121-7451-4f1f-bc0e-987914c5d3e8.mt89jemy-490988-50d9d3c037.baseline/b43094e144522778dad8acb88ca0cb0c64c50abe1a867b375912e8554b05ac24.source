import Database from 'better-sqlite3';

/** Week-start day for the date-range picker (spec §4.5). */
export type WeekStart = 'monday' | 'saturday' | 'sunday';

/** One user-defined named preset (spec §6.2). */
export interface UserPreset {
  id: string;
  name: string;
  from: string; // YYYY-MM-DD
  to: string; // YYYY-MM-DD
}

export interface DateRangeInput {
  from: string;
  to: string;
}

/** The stored per-user preference set (camelCase — the API shape). */
export interface UserPreferences {
  weekStart: WeekStart;
  defaultRange: DateRangeInput | null;
  presets: UserPreset[];
}

interface PreferencesRow {
  week_start: string;
  default_range: string | null;
  presets: string;
}

function isWeekStart(value: unknown): value is WeekStart {
  return value === 'monday' || value === 'saturday' || value === 'sunday';
}

/** Fresh server defaults — an absent row means these (spec §6.1 backfill). */
function defaultPreferences(): UserPreferences {
  return { weekStart: 'monday', defaultRange: null, presets: [] };
}

/**
 * Parses a stored row defensively — a corrupt JSON blob or an unknown
 * week-start falls back to the default for that field, never throws.
 */
function parseRow(row: PreferencesRow): UserPreferences {
  let defaultRange: UserPreferences['defaultRange'] = null;
  try {
    const parsed = row.default_range ? JSON.parse(row.default_range) : null;
    if (
      parsed &&
      typeof parsed === 'object' &&
      typeof parsed.from === 'string' &&
      typeof parsed.to === 'string'
    ) {
      defaultRange = { from: parsed.from, to: parsed.to };
    }
  } catch {
    /* corrupt → null */
  }

  let presets: UserPreset[] = [];
  try {
    const parsed = JSON.parse(row.presets);
    if (Array.isArray(parsed)) {
      presets = parsed.filter(
        (p): p is UserPreset =>
          p !== null &&
          typeof p === 'object' &&
          typeof (p as Record<string, unknown>).id === 'string' &&
          typeof (p as Record<string, unknown>).name === 'string' &&
          typeof (p as Record<string, unknown>).from === 'string' &&
          typeof (p as Record<string, unknown>).to === 'string',
      );
    }
  } catch {
    /* corrupt → [] */
  }

  return {
    weekStart: isWeekStart(row.week_start) ? row.week_start : 'monday',
    defaultRange,
    presets,
  };
}

/** The current preferences for [userId] — server defaults when no row exists. */
export function getForUser(db: Database.Database, userId: number): UserPreferences {
  const row = db
    .prepare('SELECT week_start, default_range, presets FROM user_preferences WHERE user_id = ?')
    .get(userId) as PreferencesRow | undefined;
  return row ? parseRow(row) : defaultPreferences();
}

/**
 * Upserts a partial update for [userId] (single statement = atomic) and
 * returns the merged preferences. Fields not present in [partial] keep
 * their current value.
 */
export function updateForUser(
  db: Database.Database,
  userId: number,
  partial: Partial<UserPreferences>,
): UserPreferences {
  const current = getForUser(db, userId);
  const next: UserPreferences = {
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
  `).run(
    userId,
    next.weekStart,
    next.defaultRange ? JSON.stringify(next.defaultRange) : null,
    JSON.stringify(next.presets),
  );

  return next;
}
