import Database from 'better-sqlite3';
import { getForUser, updateForUser } from '../models/UserPreferences';

let db: Database.Database;

beforeEach(() => {
  db = new Database(':memory:');
  db.exec(`
    CREATE TABLE user_preferences (
      user_id       INTEGER PRIMARY KEY,
      week_start    TEXT NOT NULL DEFAULT 'monday',
      default_range TEXT,
      presets       TEXT NOT NULL DEFAULT '[]',
      updated_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
  `);
});

afterEach(() => {
  db.close();
});

describe('UserPreferences model', () => {
  it('returns server defaults when no row exists', () => {
    expect(getForUser(db, 1)).toEqual({ weekStart: 'monday', defaultRange: null, presets: [] });
  });

  it('upserts a row on update and persists the merged values', () => {
    const saved = updateForUser(db, 1, { weekStart: 'saturday' });
    expect(saved).toEqual({ weekStart: 'saturday', defaultRange: null, presets: [] });
    expect(getForUser(db, 1)).toEqual({ weekStart: 'saturday', defaultRange: null, presets: [] });
  });

  it('keeps users isolated', () => {
    updateForUser(db, 1, {
      weekStart: 'saturday',
      defaultRange: { from: '2026-08-03', to: '2026-08-09' },
    });
    updateForUser(db, 2, { weekStart: 'sunday' });

    expect(getForUser(db, 1).weekStart).toBe('saturday');
    expect(getForUser(db, 1).defaultRange).toEqual({ from: '2026-08-03', to: '2026-08-09' });
    expect(getForUser(db, 2).weekStart).toBe('sunday');
    expect(getForUser(db, 2).defaultRange).toBeNull();
    expect(getForUser(db, 2).presets).toEqual([]);
  });

  it('merges partial updates without clobbering untouched fields', () => {
    updateForUser(db, 1, {
      weekStart: 'sunday',
      defaultRange: { from: '2026-01-01', to: '2026-01-31' },
    });
    updateForUser(db, 1, {
      presets: [{ id: 'p1', name: 'Q1', from: '2026-01-01', to: '2026-03-31' }],
    });

    const current = getForUser(db, 1);
    expect(current.weekStart).toBe('sunday');
    expect(current.defaultRange).toEqual({ from: '2026-01-01', to: '2026-01-31' });
    expect(current.presets).toHaveLength(1);
  });

  it('can clear the default range with an explicit null', () => {
    updateForUser(db, 1, { defaultRange: { from: '2026-08-03', to: '2026-08-09' } });
    updateForUser(db, 1, { defaultRange: null });
    expect(getForUser(db, 1).defaultRange).toBeNull();
  });

  it('round-trips presets through JSON storage', () => {
    const presets = [
      { id: 'p1', name: 'Summer', from: '2026-06-01', to: '2026-08-31' },
      { id: 'p2', name: 'Winter', from: '2026-12-01', to: '2027-02-28' },
    ];
    updateForUser(db, 1, { presets });
    expect(getForUser(db, 1).presets).toEqual(presets);
  });

  it('falls back to defaults for a corrupt stored row', () => {
    db.prepare(
      `INSERT INTO user_preferences (user_id, week_start, default_range, presets)
       VALUES (1, 'not-a-week', 'not-json', 'not-json')`,
    ).run();
    expect(getForUser(db, 1)).toEqual({ weekStart: 'monday', defaultRange: null, presets: [] });
  });
});
