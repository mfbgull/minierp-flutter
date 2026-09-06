// Customers list screen — PORTING.md §5/§6. The project's only
// server-paginated list: `GET /customers` returns one page plus a
// `pagination` block, so unlike the items grid (full list, client-side
// sort) this screen drives page/limit/search/sortBy/sortOrder through the
// provider and renders a [ServerPaginationBar] under the grid. Column
// sort maps to the server's CUSTOMER_SORT_COLUMNS whitelist.
//
// Web parity (customer-module-spec.md §5): the grid mirrors the web
// CustomersPage columns (Code, Name+contact, Phone/Email, Address, Credit
// Limit, Current Balance, Credit Utilization, Payment Terms, Status) plus
// a per-row actions menu (View/Edit/Delete), an All/Active/Inactive
// status filter (server `?status=`), and a "Fix Balances" recalculate
// action (`POST /customers/recalculate-balances`).
//
// Built on the shared [PlutoGridScreen] mixin: F2/Enter + double-tap open
// the focused row's detail, and the keyboard-hint status bar sits beneath
// the grid. The only mixin overrides beyond the data mapping are
// [gridRowsFrom] (the provider yields a `PagedResponse` envelope, not a
// plain list) and [onGridSorted] (sorting happens server-side).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart';
import '../../data/models/customer.dart' show Customer;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/customer_repository.dart'
    show customerRepositoryProvider;
import '../../data/repositories/paged_request.dart' show PagedResponse;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/pagination_bar.dart';
import '../../widgets/pluto_grid_screen.dart';
import '../../widgets/screen_toolbar.dart';
import '../../widgets/offline_cache_badge.dart';
import 'customers_grid_columns.dart';
import 'customers_row_actions.dart';
import 'customer_form_dialog.dart';
import 'customer_providers.dart';

/// The grid's status filter. All omits the `status` param; Active /
/// Inactive map to the server's `?status=active|inactive` values (the web
/// CustomersPage tab bar).
enum _StatusFilter { all, active, inactive }

/// The per-row actions menu items (web ⋮ dropdown: View / Edit / Delete).
class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen>
    with PlutoGridScreen<Customer, CustomersScreen> {
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();
  bool _fixingBalances = false;

  @override
  void openRowDetail(int customerId) {
    if (!mounted) return;
    // Web parity: double-tap / F2 / Enter / ⋮ View open the full-screen
    // detail page (customer-module-spec.md §4) instead of the old
    // read-only dialog.
    context.push('/customers/$customerId');
  }

  /// The customers provider returns a `PagedResponse` envelope — unwrap
  /// the current page's items as the grid rows.
  @override
  Iterable<Customer> gridRowsFrom(Object? value) =>
      (value as PagedResponse<Customer>).items;

  /// The row's record id (the mixin's hidden `id` cell) plus the full
  /// [Customer] object the actions menu needs (hidden `data` cell).
  @override
  List<String> get hiddenGridColumnFields => const ['id', 'data'];

  /// Bulk selection (SHORTCOMINGS-FIX 4.4): checkbox column + select-all
  /// header, driving the bulk action bar (export the selected rows).
  /// Selection resets whenever the grid rows are replaced.
  @override
  bool get enableBulkSelection => true;

  @override
  PlutoRow gridRowFor(Customer customer) => PlutoRow(
    cells: {
      'id': PlutoCell(value: customer.id),
      'data': PlutoCell(value: customer),
      'code': PlutoCell(value: customer.customerCode),
      'name': PlutoCell(value: customer.customerName),
      'phone': PlutoCell(value: customer.phone ?? ''),
      'email': PlutoCell(value: customer.email ?? ''),
      'address': PlutoCell(value: customer.billingAddress ?? ''),
      'creditLimit': PlutoCell(value: customer.creditLimit ?? 0),
      'balance': PlutoCell(value: customer.currentBalance),
      'utilization': PlutoCell(value: customer.creditUtilizationPercent ?? 0),
      'terms': PlutoCell(value: customer.paymentTermsDays ?? 0),
      'active': PlutoCell(value: customer.isActive),
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
      ref.read(customersSearchProvider.notifier).state = value.trim();
      // A new search starts back at page 1.
      if (ref.read(customersPageProvider) != 1) {
        ref.read(customersPageProvider.notifier).state = 1;
      }
    });
  }

  void _onStatusChanged(_StatusFilter filter) {
    final status = switch (filter) {
      _StatusFilter.all => null,
      _StatusFilter.active => 'active',
      _StatusFilter.inactive => 'inactive',
    };
    ref.read(customersStatusProvider.notifier).state = status;
    // A new filter starts back at page 1.
    if (ref.read(customersPageProvider) != 1) {
      ref.read(customersPageProvider.notifier).state = 1;
    }
  }

  /// Grid field → server sort column (whitelist in sqlSanitizer.ts).
  /// `utilization` and `terms` have no whitelisted server column, so
  /// sorting them is a no-op (null).
  String? _sortColumnFor(String field) => switch (field) {
    'code' => 'customer_code',
    'name' => 'customer_name',
    'phone' => 'phone',
    'email' => 'email',
    'address' => 'billing_address',
    'creditLimit' => 'credit_limit',
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
    ref.read(customersSortProvider.notifier).state = sort.isNone
        ? null
        : CustomerSort(
            sortBy,
            sort == PlutoColumnSort.ascending ? 'ASC' : 'DESC',
          );
    if (ref.read(customersPageProvider) != 1) {
      ref.read(customersPageProvider.notifier).state = 1;
    }
  }

  /// Bulk CSV export — the selected customers' rows only (SHORTCOMINGS-
  /// FIX 4.4), mirroring the grid columns via [buildCustomersCsv].
  void _bulkExport(Set<int> ids) {
    final l10n = AppLocalizations.of(context)!;
    final customers =
        ref.read(customersProvider).valueOrNull?.items ?? const <Customer>[];
    final selected = [
      for (final c in customers)
        if (ids.contains(c.id)) c,
    ];
    if (selected.isEmpty) return;
    saveCsv(
      context,
      suggestedName: csvSuggestedName('customers'),
      csv: buildCustomersCsv(l10n, selected),
      successMessage: l10n.customersExportsuccess,
      errorMessage: l10n.customersExportfailed,
    );
  }

  Future<void> _fixBalances() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.customersFixbalances,
      message: l10n.customersFixbalancesconfirm,
      confirmLabel: l10n.customersFixbalances,
    );
    if (!confirmed || !mounted) return;

    setState(() => _fixingBalances = true);
    final result = await ref.read(
      customerRepositoryProvider,
    ).recalculateBalances();
    if (!mounted) return;
    setState(() => _fixingBalances = false);

    switch (result) {
      case ApiSuccess():
        showAppToast(context, l10n.customersFixbalancessuccess);
        ref.invalidate(customersProvider);
      case ApiFailure(:final error):
        showAppToast(context, error.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customersProvider);
    final l10n = AppLocalizations.of(context)!;
    final page = customers.valueOrNull;
    final status = ref.watch(customersStatusProvider);

    // Keep the grid in sync with provider transitions (loading → data).
    watchGridProvider(customersProvider);

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
            ref.read(customersSearchProvider.notifier).state = '';
            if (ref.read(customersPageProvider) != 1) {
              ref.read(customersPageProvider.notifier).state = 1;
            }
          },
          // All / Active / Inactive status filter (web tab bar) — the
          // `?status=` param is applied server-side.
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
          onRefresh: () => ref.invalidate(customersProvider),
          actions: [const OfflineCacheBadge()],
          // The web's "Fix Balances" action (recalculate all customer
          // balances from unpaid invoices). Kept AFTER the New-customer
          // button so the Ctrl+N chord stays on Add Customer and the
          // secondary `actions` slot (the Ctrl+E export chord) stays free.
          primaryActions: [
            FilledButton.tonalIcon(
              onPressed: () => showCustomerFormDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.customersNewcustomer),
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
              label: Text(l10n.customersFixbalances),
            ),
          ],
        ),
        // Bulk action bar (checkbox rows selected) — export the selected
        // customers to CSV (SHORTCOMINGS-FIX 4.4).
        ValueListenableBuilder<Set<int>>(
          valueListenable: bulkSelection.selected,
          builder: (context, sel, _) {
            if (sel.isEmpty) return const SizedBox.shrink();
            return BulkActionBar(
              count: sel.length,
              onClearSelection: bulkSelection.clear,
              actions: [
                TextButton.icon(
                  onPressed: () => _bulkExport(sel),
                  icon: const Icon(Icons.file_download_outlined, size: 18),
                  label: Text(l10n.bulkExportSelected),
                ),
              ],
            );
          },
        ),
        Expanded(child: gridScreenBody(customers, provider: customersProvider)),
        if (page != null)
          ServerPaginationBar(
            page: page.currentPage,
            totalPages: page.totalPages,
            totalItems: page.totalItems,
            hasNext: page.hasNext,
            hasPrev: page.hasPrev,
            limit: ref.watch(customersLimitProvider),
            itemLabel: l10n.customersCustomers,
            onPageChanged: (p) =>
                ref.read(customersPageProvider.notifier).state = p,
            onLimitChanged: (limit) {
              ref.read(customersLimitProvider.notifier).state = limit;
              if (ref.read(customersPageProvider) != 1) {
                ref.read(customersPageProvider.notifier).state = 1;
              }
            },
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  /// Column set — order/format mirrors the web CustomersGrid: Code, Name
  /// (+ contact person), Contact Info (phone + email), Address, Credit
  /// Limit, Current Balance, Credit Utilization, Payment Terms, Status,
  /// Actions. Balance/utilization cells carry the web's color coding
  /// (due = amber, clear = green, utilization ≥90% red / ≥75% amber).
  ///
  /// Column definitions live in `customers_grid_columns.dart` (spec 1.3);
  /// this method only wires the row-menu callback into the shared builder.
  @override
  List<PlutoColumn> buildGridColumns(AppLocalizations l10n) {
    return buildCustomerColumns(l10n: l10n, onOpenRowMenu: _openRowMenu);
  }

  /// Row-actions menu + delete logic live in `customers_row_actions.dart`
  /// (spec 1.3); the grid's ⋮ cell only needs to forward the tap.
  Future<void> _openRowMenu(BuildContext cellContext, Customer? customer) async {
    if (customer == null || !mounted) return;
    await openCustomerRowMenu(context: cellContext, ref: ref, customer: customer);
  }

}
