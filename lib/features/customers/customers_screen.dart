// Customers list screen — PORTING.md §5/§6. The project's only
// server-paginated list: `GET /customers` returns one page plus a
// `pagination` block, so unlike the items grid (full list, client-side
// sort) this screen drives page/limit/search/sortBy/sortOrder through the
// provider and renders a [ServerPaginationBar] under the grid. Column
// sort maps to the server's CUSTOMER_SORT_COLUMNS whitelist.
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
import '../../data/models/customer.dart' show Customer;
import '../../data/repositories/paged_request.dart' show PagedResponse;
import '../../l10n/app_localizations.dart';
import '../../widgets/pagination_bar.dart';
import '../../widgets/pluto_grid_screen.dart';
import '../../widgets/status_badge.dart';
import 'customer_detail_dialog.dart';
import 'customer_form_dialog.dart';
import 'customer_providers.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen>
    with PlutoGridScreen<Customer, CustomersScreen> {
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();

  @override
  void openRowDetail(int customerId) {
    if (!mounted) return;
    showCustomerDetailDialog(context, customerId: customerId);
  }

  /// The customers provider returns a `PagedResponse` envelope — unwrap
  /// the current page's items as the grid rows.
  @override
  Iterable<Customer> gridRowsFrom(Object? value) =>
      (value as PagedResponse<Customer>).items;

  @override
  PlutoRow gridRowFor(Customer customer) => PlutoRow(
    cells: {
      'id': PlutoCell(value: customer.id),
      'code': PlutoCell(value: customer.customerCode),
      'name': PlutoCell(value: customer.customerName),
      'phone': PlutoCell(value: customer.phone ?? ''),
      'email': PlutoCell(value: customer.email ?? ''),
      'balance': PlutoCell(value: customer.currentBalance),
      'active': PlutoCell(value: customer.isActive),
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

  /// Grid field → server sort column (whitelist in sqlSanitizer.ts).
  String? _sortColumnFor(String field) => switch (field) {
    'code' => 'customer_code',
    'name' => 'customer_name',
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

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customersProvider);
    final l10n = AppLocalizations.of(context)!;
    final page = customers.valueOrNull;

    // Keep the grid in sync with provider transitions (loading → data).
    watchGridProvider(customersProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _searchController,
                    builder: (context, value, _) => TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        hintText: l10n.commonSearch,
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: value.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  // Cancel any pending debounce so a stale
                                  // timer can't resurrect the old term.
                                  _debounce?.cancel();
                                  _searchController.clear();
                                  ref
                                          .read(
                                            customersSearchProvider.notifier,
                                          )
                                          .state =
                                      '';
                                  if (ref.read(customersPageProvider) != 1) {
                                    ref
                                            .read(
                                              customersPageProvider.notifier,
                                            )
                                            .state =
                                        1;
                                  }
                                },
                              ),
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: () => showCustomerFormDialog(context),
                icon: const Icon(Icons.add, size: 18),
                label: Text(l10n.customersNewcustomer),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: l10n.commonRefresh,
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(customersProvider),
              ),
            ],
          ),
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

  /// Column set — order/format mirrors the web CustomersGrid (Code, Name,
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
      textColumn('code', l10n.customersCustomercode, 120),
      textColumn('name', l10n.customersCustomername, 220),
      textColumn('phone', l10n.customersPhone, 130),
      textColumn('email', l10n.customersEmail, 190),
      PlutoColumn(
        title: l10n.customersBalance,
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
