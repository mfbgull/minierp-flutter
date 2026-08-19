// Purchase returns list screen — a grid over `GET /purchase-returns`
// (**server-paginated** return headers; search and sorting happen
// server-side — the endpoint returns a `pagination` block). Rendered
// with PlutoGrid via the shared [PlutoGridScreen] mixin: F2/Enter +
// double-tap open the return detail, and the [ServerPaginationBar] sits
// beneath the grid. Hosted as the 'Purchase Returns' tab of the
// purchasing shell.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/formatters.dart';
import '../../core/utils/csv_export.dart';
import '../../core/utils/purchase_return_status.dart';
import '../../core/utils/purchase_return_type.dart';
import '../../data/models/purchase_return.dart' show PurchaseReturn;
import '../../data/repositories/paged_request.dart' show PagedResponse;
import '../../l10n/app_localizations.dart';
import '../../widgets/date_range_picker.dart' show DateRangeFilter;
import '../../widgets/pagination_bar.dart' show ServerPaginationBar;
import '../../widgets/pluto_grid_screen.dart';
import '../../widgets/screen_toolbar.dart';
import '../../widgets/status_badge.dart';
import 'purchase_return_detail_dialog.dart';
import 'purchase_return_providers.dart';
import 'purchase_return_void_dialog.dart';
import 'return_source_picker_dialog.dart' show showReturnSourcePicker;

class PurchaseReturnsScreen extends ConsumerStatefulWidget {
  const PurchaseReturnsScreen({super.key});

  @override
  ConsumerState<PurchaseReturnsScreen> createState() =>
      _PurchaseReturnsScreenState();
}

class _PurchaseReturnsScreenState extends ConsumerState<PurchaseReturnsScreen>
    with PlutoGridScreen<PurchaseReturn, PurchaseReturnsScreen> {
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();

  /// Row id → model for the detail dialog — there is no per-row endpoint,
  /// so the dialog renders from the row the grid was built from.
  final Map<int, PurchaseReturn> _returnsById = {};

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
      ref.read(purchaseReturnsSearchProvider.notifier).state = value.trim();
      // A new search starts back at page 1.
      if (ref.read(purchaseReturnsPageProvider) != 1) {
        ref.read(purchaseReturnsPageProvider.notifier).state = 1;
      }
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    ref.read(purchaseReturnsSearchProvider.notifier).state = '';
    if (ref.read(purchaseReturnsPageProvider) != 1) {
      ref.read(purchaseReturnsPageProvider.notifier).state = 1;
    }
  }

  bool get _hasActiveFilters =>
      ref.read(purchaseReturnsStatusFilterProvider) != null ||
      ref.read(purchaseReturnsFromDateProvider) != null ||
      ref.read(purchaseReturnsToDateProvider) != null;

  /// Resets every toolbar filter (including the date range) back to page 1.
  void _clearFilters() {
    ref.read(purchaseReturnsStatusFilterProvider.notifier).state = null;
    ref.read(purchaseReturnsFromDateProvider.notifier).state = null;
    ref.read(purchaseReturnsToDateProvider.notifier).state = null;
    if (ref.read(purchaseReturnsPageProvider) != 1) {
      ref.read(purchaseReturnsPageProvider.notifier).state = 1;
    }
  }

  /// The purchase-returns provider returns a `PagedResponse` envelope —
  /// unwrap the current page's items as the grid rows.
  @override
  Iterable<PurchaseReturn> gridRowsFrom(Object? value) =>
      (value as PagedResponse<PurchaseReturn>).items;

  /// Grid field → server sort column (whitelist in sqlSanitizer.ts —
  /// `PURCHASE_RETURN_HEADER_SORT_COLUMNS`). Header-level sort only; the
  /// qty column has no server sort column, so it stays unsortable.
  String? _sortColumnFor(String field) => switch (field) {
    'returnNo' => 'return_no',
    'date' => 'return_date',
    'source' => 'source_no',
    'total' => 'total_amount',
    'warehouse' => 'warehouse_name',
    _ => null,
  };

  /// Column sort maps to the server-side sort provider (this endpoint is
  /// server-paginated, so ordering happens on the server).
  @override
  void onGridSorted(PlutoGridOnSortedEvent event) {
    final sortBy = _sortColumnFor(event.column.field);
    if (sortBy == null) return;
    final sort = event.column.sort;
    ref.read(purchaseReturnsSortProvider.notifier).state = sort.isNone
        ? null
        : PurchaseReturnSort(
            sortBy,
            sort == PlutoColumnSort.ascending ? 'ASC' : 'DESC',
          );
    if (ref.read(purchaseReturnsPageProvider) != 1) {
      ref.read(purchaseReturnsPageProvider.notifier).state = 1;
    }
  }

  @override
  void openRowDetail(int returnId) {
    if (!mounted) return;
    final purchaseReturn = _returnsById[returnId];
    if (purchaseReturn == null) return;
    showPurchaseReturnDetailDialog(context, purchaseReturn: purchaseReturn);
  }

  /// Opt into the per-row ⋮ actions menu (View detail + Void — the latter
  /// hidden once the return is already VOIDED).
  @override
  bool get hasRowActions => true;

  @override
  List<GridRowAction>? gridRowActionsFor(PlutoRow row, BuildContext context) {
    final id = row.cells['id']?.value as int?;
    if (id == null || id <= 0) return null;
    final purchaseReturn = _returnsById[id];
    if (purchaseReturn == null) return null;
    final l10n = AppLocalizations.of(context)!;
    return [
      GridRowAction(
        icon: Icons.visibility_outlined,
        label: l10n.commonView,
        onTap: () => showPurchaseReturnDetailDialog(
          context,
          purchaseReturn: purchaseReturn,
        ),
      ),
      if (!purchaseReturn.isVoided)
        GridRowAction(
          icon: Icons.block,
          label: l10n.purchasesVoid,
          color: Theme.of(context).colorScheme.error,
          onTap: () =>
              showVoidReturnDialog(context, purchaseReturn: purchaseReturn),
        ),
    ];
  }

  @override
  PlutoRow gridRowFor(PurchaseReturn purchaseReturn) {
    // Cache the model for the F2/Enter/double-tap detail path.
    _returnsById[purchaseReturn.id] = purchaseReturn;
    return PlutoRow(
      cells: {
        'id': PlutoCell(value: purchaseReturn.id),
        'returnNo': PlutoCell(value: purchaseReturn.returnNo),
        'date': PlutoCell(value: purchaseReturn.returnDate),
        'source': PlutoCell(value: purchaseReturn.sourceNo),
        'qty': PlutoCell(value: purchaseReturn.totalQty),
        'total': PlutoCell(value: purchaseReturn.totalAmount),
        'type': PlutoCell(value: purchaseReturn.returnType),
        'status': PlutoCell(value: purchaseReturn.status),
        'warehouse': PlutoCell(value: purchaseReturn.warehouseName),
        'remarks': PlutoCell(value: purchaseReturn.reason ?? ''),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final returns = ref.watch(purchaseReturnsProvider);
    final l10n = AppLocalizations.of(context)!;
    // The full filtered list feeds the CSV export (desktop) and the
    // compact mobile cards (both use the same active filters).
    final filtered = ref.watch(filteredPurchaseReturnsProvider);

    // Keep the grid in sync with provider transitions (loading → data).
    // The mixin listener routes through the default syncGridRows, which
    // unwraps the PagedResponse via gridRowsFrom.
    watchGridProvider(purchaseReturnsProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < 768;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Toolbar: search + status/date filters + CSV export + refresh +
            // the New Return action (opens the source picker → entry form).
            // The shared toolbar is a Wrap, so it stacks on narrow panes —
            // the New Return action stays reachable without a separate FAB.
            ScreenToolbar(
              searchController: _searchController,
              searchHint: l10n.commonSearch,
              onSearchChanged: _onSearchChanged,
              onClearSearch: _clearSearch,
              filters: [
                ScreenToolbarDropdown<String?>(
                  key: const ValueKey('purchase-returns-status-filter'),
                  value: ref.watch(purchaseReturnsStatusFilterProvider),
                  hint: l10n.expensesAllstatuses,
                  items: const [null, 'POSTED', 'VOIDED'],
                  labelBuilder: (v) => v == null
                      ? l10n.expensesAllstatuses
                      : purchaseReturnStatusLabel(l10n, v),
                  width: 140,
                  onChanged: (v) {
                    ref
                            .read(purchaseReturnsStatusFilterProvider.notifier)
                            .state =
                        v;
                    if (ref.read(purchaseReturnsPageProvider) != 1) {
                      ref.read(purchaseReturnsPageProvider.notifier).state = 1;
                    }
                  },
                ),
                DateRangeFilter(
                  height: 40,
                  fromProvider: purchaseReturnsFromDateProvider,
                  toProvider: purchaseReturnsToDateProvider,
                  onClear: _clearFilters,
                  showClear: () => _hasActiveFilters,
                ),
              ],
              onRefresh: () => ref.invalidate(purchaseReturnsProvider),
              primaryActions: [
                FilledButton.icon(
                  onPressed: () => showReturnSourcePicker(context),
                  icon: const Icon(Icons.assignment_return_outlined, size: 18),
                  label: Text(l10n.purchasesNewreturn),
                ),
              ],
              actions: [
                // CSV export — mirrors the invoice-returns grid: the pure
                // builder runs over the currently-filtered rows and the
                // shared save helper owns the FilePicker + toast.
                TextButton.icon(
                  onPressed:
                      returns.isLoading ||
                          (filtered.valueOrNull ?? const []).isEmpty
                      ? null
                      : () => saveCsv(
                          context,
                          suggestedName: csvSuggestedName('purchase-returns'),
                          csv: buildPurchaseReturnsCsv(
                            l10n,
                            filtered.valueOrNull ?? const [],
                          ),
                          successMessage: l10n.purchasesExported,
                          errorMessage: l10n.purchasesExportfailed,
                        ),
                  icon: const Icon(Icons.file_download_outlined, size: 18),
                  label: Text(l10n.purchasesExportcsv),
                ),
              ],
            ),
            Expanded(
              child: mobile
                  ? _mobileList(l10n)
                  : gridScreenBody(returns, provider: purchaseReturnsProvider),
            ),
            if (!mobile)
              if (returns.valueOrNull case final page?)
                ServerPaginationBar(
                  page: page.currentPage,
                  totalPages: page.totalPages,
                  totalItems: page.totalItems,
                  hasNext: page.hasNext,
                  hasPrev: page.hasPrev,
                  limit: ref.watch(purchaseReturnsLimitProvider),
                  itemLabel: l10n.purchasesPurchaseReturns,
                  onPageChanged: (p) =>
                      ref.read(purchaseReturnsPageProvider.notifier).state = p,
                  onLimitChanged: (limit) {
                    ref.read(purchaseReturnsLimitProvider.notifier).state =
                        limit;
                    if (ref.read(purchaseReturnsPageProvider) != 1) {
                      ref.read(purchaseReturnsPageProvider.notifier).state = 1;
                    }
                  },
                ),
            if (!mobile) const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  /// Compact cards under 768px (Compact Card System — modeled on
  /// `DemandForecastScreen._mobileList`): one card per return header fed
  /// by the full *filtered* list provider, so search + status + date
  /// filters apply to the mobile view too. Tapping a card (or the ⋮
  /// menu's View) opens the detail modal; the ⋮ menu also offers Void
  /// for posted returns (mirroring the desktop row actions).
  Widget _mobileList(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final filtered = ref.watch(filteredPurchaseReturnsProvider);
    return filtered.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            l10n.purchasesReturnloaderror,
            style: TextStyle(color: scheme.error),
          ),
        ),
      ),
      data: (rows) => rows.isEmpty
          ? Center(
              child: Text(
                l10n.purchasesReturnnoitems,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final purchaseReturn = rows[i];
                return _CompactReturnCard(
                  purchaseReturn: purchaseReturn,
                  l10n: l10n,
                  onView: () => showPurchaseReturnDetailDialog(
                    context,
                    purchaseReturn: purchaseReturn,
                  ),
                  onVoid: () => showVoidReturnDialog(
                    context,
                    purchaseReturn: purchaseReturn,
                  ),
                );
              },
            ),
    );
  }

  /// Column set — mirrors the return-header columns (Return No, Date,
  /// Source, Qty, Total, Type, Status, Warehouse, Remarks); read-only
  /// (returns are created through the source-picker flow and voided from
  /// the row menu).
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
        // Hidden in onLoaded — never reveal it via the column menu.
        enableContextMenu: false,
        enableFilterMenuItem: false,
        enableHideColumnMenuItem: false,
        enableSetColumnsMenuItem: false,
      ),
      textColumn('returnNo', l10n.purchasesReturnno, 120),
      PlutoColumn(
        title: l10n.purchasesReturndate,
        field: 'date',
        type: PlutoColumnType.text(),
        width: 110,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) => Builder(
          builder: (cellContext) => Align(
            alignment: Alignment.centerLeft,
            child: Text(
              Formatters.date(ctx.cell.value as String? ?? ''),
              style: Theme.of(cellContext).textTheme.bodyMedium,
            ),
          ),
        ),
      ),
      textColumn('source', l10n.fieldsReference, 140),
      PlutoColumn(
        title: l10n.purchasesReturnqty,
        field: 'qty',
        type: PlutoColumnType.number(format: '#,###.##'),
        width: 90,
        readOnly: true,
        textAlign: PlutoColumnTextAlign.end,
        titleTextAlign: PlutoColumnTextAlign.end,
        enableContextMenu: false,
        renderer: (ctx) => Align(
          alignment: Alignment.centerRight,
          child: Text(Formatters.number(ctx.cell.value as num? ?? 0)),
        ),
      ),
      PlutoColumn(
        title: l10n.purchasesReturnvalue,
        field: 'total',
        type: PlutoColumnType.number(format: '#,###.00'),
        width: 120,
        readOnly: true,
        textAlign: PlutoColumnTextAlign.end,
        titleTextAlign: PlutoColumnTextAlign.end,
        enableContextMenu: false,
        renderer: (ctx) => Align(
          alignment: Alignment.centerRight,
          child: Text(Formatters.currency(ctx.cell.value as num? ?? 0)),
        ),
      ),
      PlutoColumn(
        title: l10n.purchasesReturntype,
        field: 'type',
        type: PlutoColumnType.text(),
        width: 140,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) => Builder(
          builder: (cellContext) {
            final type = ctx.cell.value as String? ?? '';
            final (color, darkColor) = returnTypeColors(type);
            return Align(
              alignment: Alignment.centerLeft,
              child: StatusBadge(
                status: returnTypeLabel(
                  AppLocalizations.of(cellContext)!,
                  type,
                ),
                color: color,
                darkColor: darkColor,
              ),
            );
          },
        ),
      ),
      PlutoColumn(
        title: l10n.fieldsStatus,
        field: 'status',
        type: PlutoColumnType.text(),
        width: 100,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) => Builder(
          builder: (cellContext) {
            final status = ctx.cell.value as String? ?? '';
            final (color, darkColor) = purchaseReturnStatusColors(status);
            return Align(
              alignment: Alignment.centerLeft,
              child: StatusBadge(
                status: purchaseReturnStatusLabel(
                  AppLocalizations.of(cellContext)!,
                  status,
                ),
                color: color,
                darkColor: darkColor,
              ),
            );
          },
        ),
      ),
      textColumn('warehouse', l10n.fieldsWarehouse, 140),
      textColumn('remarks', l10n.fieldsNotes, 180),
    ];
  }
}

/// One compact card for the mobile returns list (spec §8.5): return no +
/// source doc header, status badge, return date + type badge, qty /
/// amount / warehouse stats, optional reason, and a per-card ⋮ menu
/// (View + Void) mirroring the desktop row actions. Tapping the card
/// opens the same [PurchaseReturnDetailDialog] the grid F2/Enter opens.
class _CompactReturnCard extends StatelessWidget {
  const _CompactReturnCard({
    required this.purchaseReturn,
    required this.l10n,
    required this.onView,
    required this.onVoid,
  });

  final PurchaseReturn purchaseReturn;
  final AppLocalizations l10n;
  final VoidCallback onView;
  final VoidCallback onVoid;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final r = purchaseReturn;

    final (typeColor, typeDark) = returnTypeColors(r.returnType);
    final (statusColor, statusDark) = purchaseReturnStatusColors(r.status);
    final reason = r.reason?.trim();

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onView,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.returnNo,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${l10n.fieldsReference}: ${r.sourceNo}',
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusBadge(
                    status: purchaseReturnStatusLabel(l10n, r.status),
                    color: statusColor,
                    darkColor: statusDark,
                  ),
                  const SizedBox(width: 4),
                  // Per-card ⋮ menu — View + Void, mirroring the desktop
                  // row actions (Void hidden once the return is voided).
                  PopupMenuButton<String>(
                    tooltip: l10n.commonActions,
                    icon: Icon(
                      Icons.more_vert,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    onSelected: (value) {
                      switch (value) {
                        case 'view':
                          onView();
                        case 'void':
                          onVoid();
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'view',
                        child: Row(
                          children: [
                            Icon(
                              Icons.visibility_outlined,
                              size: 18,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Flexible(child: Text(l10n.commonView)),
                          ],
                        ),
                      ),
                      if (!r.isVoided)
                        PopupMenuItem(
                          value: 'void',
                          child: Row(
                            children: [
                              Icon(Icons.block, size: 18, color: scheme.error),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  l10n.purchasesVoid,
                                  style: TextStyle(color: scheme.error),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.event_outlined,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    Formatters.date(r.returnDate),
                    style: textTheme.bodySmall,
                  ),
                  const SizedBox(width: 10),
                  StatusBadge(
                    status: returnTypeLabel(l10n, r.returnType),
                    color: typeColor,
                    darkColor: typeDark,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _cardStat(
                    context,
                    l10n.purchasesReturnqty,
                    Formatters.number(r.totalQty),
                  ),
                  _cardStat(
                    context,
                    l10n.purchasesReturnvalue,
                    Formatters.currency(r.totalAmount),
                  ),
                  // Warehouse is fixed to the source document — shown
                  // read-only with a lock, mirroring the entry form.
                  _cardStat(
                    context,
                    l10n.fieldsWarehouse,
                    r.warehouseName,
                    leading: Icon(
                      Icons.lock_outline,
                      size: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (reason != null && reason.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  reason,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _cardStat(
    BuildContext context,
    String label,
    String value, {
    Widget? leading,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              if (leading != null) ...[leading, const SizedBox(width: 4)],
              Flexible(
                child: Text(
                  value,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
