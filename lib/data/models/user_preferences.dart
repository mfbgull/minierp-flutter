// Per-user date-range preferences — wire shape from
// GET/PUT /api/preferences (date-range-picker-spec.md §6.1):
//
//   { weekStart: 'monday'|'saturday'|'sunday',
//     defaultRange: {from, to} | null,
//     presets: [{id, name, from, to}] }
//
// The server stores JSON fields as TEXT and backfills defaults in memory
// when no row exists (no write-on-GET); this client mirrors that with
// tolerant parsing — an unknown week start or malformed range falls back
// to the default rather than throwing (json_helpers.dart conventions).

import '../../core/utils/date_range_math.dart' show DateRange, WeekStart;
import '../../core/utils/date_utils.dart' show isoDate;
import 'json_helpers.dart';

/// One user-defined range preset (`{id, name, from, to}`).
class UserPreset {
  const UserPreset({
    required this.id,
    required this.name,
    required this.from,
    required this.to,
  });

  /// Parses a preset row, or null when the id is empty or a date is
  /// missing/unparseable. The server never sends such rows, but a corrupt
  /// cached blob must be skipped rather than fabricating bogus dates.
  static UserPreset? tryFromJson(Map<String, dynamic> json) {
    final id = asString(json['id']);
    final name = asString(json['name']);
    final from = _parseIsoDate(asString(json['from']));
    final to = _parseIsoDate(asString(json['to']));
    if (id == null || id.isEmpty || name == null || from == null || to == null) {
      return null;
    }
    return UserPreset(id: id, name: name, from: from, to: to);
  }

  /// Non-empty unique id (server-validated on PUT).
  final String id;
  final String name;

  /// Normalized local dates (inclusive range bounds).
  final DateTime from;
  final DateTime to;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'from': isoDate(from),
    'to': isoDate(to),
  };
}

/// The user's date-range preferences (camelCase = wire shape).
class UserPreferences {
  const UserPreferences({
    required this.weekStart,
    this.defaultRange,
    required this.presets,
  });

  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    final presets = <UserPreset>[];
    for (final row in json['presets'] as List? ?? const []) {
      if (row is Map<String, dynamic>) {
        final preset = UserPreset.tryFromJson(row);
        if (preset != null) presets.add(preset);
      }
    }
    return UserPreferences(
      weekStart: _parseWeekStart(asString(json['weekStart'])),
      defaultRange: _parseDateRange(json['defaultRange']),
      presets: presets,
    );
  }

  /// The saved week-start day (monday default — affects calendar grids,
  /// This week / Last week presets, and the server's `period=week`).
  final WeekStart weekStart;

  /// The saved default report range (null = none set); report and list
  /// screens seed their From/To from this at boot.
  final DateRange? defaultRange;

  /// User-defined presets shown under the picker's built-ins.
  final List<UserPreset> presets;
}

/// Parses a week-start wire value; anything unknown falls back to Monday
/// (the server default).
WeekStart _parseWeekStart(String? value) => switch (value) {
  'saturday' => WeekStart.saturday,
  'sunday' => WeekStart.sunday,
  _ => WeekStart.monday,
};

/// Parses `{from, to}` (ISO dates) or null. A malformed block returns
/// null rather than throwing — the server never sends one, but a corrupt
/// cached blob must not crash the picker.
DateRange? _parseDateRange(Object? json) {
  if (json is! Map<String, dynamic>) return null;
  final from = _parseIsoDate(asString(json['from']));
  final to = _parseIsoDate(asString(json['to']));
  if (from == null || to == null) return null;
  return (from: from, to: to);
}

/// Parses a `YYYY-MM-DD` string to a normalized local date (Dart parses
/// date-only ISO strings as local midnight, matching `dateOnly`).
DateTime? _parseIsoDate(String? value) {
  if (value == null) return null;
  return DateTime.tryParse(value);
}
