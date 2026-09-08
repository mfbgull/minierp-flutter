// Owner capital list tab — read-only PlutoGrid over
// `GET /owner-equity/capital` with server-side paging + search + date
// filters (`PagedResponse<OwnerCapitalEntry>` + `ServerPaginationBar`,
// same shape as the expenses screen). Migrated to PlutoGridScreen mixin
// with bulk void + export (D5, D9).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/auth/auth_notifier.dart';
import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/owner_equity.dart' show OwnerCapitalEntry;
import '../../data/repositories/paged_request.dart' show PagedResponse;
import '../../l10n/app_localizations.dart';
import '../../widgets/bulk_operations.dart';
import '../../widgets/date_range_picker.dart' show DateRangeFilter;
import '../../widgets/pagination_bar.dart' show ServerPaginationBar;
import '../../widgets/pluto_grid_screen.dart';
import '../../widgets/screen_toolbar.dart';
import 'owner_capital_form_dialog.dart';
import 'owner_equity_providers.dart';
import '../../data/repositories/owner_equity_repository.dart' show ownerEquityRepositoryProvider;

class OwnerCapitalTab extends ConsumerStatefulWidget {
  const OwnerCapitalTab({super.key});

  @override
  ConsumerState<OwnerCapitalTab> createState() => _OwnerCapitalTabState();
}

class _OwnerCapitalTabState extends ConsumerState<OwnerCapitalTab>
    with PlutoGridScreen<OwnerCapitalEntry, OwnerCapitalTab> {
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();

  @override
  bool get enableBulkSelection => true;

  @override
  String get filterSignature {
    final search = ref.read(capitalSearchProvider);
    final from = ref.read(capitalFromDateProvider);
    final to = ref.read(capitalToDateProvider);
    return '$search|$from|$to';
  }

  @override
  bool get hasRowActions => true;

  @override
  List<GridRowAction>? gridRowActionsFor(PlutoRow row, BuildContext context) {
    final id = row.cells['id']?.value as int?;
    if (id == null || id <= 0) return null;
    final l10n = AppLocalizations.of(context)!;
    return [
      GridRowAction(
        icon: Icons.visibility_outlined,
        label: l10n.commonView,
        onTap: () => _openEntry(id),
      ),
      GridRowAction(
        icon: Icons.edit_outlined,
        label: l10n.commonEdit,
        onTap: () => _openEntry(id),
      ),
    ];
  }

  void _openEntry(int id) {
    final entries =
        ref.read(ownerCapitalProvider).valueOrNull?.items ??
        const <OwnerCapitalEntry>[];
    for (final entry in entries) {
      if (entry.id == id) {
        showOwnerCapitalFormDialog(context, entry: entry);
        return;
      }
    }
  }

  @override
  void openRowDetail(int rowId) => _openEntry(rowId);

  @override
  Iterable<OwnerCapitalEntry> gridRowsFrom(Object? value) =>
      (value as PagedResponse<OwnerCapitalEntry>).items;

  @override
  PlutoRow gridRowFor(OwnerCapitalEntry entry) => PlutoRow(
    cells: {
      'id': PlutoCell(value: entry.id),
      'capital_no': PlutoCell(value: entry.capitalNo),
      'capital_date': PlutoCell(value: entry.capitalDate),
      'payment_method': PlutoCell(value: entry.paymentMethod ?? ''),
      'note': PlutoCell(value: entry.note ?? ''),
      'amount': PlutoCell(value: entry.amount),
      'status': PlutoCell(value: entry.status),
      'created_by': PlutoCell(value: entry.createdByName ?? ''),
    },
  );

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

  @override
  void onGridSorted(PlutoGridOnSortedEvent event) {
    final sortBy = _sortColumnFor(event.column.field);
    if (sortBy == null) return;
    final sort = event.column.sort;
    final order = sort == PlutoColumnSort.ascending ? 'ASC' : 'DESC';
    ref.read(capitalSortProvider.notifier).state = EquitySort(sortBy, order);
    if (ref.read(capitalPageProvider) != 1) {
      ref.read(capitalPageProvider.notifier).state = 1;
    }
  }

  void _bulkVoid(Set<int> ids) async {
    final l10n = AppLocalizations.of(context)!;
    final entries =
        ref.read(ownerCapitalProvider).valueOrNull?.items ??
        const <OwnerCapitalEntry>[];
    final selected = [
      for (final e in entries)
        if (ids.contains(e.id)) e,
    ];
    if (selected.isEmpty) return;
    final repo = ref.read(ownerEquityRepositoryProvider);
    final result = await runBulkOperation(
      ids: selected.map((e) => e.id).toList(),
      labelFor: (id) {
        final e = selected.firstWhere((e) => e.id == id);
        return e.capitalNo;
      },
      operation: (id) => repo.voidCapital(id),
    );
    if (!mounted) return;
    await finishBulkOperation(
      context,
      bulk: bulkSelection,
      result: result,
      successMessage: (count) => l10n.equityVoided,
      onComplete: () {
        ref.invalidate(ownerCapitalProvider);
        ref.invalidate(equitySummaryProvider);
      },
    );
  }

  void _bulkExport(Set<int> ids) {
    final l10n = AppLocalizations.of(context)!;
    final entries =
        ref.read(ownerCapitalProvider).valueOrNull?.items ??
        const <OwnerCapitalEntry>[];
    final selected = [
      for (final e in entries)
        if (ids.contains(e.id)) e,
    ];
    if (selected.isEmpty) return;
    saveCsv(
      context,
      suggestedName: csvSuggestedName('owner-capital'),
      csv: buildOwnerCapitalCsv(l10n, selected),
      successMessage: l10n.equityExported,
      errorMessage: l10n.equityExportfailed,
    );
  }

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

  @override
  Widget build(BuildContext context) {
    final capital = ref.watch(ownerCapitalProvider);
    final page = capital.valueOrNull;
    final l10n = AppLocalizations.of(context)!;

    watchGridProvider(ownerCapitalProvider);

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
        ValueListenableBuilder<Set<int>>(
          valueListenable: bulkSelection.selected,
          builder: (context, sel, _) {
            if (sel.isEmpty) return const SizedBox.shrink();
            final user = ref.watch(authProvider).user;
            return BulkActionBar(
              count: sel.length,
              onClearSelection: bulkSelection.clear,
              actions: [
                if (user?.hasPermission('accounting', 'delete') ?? false)
                  TextButton.icon(
                    onPressed: () => _bulkVoid(sel),
                    icon: const Icon(Icons.block_outlined, size: 18),
                    label: Text(l10n.purchasesVoid),
                  ),
                if (user?.hasPermission('accounting', 'read') ?? false)
                  TextButton.icon(
                    onPressed: () => _bulkExport(sel),
                    icon: const Icon(Icons.file_download_outlined, size: 18),
                    label: Text(l10n.bulkExportSelected),
                  ),
              ],
            );
          },
        ),
        Expanded(child: gridScreenBody(capital, provider: ownerCapitalProvider)),
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
