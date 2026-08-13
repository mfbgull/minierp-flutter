// Unit tests for the shared value formatters
// (`lib/core/utils/formatters.dart`), currently the compact range text the
// date-picker pill renders (reference §2.1 — en-dashes exactly like the
// web prototype).

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:minierp_app/core/utils/formatters.dart';

void main() {
  setUpAll(() async {
    // compactRange runs through intl date formats.
    await initializeDateFormatting('en');
  });

  group('compactRange', () {
    test('same day renders a full date', () {
      expect(
        Formatters.compactRange(DateTime(2026, 8, 13), DateTime(2026, 8, 13)),
        'Aug 13, 2026',
      );
    });

    test('same month and year uses a bare en-dash', () {
      expect(
        Formatters.compactRange(DateTime(2026, 8, 7), DateTime(2026, 8, 13)),
        'Aug 7–13, 2026',
      );
    });

    test('same year renders two months with a spaced en-dash', () {
      expect(
        Formatters.compactRange(DateTime(2026, 8, 7), DateTime(2026, 9, 13)),
        'Aug 7 – Sep 13, 2026',
      );
    });

    test('different years render both full dates', () {
      expect(
        Formatters.compactRange(DateTime(2026, 8, 7), DateTime(2027, 9, 13)),
        'Aug 7, 2026 – Sep 13, 2027',
      );
    });

    test('crosses the month boundary within the same month branch', () {
      // Aug 31 – Sep 1 shares no month, so it falls to the same-year branch.
      expect(
        Formatters.compactRange(DateTime(2026, 8, 31), DateTime(2026, 9, 1)),
        'Aug 31 – Sep 1, 2026',
      );
    });
  });
}
