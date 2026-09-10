-- Per-user date-range picker preferences (date-range-picker-spec.md §6.1):
-- week-start day, the default range new screens open with, and the user's
-- custom named presets. One row per user; an absent row means server
-- defaults (backfilled on read — see models/UserPreferences.ts).

CREATE TABLE IF NOT EXISTS user_preferences (
    user_id       INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    week_start    TEXT NOT NULL DEFAULT 'monday',   -- 'monday' | 'saturday' | 'sunday'
    default_range TEXT,                             -- JSON { "from": "YYYY-MM-DD", "to": "YYYY-MM-DD" } or NULL
    presets       TEXT NOT NULL DEFAULT '[]',       -- JSON array of { id, name, from, to }
    updated_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
