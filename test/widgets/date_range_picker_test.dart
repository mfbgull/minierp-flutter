// Widget tests for the Phase 3 date-range picker
// (`lib/widgets/date_range_picker.dart`): the pill bar, the anchored
// popover (presets sidebar + dual-month calendar), instant-apply
// selection, shift arrows, single-date mode, keyboard nav, and the dark
// theme (spec §9.2 / tasks T3.1–T3.4).

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:minierp_app/core/api/api_client.dart' show dioProvider;
import 'package:minierp_app/core/utils/date_range_math.dart';
import 'package:minierp_app/core/utils/date_utils.dart' show isoDate;
import 'package:minierp_app/core/utils/formatters.dart';
import 'package:minierp_app/features/preferences/preference_providers.dart';
import 'package:minierp_app/l10n/app_localizations.dart';
import 'package:minierp_app/widgets/date_range_picker.dart';

/// In-memory fake for GET/PUT /api/preferences — the picker's week-start
/// / default-range / preset writes go through the Phase 2 save helpers,
/// so tests override dio to keep them hermetic (mirrors the Phase 2 fake).
class _PrefsFakeAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == '/preferences' && options.method == 'PUT') {
      final body = jsonDecode(options.data as String) as Map<String, dynamic>;
      return _json({
        'success': true,
        'data': {
          'weekStart': body['weekStart'] ?? 'monday',
          'defaultRange': body['defaultRange'],
          'presets': body['presets'] ?? <Object>[],
        },
      });
    }
    return _json({
      'success': false,
      'error': {'code': 'NOT_FOUND', 'message': 'Not found'},
    }, status: 404);
  }

  ResponseBody _json(Object body, {int status = 200}) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
  );
}

Dio _dio() =>
    Dio(BaseOptions(baseUrl: 'http://localhost:3011/api'))
      ..httpClientAdapter = _PrefsFakeAdapter();

/// Shared nullable provider pair for the pill harness — values overridden
/// per test.
final _fromProvider = StateProvider<DateTime?>((ref) => null);
final _toProvider = StateProvider<DateTime?>((ref) => null);
final _dateProvider = StateProvider<DateTime?>((ref) => null);

/// Pumps a [DateRangeFilter] inside the app's l10n MaterialApp with the
/// fake preferences backend, so the widget resolves `AppLocalizations`,
/// intl date formats, and the preference write-through providers.
Widget _harness({
  DateTime? from,
  DateTime? to,
  DateRangeMode mode = DateRangeMode.range,
  bool showAllDates = true,
  VoidCallback? onChanged,
  VoidCallback? onClear,
  bool Function()? showClear,
  ThemeData? theme,
}) {
  return ProviderScope(
    overrides: [
      dioProvider.overrideWithValue(_dio()),
      _fromProvider.overrideWith((ref) => from),
      _toProvider.overrideWith((ref) => to),
    ],
    child: MaterialApp(
      theme: theme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: DateRangeFilter(
            fromProvider: _fromProvider,
            toProvider: _toProvider,
            mode: mode,
            showAllDates: showAllDates,
            dateProvider: mode == DateRangeMode.singleDate ? _dateProvider : null,
            onChanged: onChanged,
            onClear: onClear,
            showClear: showClear,
          ),
        ),
      ),
    ),
  );
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(DateRangeFilter)));

/// Today's normalized date — the widget's "today".
DateTime get _today => dateOnly(DateTime.now());

/// Finder for a single day cell via its stable `drp-day-YYYY-MM-DD` key
/// (day numbers repeat across the two visible months, so text finders
/// are ambiguous).
Finder _dayCell(int day) {
  final d = DateTime(_today.year, _today.month, day);
  return find.byKey(ValueKey('drp-day-${isoDate(d)}'));
}

void main() {
  setUpAll(() async {
    // Pill labels + month titles run through intl DateFormat.
    await initializeDateFormatting('en');
  });

  group('pill bar', () {
    testWidgets('shows "All dates" when both providers are null', (
      tester,
    ) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      expect(find.text('All dates'), findsOneWidget);
      expect(find.byType(DateRangeFilter), findsOneWidget);
      // No preset chip when there is no range.
      expect(find.text('Custom'), findsNothing);
    });

    testWidgets('renders compact range text and the matched preset chip', (
      tester,
    ) async {
      final range = presetRange(DatePreset.thisWeek, _today, WeekStart.monday);
      await tester.pumpWidget(
        _harness(from: range.from, to: range.to),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(Formatters.compactRange(range.from, range.to)),
        findsOneWidget,
      );
      expect(find.text('This week'), findsOneWidget);
    });

    testWidgets('shows a Custom chip when the range matches no preset', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          from: DateTime(2026, 6, 3),
          to: DateTime(2026, 6, 21),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Custom'), findsOneWidget);
    });

    testWidgets('clear button follows the onClear/showClear contract', (
      tester,
    ) async {
      // Both null → hidden even with onClear.
      await tester.pumpWidget(_harness(onClear: () {}));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.filter_alt_off_outlined), findsNothing);

      // Tear the tree down so the next pump builds a fresh container
      // (re-pumping the same harness in place reuses the provider state).
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      // One set → visible.
      await tester.pumpWidget(
        _harness(from: DateTime(2026, 8, 3), onClear: () {}),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.filter_alt_off_outlined), findsOneWidget);
    });

    testWidgets('clear button fires onClear then onChanged', (tester) async {
      var cleared = 0;
      var changed = 0;
      await tester.pumpWidget(
        _harness(
          from: DateTime(2026, 8, 3),
          onClear: () => cleared++,
          onChanged: () => changed++,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.filter_alt_off_outlined));
      expect(cleared, 1);
      expect(changed, 1);
    });
  });

  group('popover', () {
    testWidgets('opens on pill tap with presets + dual months', (
      tester,
    ) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      await tester.tap(find.text('All dates'));
      await tester.pumpAndSettle();

      expect(find.text('Today'), findsWidgets);
      expect(find.text('This week'), findsWidgets);
      expect(find.text('Last 7 days'), findsWidgets);
      expect(find.text('Last 30 days'), findsWidgets);
      expect(find.text('This month'), findsWidgets);
      expect(find.text('Custom range'), findsWidgets);
      // Both months of the pair are rendered.
      expect(find.text('Pick a start date'), findsOneWidget);
    });

    testWidgets('tapping the pill again closes it', (tester) async {
      // Tall surface so the panel opens *below* the pill (the default
      // 800×600 would flip it up over the pill, making the pill
      // unreachable and this test about the barrier, not the toggle).
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      await tester.tap(find.text('All dates'));
      await tester.pumpAndSettle();
      expect(find.text('This week'), findsWidgets);

      // Tap the pill's calendar icon (the open panel also shows an
      // "All dates" sidebar tile, so a text finder is ambiguous).
      await tester.tap(find.byIcon(Icons.calendar_month_outlined));
      await tester.pumpAndSettle();
      expect(find.text('This week'), findsNothing);
      expect(find.text('Pick a start date'), findsNothing);
    });

    testWidgets('Escape closes the panel', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      await tester.tap(find.text('All dates'));
      await tester.pumpAndSettle();
      expect(find.text('This week'), findsWidgets);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('This week'), findsNothing);
    });
  });

  group('instant apply', () {
    testWidgets('a preset click commits, fires onChanged, and closes', (
      tester,
    ) async {
      var changed = 0;
      await tester.pumpWidget(_harness(onChanged: () => changed++));
      await tester.pumpAndSettle();

      await tester.tap(find.text('All dates'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('This week').last);
      await tester.pumpAndSettle();

      final container = _container(tester);
      final expected = presetRange(DatePreset.thisWeek, _today, WeekStart.monday);
      expect(container.read(_fromProvider), expected.from);
      expect(container.read(_toProvider), expected.to);
      expect(changed, 1);
      // Panel closed; pill chip reflects the preset.
      expect(find.text('Pick a start date'), findsNothing);
      expect(find.text('This week'), findsOneWidget);
    });

    testWidgets('custom two-click commits on the end pick', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      await tester.tap(find.text('All dates'));
      await tester.pumpAndSettle();

      // First click → start only, hint switches.
      await tester.tap(_dayCell(11));
      await tester.pumpAndSettle();
      expect(find.text('Pick an end date'), findsOneWidget);

      // Second click → commit and close.
      await tester.tap(_dayCell(18));
      await tester.pumpAndSettle();

      final container = _container(tester);
      expect(container.read(_fromProvider), DateTime(_today.year, _today.month, 11));
      expect(container.read(_toProvider), DateTime(_today.year, _today.month, 18));
      expect(find.text('Pick an end date'), findsNothing);
    });

    testWidgets('swaps when the end precedes the start', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      await tester.tap(find.text('All dates'));
      await tester.pumpAndSettle();
      await tester.tap(_dayCell(18));
      await tester.pumpAndSettle();
      await tester.tap(_dayCell(11));
      await tester.pumpAndSettle();

      final container = _container(tester);
      expect(container.read(_fromProvider), DateTime(_today.year, _today.month, 11));
      expect(container.read(_toProvider), DateTime(_today.year, _today.month, 18));
    });

    testWidgets('clicking the same day twice commits a single-day range', (
      tester,
    ) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      await tester.tap(find.text('All dates'));
      await tester.pumpAndSettle();
      await tester.tap(_dayCell(15));
      await tester.pumpAndSettle();
      await tester.tap(_dayCell(15));
      await tester.pumpAndSettle();

      final container = _container(tester);
      expect(container.read(_fromProvider), DateTime(_today.year, _today.month, 15));
      expect(container.read(_toProvider), DateTime(_today.year, _today.month, 15));
    });

    testWidgets('closing without an end discards the pending start', (
      tester,
    ) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      await tester.tap(find.text('All dates'));
      await tester.pumpAndSettle();
      await tester.tap(_dayCell(11));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      final container = _container(tester);
      expect(container.read(_fromProvider), isNull);
      expect(container.read(_toProvider), isNull);
    });

    testWidgets('"All dates" preset clears both providers', (tester) async {
      final range = presetRange(DatePreset.thisWeek, _today, WeekStart.monday);
      await tester.pumpWidget(_harness(from: range.from, to: range.to));
      await tester.pumpAndSettle();

      await tester.tap(find.text('This week'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All dates'));
      await tester.pumpAndSettle();

      final container = _container(tester);
      expect(container.read(_fromProvider), isNull);
      expect(container.read(_toProvider), isNull);
      expect(find.text('All dates'), findsOneWidget);
    });
  });

  group('shift arrows', () {
    testWidgets('shifts a week preset by 7 days and commits', (tester) async {
      final range = presetRange(DatePreset.lastWeek, _today, WeekStart.monday);
      await tester.pumpWidget(_harness(from: range.from, to: range.to));
      await tester.pumpAndSettle();

      final type = shiftTypeForRange((from: range.from, to: range.to), _today, WeekStart.monday);
      final shifted = shiftRangeClamped(
        (from: range.from, to: range.to),
        type,
        1,
        _today,
      );
      expect(shifted, isNotNull);

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();

      final container = _container(tester);
      expect(container.read(_fromProvider), shifted!.from);
      expect(container.read(_toProvider), shifted.to);
    });

    testWidgets('forward arrow is disabled once the range start hits today', (
      tester,
    ) async {
      final today = _today;
      await tester.pumpWidget(_harness(from: today, to: today));
      await tester.pumpAndSettle();

      final right = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_right),
      );
      expect(right.onPressed, isNull);
    });

    testWidgets('arrows are disabled on "All dates"', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.chevron_left),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.chevron_right),
            )
            .onPressed,
        isNull,
      );
    });
  });

  group('week start', () {
    testWidgets('changing the week start persists and reorders the grid', (
      tester,
    ) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      await tester.tap(find.text('All dates'));
      await tester.pumpAndSettle();

      // The grid header currently starts Monday-first (Mo first).
      expect(find.text('Mo'), findsWidgets);
      await tester.tap(find.text('Sunday'));
      await tester.pumpAndSettle();

      final container = _container(tester);
      expect(container.read(weekStartProvider), WeekStart.sunday);
      // First weekday cell is now Su.
      expect(find.text('Su'), findsWidgets);
    });
  });

  group('single-date mode', () {
    testWidgets('pill shows the date; reduced presets; tap-a-day commits', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(mode: DateRangeMode.singleDate),
      );
      await tester.pumpAndSettle();

      // Pill shows today's date (null provider → today) — never the
      // range-mode "All dates" fallback.
      expect(find.text('All dates'), findsNothing);
      expect(find.text(Formatters.date(isoDate(_today))), findsOneWidget);

      await tester.tap(find.byType(DateRangeFilter));
      await tester.pumpAndSettle();

      // Reduced preset set — no week/span presets.
      expect(find.text('Today'), findsWidgets);
      expect(find.text('Yesterday'), findsWidgets);
      expect(find.text('This month'), findsWidgets);
      expect(find.text('This week'), findsNothing);
      expect(find.text('Custom range'), findsNothing);

      // Tap a day → commits immediately.
      await tester.tap(_dayCell(20));
      await tester.pumpAndSettle();

      final container = _container(tester);
      expect(container.read(_dateProvider), DateTime(_today.year, _today.month, 20));
      expect(find.text('Pick a date'), findsNothing);
    });

    testWidgets('arrows shift ±1 day and stop at today', (tester) async {
      final today = _today;
      final dateProvider = StateProvider<DateTime?>(
        (ref) => DateTime(today.year, today.month, today.day - 2),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dioProvider.overrideWithValue(_dio()),
            dateProvider.overrideWith((ref) => DateTime(today.year, today.month, today.day - 2)),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Center(
                child: DateRangeFilter(
                  fromProvider: _fromProvider,
                  toProvider: _toProvider,
                  mode: DateRangeMode.singleDate,
                  dateProvider: dateProvider,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Shift forward one day.
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(DateRangeFilter)),
      );
      expect(container.read(dateProvider), DateTime(today.year, today.month, today.day - 1));

      // Reaching today disables the forward arrow.
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      expect(container.read(dateProvider), today);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.chevron_right),
            )
            .onPressed,
        isNull,
      );
    });
  });

  group('keyboard navigation', () {
    testWidgets('arrow keys move focus and Enter selects', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      await tester.tap(find.text('All dates'));
      await tester.pumpAndSettle();

      // Focus day 11 of the visible month — `.first` is the cell's own
      // Focus (the panel root also has one further up the ancestry).
      tester
          .widget<Focus>(
            find.ancestor(
              of: _dayCell(11),
              matching: find.byType(Focus),
            ).first,
          )
          .focusNode!
          .requestFocus();
      await tester.pumpAndSettle();

      // Enter selects the focused day as the start…
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      // …arrow right moves focus to day 12…
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      // …Enter commits the end → 11–12.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      final container = _container(tester);
      expect(container.read(_fromProvider), DateTime(_today.year, _today.month, 11));
      expect(container.read(_toProvider), DateTime(_today.year, _today.month, 12));
    });

    testWidgets('arrow keys work immediately after opening (no click)', (
      tester,
    ) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      // Open on "All dates" → the anchor day is today, and opening
      // hands keyboard focus to that cell (reviewer fix #4).
      await tester.tap(find.text('All dates'));
      await tester.pumpAndSettle();

      // Arrow right → focus tomorrow, Enter twice → single-day commit.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      final container = _container(tester);
      final tomorrow = addDays(_today, 1);
      expect(container.read(_fromProvider), tomorrow);
      expect(container.read(_toProvider), tomorrow);
    });

    testWidgets('PageUp/PageDown page the month pair', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      await tester.tap(find.text('All dates'));
      await tester.pumpAndSettle();

      final before = _monthTitles(tester);
      tester
          .widget<Focus>(
            find.ancestor(
              of: _dayCell(11),
              matching: find.byType(Focus),
            ).first,
          )
          .focusNode!
          .requestFocus();
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      final after = _monthTitles(tester);
      expect(after, isNot(before));
    });
  });

  group('theme', () {
    testWidgets('renders in dark mode without overflow', (tester) async {
      await tester.pumpWidget(
        _harness(theme: ThemeData(brightness: Brightness.dark)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('All dates'));
      await tester.pumpAndSettle();

      expect(find.text('This week'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}

/// The month titles currently visible in the popover (e.g. "August 2026").
List<String> _monthTitles(WidgetTester tester) {
  final titles = <String>[];
  for (final element in tester.elementList(find.byType(Text))) {
    final text = (element.widget as Text).data;
    if (text != null && RegExp(r'^[A-Za-z]+ \d{4}$').hasMatch(text)) {
      titles.add(text);
    }
  }
  return titles;
}


