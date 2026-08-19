"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const ActivityLog_1 = require("../models/ActivityLog");
/**
 * `created_at` is stored in UTC (SQLite CURRENT_TIMESTAMP) while the
 * client filters by LOCAL calendar dates. The model converts the local
 * date to UTC bound instants before comparing — a UTC+ timezone would
 * otherwise push the whole local day into the previous UTC calendar day
 * and `created_at >= 'local-monday'` would silently exclude it (the
 * "empty activity log grid" bug). These tests pin the conversion's
 * invariants regardless of the machine's timezone.
 */
/// Parses the `YYYY-MM-DD HH:MM:SS` UTC string back to a Date (treated
/// as UTC), so the LOCAL components assert the conversion's invariants
/// regardless of the machine's timezone.
function toLocalDate(bound) {
    return new Date(`${bound.replace(' ', 'T')}Z`);
}
describe('localDateToUtcBound', () => {
    it('start bound is local midnight of the given day', () => {
        const bound = (0, ActivityLog_1.localDateToUtcBound)('2026-08-17', false);
        const local = toLocalDate(bound);
        expect(local.getFullYear()).toBe(2026);
        expect(local.getMonth()).toBe(7); // August
        expect(local.getDate()).toBe(17);
        expect(local.getHours()).toBe(0);
        expect(local.getMinutes()).toBe(0);
        expect(local.getSeconds()).toBe(0);
    });
    it('end bound is local midnight of the NEXT day (exclusive upper bound)', () => {
        const bound = (0, ActivityLog_1.localDateToUtcBound)('2026-08-23', true);
        const local = toLocalDate(bound);
        expect(local.getFullYear()).toBe(2026);
        expect(local.getMonth()).toBe(7); // August
        expect(local.getDate()).toBe(24); // exclusive: the day after end
        expect(local.getHours()).toBe(0);
        expect(local.getMinutes()).toBe(0);
    });
    it('start bound lies strictly before the end bound', () => {
        const start = (0, ActivityLog_1.localDateToUtcBound)('2026-08-17', false);
        const end = (0, ActivityLog_1.localDateToUtcBound)('2026-08-17', true);
        expect(start < end).toBe(true);
    });
    it('crosses a month boundary', () => {
        const start = (0, ActivityLog_1.localDateToUtcBound)('2026-08-31', false);
        const end = (0, ActivityLog_1.localDateToUtcBound)('2026-08-31', true);
        const endLocal = toLocalDate(end);
        expect(endLocal.getMonth()).toBe(8); // September
        expect(endLocal.getDate()).toBe(1);
        expect(start < end).toBe(true);
    });
});
//# sourceMappingURL=activityLog.test.js.map