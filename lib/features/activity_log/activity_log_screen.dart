// Activity log screen — PORTING.md §5 (`/activity-log` →
// `ActivityLogScreen`) over `GET /activity-logs`.
//
// Built on the shared [PlutoGridScreen] mixin: F2/Enter + double-tap open
// the focused row's detail, and the keyboard-hint status bar sits beneath
// the grid. The one mixin override beyond the data mapping is
// [gridRowsFrom] — the provider yields an `OffsetPagedResponse` envelope
// (the server returns raw `total/limit/offset` counters, not a
// `pagination` block), so the screen unwraps it and renders a
// [ServerPaginationBar] under the grid like the customers screen.
//
// Toolbar: search + entity-type/action/user dropdowns (options come from
// the server), CSV export of the current page, refresh, and an admin-only
// Cleanup action (`POST /activity-logs/cleanup`). A compact
// stats strip above the grid shows the totals from `GET
// /activity-logs/stats`.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/auth/auth_notifier.dart' show authProvider;
import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/activity_log.dart' show ActivityCount, ActivityLog;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../data/repositories/paged_request.dart' show OffsetPagedResponse;
import '../../l10n/app_localizations.dart';
import '../../widgets/date_range_picker.dart' show DateRangeFilter;
import '../../widgets/pagination_bar.dart';
import '../../widgets/pluto_grid_screen.dart';
import '../../widgets/screen_error_panel.dart';
import '../../widgets/screen_toolbar.dart';
import '../../widgets/status_badge.dart';
import 'activity_log_cleanup_dialog.dart';
import 'activity_log_detail_dialog.dart';
import 'activity_log_presenters.dart';
import 'activity_log_providers.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';

class ActivityLogScreen extends ConsumerStatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  ConsumerState<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends ConsumerState<ActivityLogScreen>
    with PlutoGridScreen<ActivityLog, ActivityLogScreen> {
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      ref.read(activityLogSearchProvider.notifier).state = value.trim();
      // A new search starts back at page 1.
      if (ref.read(activityLogPageProvider) != 1) {
        ref.read(activityLogPageProvider.notifier).state = 1;
      }
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    ref.read(activityLogSearchProvider.notifier).state = '';
    if (ref.read(activityLogPageProvider) != 1) {
      ref.read(activityLogPageProvider.notifier).state = 1;
    }
  }

  bool get _hasActiveFilters =>
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

  /// Opt into the per-row ⋮ actions menu (View detail).
  @override
  bool get hasRowActions => true;

  @override
  List<GridRowAction>? gridRowActionsFor(PlutoRow row, BuildContext context) {
    final id = row.cells['id']?.value as int?;
    if (id == null || id <= 0) return null;
    final logs =
        ref.read(activityLogsProvider).valueOrNull?.items ??
        const <ActivityLog>[];
    for (final log in logs) {
      if (log.id == id) {
        final l10n = AppLocalizations.of(context)!;
        return [
          GridRowAction(
            icon: Icons.visibility_outlined,
            label: l10n.commonView,
            onTap: () => showActivityLogDetailDialog(context, log: log),
          ),
        ];
      }
    }
    return null;
  }

  @override
  PlutoRow gridRowFor(ActivityLog log) => PlutoRow(
    cells: {
      'id': PlutoCell(value: log.id),
      'timestamp': PlutoCell(value: log.createdAt),
      'user': PlutoCell(value: log.username ?? ''),
      'action': PlutoCell(value: log.action),
      'entity': PlutoCell(value: log.entityLabel),
      'description': PlutoCell(value: log.description),
      'level': PlutoCell(value: log.logLevel),
    },
  );

  /// The grid row only exists when the provider has data, so the lookup
  /// always succeeds (defensive no-op otherwise).
  @override
  void openRowDetail(int rowId) {
    final logs =
        ref.read(activityLogsProvider).valueOrNull?.items ??
        const <ActivityLog>[];
    for (final log in logs) {
      if (log.id == rowId) {
        showActivityLogDetailDialog(context, log: log);
        return;
      }
    }
  }

  @override
  List<PlutoColumn> buildGridColumns(AppLocalizations l10n) {
    PlutoColumn textColumn(String field, String title, double width) =>
        PlutoColumn(
          title: title,
          field: field,
          type: PlutoColumnType.text(),
          width: width,
          readOnly: true,
          enableContextMenu: false,
        );

    return [
      PlutoColumn(
        title: '',
        field: 'id',
        type: PlutoColumnType.number(),
        width: 80,
        readOnly: true,
        renderer: (ctx) => const SizedBox.shrink(),
        enableContextMenu: false,
        enableFilterMenuItem: false,
        enableHideColumnMenuItem: false,
        enableSetColumnsMenuItem: false,
      ),
      PlutoColumn(
        title: l10n.activitylogTimestamp,
        field: 'timestamp',
        type: PlutoColumnType.text(),
        width: 170,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) => Align(
          alignment: Alignment.centerLeft,
          child: Text(formatActivityTimestamp(ctx.cell.value as String? ?? '')),
        ),
      ),
      textColumn('user', l10n.activitylogUser, 110),
      textColumn('action', l10n.activitylogAction, 120),
      textColumn('entity', l10n.activitylogEntity, 160),
      textColumn('description', l10n.commonDescription, 300),
      PlutoColumn(
        title: l10n.activitylogLevel,
        field: 'level',
        type: PlutoColumnType.text(),
        width: 110,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) => Builder(
          builder: (cellContext) {
            final level = ctx.cell.value as String? ?? '';
            return Align(
              alignment: Alignment.centerLeft,
              child: StatusBadge(
                status: level,
                color: activityLogLevelColor(Theme.of(cellContext).colorScheme, level),
              ),
            );
          },
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(activityLogsProvider);
    final page = logs.valueOrNull;
    final l10n = AppLocalizations.of(context)!;

    // Explicit failure panel before the grid so provider errors are not
    // silently swallowed by the shared grid mixin.
    if (logs.hasError) {
      final message = logs.error is ApiError
          ? (logs.error as ApiError).message
          : '$logs.error';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _toolbar(l10n, logs),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _statsStrip(l10n),
          ),
          Expanded(
            child: ScreenErrorPanel(
              message: message,
              onRetry: () => ref.invalidate(activityLogsProvider),
            ),
          ),
        ],
      );
    }

    // Keep the grid in sync with provider transitions (loading → data).
    watchGridProvider(activityLogsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _toolbar(l10n, logs),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: _statsStrip(l10n),
        ),
        Expanded(child: gridScreenBody(logs, provider: activityLogsProvider)),
        if (page != null)
          ServerPaginationBar(
            page: page.page,
            totalPages: page.totalPages,
            totalItems: page.total,
            hasNext: page.hasNext,
            hasPrev: page.hasPrev,
            limit: ref.watch(activityLogLimitProvider),
            itemLabel: l10n.activitylogCount,
            onPageChanged: (p) =>
                ref.read(activityLogPageProvider.notifier).state = p,
            onLimitChanged: (limit) {
              ref.read(activityLogLimitProvider.notifier).state = limit;
              if (ref.read(activityLogPageProvider) != 1) {
                ref.read(activityLogPageProvider.notifier).state = 1;
              }
            },
          ),
      ],
    );
  }

  Widget _toolbar(
    AppLocalizations l10n,
    AsyncValue<OffsetPagedResponse<ActivityLog>> logs,
  ) {
    final entityTypes =
        ref.watch(activityEntityTypesProvider).valueOrNull ?? const [];
    final actions = ref.watch(activityActionsProvider).valueOrNull ?? const [];
    final users = ref.watch(activityUsersProvider).valueOrNull ?? const [];

    return ScreenToolbar(
      searchController: _searchController,
      searchHint: l10n.commonSearch,
      onSearchChanged: _onSearchChanged,
      onClearSearch: _clearSearch,
      filters: [
        ScreenToolbarDropdown<String?>(
          key: const ValueKey('activity-entity-filter'),
          value: ref.watch(activityLogEntityTypeProvider),
          hint: l10n.activitylogAllentities,
          items: [null, ...entityTypes],
          labelBuilder: (v) => v ?? l10n.activitylogAllentities,
          width: 170,
          onChanged: (v) {
            ref.read(activityLogEntityTypeProvider.notifier).state = v;
            if (ref.read(activityLogPageProvider) != 1) {
              ref.read(activityLogPageProvider.notifier).state = 1;
            }
          },
        ),
        ScreenToolbarDropdown<String?>(
          key: const ValueKey('activity-action-filter'),
          value: ref.watch(activityLogActionProvider),
          hint: l10n.activitylogAllactions,
          items: [null, ...actions],
          labelBuilder: (v) => v ?? l10n.activitylogAllactions,
          width: 140,
          onChanged: (v) {
            ref.read(activityLogActionProvider.notifier).state = v;
            if (ref.read(activityLogPageProvider) != 1) {
              ref.read(activityLogPageProvider.notifier).state = 1;
            }
          },
        ),
        ScreenToolbarDropdown<int?>(
          key: const ValueKey('activity-user-filter'),
          value: ref.watch(activityLogUserIdProvider),
          hint: l10n.activitylogAllusers,
          items: [null, for (final user in users) user.id],
          labelBuilder: (v) {
            if (v == null) return l10n.activitylogAllusers;
            for (final user in users) {
              if (user.id == v) return user.username;
            }
            return '$v';
          },
          width: 140,
          onChanged: (v) {
            ref.read(activityLogUserIdProvider.notifier).state = v;
            if (ref.read(activityLogPageProvider) != 1) {
              ref.read(activityLogPageProvider.notifier).state = 1;
            }
          },
        ),
        DateRangeFilter(
          height: 40,
          fromProvider: activityLogFromDateProvider,
          toProvider: activityLogToDateProvider,
          onClear: _clearFilters,
          showClear: () => _hasActiveFilters,
        ),
      ],
      onRefresh: () {
        ref.invalidate(activityLogsProvider);
        ref.invalidate(activityStatsProvider);
      },
      actions: [
        TextButton.icon(
          onPressed: logs.isLoading || _hasNoRows
              ? null
              : () => saveCsv(
                  context,
                  suggestedName: csvSuggestedName('activity-logs'),
                  csv: buildActivityLogCsv(l10n, _filteredRows),
                  successMessage: l10n.activitylogExported,
                  errorMessage: l10n.activitylogExportfailed,
                ),
          icon: const Icon(Icons.file_download_outlined, size: 18),
          label: Text(l10n.activitylogExportcsv),
        ),
        if (ref.watch(authProvider).user?.isAdmin ?? false)
          TextButton.icon(
            onPressed: () => showActivityLogCleanupDialog(context),
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
            label: Text(l10n.activitylogCleanup),
          ),
      ],
    );
  }


  /// Rows currently visible in the grid — the provider's loaded page
  /// (empty while loading or on error). The export mirrors exactly what
  /// the grid shows under the active filters.
  List<ActivityLog> get _filteredRows =>
      ref.read(activityLogsProvider).valueOrNull?.items ??
      const <ActivityLog>[];

  bool get _hasNoRows => _filteredRows.isEmpty;

  /// Compact strip: total log volume + today's count + top action — all
  /// from `GET /activity-logs/stats` (the strip degrades gracefully while
  /// stats load or on error: chips just show an em dash).
  Widget _statsStrip(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final stats = ref.watch(activityStatsProvider).valueOrNull;

    var todayCount = 0;
    ActivityCount? topAction;
    if (stats != null) {
      final today = _isoDate(DateTime.now());
      for (final day in stats.dailyActivity) {
        if (day.label == today) {
          todayCount = day.count;
          break;
        }
      }
      if (stats.actions.isNotEmpty) topAction = stats.actions.first;
    }

    Widget chip(IconData icon, String label, String value) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: AppBorderRadius.smRadius,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(width: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
          ),
        ],
      ),
    );

    return Row(
      children: [
        chip(
          Icons.receipt_long_outlined,
          l10n.activitylogTotal,
          stats == null ? '—' : Formatters.number(stats.totalLogs),
        ),
        const SizedBox(width: 8),
        chip(
          Icons.today_outlined,
          l10n.activitylogToday,
          stats == null ? '—' : Formatters.number(todayCount),
        ),
        const SizedBox(width: 8),
        if (topAction != null)
          chip(
            Icons.bolt_outlined,
            topAction.label,
            Formatters.number(topAction.count),
          ),
      ],
    );
  }

  static String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
