// Sales (invoices) list screen — PORTING.md §5/§6: read-only PlutoGrid
// over `GET /invoices` with server-side status/search/date filters and
// server-side paging + sort (grid-pagination §5 — the endpoint returns
// a `pagination` block). The grid renders one page; the summary strip
// and CSV export run over the full *filtered* list
// ([filteredInvoicesProvider]).
//
// Grid state: same pattern as ItemsScreen/ExpensesScreen — rows are fed
// through the PlutoGridStateManager (clear + append) on provider
// changes; the provider is the single source of truth. Double-tapping a
// row opens the A4 print preview; New Invoice opens the create form.
//
// Summary strip: Total Sales / Total Paid / Total Due computed from the
// *filtered* rows, so it always matches the active filters.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart';
import '../../data/models/invoice.dart' show Invoice;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../data/repositories/invoice_repository.dart'
    show invoiceRepositoryProvider;
import '../../data/repositories/paged_request.dart' show PagedResponse;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/date_range_picker.dart' show DateRangeFilter;
import '../../widgets/pagination_bar.dart' show ServerPaginationBar;
import '../../widgets/grid_column_widths.dart';
import '../../widgets/pluto_grid_screen.dart'
    show
        GridBulkSelection,
        autoFitPlutoColumns,
        bulkSelectColumn,
        plutoGridConfigurationFor,
        withSerialCell;
import '../../widgets/screen_error_panel.dart';
import '../../widgets/screen_toolbar.dart';
import 'invoice_providers.dart';
import 'sales_grid_columns.dart' show buildSalesColumns;
import 'sales_row_actions.dart' show openSalesRowMenu;
import 'sales_summary_strip.dart';

/// Invoice-status options for the filter dropdown (display → server
/// value; `All` = null = param omitted).
const List<(String, String?)> _statusOptions = [
  ('All', null),
  ('Paid', 'Paid'),
  ('Unpaid', 'Unpaid'),
  ('Partially Paid', 'Partially Paid'),
  ('Overdue', 'Overdue'),
];

class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});

  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();
  PlutoGridStateManager? _stateManager;
  late List<PlutoColumn> _columns;
  bool _columnsReady = false;

  /// Bulk selection (SHORTCOMINGS-FIX 4.4): checkbox column + the bulk
  /// action bar's selected-ids notifier. Selection resets whenever the
  /// grid rows are replaced (page/filter/refresh — see [_applyInvoices]).
  late final GridBulkSelection _bulk = GridBulkSelection(
    manager: () => _stateManager,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_columnsReady) {
      // The bulk-selection checkbox column (with select-all header)
      // precedes the data columns.
      _columns = [
        bulkSelectColumn(_bulk),
        ...buildSalesColumns(
          l10n: AppLocalizations.of(context)!,
          onOpenRowMenu: (cellContext, invoice) {
            openSalesRowMenu(context: cellContext, ref: ref, invoice: invoice);
          },
        ),
      ];
      _columnsReady = true;
    }
  }

  GridColumnWidths? _widthTracker;

  @override
  void dispose() {
    _bulk.dispose();
    _widthTracker?.dispose();
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      ref.read(invoicesSearchProvider.notifier).state = value.trim();
      // A new search starts back at page 1.
      if (ref.read(invoicesPageProvider) != 1) {
        ref.read(invoicesPageProvider.notifier).state = 1;
      }
    });
  }

  bool get _hasActiveFilters =>
      ref.read(invoicesStatusProvider) != null ||
      ref.read(invoicesFromDateProvider) != null ||
      ref.read(invoicesToDateProvider) != null ||
      ref.read(invoicesSearchProvider).isNotEmpty;

  void _clearFilters() {
    _searchController.clear();
    ref.read(invoicesStatusProvider.notifier).state = null;
    ref.read(invoicesFromDateProvider.notifier).state = null;
    ref.read(invoicesToDateProvider.notifier).state = null;
    ref.read(invoicesSearchProvider.notifier).state = '';
    if (ref.read(invoicesPageProvider) != 1) {
      ref.read(invoicesPageProvider.notifier).state = 1;
    }
  }

  /// Pushes the provider state into the grid manager (clear + append,
  /// with the loading overlay toggled). No-op until `onLoaded`.
  void _applyInvoices(AsyncValue<PagedResponse<Invoice>> value) {
    final manager = _stateManager;
    if (manager == null) return;

    final rows = value.value?.items ?? const <Invoice>[];
    // The grid is showing a fresh page — a selection made against the
    // previous rows no longer maps to visible records.
    _bulk.clear();
    manager.removeAllRows();
    manager.appendRows([
      for (final (index, inv) in rows.indexed)
        withSerialCell(
          PlutoRow(
            cells: {
              // Hidden cell carrying the full Invoice for the actions
              // menu (the id cell alone isn't enough — the menu needs
              // status + amounts for the guards).
              'data': PlutoCell(value: inv),
              'id': PlutoCell(value: inv.id),
              'invoice_no': PlutoCell(value: inv.invoiceNo),
              'invoice_date': PlutoCell(value: inv.invoiceDate),
              'customer_name': PlutoCell(value: inv.customerName ?? ''),
              'status': PlutoCell(value: inv.status),
              'override_sale': PlutoCell(value: inv.overrideSale),
              'total_amount': PlutoCell(value: inv.totalAmount),
              'paid_amount': PlutoCell(value: inv.paidAmount),
              'balance_amount': PlutoCell(value: inv.balanceAmount),
              'created_by': PlutoCell(value: inv.createdByUsername ?? ''),
              'actions': PlutoCell(value: ''),
            },
          ),
          index,
        ),
    ]);
    manager.setShowLoading(value.isLoading);
    // Column widths re-fit to the fresh rows (post-frame: resizeColumn
    // notifies listeners and provider callbacks can fire during build).
    // The tracker guard keeps auto-fit from recording as user edits and
    // re-applies dragged widths afterwards.
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

  Future<void> _refresh() => ref.refresh(invoicesProvider.future);

  /// Bulk soft-delete of the selected invoices (SHORTCOMINGS-FIX 4.4).
  /// Each delete runs the server's own soft-delete flow (voids GL,
  /// reverses stock, stamps `deleted_at`) and rejects paid/returned/
  /// cancelled invoices with a clear message — so the confirm dialog
  /// warns that only draft/unpaid invoices can be deleted.
  Future<void> _bulkDelete(Set<int> ids) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.commonDelete,
      message: '${l10n.bulkDeleteSelected} (${ids.length})?',
      confirmLabel: l10n.commonDelete,
      cancelLabel: l10n.commonCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    final repo = ref.read(invoiceRepositoryProvider);
    var ok = 0;
    var failed = 0;
    for (final id in ids) {
      final result = await repo.delete(id);
      if (!mounted) return;
      result.fold(
        onSuccess: (_) => ok++,
        onFailure: (_) => failed++,
      );
    }
    if (!mounted) return;
    _bulk.clear();
    if (failed == 0) {
      // The 4.2 undo pattern — one 10s toast with a single Undo action
      // that restores every deleted invoice in place (server-side
      // `POST /invoices/:id/restore`).
      showAppToast(
        context,
        l10n.bulkDeleted(ok),
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: l10n.commonUndo,
          onPressed: () async {
            for (final id in ids) {
              final undo = await repo.restore(id);
              if (!mounted) return;
              undo.fold(
                onSuccess: (_) {},
                onFailure: (err) =>
                    showAppToast(context, err.message, isError: true),
              );
            }
            if (!mounted) return;
            ref.invalidate(invoicesProvider);
            ref.invalidate(filteredInvoicesProvider);
          },
        ),
      );
    } else {
      showAppToast(context, l10n.bulkDeleteFailed, isError: true);
    }
    ref.invalidate(invoicesProvider);
    ref.invalidate(filteredInvoicesProvider);
  }

  /// Bulk CSV export — the selected invoices' rows only (mirrors the
  /// toolbar export, which runs over the full filtered list).
  void _bulkExport(Set<int> ids) {
    final l10n = AppLocalizations.of(context)!;
    final filtered =
        ref.read(filteredInvoicesProvider).valueOrNull ?? const <Invoice>[];
    final selected = [
      for (final inv in filtered)
        if (ids.contains(inv.id)) inv,
    ];
    if (selected.isEmpty) return;
    saveCsv(
      context,
      suggestedName: csvSuggestedName('invoices'),
      csv: buildInvoicesCsv(l10n, selected),
      successMessage: l10n.salesExported,
      errorMessage: l10n.salesExportfailed,
    );
  }

  Widget _buildBody(AsyncValue<PagedResponse<Invoice>> invoices) {
    final errorMessage = switch (invoices) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };
    if (errorMessage != null) {
      _stateManager = null;
      return ScreenErrorPanel(
        message: errorMessage,
        onRetry: () => ref.invalidate(invoicesProvider),
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
        // Must be a modifiable list — FilteredList appends into it (a
        // const list throws "Cannot add to an unmodifiable list").
        rows: <PlutoRow>[],
        onLoaded: (event) {
          _stateManager = event.stateManager;
          _stateManager?.hideColumn(
            _columns.firstWhere((c) => c.field == 'id'),
            true,
            notify: false,
          );
          _applyInvoices(ref.read(invoicesProvider));
          _widthTracker?.dispose();
          _widthTracker = GridColumnWidths.attach(
            stateManager: event.stateManager,
            screenKey: 'sales',
          );
        },
        onSorted: _onGridSorted,
        onRowChecked: (_) => _bulk.syncFromManager(),
        onRowDoubleTap: (event) {
          final id = event.row.cells['id']?.value as int?;
          if (id == null || id <= 0) return;
          // The grid row only exists when the provider has data, so the
          // lookup always succeeds (defensive no-op otherwise).
          final invoices =
              ref.read(invoicesProvider).valueOrNull?.items ?? const <Invoice>[];
          final matches = invoices.where((i) => i.id == id);
          if (matches.isEmpty) return;
          // Double-tap → print preview (not the edit form); the preview
          // refetches the saved detail so it always matches the document.
          context.push('/sales/print-preview', extra: matches.first);
        },
        noRowsWidget: Center(
          child: Text(
            l10n.commonNoresults,
            style: TextStyle(color: scheme.outline),
          ),
        ),
      ),
    );
  }

  /// Grid field → server sort column (whitelist in sqlSanitizer.ts).
  String? _sortColumnFor(String field) => switch (field) {
    'invoice_no' => 'invoice_no',
    'invoice_date' => 'invoice_date',
    'customer_name' => 'customer_name',
    'status' => 'status',
    'total_amount' => 'total_amount',
    'paid_amount' => 'paid_amount',
    'balance_amount' => 'balance_amount',
    _ => null,
  };

  /// Column sort maps to the server-side sort provider (this endpoint is
  /// server-paginated, so ordering happens on the server).
  void _onGridSorted(PlutoGridOnSortedEvent event) {
    final sortBy = _sortColumnFor(event.column.field);
    if (sortBy == null) return;
    final sort = event.column.sort;
    ref.read(invoicesSortProvider.notifier).state = sort.isNone
        ? null
        : InvoiceSort(
            sortBy,
            sort == PlutoColumnSort.ascending ? 'ASC' : 'DESC',
          );
    if (ref.read(invoicesPageProvider) != 1) {
      ref.read(invoicesPageProvider.notifier).state = 1;
    }
  }
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final invoices = ref.watch(invoicesProvider);
    // The full filtered list feeds the summary strip + CSV export.
    final filtered = ref.watch(filteredInvoicesProvider);
    // Filters drive the date-button labels and the summary strip, so
    // they must be watched here for the build to re-run.
    ref.watch(invoicesSearchProvider);
    ref.watch(invoicesFromDateProvider);
    ref.watch(invoicesToDateProvider);
    ref.watch(invoicesStatusProvider);
    // Keep the grid in sync with provider changes after first load
    // (loading flags, page/filter refetches) — same as ExpensesScreen.
    ref.listen(invoicesProvider, (previous, next) => _applyInvoices(next));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Toolbar: search + status filter + date range + actions.
        ScreenToolbar(
          searchController: _searchController,
          searchHint: l10n.salesSearchplaceholder,
          onSearchChanged: _onSearchChanged,
          filters: [
            ScreenToolbarDropdown<String?>(
              items: [for (final (_, value) in _statusOptions) value],
              value: ref.watch(invoicesStatusProvider),
              hint: _statusOptions.first.$1,
              labelBuilder: (value) {
                for (final (label, option) in _statusOptions) {
                  if (option == value) return label;
                }
                return value ?? '';
              },
              width: 170,
              onChanged: (v) {
                ref.read(invoicesStatusProvider.notifier).state = v;
                // A new status filter starts back at page 1.
                if (ref.read(invoicesPageProvider) != 1) {
                  ref.read(invoicesPageProvider.notifier).state = 1;
                }
              },
            ),
            DateRangeFilter(
              width: 120,
              fromProvider: invoicesFromDateProvider,
              toProvider: invoicesToDateProvider,
              onChanged: () {
                // A new date range starts back at page 1.
                if (ref.read(invoicesPageProvider) != 1) {
                  ref.read(invoicesPageProvider.notifier).state = 1;
                }
              },
            ),
          ],
          onRefresh: _refresh,
          onClearAll: _clearFilters,
          hasActiveFilters: _hasActiveFilters,
          actions: [
            // CSV export — mirrors the orders grids: the pure builder
            // runs over the currently-filtered rows and the shared
            // save helper owns the FilePicker + toast. Disabled until
            // rows are loaded.
            TextButton.icon(
              onPressed:
                  invoices.isLoading || (filtered.valueOrNull ?? const []).isEmpty
                  ? null
                  : () => saveCsv(
                      context,
                      suggestedName: csvSuggestedName('invoices'),
                      csv: buildInvoicesCsv(
                        l10n,
                        filtered.valueOrNull ?? const [],
                      ),
                      successMessage: l10n.salesExported,
                      errorMessage: l10n.salesExportfailed,
                    ),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: Text(l10n.salesExportcsv),
            ),
          ],
          primaryActions: [
            FilledButton.icon(
              onPressed: () => context.push('/sales/form'),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.salesNewinvoice),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SalesSummaryStrip(rows: filtered.valueOrNull ?? const []),
        ),
        // Bulk action bar (checkbox rows selected) — export or delete the
        // selected invoices (SHORTCOMINGS-FIX 4.4).
        ValueListenableBuilder<Set<int>>(
          valueListenable: _bulk.selected,
          builder: (context, sel, _) {
            if (sel.isEmpty) return const SizedBox.shrink();
            return BulkActionBar(
              count: sel.length,
              onClearSelection: _bulk.clear,
              actions: [
                TextButton.icon(
                  onPressed: () => _bulkExport(sel),
                  icon: const Icon(Icons.file_download_outlined, size: 18),
                  label: Text(l10n.bulkExportSelected),
                ),
                TextButton.icon(
                  onPressed: () => _bulkDelete(sel),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  label: Text(l10n.bulkDeleteSelected),
                ),
              ],
            );
          },
        ),
        Expanded(child: _buildBody(invoices)),
        if (invoices.valueOrNull case final page?)
          ServerPaginationBar(
            page: page.currentPage,
            totalPages: page.totalPages,
            totalItems: page.totalItems,
            hasNext: page.hasNext,
            hasPrev: page.hasPrev,
            limit: ref.watch(invoicesLimitProvider),
            itemLabel: l10n.salesInvoices,
            onPageChanged: (p) =>
                ref.read(invoicesPageProvider.notifier).state = p,
            onLimitChanged: (limit) {
              ref.read(invoicesLimitProvider.notifier).state = limit;
              if (ref.read(invoicesPageProvider) != 1) {
                ref.read(invoicesPageProvider.notifier).state = 1;
              }
            },
          ),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// Full-pane error state with a retry — same pattern as the items screen.
