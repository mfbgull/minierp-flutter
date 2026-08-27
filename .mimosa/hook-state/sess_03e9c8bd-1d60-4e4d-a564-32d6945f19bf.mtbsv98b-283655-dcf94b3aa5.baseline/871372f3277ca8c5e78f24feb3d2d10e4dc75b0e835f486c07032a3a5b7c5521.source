/**
 * Week-boundary math for the week-aware `period=week` dashboard blocks
 * (date-range-picker-spec.md §6.3). The Flutter picker mirrors this in
 * lib/core/utils/date_range_math.dart.
 *
 * All dates are plain `YYYY-MM-DD` strings (the wire format the rest of the
 * server uses); math happens in UTC so values never shift with the server's
 * local timezone.
 */

export type WeekStart = 'monday' | 'saturday' | 'sunday';

/** Index of the week-start day in a Monday-based week (Mon=0, Sat=5, Sun=6). */
const WEEK_START_INDEX: Record<WeekStart, number> = {
  monday: 0,
  saturday: 5,
  sunday: 6,
};

function parseISO(iso: string): Date {
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d));
}

function toISO(date: Date): string {
  const y = date.getUTCFullYear();
  const m = String(date.getUTCMonth() + 1).padStart(2, '0');
  const d = String(date.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function addDaysUTC(date: Date, n: number): Date {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate() + n));
}

/**
 * Inclusive ISO bounds of the calendar week containing [todayISO] for the
 * given [weekStart] (default monday): `{ from, to }` where `from` is the
 * week's first day and `to` is `from + 6`.
 *
 * Examples (Thursday 2026-08-13):
 *   monday   → { from: '2026-08-10', to: '2026-08-16' }
 *   saturday → { from: '2026-08-08', to: '2026-08-14' }
 *   sunday   → { from: '2026-08-09', to: '2026-08-15' }
 */
export function weekBounds(todayISO: string, weekStart: WeekStart = 'monday'): { from: string; to: string } {
  const today = parseISO(todayISO);
  // JS getUTCDay(): Sun=0…Sat=6 → Monday-based index (Mon=0…Sun=6).
  const mondayIndex = (today.getUTCDay() + 6) % 7;
  const offset = (mondayIndex - WEEK_START_INDEX[weekStart] + 7) % 7;
  const from = addDaysUTC(today, -offset);
  const to = addDaysUTC(from, 6);
  return { from: toISO(from), to: toISO(to) };
}
