// Widget tests for the shared date-picker helpers
// (`lib/widgets/date_picker_helpers.dart`): the `showDatePicker`
// bounds for `pickDate`, the provider-write behavior of
// `pickFilterDate`/`pickReportDate`, the `DateFilterButton`
// rendering, and the `DateRangeFilter`/`ReportDateRangeFilter`
// label formatting + provider writes. The dialog's
// `initialDate`/`firstDate`/`lastDate` fields are asserted directly
// on the opened `DatePickerDialog`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:minierp_app/l10n/app_localizations.dart';
import 'package:minierp_app/widgets/date_picker_helpers.dart';

/// Pumps a bare `MaterialApp` with a single button that calls the given
/// picker function, so the tests stay focused on the helpers themselves.
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
  setUpAll(() async {
    // DateRangeFilter labels run through Formatters.date (intl).
    await initializeDateFormatting('en');
  });

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

  group('pickFilterDate (nullable filter providers)', () {
    testWidgets('writes the confirmed date to the isFrom provider', (
      tester,
    ) async {
      final from = StateProvider<DateTime?>((ref) => DateTime(2026, 6, 15));
      final to = StateProvider<DateTime?>((ref) => null);

      await tester.pumpWidget(
        ProviderScope(
          child: _FilterHarness(
            fromProvider: from,
            toProvider: to,
            isFrom: true,
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(_FilterHarness)),
      );
      expect(container.read(from), DateTime(2026, 6, 15));
      expect(container.read(to), isNull);
    });

    testWidgets('writes the confirmed date to the isTo provider', (
      tester,
    ) async {
      final from = StateProvider<DateTime?>((ref) => null);
      final to = StateProvider<DateTime?>((ref) => DateTime(2026, 7, 20));

      await tester.pumpWidget(
        ProviderScope(
          child: _FilterHarness(
            fromProvider: from,
            toProvider: to,
            isFrom: false,
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(_FilterHarness)),
      );
      expect(container.read(from), isNull);
      expect(container.read(to), DateTime(2026, 7, 20));
    });

    testWidgets('caps the picker at today (no future filter dates)', (
      tester,
    ) async {
      final from = StateProvider<DateTime?>((ref) => DateTime(2026, 6, 15));
      final to = StateProvider<DateTime?>((ref) => null);

      await tester.pumpWidget(
        ProviderScope(
          child: _FilterHarness(
            fromProvider: from,
            toProvider: to,
            isFrom: true,
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final now = DateTime.now();
      expect(_dialog(tester).lastDate, DateTime(now.year, now.month, now.day));
    });
  });

  group('pickReportDate (non-nullable report providers)', () {
    testWidgets('writes the confirmed date to the isFrom provider', (
      tester,
    ) async {
      final from = StateProvider<DateTime>((ref) => DateTime(2026, 6, 15));
      final to = StateProvider<DateTime>((ref) => DateTime(2026, 7, 20));

      await tester.pumpWidget(
        ProviderScope(
          child: _ReportHarness(
            fromProvider: from,
            toProvider: to,
            isFrom: true,
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(_ReportHarness)),
      );
      expect(container.read(from), DateTime(2026, 6, 15));
      expect(container.read(to), DateTime(2026, 7, 20));
    });

    testWidgets('writes the confirmed date to the isTo provider', (
      tester,
    ) async {
      final from = StateProvider<DateTime>((ref) => DateTime(2026, 6, 15));
      final to = StateProvider<DateTime>((ref) => DateTime(2026, 7, 20));

      await tester.pumpWidget(
        ProviderScope(
          child: _ReportHarness(
            fromProvider: from,
            toProvider: to,
            isFrom: false,
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(_ReportHarness)),
      );
      expect(container.read(from), DateTime(2026, 6, 15));
      expect(container.read(to), DateTime(2026, 7, 20));
    });

    testWidgets('caps the picker at today', (tester) async {
      final from = StateProvider<DateTime>((ref) => DateTime(2026, 6, 15));
      final to = StateProvider<DateTime>((ref) => DateTime(2026, 7, 20));

      await tester.pumpWidget(
        ProviderScope(
          child: _ReportHarness(
            fromProvider: from,
            toProvider: to,
            isFrom: true,
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final now = DateTime.now();
      expect(_dialog(tester).lastDate, DateTime(now.year, now.month, now.day));
    });
  });

  group('DateRangeFilter', () {
    testWidgets('renders From/To labels from the providers', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: _RangeHarness(
            fromProvider: _fromProvider,
            toProvider: _toProvider,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('From'), findsOneWidget);
      expect(find.text('To'), findsOneWidget);
      expect(find.byType(DateRangeFilter), findsOneWidget);
    });

    testWidgets('shows formatted dates once set', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            _fromProvider.overrideWith((ref) => DateTime(2026, 8, 3)),
            _toProvider.overrideWith((ref) => DateTime(2026, 8, 10)),
          ],
          child: _RangeHarness(
            fromProvider: _fromProvider,
            toProvider: _toProvider,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Aug 3, 2026'), findsOneWidget);
      expect(find.text('Aug 10, 2026'), findsOneWidget);
      expect(find.text('From'), findsNothing);
      expect(find.text('To'), findsNothing);
    });

    testWidgets('tapping From opens the picker capped at today', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: _RangeHarness(
            fromProvider: _fromProvider,
            toProvider: _toProvider,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('From'));
      await tester.pumpAndSettle();
      final dialog = _dialog(tester);
      final now = DateTime.now();
      expect(dialog.lastDate, DateTime(now.year, now.month, now.day));
      expect(dialog.firstDate, DateTime(2000));
    });

    testWidgets('writes the confirmed date to the from provider', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: _RangeHarness(
            fromProvider: _fromProvider,
            toProvider: _toProvider,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('From'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(_RangeHarness)),
      );
      final now = DateTime.now();
      expect(
        container.read(_fromProvider),
        DateTime(now.year, now.month, now.day),
      );
      expect(container.read(_toProvider), isNull);
    });

    testWidgets('clear button appears when a date is set and onClear given', (
      tester,
    ) async {
      var cleared = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            _fromProvider.overrideWith((ref) => DateTime(2026, 8, 3)),
          ],
          child: _RangeHarness(
            fromProvider: _fromProvider,
            toProvider: _toProvider,
            onClear: () => cleared++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.filter_alt_off_outlined), findsOneWidget);
      await tester.tap(find.byIcon(Icons.filter_alt_off_outlined));
      expect(cleared, 1);
    });

    testWidgets('clear button hidden when no date is set', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: _RangeHarness(
            fromProvider: _fromProvider,
            toProvider: _toProvider,
            onClear: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.filter_alt_off_outlined), findsNothing);
    });

    testWidgets('showClear override forces the clear button visible', (
      tester,
    ) async {
      var cleared = 0;
      await tester.pumpWidget(
        ProviderScope(
          child: _RangeHarness(
            fromProvider: _fromProvider,
            toProvider: _toProvider,
            onClear: () => cleared++,
            showClear: () => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.filter_alt_off_outlined), findsOneWidget);
    });
  });

  group('ReportDateRangeFilter', () {
    testWidgets('renders colon-prefixed From/To labels', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            _fromReportProvider.overrideWith((ref) => DateTime(2026, 8, 3)),
            _toReportProvider.overrideWith((ref) => DateTime(2026, 8, 10)),
          ],
          child: const _ReportRangeHarness(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('From: Aug 3, 2026'), findsOneWidget);
      expect(find.text('To: Aug 10, 2026'), findsOneWidget);
      expect(find.byType(ReportDateRangeFilter), findsOneWidget);
    });

    testWidgets('renders today-formatted labels by default', (tester) async {
      await tester.pumpWidget(
        ProviderScope(child: const _ReportRangeHarness()),
      );
      await tester.pumpAndSettle();

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      // Independent oracle — matches Formatters.date's yMMMd('en').
      final expected = DateFormat.yMMMd('en').format(today);
      expect(find.text('From: $expected'), findsOneWidget);
      expect(find.text('To: $expected'), findsOneWidget);
    });

    testWidgets('tapping From opens the picker capped at today', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(child: const _ReportRangeHarness()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('From:'));
      await tester.pumpAndSettle();
      final dialog = _dialog(tester);
      final now = DateTime.now();
      expect(dialog.lastDate, DateTime(now.year, now.month, now.day));
      expect(dialog.firstDate, DateTime(2000));
    });

    testWidgets('writes a newly picked date to the from provider', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            _fromReportProvider.overrideWith((ref) => DateTime(2026, 8, 3)),
          ],
          child: const _ReportRangeHarness(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('From:'));
      await tester.pumpAndSettle();
      // Pick a different day than the seeded Aug 3 — proves the write
      // actually happened (OK on the initial date would be tautological).
      await tester.tap(
        find.descendant(
          of: find.byType(CalendarDatePicker),
          matching: find.text('5'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(_ReportRangeHarness)),
      );
      expect(container.read(_fromReportProvider), DateTime(2026, 8, 5));
      // The label re-renders from the updated provider.
      expect(find.text('From: Aug 5, 2026'), findsOneWidget);
      expect(find.text('From: Aug 3, 2026'), findsNothing);
      // The To provider was never touched — still its today default.
      final now = DateTime.now();
      expect(
        container.read(_toReportProvider),
        DateTime(now.year, now.month, now.day),
      );
    });

    testWidgets('To button opens on the to-provider date and writes back', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            _toReportProvider.overrideWith((ref) => DateTime(2026, 8, 2)),
          ],
          child: const _ReportRangeHarness(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('To:'));
      await tester.pumpAndSettle();
      // The picker seeds from the to-provider value.
      expect(_dialog(tester).initialDate, DateTime(2026, 8, 2));

      await tester.tap(
        find.descendant(
          of: find.byType(CalendarDatePicker),
          matching: find.text('6'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(_ReportRangeHarness)),
      );
      expect(container.read(_toReportProvider), DateTime(2026, 8, 6));
      expect(find.text('To: Aug 6, 2026'), findsOneWidget);
      // The From provider was never touched — still its today default.
      final now = DateTime.now();
      expect(
        container.read(_fromReportProvider),
        DateTime(now.year, now.month, now.day),
      );
    });
  });

  group('DateFilterButton', () {
    testWidgets('renders the label and calendar icon and fires onTap', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DateFilterButton(
              label: 'From: Aug 3, 2026',
              onTap: () => taps++,
              width: 120,
              height: 40,
            ),
          ),
        ),
      );

      expect(find.text('From: Aug 3, 2026'), findsOneWidget);
      expect(find.byIcon(Icons.calendar_today_outlined), findsOneWidget);
      expect(find.byType(OutlinedButton), findsOneWidget);

      await tester.tap(find.byType(DateFilterButton));
      expect(taps, 1);
    });

    testWidgets('applies the optional width/height constraints', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DateFilterButton(
              label: 'To',
              onTap: () {},
              width: 120,
              height: 40,
            ),
          ),
        ),
      );
      final box = tester.getSize(find.byType(DateFilterButton));
      expect(box.width, 120);
      expect(box.height, 40);
    });

    testWidgets('renders unconstrained when width/height are omitted', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DateFilterButton(label: 'From', onTap: () {}),
          ),
        ),
      );
      expect(find.byType(DateFilterButton), findsOneWidget);
      expect(find.text('From'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsOneWidget);
    });
  });
}

/// Button harness that calls [pickFilterDate] with the given nullable
/// provider pair.
class _FilterHarness extends ConsumerWidget {
  const _FilterHarness({
    required this.fromProvider,
    required this.toProvider,
    required this.isFrom,
  });

  final StateProvider<DateTime?> fromProvider;
  final StateProvider<DateTime?> toProvider;
  final bool isFrom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => pickFilterDate(
                context,
                ref,
                fromProvider: fromProvider,
                toProvider: toProvider,
                isFrom: isFrom,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }
}

/// Button harness that calls [pickReportDate] with the given
/// non-nullable provider pair.
class _ReportHarness extends ConsumerWidget {
  const _ReportHarness({
    required this.fromProvider,
    required this.toProvider,
    required this.isFrom,
  });

  final StateProvider<DateTime> fromProvider;
  final StateProvider<DateTime> toProvider;
  final bool isFrom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => pickReportDate(
                context,
                ref,
                fromProvider: fromProvider,
                toProvider: toProvider,
                isFrom: isFrom,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared nullable provider pair for the [DateRangeFilter] tests —
/// recreated per group via overrides where a seeded value is needed.
final _fromProvider = StateProvider<DateTime?>((ref) => null);
final _toProvider = StateProvider<DateTime?>((ref) => null);

/// Shared non-nullable provider pair for the [ReportDateRangeFilter]
/// tests — defaults to today so the widget renders without overrides.
final _fromReportProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});
final _toReportProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

/// Renders a [DateRangeFilter] inside the app's l10n MaterialApp so the
/// widget can resolve `AppLocalizations` and intl date formats.
class _RangeHarness extends ConsumerWidget {
  const _RangeHarness({
    required this.fromProvider,
    required this.toProvider,
    this.onClear,
    this.showClear,
  });

  final StateProvider<DateTime?> fromProvider;
  final StateProvider<DateTime?> toProvider;
  final VoidCallback? onClear;
  final bool Function()? showClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: DateRangeFilter(
            fromProvider: fromProvider,
            toProvider: toProvider,
            onClear: onClear,
            showClear: showClear,
          ),
        ),
      ),
    );
  }
}

/// Renders a [ReportDateRangeFilter] bound to the shared non-nullable
/// provider pair, inside the app's l10n MaterialApp.
class _ReportRangeHarness extends ConsumerWidget {
  const _ReportRangeHarness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: ReportDateRangeFilter(
            fromProvider: _fromReportProvider,
            toProvider: _toReportProvider,
          ),
        ),
      ),
    );
  }
}
