// Suppliers list screen — PORTING.md §5/§6. Server-paginated like
// customers: `GET /suppliers` returns one page plus a `pagination` block,
// so this screen drives page/limit/search/sortBy/sortOrder through the
// provider and renders a [ServerPaginationBar] under the grid. Column
// sort maps to the server's SUPPLIER_SORT_COLUMNS whitelist.
//
// Built on the shared [PlutoGridScreen] mixin: F2/Enter + double-tap open
// the focused row's detail, and the keyboard-hint status bar sits beneath
// the grid. The only mixin overrides beyond the data mapping are
// [gridRowsFrom] (the provider yields a `PagedResponse` envelope, not a
// plain list) and [onGridSorted] (sorting happens server-side).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/supplier.dart' show Supplier;
import '../../data/repositories/paged_request.dart' show PagedResponse;
import '../../l10n/app_localizations.dart';
import '../../widgets/pagination_bar.dart';
import '../../widgets/pluto_grid_screen.dart';
import '../../widgets/screen_toolbar.dart';
import '../../widgets/status_badge.dart';
import 'supplier_detail_dialog.dart';
import 'supplier_form_dialog.dart';
import 'supplier_providers.dart';

class SuppliersScreen extends ConsumerStatefulWidget {
  const SuppliersScreen({super.key});

  @override
  ConsumerState<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends ConsumerState<SuppliersScreen>
    with PlutoGridScreen<Supplier, SuppliersScreen> {
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();

  @override
  void openRowDetail(int supplierId) {
    if (!mounted) return;
    showSupplierDetailDialog(context, supplierId: supplierId);
  }

  /// The suppliers provider returns a `PagedResponse` envelope — unwrap
  /// the current page's items as the grid rows.
  @override
  Iterable<Supplier> gridRowsFrom(Object? value) =>
      (value as PagedResponse<Supplier>).items;

  @override
  PlutoRow gridRowFor(Supplier supplier) => PlutoRow(
    cells: {
      'id': PlutoCell(value: supplier.id),
      'code': PlutoCell(value: supplier.supplierCode),
      'name': PlutoCell(value: supplier.supplierName),
      'phone': PlutoCell(value: supplier.phone ?? ''),
      'email': PlutoCell(value: supplier.email ?? ''),
      'balance': PlutoCell(value: supplier.currentBalance ?? 0),
      'active': PlutoCell(value: supplier.isActive),
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

  @override
  Widget build(BuildContext context) {
    final suppliers = ref.watch(suppliersProvider);
    final l10n = AppLocalizations.of(context)!;
    final page = suppliers.valueOrNull;

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
          onRefresh: () => ref.invalidate(suppliersProvider),
          primaryActions: [
            FilledButton.tonalIcon(
              onPressed: () => showSupplierFormDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.suppliersNewsupplier),
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

  /// Column set — order/format mirrors the web SuppliersGrid (Code, Name,
  /// Phone, Email, Balance, Active); read-only for now.
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
      textColumn('code', l10n.suppliersSuppliercode, 120),
      textColumn('name', l10n.suppliersSuppliername, 220),
      textColumn('phone', l10n.suppliersPhone, 130),
      textColumn('email', l10n.suppliersEmail, 190),
      PlutoColumn(
        title: l10n.suppliersBalance,
        field: 'balance',
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
              color: active ? Colors.green : Colors.blueGrey,
            ),
          );
        },
      ),
    ];
  }
}
