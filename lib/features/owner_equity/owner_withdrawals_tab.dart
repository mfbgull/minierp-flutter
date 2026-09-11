// Owner withdrawals list tab — read-only PlutoGrid over
// `GET /owner-equity/withdrawals` with kind/search/date filters. Goods
// rows double-tap to the batch-consumption breakdown; both kinds open the
// edit dialog from the row menu.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/auth/auth_notifier.dart';
import '../../core/theme/money_direction.dart';
import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/owner_equity.dart' show OwnerWithdrawal;
import '../../data/repositories/owner_equity_repository.dart'
    show ownerEquityRepositoryProvider;
import '../../data/repositories/paged_request.dart' show PagedResponse;
import '../../l10n/app_localizations.dart';
import '../../widgets/bulk_operations.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/date_range_picker.dart' show DateRangeFilter;
import '../../widgets/pagination_bar.dart' show ServerPaginationBar;
import '../../widgets/pluto_grid_screen.dart';
import '../../widgets/screen_toolbar.dart';
import 'owner_equity_providers.dart';
import 'owner_withdrawal_detail_dialog.dart';
import 'owner_withdrawal_form_dialog.dart';

class OwnerWithdrawalsTab extends ConsumerStatefulWidget {
  const OwnerWithdrawalsTab({super.key});

  @override
  ConsumerState<OwnerWithdrawalsTab> createState() =>
      _OwnerWithdrawalsTabState();
}

class _OwnerWithdrawalsTabState extends ConsumerState<OwnerWithdrawalsTab>
    with PlutoGridScreen<OwnerWithdrawal, OwnerWithdrawalsTab> {
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();
  bool _bulkBusy = false;

  final Map<int, OwnerWithdrawal> _withdrawalsById = {};

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
      ref.read(withdrawalsSearchProvider.notifier).state = value.trim();
    });
  }

  bool get _hasActiveFilters =>
      ref.read(withdrawalsKindProvider) != null ||
      ref.read(withdrawalsFromDateProvider) != null ||
      ref.read(withdrawalsToDateProvider) != null;

  void _clearFilters() {
    ref.read(withdrawalsKindProvider.notifier).state = null;
    ref.read(withdrawalsFromDateProvider.notifier).state = null;
    ref.read(withdrawalsToDateProvider.notifier).state = null;
  }

  @override
  Iterable<OwnerWithdrawal> gridRowsFrom(Object? value) =>
      (value as PagedResponse<OwnerWithdrawal>).items;

  @override
  PlutoRow gridRowFor(OwnerWithdrawal row) {
    _withdrawalsById[row.id] = row;
    return PlutoRow(
      cells: {
        'data': PlutoCell(value: row),
        'id': PlutoCell(value: row.id),
        'withdrawal_no': PlutoCell(value: row.withdrawalNo),
        'withdrawal_date': PlutoCell(value: row.withdrawalDate),
        'kind': PlutoCell(value: row.kind),
        'amount': PlutoCell(value: row.amount),
        'items': PlutoCell(
          value: row.kind == 'goods' ? row.itemLineCount : null,
        ),
        'payment_method': PlutoCell(value: row.paymentMethod ?? ''),
        'note': PlutoCell(value: row.note ?? ''),
        'status': PlutoCell(value: row.status),
        'created_by': PlutoCell(value: row.createdByName ?? ''),
      },
    );
  }

  @override
  void openRowDetail(int rowId) {
    if (!mounted) return;
    final row = _withdrawalsById[rowId];
    if (row == null) return;
    if (row.kind == 'goods') {
      showOwnerWithdrawalDetailDialog(context, row.id);
    } else {
      showOwnerWithdrawalFormDialog(context, entry: row);
    }
  }

  @override
  bool get enableBulkSelection => true;

  @override
  bool get hasRowActions => true;

  @override
  List<String> get hiddenGridColumnFields => const ['id'];

  @override
  String get filterSignature {
    final search = ref.read(withdrawalsSearchProvider);
    final kind = ref.read(withdrawalsKindProvider);
    final from = ref.read(withdrawalsFromDateProvider);
    final to = ref.read(withdrawalsToDateProvider);
    return '$search|$kind|$from|$to';
  }

  String? _sortColumnFor(String field) => switch (field) {
    'withdrawal_no' => 'ow.withdrawal_no',
    'withdrawal_date' => 'ow.withdrawal_date',
    'kind' => 'ow.kind',
    'amount' => 'ow.amount',
    'status' => 'ow.status',
    'created_by' => 'ow.created_at',
    _ => null,
  };

  @override
  void onGridSorted(PlutoGridOnSortedEvent event) {
    final sortBy = _sortColumnFor(event.column.field);
    if (sortBy == null) return;
    final sort = event.column.sort;
    final order = sort == PlutoColumnSort.ascending ? 'ASC' : 'DESC';
    ref.read(withdrawalsSortProvider.notifier).state =
        EquitySort(sortBy, order);
    if (ref.read(withdrawalsPageProvider) != 1) {
      ref.read(withdrawalsPageProvider.notifier).state = 1;
    }
  }

  @override
  List<GridRowAction>? gridRowActionsFor(PlutoRow row, BuildContext context) {
    final id = row.cells['id']?.value as int?;
    if (id == null || id <= 0) return null;
    final l10n = AppLocalizations.of(context)!;
    final withdrawal = _withdrawalsById[id];
    return [
      GridRowAction(
        icon: Icons.visibility_outlined,
        label: l10n.commonView,
        onTap: () {
          if (withdrawal?.kind == 'goods') {
            showOwnerWithdrawalDetailDialog(context, id);
          } else {
            showOwnerWithdrawalFormDialog(context, entry: withdrawal);
          }
        },
      ),
      GridRowAction(
        icon: Icons.edit_outlined,
        label: l10n.commonEdit,
        onTap: () => showOwnerWithdrawalFormDialog(context, entry: withdrawal),
      ),
    ];
  }

  Future<void> _bulkVoid(Set<int> ids) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.equityVoided,
      message: '${l10n.equityDeleteconfirmdesc}\n\n(${ids.length})',
      confirmLabel: l10n.commonConfirm,
      cancelLabel: l10n.commonCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    final repo = ref.read(ownerEquityRepositoryProvider);
    setState(() => _bulkBusy = true);
    final result = await runBulkOperation(
      ids: ids.toList(),
      labelFor: (id) => _withdrawalsById[id]?.withdrawalNo ?? '#$id',
      operation: repo.voidWithdrawal,
    );
    if (!mounted) return;
    setState(() => _bulkBusy = false);
    await finishBulkOperation(
      context,
      bulk: bulkSelection,
      result: result,
      successMessage: (n) => l10n.bulkDeleted(n),
      onComplete: () {
        ref.invalidate(ownerWithdrawalsProvider);
        ref.invalidate(equitySummaryProvider);
      },
    );
  }

  void _bulkExport(Set<int> ids) {
    final l10n = AppLocalizations.of(context)!;
    final selected = [
      for (final w in _withdrawalsById.values)
        if (ids.contains(w.id)) w,
    ];
    if (selected.isEmpty) return;
    saveCsv(
      context,
      suggestedName: csvSuggestedName('owner-withdrawals'),
      csv: buildOwnerWithdrawalsCsv(l10n, selected),
      successMessage: l10n.equityExported,
      errorMessage: l10n.equityExportfailed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final withdrawals = ref.watch(ownerWithdrawalsProvider);
    final page = withdrawals.valueOrNull;
    final l10n = AppLocalizations.of(context)!;

    watchGridProvider(ownerWithdrawalsProvider);

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
              busy: _bulkBusy,
              actions: [
                if (user?.hasPermission('accounting', 'read') ?? false)
                  TextButton.icon(
                    onPressed: () => _bulkExport(sel),
                    icon: const Icon(Icons.file_download_outlined, size: 18),
                    label: Text(l10n.bulkExportSelected),
                  ),
                if (user?.hasPermission('accounting', 'delete') ?? false)
                  TextButton.icon(
                    onPressed: () => _bulkVoid(sel),
                    icon: const Icon(Icons.block_outlined, size: 18),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    label: Text(l10n.equityVoided),
                  ),
              ],
            );
          },
        ),
        Expanded(
          child: gridScreenBody(
            withdrawals,
            provider: ownerWithdrawalsProvider,
            rowColorCallback: moneyRowColorCallback(
              context,
              ref,
              // Money out — the owner draws value out of the business.
              // Voided entries are neutral (never realized).
              (row) => row.cells['status']?.value == 'voided'
                  ? MoneyDirection.neutral
                  : MoneyDirection.outflow,
            ),
          ),
        ),
        if (page != null)
          ServerPaginationBar(
            page: page.currentPage,
            totalPages: page.totalPages,
            totalItems: page.totalItems,
            hasNext: page.hasNext,
            hasPrev: page.hasPrev,
            limit: ref.watch(withdrawalsLimitProvider),
            itemLabel: l10n.equityWithdrawals,
            onPageChanged: (p) =>
                ref.read(withdrawalsPageProvider.notifier).state = p,
            onLimitChanged: (limit) {
              ref.read(withdrawalsLimitProvider.notifier).state = limit;
              if (ref.read(withdrawalsPageProvider) != 1) {
                ref.read(withdrawalsPageProvider.notifier).state = 1;
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
        ref.read(withdrawalsSearchProvider.notifier).state = '';
      },
      filters: [
        ScreenToolbarDropdown<String?>(
          key: const ValueKey('equity-withdrawals-kind'),
          value: ref.watch(withdrawalsKindProvider),
          hint: l10n.equityAllkinds,
          items: const [null, 'cash', 'goods'],
          labelBuilder: (v) => v == null
              ? l10n.equityAllkinds
              : (v == 'goods' ? l10n.equityKindgoods : l10n.equityKindcash),
          width: 130,
          onChanged: (v) {
            ref.read(withdrawalsKindProvider.notifier).state = v;
            if (ref.read(withdrawalsPageProvider) != 1) {
              ref.read(withdrawalsPageProvider.notifier).state = 1;
            }
          },
        ),
        ScreenToolbarDropdown<String?>(
          key: const ValueKey('equity-withdrawals-sort'),
          value: ref.watch(withdrawalsSortProvider)?.column,
          hint: 'Sort',
          items: const [
            null,
            'ow.withdrawal_date',
            'ow.amount',
            'ow.kind',
            'ow.withdrawal_no',
            'ow.created_at',
          ],
          labelBuilder: (v) {
            switch (v) {
              case 'ow.withdrawal_date':
                return 'Date';
              case 'ow.amount':
                return 'Amount';
              case 'ow.kind':
                return 'Kind';
              case 'ow.withdrawal_no':
                return 'Doc No';
              case 'ow.created_at':
                return 'Created';
              default:
                return 'Sort';
            }
          },
          width: 130,
          onChanged: (v) {
            final current = ref.read(withdrawalsSortProvider);
            final next = v == null
                ? null
                : EquitySort(
                    v,
                    current == null || current.column != v
                        ? 'DESC'
                        : (current.order == 'ASC' ? 'DESC' : 'ASC'),
                  );
            ref.read(withdrawalsSortProvider.notifier).state = next;
            if (ref.read(withdrawalsPageProvider) != 1) {
              ref.read(withdrawalsPageProvider.notifier).state = 1;
            }
          },
        ),
        DateRangeFilter(
          height: 40,
          fromProvider: withdrawalsFromDateProvider,
          toProvider: withdrawalsToDateProvider,
          onClear: _clearFilters,
          showClear: () => _hasActiveFilters,
        ),
        moneyTintFilterChip(context, ref, l10n: l10n),
      ],
      onRefresh: () => ref.invalidate(ownerWithdrawalsProvider),
      actions: [
        TextButton.icon(
          onPressed: () {
            final rows = ref.read(allOwnerWithdrawalsProvider).valueOrNull;
            if (rows == null || rows.isEmpty) return;
            saveCsv(
              context,
              suggestedName: csvSuggestedName('owner-withdrawals'),
              csv: buildOwnerWithdrawalsCsv(l10n, rows),
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
          onPressed: () => showOwnerWithdrawalFormDialog(context),
          icon: const Icon(Icons.add, size: 18),
          label: Text(l10n.equityNewwithdrawal),
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
      textColumn('withdrawal_no', l10n.equityWithdrawalno, 140),
      PlutoColumn(
        title: l10n.fieldsDate,
        field: 'withdrawal_date',
        type: PlutoColumnType.text(),
        width: 110,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) => Align(
          alignment: Alignment.centerLeft,
          child: Text(Formatters.date(ctx.cell.value as String? ?? '')),
        ),
      ),
      PlutoColumn(
        title: l10n.equityKind,
        field: 'kind',
        type: PlutoColumnType.text(),
        width: 100,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) {
          final kind = ctx.cell.value as String? ?? '';
          return Builder(
            builder: (cellContext) {
              final cellL10n = AppLocalizations.of(cellContext)!;
              final goods = kind == 'goods';
              return Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      goods
                          ? Icons.inventory_2_outlined
                          : Icons.payments_outlined,
                      size: 15,
                      color: Theme.of(cellContext).colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      goods
                          ? cellL10n.equityKindgoods
                          : cellL10n.equityKindcash,
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
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
      PlutoColumn(
        title: l10n.equityItems,
        field: 'items',
        type: PlutoColumnType.number(),
        width: 80,
        readOnly: true,
        textAlign: PlutoColumnTextAlign.end,
        titleTextAlign: PlutoColumnTextAlign.end,
        enableContextMenu: false,
        renderer: (ctx) {
          final count = ctx.cell.value as int?;
          if (count == null) return const SizedBox.shrink();
          return Align(
            alignment: Alignment.centerRight,
            child: Text('$count'),
          );
        },
      ),
      textColumn('payment_method', l10n.expensesPaymentmethod, 140),
      textColumn('note', l10n.fieldsNote, 220),
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
