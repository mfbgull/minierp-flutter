"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const better_sqlite3_1 = __importDefault(require("better-sqlite3"));
const UserPreferences_1 = require("../models/UserPreferences");
let db;
beforeEach(() => {
    db = new better_sqlite3_1.default(':memory:');
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
        expect((0, UserPreferences_1.getForUser)(db, 1)).toEqual({ weekStart: 'monday', defaultRange: null, presets: [] });
    });
    it('upserts a row on update and persists the merged values', () => {
        const saved = (0, UserPreferences_1.updateForUser)(db, 1, { weekStart: 'saturday' });
        expect(saved).toEqual({ weekStart: 'saturday', defaultRange: null, presets: [] });
        expect((0, UserPreferences_1.getForUser)(db, 1)).toEqual({ weekStart: 'saturday', defaultRange: null, presets: [] });
    });
    it('keeps users isolated', () => {
        (0, UserPreferences_1.updateForUser)(db, 1, {
            weekStart: 'saturday',
            defaultRange: { from: '2026-08-03', to: '2026-08-09' },
        });
        (0, UserPreferences_1.updateForUser)(db, 2, { weekStart: 'sunday' });
        expect((0, UserPreferences_1.getForUser)(db, 1).weekStart).toBe('saturday');
        expect((0, UserPreferences_1.getForUser)(db, 1).defaultRange).toEqual({ from: '2026-08-03', to: '2026-08-09' });
        expect((0, UserPreferences_1.getForUser)(db, 2).weekStart).toBe('sunday');
        expect((0, UserPreferences_1.getForUser)(db, 2).defaultRange).toBeNull();
        expect((0, UserPreferences_1.getForUser)(db, 2).presets).toEqual([]);
    });
    it('merges partial updates without clobbering untouched fields', () => {
        (0, UserPreferences_1.updateForUser)(db, 1, {
            weekStart: 'sunday',
            defaultRange: { from: '2026-01-01', to: '2026-01-31' },
        });
        (0, UserPreferences_1.updateForUser)(db, 1, {
            presets: [{ id: 'p1', name: 'Q1', from: '2026-01-01', to: '2026-03-31' }],
        });
        const current = (0, UserPreferences_1.getForUser)(db, 1);
        expect(current.weekStart).toBe('sunday');
        expect(current.defaultRange).toEqual({ from: '2026-01-01', to: '2026-01-31' });
        expect(current.presets).toHaveLength(1);
    });
    it('can clear the default range with an explicit null', () => {
        (0, UserPreferences_1.updateForUser)(db, 1, { defaultRange: { from: '2026-08-03', to: '2026-08-09' } });
        (0, UserPreferences_1.updateForUser)(db, 1, { defaultRange: null });
        expect((0, UserPreferences_1.getForUser)(db, 1).defaultRange).toBeNull();
    });
    it('round-trips presets through JSON storage', () => {
        const presets = [
            { id: 'p1', name: 'Summer', from: '2026-06-01', to: '2026-08-31' },
            { id: 'p2', name: 'Winter', from: '2026-12-01', to: '2027-02-28' },
        ];
        (0, UserPreferences_1.updateForUser)(db, 1, { presets });
        expect((0, UserPreferences_1.getForUser)(db, 1).presets).toEqual(presets);
    });
    it('falls back to defaults for a corrupt stored row', () => {
        db.prepare(`INSERT INTO user_preferences (user_id, week_start, default_range, presets)
       VALUES (1, 'not-a-week', 'not-json', 'not-json')`).run();
        expect((0, UserPreferences_1.getForUser)(db, 1)).toEqual({ weekStart: 'monday', defaultRange: null, presets: [] });
    });
});
