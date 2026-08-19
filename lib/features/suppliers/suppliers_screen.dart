// Suppliers list screen — PORTING.md §5/§6. Server-paginated like
// customers: `GET /suppliers` returns one page plus a `pagination` block,
// so this screen drives page/limit/search/sortBy/sortOrder through the
// provider and renders a [ServerPaginationBar] under the grid. Column
// sort maps to the server's SUPPLIER_SORT_COLUMNS whitelist.
//
// Web parity (same treatment as the customers module): the grid mirrors
// the web SuppliersPage columns (Code, Name + contact person, Phone +
// Email, Payment Terms, Balance, Status) plus a per-row actions menu
// (View/Edit/Delete), an All/Active/Inactive status filter (server
// `?status=`), and a "Fix Balances" recalculate action
// (`POST /suppliers/recalculate-balances`).
//
// Built on the shared [PlutoGridScreen] mixin: F2/Enter + double-tap open
// the focused row's detail (the full-screen supplier detail page), and
// the keyboard-hint status bar sits beneath the grid.

import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/theme/status_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/supplier.dart' show Supplier;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/paged_request.dart' show PagedResponse;
import '../../data/repositories/supplier_repository.dart'
    show supplierRepositoryProvider;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/pagination_bar.dart';
import '../../widgets/pluto_grid_screen.dart';
import '../../widgets/screen_toolbar.dart';
import '../../widgets/status_badge.dart';
import 'supplier_form_dialog.dart';
import 'supplier_providers.dart';

/// The grid's status filter. All omits the `status` param; Active /
/// Inactive map to the server's `?status=active|inactive` values (the web
/// SuppliersPage tab bar).
enum _StatusFilter { all, active, inactive }

/// The per-row actions menu items (web ⋮ dropdown: View / Edit / Delete).
enum _RowAction { view, edit, delete }

class SuppliersScreen extends ConsumerStatefulWidget {
  const SuppliersScreen({super.key});

  @override
  ConsumerState<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends ConsumerState<SuppliersScreen>
    with PlutoGridScreen<Supplier, SuppliersScreen> {
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();
  bool _fixingBalances = false;

  @override
  void openRowDetail(int supplierId) {
    if (!mounted) return;
    // Web parity: double-tap / F2 / Enter / ⋮ View open the full-screen
    // detail page instead of the old read-only dialog.
    context.push('/suppliers/$supplierId');
  }

  /// The suppliers provider returns a `PagedResponse` envelope — unwrap
  /// the current page's items as the grid rows.
  @override
  Iterable<Supplier> gridRowsFrom(Object? value) =>
      (value as PagedResponse<Supplier>).items;

  /// The row's record id (the mixin's hidden `id` cell) plus the full
  /// [Supplier] object the actions menu needs (hidden `data` cell).
  @override
  List<String> get hiddenGridColumnFields => const ['id', 'data'];

  @override
  PlutoRow gridRowFor(Supplier supplier) => PlutoRow(
    cells: {
      'id': PlutoCell(value: supplier.id),
      'data': PlutoCell(value: supplier),
      'code': PlutoCell(value: supplier.supplierCode),
      'name': PlutoCell(value: supplier.supplierName),
      'phone': PlutoCell(value: supplier.phone ?? ''),
      'email': PlutoCell(value: supplier.email ?? ''),
      'terms': PlutoCell(value: supplier.paymentTerms ?? ''),
      'balance': PlutoCell(value: supplier.currentBalance ?? 0),
      'active': PlutoCell(value: supplier.isActive),
      // Every column needs a cell (PlutoGrid's initializeRows null-checks
      // `row.cells[column.field]!` for ALL columns, hidden or not); the
      // actions column's renderer overrides the cell, so the value is
      // never displayed.
      'actions': PlutoCell(value: ''),
    },
  );

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
      ref.read(suppliersSearchProvider.notifier).state = value.trim();
      // A new search starts back at page 1.
      if (ref.read(suppliersPageProvider) != 1) {
        ref.read(suppliersPageProvider.notifier).state = 1;
      }
    });
  }

  void _onStatusChanged(_StatusFilter filter) {
    final status = switch (filter) {
      _StatusFilter.all => null,
      _StatusFilter.active => 'active',
      _StatusFilter.inactive => 'inactive',
    };
    ref.read(suppliersStatusProvider.notifier).state = status;
    // A new filter starts back at page 1.
    if (ref.read(suppliersPageProvider) != 1) {
      ref.read(suppliersPageProvider.notifier).state = 1;
    }
  }

  /// Grid field → server sort column (whitelist in sqlSanitizer.ts).
  String? _sortColumnFor(String field) => switch (field) {
    'code' => 'supplier_code',
    'name' => 'supplier_name',
    'email' => 'email',
    'phone' => 'phone',
    'balance' => 'current_balance',
    'active' => 'is_active', // whitelisted server sort column
    _ => null,
  };

  /// Column sort maps to the server-side sort providers (this endpoint is
  /// server-paginated, so ordering happens on the server).
  @override
  void onGridSorted(PlutoGridOnSortedEvent event) {
    final sortBy = _sortColumnFor(event.column.field);
    if (sortBy == null) return;
    final sort = event.column.sort;
    ref.read(suppliersSortProvider.notifier).state = sort.isNone
        ? null
        : SupplierSort(
            sortBy,
            sort == PlutoColumnSort.ascending ? 'ASC' : 'DESC',
          );
    if (ref.read(suppliersPageProvider) != 1) {
      ref.read(suppliersPageProvider.notifier).state = 1;
    }
  }

  void _onRowAction(_RowAction action, Supplier? supplier) {
    if (supplier == null || !mounted) return;
    switch (action) {
      case _RowAction.view:
        openRowDetail(supplier.id);
      case _RowAction.edit:
        showSupplierFormDialog(context, supplier: supplier);
      case _RowAction.delete:
        _deleteSupplier(supplier);
    }
  }

  Future<void> _deleteSupplier(Supplier supplier) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.suppliersDelete,
      message: '${l10n.suppliersConfirmdelete} "${supplier.supplierName}"?',
      confirmLabel: l10n.suppliersDelete,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    final result = await ref
        .read(supplierRepositoryProvider)
        .delete(supplier.id);
    if (!mounted) return;
    switch (result) {
      case ApiSuccess():
        showAppToast(context, l10n.suppliersSupplierdeleted);
        ref.invalidate(suppliersProvider);
      case ApiFailure(:final error):
        // Surfaces the server 400 ("Cannot delete supplier with existing
        // purchase orders") verbatim.
        showAppToast(context, error.message, isError: true);
    }
  }

  Future<void> _fixBalances() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.suppliersFixbalances,
      message: l10n.suppliersFixbalancesconfirm,
      confirmLabel: l10n.suppliersFixbalances,
    );
    if (!confirmed || !mounted) return;

    setState(() => _fixingBalances = true);
    final result = await ref
        .read(supplierRepositoryProvider)
        .recalculateBalances();
    if (!mounted) return;
    setState(() => _fixingBalances = false);

    switch (result) {
      case ApiSuccess():
        showAppToast(context, l10n.suppliersBalancesrecalculated);
        ref.invalidate(suppliersProvider);
      case ApiFailure(:final error):
        showAppToast(context, error.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final suppliers = ref.watch(suppliersProvider);
    final l10n = AppLocalizations.of(context)!;
    final page = suppliers.valueOrNull;
    final status = ref.watch(suppliersStatusProvider);

    // Keep the grid in sync with provider transitions (loading → data).
    watchGridProvider(suppliersProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScreenToolbar(
          searchController: _searchController,
          searchHint: l10n.commonSearch,
          onSearchChanged: _onSearchChanged,
          onClearSearch: () {
            // Cancel any pending debounce so a stale timer can't
            // resurrect the old term, and reset to page 1 (the
            // server-paginated search re-runs from the first page).
            _debounce?.cancel();
            _searchController.clear();
            ref.read(suppliersSearchProvider.notifier).state = '';
            if (ref.read(suppliersPageProvider) != 1) {
              ref.read(suppliersPageProvider.notifier).state = 1;
            }
          },
          // Status filter — server-side like customers (`?status=` param
          // is applied server-side).
          filters: [
            SegmentedButton<_StatusFilter>(
              segments: [
                ButtonSegment(
                  value: _StatusFilter.all,
                  label: Text(l10n.commonAll),
                ),
                ButtonSegment(
                  value: _StatusFilter.active,
                  label: Text(l10n.statusActive),
                ),
                ButtonSegment(
                  value: _StatusFilter.inactive,
                  label: Text(l10n.statusInactive),
                ),
              ],
              selected: {
                switch (status) {
                  null => _StatusFilter.all,
                  'active' => _StatusFilter.active,
                  _ => _StatusFilter.inactive,
                },
              },
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  _onStatusChanged(selection.first),
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
          onRefresh: () => ref.invalidate(suppliersProvider),
          primaryActions: [
            FilledButton.tonalIcon(
              onPressed: () => showSupplierFormDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.suppliersNewsupplier),
            ),
            FilledButton.tonalIcon(
              onPressed: _fixingBalances ? null : _fixBalances,
              icon: _fixingBalances
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 18),
              label: Text(l10n.suppliersFixbalances),
            ),
          ],
        ),
        Expanded(child: gridScreenBody(suppliers, provider: suppliersProvider)),
        if (page != null)
          ServerPaginationBar(
            page: page.currentPage,
            totalPages: page.totalPages,
            totalItems: page.totalItems,
            hasNext: page.hasNext,
            hasPrev: page.hasPrev,
            limit: ref.watch(suppliersLimitProvider),
            itemLabel: l10n.suppliersSuppliers,
            onPageChanged: (p) =>
                ref.read(suppliersPageProvider.notifier).state = p,
            onLimitChanged: (limit) {
              ref.read(suppliersLimitProvider.notifier).state = limit;
              if (ref.read(suppliersPageProvider) != 1) {
                ref.read(suppliersPageProvider.notifier).state = 1;
              }
            },
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  /// Column set — order/format mirrors the web SuppliersGrid: Code, Name
  /// (+ contact person), Contact Info (phone + email), Payment Terms,
  /// Balance, Status, Actions.
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
      // Hidden record-id cell (the mixin's id pattern) — never revealed.
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
      // Hidden cell carrying the full Supplier for the actions menu —
      // hidden with the id column in onLoaded.
      PlutoColumn(
        title: '',
        field: 'data',
        type: PlutoColumnType.text(),
        width: 80,
        readOnly: true,
        renderer: (ctx) => const SizedBox.shrink(),
        enableContextMenu: false,
        enableFilterMenuItem: false,
        enableHideColumnMenuItem: false,
        enableSetColumnsMenuItem: false,
      ),
      textColumn('code', l10n.suppliersSuppliercode, 110),
      // Supplier name + contact person sub-line.
      PlutoColumn(
        title: l10n.suppliersSuppliername,
        field: 'name',
        type: PlutoColumnType.text(),
        width: 200,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) {
          final supplier = ctx.cell.row.cells['data']?.value as Supplier?;
          return Builder(
            builder: (cellContext) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${ctx.cell.value}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (supplier?.contactPerson?.isNotEmpty ?? false)
                  Text(
                    supplier!.contactPerson!,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(cellContext).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      // Contact info (phone + email sub-line, web's Contact Info column).
      PlutoColumn(
        title: l10n.suppliersContactinfo,
        field: 'phone',
        type: PlutoColumnType.text(),
        width: 190,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) {
          final supplier = ctx.cell.row.cells['data']?.value as Supplier?;
          return Builder(
            builder: (cellContext) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${ctx.cell.value}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                if (supplier?.email?.isNotEmpty ?? false)
                  Text(
                    supplier!.email!,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(cellContext).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      textColumn('terms', l10n.suppliersPaymentterms, 120),
      PlutoColumn(
        title: l10n.suppliersBalance,
        field: 'balance',
        type: PlutoColumnType.number(format: '#,###.00'),
        width: 120,
        readOnly: true,
        textAlign: PlutoColumnTextAlign.end,
        titleTextAlign: PlutoColumnTextAlign.end,
        enableContextMenu: false,
        renderer: (ctx) => Builder(
          builder: (cellContext) {
            final balance = ctx.cell.value as num? ?? 0;
            final isDark =
                Theme.of(cellContext).brightness == Brightness.dark;
            final color = balance > 0
                ? (isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706))
                : (isDark
                      ? const Color(0xFF4ADE80)
                      : const Color(0xFF15803D));
            return Align(
              alignment: Alignment.centerRight,
              child: Text(
                Formatters.currency(balance),
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            );
          },
        ),
      ),
      PlutoColumn(
        title: l10n.commonStatus,
        field: 'active',
        type: PlutoColumnType.text(),
        width: 110,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) {
          final active = ctx.cell.value == true;
          return Align(
            alignment: Alignment.centerLeft,
            child: StatusBadge(
              status: active ? l10n.statusActive : l10n.statusInactive,
              color: StatusColors.of(context).active(active),
            ),
          );
        },
      ),
      // Per-row actions menu — the web's ⋮ dropdown (View/Edit/Delete).
      // A raw Listener opens the menu: PlutoGrid's cell gesture handler
      // competes in the gesture arena and swallows an IconButton/InkWell
      // tap, but a Listener receives pointer events regardless of the
      // arena, so the menu opens reliably (and in widget tests).
      PlutoColumn(
        title: l10n.suppliersActions,
        field: 'actions',
        // Pinned to the right edge — stays reachable when the grid scrolls.
        frozen: PlutoColumnFrozen.end,
        type: PlutoColumnType.text(),
        width: 64,
        readOnly: true,
        enableContextMenu: false,
        enableFilterMenuItem: false,
        enableHideColumnMenuItem: false,
        enableSetColumnsMenuItem: false,
        renderer: (ctx) {
          final supplier = ctx.cell.row.cells['data']?.value as Supplier?;
          return Builder(
            builder: (cellContext) => Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => _openRowMenu(cellContext, supplier),
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

  /// Opens the row-actions menu anchored at [cellContext] (the ⋮ cell).
  /// Uses [showMenu] directly — the PopupMenuButton trigger can't receive
  /// the tap inside a PlutoGrid cell, but this path only needs a position.
  Future<void> _openRowMenu(
    BuildContext cellContext,
    Supplier? supplier,
  ) async {
    if (supplier == null || !mounted) return;
    final box = cellContext.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final overlay = Overlay.of(cellContext, rootOverlay: true);
    final l10n = AppLocalizations.of(cellContext)!;
    final action = await showMenu<_RowAction>(
      context: cellContext,
      position: RelativeRect.fromRect(
        Rect.fromPoints(
          box.localToGlobal(Offset.zero),
          box.localToGlobal(box.size.bottomRight(Offset.zero)),
        ),
        Offset.zero & overlay.context.size!,
      ),
      items: [
        PopupMenuItem(
          value: _RowAction.view,
          child: Row(
            children: [
              const Icon(Icons.visibility_outlined, size: 18),
              const SizedBox(width: 8),
              Text(l10n.commonView),
            ],
          ),
        ),
        PopupMenuItem(
          value: _RowAction.edit,
          child: Row(
            children: [
              const Icon(Icons.edit_outlined, size: 18),
              const SizedBox(width: 8),
              Text(l10n.commonEdit),
            ],
          ),
        ),
        PopupMenuItem(
          value: _RowAction.delete,
          child: Row(
            children: [
              Icon(
                Icons.delete_outline,
                size: 18,
                color: Theme.of(cellContext).colorScheme.error,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.suppliersDelete,
                style: TextStyle(
                  color: Theme.of(cellContext).colorScheme.error,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    if (action != null && mounted) {
      _onRowAction(action, supplier);
    }
  }
}
