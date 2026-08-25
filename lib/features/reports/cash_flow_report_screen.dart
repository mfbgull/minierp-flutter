// Cash flow report — GET /reports/cash-flow (PORTING.md §11).
// Port of the web `CashFlowReport.tsx`: three stat cards (total inflow,
// total outflow, net cash flow) over a From/To date range, plus the
// analysis note. Below them, a movement grid lists every cash movement
// behind those totals (customer payments, refunds, supplier payments,
// expenses, salaries — server-filtered to the tracked cash accounts so
// the rows always sum to the cards). Search + pagination run client-side
// over the loaded range — the endpoint already scopes rows to the dates,
// so there is nothing further to query server-side.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/theme/status_colors.dart';
import '../../core/utils/cash_movement_labels.dart';
import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/report.dart'
    show CashFlowMovement, CashFlowReport;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/date_range_picker.dart' show DateRangeFilter;
import '../../widgets/pagination_bar.dart';
import '../../widgets/pluto_grid_screen.dart'
    show autoFitPlutoColumns, plutoGridConfigurationFor;
import '../../widgets/screen_error_panel.dart';
import '../../widgets/screen_toolbar.dart' show ScreenToolbar;
import '../../widgets/status_badge.dart';
import 'report_providers.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';

class CashFlowReportScreen extends ConsumerStatefulWidget {
  const CashFlowReportScreen({super.key});

  @override
  ConsumerState<CashFlowReportScreen> createState() =>
      _CashFlowReportScreenState();
}

class _CashFlowReportScreenState extends ConsumerState<CashFlowReportScreen> {
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();
  String _search = '';
  int _page = 1;
  int _limit = 50;

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() {
        _search = value.trim().toLowerCase();
        // A new search starts back at page 1.
        _page = 1;
      });
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    setState(() {
      _search = '';
      _page = 1;
    });
  }

  /// Case-insensitive match across the visible columns — the type via
  /// its localized label so "expense" and its Urdu equivalent both hit.
  List<CashFlowMovement> _filteredMovements(
    CashFlowReport report,
    AppLocalizations l10n,
  ) {
    if (_search.isEmpty) return report.movements;
    bool matches(CashFlowMovement m) =>
        m.reference.toLowerCase().contains(_search) ||
        m.party.toLowerCase().contains(_search) ||
        m.method.toLowerCase().contains(_search) ||
        m.description.toLowerCase().contains(_search) ||
        m.date.contains(_search) ||
        cashMovementLabel(l10n, m.type).toLowerCase().contains(_search);
    return [for (final m in report.movements) if (matches(m)) m];
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(cashFlowReportProvider);
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            l10n.reportsCashflowreport,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        ScreenToolbar(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          searchController: _searchController,
          searchHint: l10n.fieldsSearch,
          onSearchChanged: _onSearchChanged,
          onClearSearch: _clearSearch,
          filters: [
            DateRangeFilter(
              fromProvider: reportCashFlowFromDateProvider,
              toProvider: reportCashFlowToDateProvider,
              showAllDates: false,
            ),
          ],
          onRefresh: () => ref.invalidate(cashFlowReportProvider),
          actions: [
            TextButton.icon(
              onPressed: report.isLoading || report.valueOrNull == null
                  ? null
                  : () => saveCsv(
                      context,
                      suggestedName: csvSuggestedName('cash-flow'),
                      csv: buildCashFlowCsv(l10n, report.valueOrNull!),
                      successMessage: l10n.reportsExported,
                      errorMessage: l10n.reportsExportfailed,
                    ),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: Text(l10n.reportsExportcsv),
            ),
          ],
        ),
        Expanded(child: _body(context, ref, report)),
      ],
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<CashFlowReport> report,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final errorMessage = switch (report) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };
    if (errorMessage != null) {
      return ScreenErrorPanel(
        message: errorMessage,
        onRetry: () => ref.invalidate(cashFlowReportProvider),
      );
    }
    if (report.isLoading || !report.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }

    final m = report.value!;
    final scheme = Theme.of(context).colorScheme;
    final positive = m.netCashFlow >= 0;
    final filtered = _filteredMovements(m, l10n);
    final totalPages = filtered.isEmpty
        ? 1
        : (filtered.length / _limit).ceil();
    // A fresh date range or a narrowed search can shrink the list below
    // the current page — clamp instead of rendering an empty page.
    final effectivePage = _page.clamp(1, totalPages);
    final pageRows = filtered
        .skip((effectivePage - 1) * _limit)
        .take(_limit)
        .toList();

    Widget card(
      String label,
      String value,
      IconData icon, {
      Color? valueColor,
    }) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: AppBorderRadius.mdRadius,
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: scheme.primary),
            const SizedBox(height: 8),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: valueColor ?? scheme.primary,
              ),
            ),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              card(
                l10n.reportsTotalinflow,
                Formatters.currency(m.totalInflow),
                Icons.south_west,
              ),
              const SizedBox(width: 8),
              card(
                l10n.reportsTotaloutflow,
                Formatters.currency(m.totalOutflow),
                Icons.north_east,
                valueColor: m.totalOutflow > 0 ? scheme.error : scheme.primary,
              ),
              const SizedBox(width: 8),
              card(
                l10n.reportsNetcashflow,
                Formatters.currency(m.netCashFlow),
                positive ? Icons.trending_up : Icons.trending_down,
                valueColor: positive ? scheme.primary : scheme.error,
              ),
            ],
          ),
        ),
        if (m.startDate.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              '${l10n.reportsPeriod}: ${Formatters.date(m.startDate)} ${l10n.commonTo} ${Formatters.date(m.endDate)}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                positive ? Icons.trending_up : Icons.trending_down,
                size: 16,
                color: positive ? scheme.primary : scheme.error,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  positive
                      ? l10n.reportsCashflowpositive
                      : l10n.reportsCashflownegative,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _MovementsGrid(
            // PlutoGrid consumes `rows` only on its first build — its
            // didUpdateWidget ignores row changes. Rekeying on everything
            // the visible slice depends on remounts the grid exactly when
            // the slice changes (new fetch, search, page, page size).
            key: ValueKey(Object.hash(m, effectivePage, _limit, _search)),
            movements: pageRows,
          ),
        ),
        if (filtered.isNotEmpty)
          ServerPaginationBar(
            page: effectivePage,
            totalPages: totalPages,
            totalItems: filtered.length,
            hasNext: effectivePage < totalPages,
            hasPrev: effectivePage > 1,
            limit: _limit,
            itemLabel: l10n.cashposTransactions,
            onPageChanged: (p) => setState(() => _page = p),
            onLimitChanged: (limit) => setState(() {
              _limit = limit;
              _page = 1;
            }),
          ),
      ],
    );
  }
}

/// One client-side page of the cash movements behind the summary cards,
/// newest first. The server filters to the same tracked accounts the
/// cards sum over, so inflow/outflow rows reconcile with the totals
/// above by construction; search/pagination slice that loaded set.
class _MovementsGrid extends StatefulWidget {
  const _MovementsGrid({super.key, required this.movements});
  final List<CashFlowMovement> movements;

  @override
  State<_MovementsGrid> createState() => _MovementsGridState();
}

class _MovementsGridState extends State<_MovementsGrid> {
  late final PlutoGridStateManager stateManager;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return PlutoGrid(
      configuration: plutoGridConfigurationFor(context, compact: true),
      columns: [
        PlutoColumn(
          title: l10n.fieldsDate,
          field: 'date',
          type: PlutoColumnType.text(),
          width: 110,
          renderer: (ctx) => Align(
            alignment: Alignment.centerLeft,
            child: Text(
              Formatters.date(ctx.cell.value as String? ?? ''),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ),
        PlutoColumn(
          title: l10n.fieldsType,
          field: 'type',
          type: PlutoColumnType.text(),
          width: 150,
          renderer: (ctx) {
            final type = ctx.cell.value?.toString() ?? '';
            return Align(
              alignment: Alignment.centerLeft,
              child: StatusBadge(
                status: cashMovementLabel(l10n, type),
                color: cashMovementColor(context, type),
              ),
            );
          },
        ),
        PlutoColumn(title: l10n.fieldsReference, field: 'reference', type: PlutoColumnType.text(), width: 130),
        PlutoColumn(title: l10n.paymentsParty, field: 'party', type: PlutoColumnType.text(), width: 180),
        PlutoColumn(title: l10n.expensesPaymentmethod, field: 'method', type: PlutoColumnType.text(), width: 110),
        PlutoColumn(title: l10n.fieldsNotes, field: 'description', type: PlutoColumnType.text(), width: 220),
        PlutoColumn(
          title: l10n.fieldsAmount,
          field: 'amount',
          type: PlutoColumnType.number(format: '#,###.00'),
          width: 120,
          textAlign: PlutoColumnTextAlign.end,
          titleTextAlign: PlutoColumnTextAlign.end,
          renderer: (ctx) {
            final amount = (ctx.cell.value as num?) ?? 0;
            return Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${amount < 0 ? '−' : '+'}${Formatters.currency(amount.abs())}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: amount < 0
                      ? StatusColors.of(context).error
                      : StatusColors.of(context).success,
                ),
              ),
            );
          },
        ),
      ],
      rows: [
        for (final m in widget.movements)
          PlutoRow(cells: {
            'date': PlutoCell(value: m.date),
            'type': PlutoCell(value: m.type),
            'reference': PlutoCell(value: m.reference),
            'party': PlutoCell(value: m.party),
            'method': PlutoCell(value: m.method),
            'description': PlutoCell(value: m.description),
            'amount': PlutoCell(value: m.amount),
          }),
      ],
      onLoaded: (e) {
        stateManager = e.stateManager;
        stateManager.setSelectingMode(PlutoGridSelectingMode.none);
        autoFitPlutoColumns(stateManager);
      },
    );
  }
}
