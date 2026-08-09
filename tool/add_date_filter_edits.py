#!/usr/bin/env python3
"""Add the DateRangeFilter to the activity log module: providers, screen
toolbar, repo-test date params, and a widget test for the wiring."""
import sys

# --- A. Providers -----------------------------------------------------
p = 'lib/features/activity_log/activity_log_providers.dart'
t = open(p, encoding='utf-8').read()

old1 = "import '../../data/models/activity_log.dart'\n    show ActivityLog, ActivityLogUser, ActivityStats;"
new1 = "import '../../core/utils/date_utils.dart' show isoDate;\nimport '../../data/models/activity_log.dart'\n    show ActivityLog, ActivityLogUser, ActivityStats;"
if old1 not in t:
    print('A1 NOT FOUND', file=sys.stderr)
    sys.exit(1)
t = t.replace(old1, new1, 1)

old2 = """/// Active user filter; null = all (`GET /activity-logs/users`).
final activityLogUserIdProvider = StateProvider<int?>((ref) => null);
"""
new2 = """/// Active user filter; null = all (`GET /activity-logs/users`).
final activityLogUserIdProvider = StateProvider<int?>((ref) => null);

/// Inclusive date-range filter — null means unbounded (sent as
/// `start_date`/`end_date`).
final activityLogFromDateProvider = StateProvider<DateTime?>((ref) => null);
final activityLogToDateProvider = StateProvider<DateTime?>((ref) => null);
"""
if old2 not in t:
    print('A2 NOT FOUND', file=sys.stderr)
    sys.exit(1)
t = t.replace(old2, new2, 1)

old3 = """  final entityType = ref.watch(activityLogEntityTypeProvider);
  final action = ref.watch(activityLogActionProvider);
  final userId = ref.watch(activityLogUserIdProvider);

  final result = await ref
      .watch(activityLogRepositoryProvider)
      .logs(
        ActivityLogFilters(
          search: search.isEmpty ? null : search,
          offset: (page - 1) * limit,
          limit: limit,
          entityType: entityType,
          action: action,
          userId: userId,
        ),
      );
"""
new3 = """  final entityType = ref.watch(activityLogEntityTypeProvider);
  final action = ref.watch(activityLogActionProvider);
  final userId = ref.watch(activityLogUserIdProvider);
  final from = ref.watch(activityLogFromDateProvider);
  final to = ref.watch(activityLogToDateProvider);

  final result = await ref
      .watch(activityLogRepositoryProvider)
      .logs(
        ActivityLogFilters(
          search: search.isEmpty ? null : search,
          offset: (page - 1) * limit,
          limit: limit,
          entityType: entityType,
          action: action,
          userId: userId,
          startDate: from == null ? null : isoDate(from),
          endDate: to == null ? null : isoDate(to),
        ),
      );
"""
if old3 not in t:
    print('A3 NOT FOUND', file=sys.stderr)
    sys.exit(1)
t = t.replace(old3, new3, 1)
open(p, 'w', encoding='utf-8').write(t)
print('A OK')

# --- B. Screen ---------------------------------------------------------
p = 'lib/features/activity_log/activity_log_screen.dart'
t = open(p, encoding='utf-8').read()

old1 = "import '../../widgets/pagination_bar.dart';"
new1 = "import '../../widgets/date_picker_helpers.dart' show DateRangeFilter;\nimport '../../widgets/pagination_bar.dart';"
if old1 not in t:
    print('B1 NOT FOUND', file=sys.stderr)
    sys.exit(1)
t = t.replace(old1, new1, 1)

old2 = """  /// The provider yields an `OffsetPagedResponse` envelope — unwrap the
  /// page rows for the grid.
  @override
  Iterable<ActivityLog> gridRowsFrom(Object? value) =>
      (value as OffsetPagedResponse<ActivityLog>).items;
"""
new2 = """  bool get _hasActiveFilters =>
      ref.read(activityLogEntityTypeProvider) != null ||
      ref.read(activityLogActionProvider) != null ||
      ref.read(activityLogUserIdProvider) != null ||
      ref.read(activityLogFromDateProvider) != null ||
      ref.read(activityLogToDateProvider) != null;

  /// Resets every toolbar filter (including the date range) back to page 1.
  void _clearFilters() {
    ref.read(activityLogEntityTypeProvider.notifier).state = null;
    ref.read(activityLogActionProvider.notifier).state = null;
    ref.read(activityLogUserIdProvider.notifier).state = null;
    ref.read(activityLogFromDateProvider.notifier).state = null;
    ref.read(activityLogToDateProvider.notifier).state = null;
    if (ref.read(activityLogPageProvider) != 1) {
      ref.read(activityLogPageProvider.notifier).state = 1;
    }
  }

  /// The provider yields an `OffsetPagedResponse` envelope — unwrap the
  /// page rows for the grid.
  @override
  Iterable<ActivityLog> gridRowsFrom(Object? value) =>
      (value as OffsetPagedResponse<ActivityLog>).items;
"""
if old2 not in t:
    print('B2 NOT FOUND', file=sys.stderr)
    sys.exit(1)
t = t.replace(old2, new2, 1)

old3 = """          width: 140,
        ),
        const SizedBox(width: 8),
        TextButton.icon(
"""
new3 = """          width: 140,
        ),
        const SizedBox(width: 8),
        DateRangeFilter(
          height: 40,
          fromProvider: activityLogFromDateProvider,
          toProvider: activityLogToDateProvider,
          onClear: _clearFilters,
          showClear: () => _hasActiveFilters,
        ),
        const SizedBox(width: 8),
        TextButton.icon(
"""
if old3 not in t:
    print('B3 NOT FOUND', file=sys.stderr)
    sys.exit(1)
t = t.replace(old3, new3, 1)
open(p, 'w', encoding='utf-8').write(t)
print('B OK')

# --- C. Repo test ------------------------------------------------------
p = 'test/repositories/repositories_test.dart'
t = open(p, encoding='utf-8').read()

old = """        final result = await repo.logs(
          ActivityLogFilters(
            search: 'invoice',
            entityType: 'Invoice',
            action: 'CREATE',
            userId: 1,
            limit: 50,
            offset: 50,
          ),
        );
        expect(seenQuery!['search'], 'invoice');
        expect(seenQuery!['entity_type'], 'Invoice');
        expect(seenQuery!['action'], 'CREATE');
        expect(seenQuery!['user_id'], 1);
        expect(seenQuery!['limit'], 50);
        expect(seenQuery!['offset'], 50);
"""
new = """        final result = await repo.logs(
          ActivityLogFilters(
            search: 'invoice',
            entityType: 'Invoice',
            action: 'CREATE',
            userId: 1,
            startDate: '2026-08-01',
            endDate: '2026-08-09',
            limit: 50,
            offset: 50,
          ),
        );
        expect(seenQuery!['search'], 'invoice');
        expect(seenQuery!['entity_type'], 'Invoice');
        expect(seenQuery!['action'], 'CREATE');
        expect(seenQuery!['user_id'], 1);
        expect(seenQuery!['start_date'], '2026-08-01');
        expect(seenQuery!['end_date'], '2026-08-09');
        expect(seenQuery!['limit'], 50);
        expect(seenQuery!['offset'], 50);
"""
if old not in t:
    print('C NOT FOUND', file=sys.stderr)
    sys.exit(1)
t = t.replace(old, new, 1)
open(p, 'w', encoding='utf-8').write(t)
print('C OK')

# --- D. Widget test ----------------------------------------------------
p = 'test/widget_test.dart'
t = open(p, encoding='utf-8').read()

old1 = "import 'package:minierp_app/features/auth/change_password_screen.dart';"
new1 = """import 'package:minierp_app/features/activity_log/activity_log_providers.dart'
    show activityLogFromDateProvider, activityLogToDateProvider;
import 'package:minierp_app/features/activity_log/activity_log_screen.dart'
    show ActivityLogScreen;
import 'package:minierp_app/features/auth/change_password_screen.dart';"""
if old1 not in t:
    print('D1 NOT FOUND', file=sys.stderr)
    sys.exit(1)
t = t.replace(old1, new1, 1)

old2 = """  /// When true, the cleanup POST rejects with a 400 (failure-path test).
  bool rejectCleanup = false;
"""
new2 = """  /// When true, the cleanup POST rejects with a 400 (failure-path test).
  bool rejectCleanup = false;

  /// Captured query params of the last /activity-logs list GET.
  Map<String, dynamic>? lastActivityLogsQuery;
"""
if old2 not in t:
    print('D2 NOT FOUND', file=sys.stderr)
    sys.exit(1)
t = t.replace(old2, new2, 1)

old3 = """    if (options.path == '/activity-logs' && options.method == 'GET') {
      final search =
"""
new3 = """    if (options.path == '/activity-logs' && options.method == 'GET') {
      lastActivityLogsQuery = options.queryParameters;
      final search =
"""
if old3 not in t:
    print('D3 NOT FOUND', file=sys.stderr)
    sys.exit(1)
t = t.replace(old3, new3, 1)

old4 = """    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Clean up old logs'), findsNothing);
  });

  // Reports module — hub + the first report screens (PORTING.md §11).
"""
new4 = """    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Clean up old logs'), findsNothing);
  });

  testWidgets('activity log date-range filter sends start_date/end_date', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToActivityLog(tester, adapter: adapter);

    // From/To buttons from the shared DateRangeFilter render in the
    // toolbar.
    expect(find.text('From'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);

    // Set the range through the providers (the filter's own date-picker
    // interaction is covered by date_picker_helpers_test.dart).
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ActivityLogScreen)),
    );
    container.read(activityLogFromDateProvider.notifier).state =
        DateTime(2026, 8, 1);
    await tester.pumpAndSettle();
    container.read(activityLogToDateProvider.notifier).state = DateTime(
      2026,
      8,
      9,
    );
    await tester.pumpAndSettle();

    expect(adapter.lastActivityLogsQuery?['start_date'], '2026-08-01');
    expect(adapter.lastActivityLogsQuery?['end_date'], '2026-08-09');

    // The clear button resets the range and refetches without dates.
    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();
    expect(adapter.lastActivityLogsQuery?['start_date'], isNull);
    expect(adapter.lastActivityLogsQuery?['end_date'], isNull);
  });

  // Reports module — hub + the first report screens (PORTING.md §11).
"""
if old4 not in t:
    print('D4 NOT FOUND', file=sys.stderr)
    sys.exit(1)
t = t.replace(old4, new4, 1)
open(p, 'w', encoding='utf-8').write(t)
print('D OK')
