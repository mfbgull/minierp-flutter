import 'package:flutter/material.dart';

/// Shared single-date picker helper — the app's `showDatePicker` wiring
/// (PORTING.md §2). Previously this file also carried the From/To filter
/// row (`DateRangeFilter`, `DateFilterButton`, `pickFilterDate`); those
/// were replaced by the pill picker in `date_range_picker.dart` (Phase 3)
/// and the rollout (Phase 4). Form dialogs still use [pickDate] for
/// single-field dates.

/// Shows the app-standard date picker (2000 → 2100 by default) and
/// returns the picked [DateTime], or null when dismissed.
Future<DateTime?> pickDate(
  BuildContext context, {
  required DateTime initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  return showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: firstDate ?? DateTime(2000),
    lastDate: lastDate ?? DateTime(2100),
  );
}
