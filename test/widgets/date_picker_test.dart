// Widget tests for the shared single-date picker helper
// (`lib/widgets/date_picker.dart`): the `showDatePicker` bounds and
// confirm/cancel behavior of `pickDate`. The dialog's
// `initialDate`/`firstDate`/`lastDate` fields are asserted directly on
// the opened `DatePickerDialog`.
//
// The From/To filter row (`DateRangeFilter`, `DateFilterButton`,
// `pickFilterDate`) that previously lived here was replaced by the pill
// picker in Phase 3/4 — its coverage moved to
// `test/widgets/date_range_picker_test.dart`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/widgets/date_picker.dart' show pickDate;

/// Pumps a bare `MaterialApp` with a single button that calls the given
/// picker function, so the tests stay focused on the helper itself.
Widget _harness(Future<DateTime?> Function(BuildContext) onTap) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => onTap(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

DatePickerDialog _dialog(WidgetTester tester) =>
    tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));

void main() {
  group('pickDate bounds', () {
    testWidgets('uses the 2000→2100 defaults', (tester) async {
      await tester.pumpWidget(
        _harness(
          (context) => pickDate(context, initialDate: DateTime(2026, 8, 3)),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final dialog = _dialog(tester);
      expect(dialog.initialDate, DateTime(2026, 8, 3));
      expect(dialog.firstDate, DateTime(2000));
      expect(dialog.lastDate, DateTime(2100));
    });

    testWidgets('honors explicit first/last bounds', (tester) async {
      await tester.pumpWidget(
        _harness(
          (context) => pickDate(
            context,
            initialDate: DateTime(2026, 8, 3),
            firstDate: DateTime(2020),
            lastDate: DateTime(2030),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final dialog = _dialog(tester);
      expect(dialog.firstDate, DateTime(2020));
      expect(dialog.lastDate, DateTime(2030));
    });

    testWidgets('returns null when dismissed', (tester) async {
      DateTime? result = DateTime(2000);
      await tester.pumpWidget(
        _harness((context) async {
          result = await pickDate(context, initialDate: DateTime(2026, 8, 3));
          return result;
        }),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });

    testWidgets('returns the confirmed date', (tester) async {
      DateTime? result;
      await tester.pumpWidget(
        _harness((context) async {
          result = await pickDate(context, initialDate: DateTime(2026, 8, 3));
          return result;
        }),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(result, DateTime(2026, 8, 3));
    });
  });
}
