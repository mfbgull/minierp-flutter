// Unit tests for the canonical wire-format date formatter
// (`lib/core/utils/date_utils.dart`). Every repository, list screen,
// form dialog and report screen now delegates here, so these tests pin
// the exact `YYYY-MM-DD` shape the API expects (PORTING.md §2).

import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/core/utils/date_utils.dart';

void main() {
  group('isoDate', () {
    test('zero-pads month and day', () {
      expect(isoDate(DateTime(2026, 8, 3)), '2026-08-03');
    });

    test('zero-pads single-digit month and day', () {
      expect(isoDate(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('keeps double-digit month and day unpadded', () {
      expect(isoDate(DateTime(2026, 11, 25)), '2026-11-25');
    });

    test('handles leap day', () {
      expect(isoDate(DateTime(2024, 2, 29)), '2024-02-29');
    });

    test('ignores the time-of-day components', () {
      expect(isoDate(DateTime(2026, 8, 3, 14, 30, 45)), '2026-08-03');
    });

    test('handles the first day of the year', () {
      expect(isoDate(DateTime(2026, 1, 1)), '2026-01-01');
    });

    test('handles the last day of the year', () {
      expect(isoDate(DateTime(2026, 12, 31)), '2026-12-31');
    });

    test('formats the calendar fields as given, without conversion', () {
      // A UTC DateTime formats its UTC fields — isoDate never converts
      // to the local zone, so the result is stable on any host.
      expect(isoDate(DateTime.utc(2026, 8, 3)), '2026-08-03');
      expect(isoDate(DateTime.utc(2026, 12, 31)), '2026-12-31');
    });
  });
}
