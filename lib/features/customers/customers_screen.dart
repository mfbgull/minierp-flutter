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

import '../../core/utils/formatters.dart';
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
import '../../widgets/status_badge.dart';
import 'customer_form_dialog.dart';
import 'customer_providers.dart';

/// The grid's status filter. All omits the `status` param; Active /
/// Inactive map to the server's `?status=active|inactive` values (the web
/// CustomersPage tab bar).
enum _StatusFilter { all, active, inactive }

/// The per-row actions menu items (web ⋮ dropdown: View / Edit / Delete).
enum _RowAction { view, edit, delete }

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

  void _onRowAction(_RowAction action, Customer? customer) {
    if (customer == null || !mounted) return;
    switch (action) {
      case _RowAction.view:
        openRowDetail(customer.id);
      case _RowAction.edit:
        showCustomerFormDialog(context, customer: customer);
      case _RowAction.delete:
        _deleteCustomer(customer);
    }
  }

  Future<void> _deleteCustomer(Customer customer) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.customersDelete,
      message: '${l10n.customersConfirmdelete} "${customer.customerName}"?',
      confirmLabel: l10n.customersDelete,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    final result = await ref.read(customerRepositoryProvider).delete(
      customer.id,
    );
    if (!mounted) return;
    switch (result) {
      case ApiSuccess():
        showAppToast(context, l10n.customersCustomerdeleted);
        ref.invalidate(customersProvider);
      case ApiFailure(:final error):
        // Surfaces the server 400 ("Cannot delete customer with existing
        // transactions") verbatim.
        showAppToast(context, error.message, isError: true);
    }
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
  /// PlutoGrid renderers have no BuildContext, so cells needing theme
  /// colors wrap themselves in a [Builder] (same pattern as the payments
  /// screen's date cell).
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
      // Hidden cell carrying the full Customer for the actions menu —
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
      textColumn('code', l10n.customersCustomercode, 110),
      // Customer name + contact person sub-line.
      PlutoColumn(
        title: l10n.customersCustomername,
        field: 'name',
        type: PlutoColumnType.text(),
        width: 200,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) {
          final customer = ctx.cell.row.cells['data']?.value as Customer?;
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
                if (customer?.contactPerson?.isNotEmpty ?? false)
                  Text(
                    customer!.contactPerson!,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(
                        cellContext,
                      ).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      // Contact info: phone + email sub-line.
      PlutoColumn(
        title: l10n.customersContactinfo,
        field: 'phone',
        type: PlutoColumnType.text(),
        width: 180,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) {
          final email = ctx.cell.row.cells['email']?.value?.toString() ?? '';
          return Builder(
            builder: (cellContext) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${ctx.cell.value}', overflow: TextOverflow.ellipsis),
                if (email.isNotEmpty)
                  Text(
                    email,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(
                        cellContext,
                      ).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      // Billing address (multi-line, capped at 3 lines).
      PlutoColumn(
        title: l10n.customersAddress,
        field: 'address',
        type: PlutoColumnType.text(),
        width: 200,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) {
          final lines = '${ctx.cell.value}'
              .split('\n')
              .where((line) => line.isNotEmpty)
              .take(3)
              .toList();
          return Builder(
            builder: (cellContext) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in lines)
                  Text(
                    line,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(
                        cellContext,
                      ).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      // Credit limit — colored by utilization (web getCreditUtilizationClass).
      PlutoColumn(
        title: l10n.customersCreditlimit,
        field: 'creditLimit',
        type: PlutoColumnType.number(format: '#,###.00'),
        width: 120,
        readOnly: true,
        textAlign: PlutoColumnTextAlign.end,
        titleTextAlign: PlutoColumnTextAlign.end,
        enableContextMenu: false,
        renderer: (ctx) {
          final customer = ctx.cell.row.cells['data']?.value as Customer?;
          final limit = (ctx.cell.value as num?) ?? 0;
          final utilization = customer?.creditUtilizationPercent ??
              ((customer?.currentBalance ?? 0) / (limit == 0 ? 1 : limit)) *
                  100;
          return Builder(
            builder: (cellContext) {
              final color = _utilizationColor(
                cellContext,
                utilization,
                limit,
              );
              return Align(
                alignment: Alignment.centerRight,
                child: Text(
                  Formatters.currency(limit),
                  style: color == null ? null : TextStyle(color: color),
                ),
              );
            },
          );
        },
      ),
      // Current balance — due (amber) when positive, clear (green) when
      // zero/negative (web getBalanceCellClass).
      PlutoColumn(
        title: l10n.customersCurrentbalance,
        field: 'balance',
        type: PlutoColumnType.number(format: '#,###.00'),
        width: 140,
        readOnly: true,
        textAlign: PlutoColumnTextAlign.end,
        titleTextAlign: PlutoColumnTextAlign.end,
        enableContextMenu: false,
        renderer: (ctx) {
          final balance = (ctx.cell.value as num?) ?? 0;
          return Builder(
            builder: (cellContext) => Align(
              alignment: Alignment.centerRight,
              child: Text(
                Formatters.currency(balance),
                style: TextStyle(
                  color: _balanceColor(cellContext, balance),
                ),
              ),
            ),
          );
        },
      ),
      // Credit utilization % — N/A when no credit limit; colored ≥90% red,
      // ≥75% amber, else low (web credit-utilization classes).
      PlutoColumn(
        title: l10n.customersCreditutilization,
        field: 'utilization',
        type: PlutoColumnType.number(format: '#,###.00'),
        width: 140,
        readOnly: true,
        textAlign: PlutoColumnTextAlign.end,
        titleTextAlign: PlutoColumnTextAlign.end,
        enableContextMenu: false,
        renderer: (ctx) {
          final customer = ctx.cell.row.cells['data']?.value as Customer?;
          final limit = customer?.creditLimit ?? 0;
          final utilization = (ctx.cell.value as num?) ?? 0;
          return Builder(
            builder: (cellContext) {
              if (limit <= 0) {
                return Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    l10n.customersNotapplicable,
                    style: TextStyle(
                      color: Theme.of(
                        cellContext,
                      ).colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              final color = _utilizationColor(
                cellContext,
                utilization,
                limit,
              );
              return Align(
                alignment: Alignment.centerRight,
                child: Text(
                  // Two decimals like the web (`(value || 0).toFixed(2)`).
                  '${utilization.toStringAsFixed(2)}%',
                  style: color == null ? null : TextStyle(color: color),
                ),
              );
            },
          );
        },
      ),
      // Payment terms in days (e.g. "14 days").
      PlutoColumn(
        title: l10n.customersPaymenttermsdays,
        field: 'terms',
        type: PlutoColumnType.number(),
        width: 120,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) {
          final days = (ctx.cell.value as num?) ?? 0;
          return Text(l10n.customersDays(days));
        },
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
      // Per-row actions menu — the web's ⋮ dropdown (View/Edit/Delete).
      // A raw Listener opens the menu: PlutoGrid's cell gesture handler
      // competes in the gesture arena and swallows an IconButton/InkWell
      // tap, but a Listener receives pointer events regardless of the
      // arena, so the menu opens reliably (and in widget tests).
      PlutoColumn(
        title: l10n.customersActions,
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
          final customer = ctx.cell.row.cells['data']?.value as Customer?;
          return Builder(
            builder: (cellContext) => Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => _openRowMenu(cellContext, customer),
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
    Customer? customer,
  ) async {
    if (customer == null || !mounted) return;
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
                l10n.customersDelete,
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
      _onRowAction(action, customer);
    }
  }

  /// Credit-utilization cell color — web `cell-credit-high` (red ≥90%) /
  /// `cell-credit-warn` (amber ≥75%); null = neutral (no credit limit or
  /// low utilization).
  Color? _utilizationColor(
    BuildContext context,
    num utilization,
    num creditLimit,
  ) {
    if (creditLimit <= 0) return null;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (utilization >= 90) {
      return isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
    }
    if (utilization >= 75) {
      return isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
    }
    return null;
  }

  /// Balance cell color — web `cell-balance-due` (amber, balance > 0) /
  /// `cell-balance-clear` (green, ≤ 0).
  Color _balanceColor(BuildContext context, num balance) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (balance > 0) {
      return isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
    }
    return isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D);
  }
}
