// Pure date-range math for the date-range picker (date-range-picker-spec.md
// §4.5 / §5.3 / §5.4). Everything operates on normalized local dates
// (midnight, no time component) and is free of widgets/providers so it can
// be unit-tested in isolation.
//
// Mirrors the reference web picker's date helpers (startOfWeek, presets,
// spanDays, shiftRange) — see `D:/date-range-picker.html`.

/// Week-start day — drives the calendar grids and the This week / Last week
/// presets (spec §4.5). Monday is the default.
enum WeekStart { monday, saturday, sunday }

/// The period kind of a range — what the picker's ‹ › arrows shift by
/// (spec §2.2 / §5.4).
enum PresetType { day, week, span, month, custom }

/// The built-in named presets (spec §2.3). "All dates" / custom ranges are
/// handled by the widget layer (they map to null providers), not here.
enum DatePreset { today, yesterday, thisWeek, lastWeek, last7, last30, last90, thisMonth, lastMonth }

/// An inclusive date range of normalized local dates.
typedef DateRange = ({DateTime from, DateTime to});

/// Normalizes [d] to local midnight.
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Adds [n] days to [d] (negative shifts backwards; overflows month/year).
DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// Index of [day]'s weekday in a Monday-based week (Mon=0 … Sun=6).
int mondayBasedIndex(DateTime day) => day.weekday - 1; // DateTime.weekday: Mon=1…Sun=7.

/// Index of [start] in a Monday-based week (Mon=0, Sat=5, Sun=6).
int weekStartIndex(WeekStart start) => switch (start) {
  WeekStart.monday => 0,
  WeekStart.saturday => 5,
  WeekStart.sunday => 6,
};

/// The Monday/Saturday/Sunday at the start of [day]'s calendar week.
DateTime startOfWeek(DateTime day, WeekStart start) {
  final d = dateOnly(day);
  final offset = (mondayBasedIndex(d) - weekStartIndex(start) + 7) % 7;
  return addDays(d, -offset);
}

/// The last day (start + 6) of [day]'s calendar week.
DateTime endOfWeek(DateTime day, WeekStart start) =>
    addDays(startOfWeek(day, start), 6);

/// Inclusive number of days in [from]..[to] (both normalized; `to >= from`).
///
/// Computed in UTC so a DST transition between the two local midnights can't
/// make two adjacent days differ by 23/25h (which would turn `.inDays` into 0).
int daysInRange(DateTime from, DateTime to) {
  final a = dateOnly(from);
  final b = dateOnly(to);
  return DateTime.utc(b.year, b.month, b.day)
          .difference(DateTime.utc(a.year, a.month, a.day))
          .inDays +
      1;
}

/// The built-in range for [preset] relative to [today] (normalized).
DateRange presetRange(DatePreset preset, DateTime today, WeekStart weekStart) {
  final t = dateOnly(today);
  switch (preset) {
    case DatePreset.today:
      return (from: t, to: t);
    case DatePreset.yesterday:
      final y = addDays(t, -1);
      return (from: y, to: y);
    case DatePreset.thisWeek:
      final s = startOfWeek(t, weekStart);
      return (from: s, to: addDays(s, 6));
    case DatePreset.lastWeek:
      final s = addDays(startOfWeek(t, weekStart), -7);
      return (from: s, to: addDays(s, 6));
    case DatePreset.last7:
      return (from: addDays(t, -6), to: t);
    case DatePreset.last30:
      return (from: addDays(t, -29), to: t);
    case DatePreset.last90:
      return (from: addDays(t, -89), to: t);
    case DatePreset.thisMonth:
      final first = DateTime(t.year, t.month, 1);
      return (from: first, to: DateTime(t.year, t.month + 1, 0));
    case DatePreset.lastMonth:
      final first = DateTime(t.year, t.month - 1, 1);
      return (from: first, to: DateTime(t.year, t.month, 0));
  }
}

/// The period kind [preset] shifts by (spec §2.2).
PresetType presetType(DatePreset preset) => switch (preset) {
  DatePreset.today || DatePreset.yesterday => PresetType.day,
  DatePreset.thisWeek || DatePreset.lastWeek => PresetType.week,
  DatePreset.last7 || DatePreset.last30 || DatePreset.last90 => PresetType.span,
  DatePreset.thisMonth || DatePreset.lastMonth => PresetType.month,
};

/// The built-in preset whose range exactly equals [range] (day-exact, per
/// spec §5.3), or null when no built-in matches (a "custom" range).
DatePreset? matchPreset(DateRange range, DateTime today, WeekStart weekStart) {
  final from = dateOnly(range.from);
  final to = dateOnly(range.to);
  for (final preset in DatePreset.values) {
    final r = presetRange(preset, today, weekStart);
    if (r.from == from && r.to == to) return preset;
  }
  return null;
}

/// The shift kind for [range] — the matched built-in's [presetType] when the
/// range exactly matches one, otherwise [PresetType.custom] (shift by the
/// range's own length). Used by the picker's ‹ › arrows; unlike [presetType]
/// it takes a *range* rather than a named preset.
PresetType shiftTypeForRange(DateRange range, DateTime today, WeekStart weekStart) {
  final preset = matchPreset(range, today, weekStart);
  return preset == null ? PresetType.custom : presetType(preset);
}

/// Shifts [range] by one period in [direction] (±1) per the reference
/// behavior (spec §2.2):
///
/// - `month` → first of ±1 month → that month's end
/// - `week`  → both ends ±7 days
/// - `day`   → both ends ±1 day
/// - `span`/`custom` → both ends ± the range's own length
DateRange shiftRange(DateRange range, PresetType type, int direction) {
  final from = dateOnly(range.from);
  final to = dateOnly(range.to);
  switch (type) {
    case PresetType.month:
      final first = DateTime(from.year, from.month + direction, 1);
      return (from: first, to: DateTime(first.year, first.month + 1, 0));
    case PresetType.week:
      return (from: addDays(from, 7 * direction), to: addDays(to, 7 * direction));
    case PresetType.day:
      return (from: addDays(from, direction), to: addDays(to, direction));
    case PresetType.span:
    case PresetType.custom:
      final n = daysInRange(from, to);
      return (from: addDays(from, n * direction), to: addDays(to, n * direction));
  }
}

/// The result of shifting [range] one period, or null when it would **start
/// after [today]** — the clamped-at-today rule for the picker's forward ‹ ›
/// arrow (locked during the Phase 0 review): a range may contain future days
/// (e.g. This week), but shifting may never move its start into the future.
/// Backward shifts always pass.
DateRange? shiftRangeClamped(DateRange range, PresetType type, int direction, DateTime today) {
  final shifted = shiftRange(range, type, direction);
  if (dateOnly(shifted.from).isAfter(dateOnly(today))) return null;
  return shifted;
}
