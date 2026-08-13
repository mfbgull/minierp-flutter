// Unit tests for the pure date-range math helpers
// (`lib/core/utils/date_range_math.dart`): week-start math, built-in
// preset ranges, preset matching and the ‹ › shift arithmetic. All cases
// use fixed dates so the tests are deterministic (2026-08-13 is a
// Thursday).

import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/core/utils/date_range_math.dart';

void main() {
  final today = DateTime(2026, 8, 13); // Thursday

  group('dateOnly / addDays / daysInRange', () {
    test('dateOnly strips the time component', () {
      expect(dateOnly(DateTime(2026, 8, 13, 23, 59, 59)), DateTime(2026, 8, 13));
    });

    test('addDays crosses month and year boundaries', () {
      expect(addDays(DateTime(2026, 8, 31), 1), DateTime(2026, 9, 1));
      expect(addDays(DateTime(2026, 1, 1), -1), DateTime(2025, 12, 31));
    });

    test('daysInRange counts inclusively', () {
      expect(daysInRange(DateTime(2026, 8, 13), DateTime(2026, 8, 13)), 1);
      expect(daysInRange(DateTime(2026, 8, 10), DateTime(2026, 8, 16)), 7);
      expect(daysInRange(DateTime(2026, 7, 28), DateTime(2026, 8, 3)), 7);
    });

    test('daysInRange is DST-safe across a transition day', () {
      // Mar 8 2026 is a US spring-forward day; the UTC-based computation
      // must still count two adjacent days as 2 regardless of the host
      // timezone.
      expect(daysInRange(DateTime(2026, 3, 7), DateTime(2026, 3, 8)), 2);
      expect(
        daysInRange(DateTime(2026, 3, 7), DateTime(2026, 3, 14)),
        8,
      );
    });
  });

  group('startOfWeek / endOfWeek', () {
    test('monday-first week', () {
      expect(startOfWeek(today, WeekStart.monday), DateTime(2026, 8, 10));
      expect(endOfWeek(today, WeekStart.monday), DateTime(2026, 8, 16));
    });

    test('saturday-first week', () {
      expect(startOfWeek(today, WeekStart.saturday), DateTime(2026, 8, 8));
      expect(endOfWeek(today, WeekStart.saturday), DateTime(2026, 8, 14));
    });

    test('sunday-first week', () {
      expect(startOfWeek(today, WeekStart.sunday), DateTime(2026, 8, 9));
      expect(endOfWeek(today, WeekStart.sunday), DateTime(2026, 8, 15));
    });

    test('a day on the week start has offset zero', () {
      expect(
        startOfWeek(DateTime(2026, 8, 10), WeekStart.monday),
        DateTime(2026, 8, 10),
      );
    });
  });

  group('presetRange', () {
    test('today / yesterday', () {
      expect(
        presetRange(DatePreset.today, today, WeekStart.monday),
        (from: DateTime(2026, 8, 13), to: DateTime(2026, 8, 13)),
      );
      expect(
        presetRange(DatePreset.yesterday, today, WeekStart.monday),
        (from: DateTime(2026, 8, 12), to: DateTime(2026, 8, 12)),
      );
    });

    test('this/last week respect the week start', () {
      expect(
        presetRange(DatePreset.thisWeek, today, WeekStart.monday),
        (from: DateTime(2026, 8, 10), to: DateTime(2026, 8, 16)),
      );
      expect(
        presetRange(DatePreset.thisWeek, today, WeekStart.saturday),
        (from: DateTime(2026, 8, 8), to: DateTime(2026, 8, 14)),
      );
      expect(
        presetRange(DatePreset.lastWeek, today, WeekStart.monday),
        (from: DateTime(2026, 8, 3), to: DateTime(2026, 8, 9)),
      );
    });

    test('rolling spans end today', () {
      expect(
        presetRange(DatePreset.last7, today, WeekStart.monday),
        (from: DateTime(2026, 8, 7), to: DateTime(2026, 8, 13)),
      );
      expect(
        presetRange(DatePreset.last30, today, WeekStart.monday),
        (from: DateTime(2026, 7, 15), to: DateTime(2026, 8, 13)),
      );
      expect(
        presetRange(DatePreset.last90, today, WeekStart.monday),
        (from: DateTime(2026, 5, 16), to: DateTime(2026, 8, 13)),
      );
    });

    test('months', () {
      expect(
        presetRange(DatePreset.thisMonth, today, WeekStart.monday),
        (from: DateTime(2026, 8, 1), to: DateTime(2026, 8, 31)),
      );
      expect(
        presetRange(DatePreset.lastMonth, today, WeekStart.monday),
        (from: DateTime(2026, 7, 1), to: DateTime(2026, 7, 31)),
      );
    });

    test('this month handles a 30-day month and a leap February', () {
      expect(
        presetRange(DatePreset.thisMonth, DateTime(2026, 4, 10), WeekStart.monday),
        (from: DateTime(2026, 4, 1), to: DateTime(2026, 4, 30)),
      );
      expect(
        presetRange(DatePreset.thisMonth, DateTime(2028, 2, 10), WeekStart.monday),
        (from: DateTime(2028, 2, 1), to: DateTime(2028, 2, 29)),
      );
    });

    test('last month crosses a year boundary', () {
      final jan = DateTime(2027, 1, 15);
      expect(
        presetRange(DatePreset.lastMonth, jan, WeekStart.monday),
        (from: DateTime(2026, 12, 1), to: DateTime(2026, 12, 31)),
      );
    });

    test('last week crosses a year boundary', () {
      final jan = DateTime(2027, 1, 4); // a Monday
      expect(
        presetRange(DatePreset.lastWeek, jan, WeekStart.monday),
        (from: DateTime(2026, 12, 28), to: DateTime(2027, 1, 3)),
      );
    });
  });

  group('presetType', () {
    test('maps each preset to its shift kind', () {
      expect(presetType(DatePreset.today), PresetType.day);
      expect(presetType(DatePreset.yesterday), PresetType.day);
      expect(presetType(DatePreset.thisWeek), PresetType.week);
      expect(presetType(DatePreset.lastWeek), PresetType.week);
      expect(presetType(DatePreset.last7), PresetType.span);
      expect(presetType(DatePreset.last30), PresetType.span);
      expect(presetType(DatePreset.last90), PresetType.span);
      expect(presetType(DatePreset.thisMonth), PresetType.month);
      expect(presetType(DatePreset.lastMonth), PresetType.month);
    });
  });

  group('matchPreset', () {
    test('matches an exact built-in range', () {
      expect(
        matchPreset(
          (from: DateTime(2026, 8, 10), to: DateTime(2026, 8, 16)),
          today,
          WeekStart.monday,
        ),
        DatePreset.thisWeek,
      );
      expect(
        matchPreset(
          (from: DateTime(2026, 8, 13), to: DateTime(2026, 8, 13)),
          today,
          WeekStart.monday,
        ),
        DatePreset.today,
      );
      expect(
        matchPreset(
          (from: DateTime(2026, 8, 7), to: DateTime(2026, 8, 13)),
          today,
          WeekStart.monday,
        ),
        DatePreset.last7,
      );
      expect(
        matchPreset(
          (from: DateTime(2026, 8, 1), to: DateTime(2026, 8, 31)),
          today,
          WeekStart.monday,
        ),
        DatePreset.thisMonth,
      );
      expect(
        matchPreset(
          (from: DateTime(2026, 8, 3), to: DateTime(2026, 8, 9)),
          today,
          WeekStart.monday,
        ),
        DatePreset.lastWeek,
      );
      expect(
        matchPreset(
          (from: DateTime(2026, 8, 12), to: DateTime(2026, 8, 12)),
          today,
          WeekStart.monday,
        ),
        DatePreset.yesterday,
      );
      expect(
        matchPreset(
          (from: DateTime(2026, 7, 15), to: DateTime(2026, 8, 13)),
          today,
          WeekStart.monday,
        ),
        DatePreset.last30,
      );
      expect(
        matchPreset(
          (from: DateTime(2026, 5, 16), to: DateTime(2026, 8, 13)),
          today,
          WeekStart.monday,
        ),
        DatePreset.last90,
      );
      expect(
        matchPreset(
          (from: DateTime(2026, 7, 1), to: DateTime(2026, 7, 31)),
          today,
          WeekStart.monday,
        ),
        DatePreset.lastMonth,
      );
    });

    test('week matching depends on the week start', () {
      expect(
        matchPreset(
          (from: DateTime(2026, 8, 10), to: DateTime(2026, 8, 16)),
          today,
          WeekStart.saturday,
        ),
        isNull,
      );
    });

    test('returns null for a range no built-in covers', () {
      expect(
        matchPreset(
          (from: DateTime(2026, 8, 12), to: DateTime(2026, 8, 16)),
          today,
          WeekStart.monday,
        ),
        isNull,
      );
    });
  });

  group('shiftTypeForRange', () {
    test('uses the matched preset kind', () {
      expect(
        shiftTypeForRange(
          (from: DateTime(2026, 8, 10), to: DateTime(2026, 8, 16)),
          today,
          WeekStart.monday,
        ),
        PresetType.week,
      );
      expect(
        shiftTypeForRange(
          (from: DateTime(2026, 8, 13), to: DateTime(2026, 8, 13)),
          today,
          WeekStart.monday,
        ),
        PresetType.day,
      );
    });

    test('falls back to custom', () {
      expect(
        shiftTypeForRange(
          (from: DateTime(2026, 8, 12), to: DateTime(2026, 8, 16)),
          today,
          WeekStart.monday,
        ),
        PresetType.custom,
      );
    });
  });

  group('shiftRange', () {
    test('month shifts to the first/last of the adjacent month', () {
      expect(
        shiftRange((from: DateTime(2026, 7, 1), to: DateTime(2026, 7, 31)), PresetType.month, 1),
        (from: DateTime(2026, 8, 1), to: DateTime(2026, 8, 31)),
      );
      expect(
        shiftRange((from: DateTime(2026, 7, 1), to: DateTime(2026, 7, 31)), PresetType.month, -1),
        (from: DateTime(2026, 6, 1), to: DateTime(2026, 6, 30)),
      );
    });

    test('month shift snaps to month ends (31 → 30 → 28-day months)', () {
      expect(
        shiftRange((from: DateTime(2026, 8, 1), to: DateTime(2026, 8, 31)), PresetType.month, 1),
        (from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 30)),
      );
      expect(
        shiftRange((from: DateTime(2026, 3, 1), to: DateTime(2026, 3, 31)), PresetType.month, 1),
        (from: DateTime(2026, 4, 1), to: DateTime(2026, 4, 30)),
      );
    });

    test('month shift crosses a year boundary', () {
      expect(
        shiftRange((from: DateTime(2026, 12, 1), to: DateTime(2026, 12, 31)), PresetType.month, 1),
        (from: DateTime(2027, 1, 1), to: DateTime(2027, 1, 31)),
      );
      expect(
        shiftRange((from: DateTime(2026, 1, 1), to: DateTime(2026, 1, 31)), PresetType.month, -1),
        (from: DateTime(2025, 12, 1), to: DateTime(2025, 12, 31)),
      );
    });

    test('week shifts by seven days', () {
      expect(
        shiftRange((from: DateTime(2026, 8, 10), to: DateTime(2026, 8, 16)), PresetType.week, 1),
        (from: DateTime(2026, 8, 17), to: DateTime(2026, 8, 23)),
      );
      expect(
        shiftRange((from: DateTime(2026, 8, 10), to: DateTime(2026, 8, 16)), PresetType.week, -1),
        (from: DateTime(2026, 8, 3), to: DateTime(2026, 8, 9)),
      );
    });

    test('day shifts by one day', () {
      expect(
        shiftRange((from: DateTime(2026, 8, 13), to: DateTime(2026, 8, 13)), PresetType.day, 1),
        (from: DateTime(2026, 8, 14), to: DateTime(2026, 8, 14)),
      );
    });

    test('span shifts by the range length (last-7 → 7 days)', () {
      expect(
        shiftRange((from: DateTime(2026, 8, 7), to: DateTime(2026, 8, 13)), PresetType.span, 1),
        (from: DateTime(2026, 8, 14), to: DateTime(2026, 8, 20)),
      );
    });

    test('custom shifts by its own length', () {
      expect(
        shiftRange((from: DateTime(2026, 8, 5), to: DateTime(2026, 8, 10)), PresetType.custom, 1),
        (from: DateTime(2026, 8, 11), to: DateTime(2026, 8, 16)),
      );
      expect(
        shiftRange((from: DateTime(2026, 8, 5), to: DateTime(2026, 8, 10)), PresetType.custom, -1),
        (from: DateTime(2026, 7, 30), to: DateTime(2026, 8, 4)),
      );
    });
  });

  group('shiftRangeClamped', () {
    test('forward shift is refused when the result starts after today', () {
      // This week (Mon 10 – Sun 16); forward lands on Mon 17 > today (Thu 13).
      expect(
        shiftRangeClamped(
          (from: DateTime(2026, 8, 10), to: DateTime(2026, 8, 16)),
          PresetType.week,
          1,
          today,
        ),
        isNull,
      );
      expect(
        shiftRangeClamped(
          (from: DateTime(2026, 8, 13), to: DateTime(2026, 8, 13)),
          PresetType.day,
          1,
          today,
        ),
        isNull,
      );
    });

    test('forward shift is allowed while the result still starts today or earlier', () {
      // Custom Aug 5–10 shifted +6 → Aug 11–16: starts before today (Thu 13).
      expect(
        shiftRangeClamped(
          (from: DateTime(2026, 8, 5), to: DateTime(2026, 8, 10)),
          PresetType.custom,
          1,
          today,
        ),
        (from: DateTime(2026, 8, 11), to: DateTime(2026, 8, 16)),
      );
    });

    test('backward shifts always pass', () {
      expect(
        shiftRangeClamped(
          (from: DateTime(2026, 8, 10), to: DateTime(2026, 8, 16)),
          PresetType.week,
          -1,
          today,
        ),
        (from: DateTime(2026, 8, 3), to: DateTime(2026, 8, 9)),
      );
    });
  });
}
