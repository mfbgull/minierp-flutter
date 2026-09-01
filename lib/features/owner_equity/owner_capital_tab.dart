// Owner capital list tab — read-only PlutoGrid over
// `GET /owner-equity/capital` with server-side paging + search + date
// filters (`PagedResponse<OwnerCapitalEntry>` + `ServerPaginationBar`,
// same shape as the expenses screen).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/owner_equity.dart' show OwnerCapitalEntry;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../data/repositories/paged_request.dart' show PagedResponse;
import '../../l10n/app_localizations.dart';
import '../../widgets/date_range_picker.dart' show DateRangeFilter;
import '../../widgets/grid_column_widths.dart';
import '../../widgets/pagination_bar.dart' show ServerPaginationBar;
import '../../widgets/pluto_grid_screen.dart'
    show autoFitPlutoColumns, plutoGridConfigurationFor, serialGridColumn, withSerialCell;
import '../../widgets/screen_error_panel.dart';
import '../../widgets/screen_toolbar.dart';
import 'owner_capital_form_dialog.dart';
import 'owner_equity_providers.dart';

class OwnerCapitalTab extends ConsumerStatefulWidget {
  const OwnerCapitalTab({super.key});

  @override
  ConsumerState<OwnerCapitalTab> createState() => _OwnerCapitalTabState();
}

class _OwnerCapitalTabState extends ConsumerState<OwnerCapitalTab> {
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();
  PlutoGridStateManager? _stateManager;
  late List<PlutoColumn> _columns;
  bool _columnsReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_columnsReady) {
      _columns = _buildColumns(AppLocalizations.of(context)!);
      _columnsReady = true;
    }
  }

  GridColumnWidths? _widthTracker;

  @override
  void dispose() {
    _widthTracker?.dispose();
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      ref.read(capitalSearchProvider.notifier).state = value.trim();
    });
  }

  bool get _hasActiveFilters =>
      ref.read(capitalFromDateProvider) != null ||
      ref.read(capitalToDateProvider) != null;

  void _clearFilters() {
    ref.read(capitalFromDateProvider.notifier).state = null;
    ref.read(capitalToDateProvider.notifier).state = null;
  }

  /// Pushes the provider state into the grid manager (clear + append,
  /// with the loading overlay toggled). No-op until `onLoaded`.
  void _applyRows(AsyncValue<PagedResponse<OwnerCapitalEntry>> value) {
    final manager = _stateManager;
    if (manager == null) return;
    manager.setShowLoading(value.isLoading);
    if (value.hasValue) {
      manager.removeAllRows();
      manager.appendRows([
        for (final (index, entry) in (value.value!.items).indexed)
          _rowFor(entry, index),
      ]);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !identical(_stateManager, manager)) return;
        final tracker = _widthTracker;
        if (tracker != null) {
          tracker.programmaticPass(() => autoFitPlutoColumns(manager));
        } else {
          autoFitPlutoColumns(manager);
        }
      });
    }
  }

  Future<void> _openRowMenu(
    BuildContext cellContext,
    OwnerCapitalEntry? entry,
  ) async {
    if (entry == null || !mounted) return;
    showOwnerCapitalFormDialog(context, entry: entry);
  }

  PlutoRow _rowFor(OwnerCapitalEntry entry, int index) => withSerialCell(
    PlutoRow(
      cells: {
        'data': PlutoCell(value: entry),
        'id': PlutoCell(value: entry.id),
        'capital_no': PlutoCell(value: entry.capitalNo),
        'capital_date': PlutoCell(value: entry.capitalDate),
        'payment_method': PlutoCell(value: entry.paymentMethod ?? ''),
        'note': PlutoCell(value: entry.note ?? ''),
        'amount': PlutoCell(value: entry.amount),
        'status': PlutoCell(value: entry.status),
        'created_by': PlutoCell(value: entry.createdByName ?? ''),
      },
    ),
    index,
  );

  @override
  Widget build(BuildContext context) {
    final capital = ref.watch(ownerCapitalProvider);
    final page = capital.valueOrNull;
    final l10n = AppLocalizations.of(context)!;

    ref.listen(ownerCapitalProvider, (previous, next) => _applyRows(next));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _equitySummaryCards(l10n),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: _toolbar(l10n),
        ),
        Expanded(child: _buildBody(capital)),
        if (page != null)
          ServerPaginationBar(
            page: page.currentPage,
            totalPages: page.totalPages,
            totalItems: page.totalItems,
            hasNext: page.hasNext,
            hasPrev: page.hasPrev,
            limit: ref.watch(capitalLimitProvider),
            itemLabel: l10n.equityCapital,
            onPageChanged: (p) =>
                ref.read(capitalPageProvider.notifier).state = p,
            onLimitChanged: (limit) {
              ref.read(capitalLimitProvider.notifier).state = limit;
              if (ref.read(capitalPageProvider) != 1) {
                ref.read(capitalPageProvider.notifier).state = 1;
              }
            },
          ),
      ],
    );
  }

  Widget _toolbar(AppLocalizations l10n) {
    return ScreenToolbar(
      searchController: _searchController,
      searchHint: l10n.commonSearch,
      onSearchChanged: _onSearchChanged,
      onClearSearch: () {
        _searchController.clear();
        ref.read(capitalSearchProvider.notifier).state = '';
      },
      filters: [
        ScreenToolbarDropdown<String?>(
          key: const ValueKey('equity-capital-sort'),
          value: ref.watch(capitalSortProvider)?.column,
          hint: 'Sort',
          items: const [
            null,
            'oc.capital_date',
            'oc.amount',
            'oc.capital_no',
            'oc.created_at',
          ],
          labelBuilder: (v) {
            switch (v) {
              case 'oc.capital_date':
                return 'Date';
              case 'oc.amount':
                return 'Amount';
              case 'oc.capital_no':
                return 'Doc No';
              case 'oc.created_at':
                return 'Created';
              default:
                return 'Sort';
            }
          },
          width: 130,
          onChanged: (v) {
            final current = ref.read(capitalSortProvider);
            final next = v == null
                ? null
                : EquitySort(
                    v,
                    current == null || current.column != v
                        ? 'DESC'
                        : (current.order == 'ASC' ? 'DESC' : 'ASC'),
                  );
            ref.read(capitalSortProvider.notifier).state = next;
            if (ref.read(capitalPageProvider) != 1) {
              ref.read(capitalPageProvider.notifier).state = 1;
            }
          },
        ),
        DateRangeFilter(
          height: 40,
          fromProvider: capitalFromDateProvider,
          toProvider: capitalToDateProvider,
          onClear: _clearFilters,
          showClear: () => _hasActiveFilters,
        ),
      ],
      onRefresh: () => ref.invalidate(ownerCapitalProvider),
      actions: [
        TextButton.icon(
          onPressed: () {
            final rows = ref.read(allOwnerCapitalProvider).valueOrNull;
            if (rows == null || rows.isEmpty) return;
            saveCsv(
              context,
              suggestedName: csvSuggestedName('owner-capital'),
              csv: buildOwnerCapitalCsv(l10n, rows),
              successMessage: l10n.equityExported,
              errorMessage: l10n.equityExportfailed,
            );
          },
          icon: const Icon(Icons.file_download_outlined, size: 18),
          label: Text(l10n.expensesExportcsv),
        ),
      ],
      primaryActions: [
        FilledButton.tonalIcon(
          onPressed: () => showOwnerCapitalFormDialog(context),
          icon: const Icon(Icons.add, size: 18),
          label: Text(l10n.equityNewcapital),
        ),
      ],
    );
  }

  Widget _buildBody(AsyncValue<PagedResponse<OwnerCapitalEntry>> capital) {
    final errorMessage = switch (capital) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };
    if (errorMessage != null) {
      _stateManager = null;
      return ScreenErrorPanel(
        message: errorMessage,
        onRetry: () => ref.invalidate(ownerCapitalProvider),
      );
    }
    return _grid();
  }

  Widget _grid() {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: PlutoGrid(
        configuration: plutoGridConfigurationFor(context, compact: true),
        columns: _columns,
        rows: <PlutoRow>[],
        onLoaded: (event) {
          _stateManager = event.stateManager;
          _stateManager?.hideColumn(
            _columns.firstWhere((c) => c.field == 'id'),
            true,
            notify: false,
          );
          _applyRows(ref.read(ownerCapitalProvider));
          _widthTracker?.dispose();
          _widthTracker = GridColumnWidths.attach(
            stateManager: event.stateManager,
            screenKey: 'owner_capital',
          );
        },
        onRowDoubleTap: (event) {
          final id = event.row.cells['id']?.value as int?;
          if (id == null || id <= 0) return;
          final rows =
              ref.read(ownerCapitalProvider).valueOrNull?.items ??
              const <OwnerCapitalEntry>[];
          for (final entry in rows) {
            if (entry.id == id) {
              showOwnerCapitalFormDialog(context, entry: entry);
              break;
            }
          }
        },
        onSorted: _onGridSorted,
        noRowsWidget: Center(
          child: Text(
            l10n.commonNoresults,
            style: TextStyle(color: scheme.outline),
          ),
        ),
      ),
    );
  }

  String? _sortColumnFor(String field) {
    switch (field) {
      case 'capital_no':
        return 'oc.capital_no';
      case 'capital_date':
        return 'oc.capital_date';
      case 'payment_method':
        return 'oc.payment_method';
      case 'amount':
        return 'oc.amount';
      case 'status':
        return 'oc.status';
      case 'created_by':
        return 'oc.created_at';
      default:
        return null;
    }
  }

  void _onGridSorted(PlutoGridOnSortedEvent event) {
    final sortBy = _sortColumnFor(event.column.field);
    if (sortBy == null) return;
    final sort = event.column.sort;
    final order = sort == PlutoColumnSort.ascending ? 'ASC' : 'DESC';
    ref.read(capitalSortProvider.notifier).state = EquitySort(sortBy, order);
    if (ref.read(capitalPageProvider) != 1) {
      ref.read(capitalPageProvider.notifier).state = 1;
    }
  }

  List<PlutoColumn> _buildColumns(AppLocalizations l10n) {
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
      serialGridColumn(),
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
      textColumn('capital_no', l10n.equityCapitalno, 140),
      PlutoColumn(
        title: l10n.fieldsDate,
        field: 'capital_date',
        type: PlutoColumnType.text(),
        width: 110,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) => Align(
          alignment: Alignment.centerLeft,
          child: Text(Formatters.date(ctx.cell.value as String? ?? '')),
        ),
      ),
      textColumn('payment_method', l10n.expensesPaymentmethod, 140),
      textColumn('note', l10n.fieldsNote, 260),
      PlutoColumn(
        title: l10n.fieldsAmount,
        field: 'amount',
        type: PlutoColumnType.number(format: '#,###.##'),
        width: 130,
        readOnly: true,
        textAlign: PlutoColumnTextAlign.end,
        titleTextAlign: PlutoColumnTextAlign.end,
        enableContextMenu: false,
        renderer: (ctx) => Align(
          alignment: Alignment.centerRight,
          child: Text(
            Formatters.currency(ctx.cell.value as num? ?? 0),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
      textColumn('status', l10n.fieldsStatus, 100),
      textColumn('created_by', l10n.expensesCreatedby, 130),
      PlutoColumn(
        title: l10n.commonActions,
        field: 'actions',
        frozen: PlutoColumnFrozen.end,
        type: PlutoColumnType.text(),
        width: 64,
        readOnly: true,
        enableContextMenu: false,
        enableFilterMenuItem: false,
        enableHideColumnMenuItem: false,
        enableSetColumnsMenuItem: false,
        renderer: (ctx) {
          final entry = ctx.cell.row.cells['data']?.value as OwnerCapitalEntry?;
          return Builder(
            builder: (cellContext) => Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => _openRowMenu(cellContext, entry),
              child: Center(
                child: Icon(
                  Icons.more_vert,
                  size: 18,
                  color: Theme.of(cellContext).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        },
      ),
    ];
  }

  Widget _equitySummaryCards(AppLocalizations l10n) {
    final summary = ref.watch(equitySummaryProvider);
    final scheme = Theme.of(context).colorScheme;
    final data = summary.valueOrNull;

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: AppBorderRadius.smRadius,
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: _EquityStat(
                icon: Icons.savings_outlined,
                label: l10n.equityTotalcapitalin,
                value: Formatters.currency(data?.totalCapitalIn ?? 0),
                color: scheme.primary,
              ),
            ),
            _equityStatDivider(scheme),
            Expanded(
              child: _EquityStat(
                icon: Icons.call_made_outlined,
                label: l10n.equityTotalwithdrawn,
                value: Formatters.currency(
                  (data?.totalWithdrawnCash ?? 0) +
                      (data?.totalWithdrawnGoods ?? 0),
                ),
                color: scheme.error,
              ),
            ),
            _equityStatDivider(scheme),
            Expanded(
              child: _EquityStat(
                icon: Icons.account_balance_outlined,
                label: l10n.equityNetcontributions,
                value: Formatters.currency(data?.netContributions ?? 0),
                color: scheme.tertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _equityStatDivider(ColorScheme scheme) => Container(
    width: 1,
    height: 36,
    color: scheme.outlineVariant,
  );

}

class _EquityStat extends StatelessWidget {
  const _EquityStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
