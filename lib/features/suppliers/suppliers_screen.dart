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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pluto_grid/pluto_grid.dart';

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
import 'supplier_form_dialog.dart';
import 'suppliers_grid_columns.dart';
import 'suppliers_row_actions.dart';
import 'supplier_providers.dart';

/// The grid's status filter. All omits the `status` param; Active /
/// Inactive map to the server's `?status=active|inactive` values (the web
/// SuppliersPage tab bar).
enum _StatusFilter { all, active, inactive }

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

  /// Column definitions live in `suppliers_grid_columns.dart` (spec 1.3);
  /// this method only wires the row-menu callback into the shared builder.
  @override
  List<PlutoColumn> buildGridColumns(AppLocalizations l10n) {
    return buildSupplierColumns(l10n: l10n, onOpenRowMenu: _openRowMenu);
  }

  /// Row-actions menu + delete logic live in `suppliers_row_actions.dart`
  /// (spec 1.3); the grid's ⋮ cell only needs to forward the tap.
  Future<void> _openRowMenu(BuildContext cellContext, Supplier? supplier) async {
    if (supplier == null || !mounted) return;
    await openSupplierRowMenu(context: cellContext, ref: ref, supplier: supplier);
  }
}
