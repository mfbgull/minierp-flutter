// Shared presenters for the activity log module — timestamp formatting
// and log-level badge colors used by both the grid screen and the detail
// dialog (AGENTS.md self-audit: no duplicated logic across the module).

import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';

/// `2026-08-09 10:30:00` (SQLite) → "Aug 9, 2026 10:30 AM".
String formatActivityTimestamp(String raw) {
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw;
  return Formatters.dateTime(parsed);
}

/// Log-level badge colors (INFO teal, WARN amber, ERROR red — matches the
/// web app's activity-log row tinting).
Color activityLogLevelColor(String level) => switch (level.toUpperCase()) {
  'ERROR' => Colors.red,
  'WARN' || 'WARNING' => Colors.orange,
  'DEBUG' => Colors.blueGrey,
  _ => Colors.teal,
};
