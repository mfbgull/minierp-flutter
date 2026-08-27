// Owner withdrawals list tab — read-only PlutoGrid over
// `GET /owner-equity/withdrawals` with kind/search/date filters. Goods
// rows double-tap to the batch-consumption breakdown; both kinds open the
// edit dialog from the row menu.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/owner_equity.dart' show OwnerWithdrawal;
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
import 'owner_equity_providers.dart';
import 'owner_withdrawal_detail_dialog.dart';
import 'owner_withdrawal_form_dialog.dart';

class OwnerWithdrawalsTab extends ConsumerStatefulWidget {
  const OwnerWithdrawalsTab({super.key});

  @override
  ConsumerState<OwnerWithdrawalsTab> createState() =>
      _OwnerWithdrawalsTabState();
}

class _OwnerWithdrawalsTabState extends ConsumerState<OwnerWithdrawalsTab> {
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

  void _applyRows(AsyncValue<PagedResponse<OwnerWithdrawal>> value) {
    final manager = _stateManager;
    if (manager == null) return;
    manager.setShowLoading(value.isLoading);
    if (value.hasValue) {
      manager.removeAllRows();
      manager.appendRows([
        for (final (index, row) in (value.value!.items).indexed)
          _rowFor(row, index),
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

  PlutoRow _rowFor(OwnerWithdrawal row, int index) => withSerialCell(
    PlutoRow(
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
    ),
    index,
  );

  @override
  Widget build(BuildContext context) {
    final withdrawals = ref.watch(ownerWithdrawalsProvider);
    final page = withdrawals.valueOrNull;
    final l10n = AppLocalizations.of(context)!;

    ref.listen(ownerWithdrawalsProvider, (previous, next) => _applyRows(next));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _toolbar(l10n),
        ),
        Expanded(child: _buildBody(withdrawals)),
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

  Widget _buildBody(AsyncValue<PagedResponse<OwnerWithdrawal>> withdrawals) {
    final errorMessage = switch (withdrawals) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };
    if (errorMessage != null) {
      _stateManager = null;
      return ScreenErrorPanel(
        message: errorMessage,
        onRetry: () => ref.invalidate(ownerWithdrawalsProvider),
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
          _applyRows(ref.read(ownerWithdrawalsProvider));
          _widthTracker?.dispose();
          _widthTracker = GridColumnWidths.attach(
            stateManager: event.stateManager,
            screenKey: 'owner_withdrawals',
          );
        },
        onRowDoubleTap: (event) {
          final id = event.row.cells['id']?.value as int?;
          if (id == null || id <= 0) return;
          final rows =
              ref.read(ownerWithdrawalsProvider).valueOrNull?.items ??
              const <OwnerWithdrawal>[];
          for (final row in rows) {
            if (row.id == id) {
              if (row.kind == 'goods') {
                showOwnerWithdrawalDetailDialog(context, row.id);
              } else {
                showOwnerWithdrawalFormDialog(context, entry: row);
              }
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
      case 'withdrawal_no':
        return 'ow.withdrawal_no';
      case 'withdrawal_date':
        return 'ow.withdrawal_date';
      case 'kind':
        return 'ow.kind';
      case 'amount':
        return 'ow.amount';
      case 'status':
        return 'ow.status';
      case 'created_by':
        return 'ow.created_at';
      default:
        return null;
    }
  }

  void _onGridSorted(PlutoGridOnSortedEvent event) {
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
          final row = ctx.cell.row.cells['data']?.value as OwnerWithdrawal?;
          return Builder(
            builder: (cellContext) => Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) {
                if (row != null && mounted) {
                  showOwnerWithdrawalFormDialog(context, entry: row);
                }
              },
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
}
