// Sales (invoices) list screen — PORTING.md §5/§6: read-only PlutoGrid
// over `GET /invoices` with a server-side status filter (CSV param) and
// client-side search + date range (the endpoint has no search/date
// params). Full dataset, client-side grid sort — the items-screen
// convention.
//
// Grid state: same pattern as ItemsScreen/ExpensesScreen — rows are fed
// through the PlutoGridStateManager (clear + append) on provider
// changes; the provider is the single source of truth. Double-tapping a
// row opens the edit form; New Invoice opens the create form.
//
// Summary strip: Total Sales / Total Paid / Total Due computed from the
// *filtered* rows, so it always matches the active filters.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/date_utils.dart' show isoDate;
import '../../core/utils/formatters.dart';
import '../../core/utils/invoice_status.dart';
import '../../data/models/invoice.dart' show Invoice;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/date_picker_helpers.dart' show DateRangeFilter;
import '../../widgets/pluto_grid_screen.dart' show serialGridColumn, withSerialCell;
import '../../widgets/screen_error_panel.dart';
import '../../widgets/screen_toolbar.dart';
import '../../widgets/status_badge.dart';
import 'invoice_providers.dart';

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_columnsReady) {
      _columns = _buildColumns(AppLocalizations.of(context)!);
      _columnsReady = true;
    }
  }

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
      ref.read(invoicesSearchProvider.notifier).state = value.trim();
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
  }

  /// Client-side filtering (search term + date range) over the loaded
  /// rows — the server only supports the status filter.
  List<Invoice> _filteredRows(AsyncValue<List<Invoice>> invoices) {
    final rows = invoices.valueOrNull ?? const <Invoice>[];
    final search = ref.read(invoicesSearchProvider).toLowerCase();
    final from = ref.read(invoicesFromDateProvider);
    final to = ref.read(invoicesToDateProvider);
    if (search.isEmpty && from == null && to == null) return rows;
    return rows.where((inv) {
      if (search.isNotEmpty &&
          !inv.invoiceNo.toLowerCase().contains(search) &&
          !(inv.customerName ?? '').toLowerCase().contains(search)) {
        return false;
      }
      final iso = inv.invoiceDate;
      if (from != null && iso.compareTo(isoDate(from)) < 0) return false;
      if (to != null && iso.compareTo(isoDate(to)) > 0) return false;
      return true;
    }).toList();
  }

  /// Pushes the provider state into the grid manager (clear + append,
  /// with the loading overlay toggled). No-op until `onLoaded`.
  void _applyInvoices(AsyncValue<List<Invoice>> value) {
    final manager = _stateManager;
    if (manager == null) return;

    final rows = _filteredRows(value);
    manager.removeAllRows();
    manager.appendRows([
      for (final (index, inv) in rows.indexed)
        withSerialCell(
          PlutoRow(
            cells: {
              'id': PlutoCell(value: inv.id),
              'invoice_no': PlutoCell(value: inv.invoiceNo),
              'invoice_date': PlutoCell(value: inv.invoiceDate),
              'customer_name': PlutoCell(value: inv.customerName ?? ''),
              'status': PlutoCell(value: inv.status),
              'total_amount': PlutoCell(value: inv.totalAmount),
              'paid_amount': PlutoCell(value: inv.paidAmount),
              'balance_amount': PlutoCell(value: inv.balanceAmount),
              'created_by': PlutoCell(value: inv.createdByUsername ?? ''),
            },
          ),
          index,
        ),
    ]);
    manager.setShowLoading(value.isLoading);
  }

  Future<void> _refresh() => ref.refresh(invoicesProvider.future);

  Widget _summaryStrip(
    AppLocalizations l10n,
    AsyncValue<List<Invoice>> invoices,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final rows = _filteredRows(invoices);
    final totalSales = rows.fold<num>(0, (sum, i) => sum + i.totalAmount);
    final totalPaid = rows.fold<num>(0, (sum, i) => sum + i.paidAmount);
    final totalDue = rows.fold<num>(0, (sum, i) => sum + i.balanceAmount);

    Widget stat(String label, num value, Color color) {
      return Expanded(
        child: Row(
          children: [
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                Formatters.currency(value),
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.receipt_long_outlined, size: 18, color: scheme.primary),
          const SizedBox(width: 14),
          stat(l10n.salesTotalsales, totalSales, scheme.primary),
          stat(l10n.salesTotalpaid, totalPaid, Colors.green.shade700),
          stat(l10n.salesTotaldue, totalDue, scheme.error),
        ],
      ),
    );
  }

  Widget _buildBody(AsyncValue<List<Invoice>> invoices) {
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
        },
        onRowDoubleTap: (event) {
          final id = event.row.cells['id']?.value as int?;
          if (id == null || id <= 0) return;
          // The grid row only exists when the provider has data, so the
          // lookup always succeeds (defensive no-op otherwise).
          final invoices =
              ref.read(invoicesProvider).valueOrNull ?? const <Invoice>[];
          final matches = invoices.where((i) => i.id == id);
          if (matches.isEmpty) return;
          context.push('/sales/form', extra: matches.first);
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

  /// Column set — dense data-screen conventions (PORTING.md §6), read-only
  /// with the id column hidden (it carries the row's invoice id to the
  /// double-tap handler).
  static List<PlutoColumn> _buildColumns(AppLocalizations l10n) {
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
      textColumn('invoice_no', l10n.salesInvoiceno, 150),
      PlutoColumn(
        title: l10n.fieldsDate,
        field: 'invoice_date',
        type: PlutoColumnType.text(),
        width: 110,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) => Align(
          alignment: Alignment.centerLeft,
          child: Text(Formatters.date(ctx.cell.value as String? ?? '')),
        ),
      ),
      textColumn('customer_name', l10n.fieldsCustomer, 200),
      PlutoColumn(
        title: l10n.fieldsStatus,
        field: 'status',
        type: PlutoColumnType.text(),
        width: 120,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) => Builder(
          builder: (cellContext) {
            final status = ctx.cell.value as String? ?? '';
            final l10n = AppLocalizations.of(cellContext)!;
            return Align(
              alignment: Alignment.centerLeft,
              child: StatusBadge(
                status: invoiceStatusLabel(l10n, status),
                color: invoiceStatusColor(status),
              ),
            );
          },
        ),
      ),
      PlutoColumn(
        title: l10n.salesTotalsales,
        field: 'total_amount',
        type: PlutoColumnType.number(format: '#,###.##'),
        width: 120,
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
        title: l10n.salesTotalpaid,
        field: 'paid_amount',
        type: PlutoColumnType.number(format: '#,###.##'),
        width: 120,
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
        title: l10n.salesTotaldue,
        field: 'balance_amount',
        type: PlutoColumnType.number(format: '#,###.##'),
        width: 120,
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
      textColumn('created_by', l10n.expensesCreatedby, 130),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final invoices = ref.watch(invoicesProvider);
    // Client-side filters drive the date-button labels and the summary
    // strip, so they must be watched here for the build to re-run.
    ref.watch(invoicesSearchProvider);
    ref.watch(invoicesFromDateProvider);
    ref.watch(invoicesToDateProvider);
    // Keep the grid in sync with provider changes after first load
    // (loading flags, status-filter refetches) — same as ExpensesScreen.
    ref.listen(invoicesProvider, (previous, next) => _applyInvoices(next));
    // Client-side filters (search term + date range) re-run the filter
    // over the loaded rows without refetching.
    ref.listen(invoicesSearchProvider, (previous, next) {
      _applyInvoices(ref.read(invoicesProvider));
    });
    ref.listen(invoicesFromDateProvider, (previous, next) {
      _applyInvoices(ref.read(invoicesProvider));
    });
    ref.listen(invoicesToDateProvider, (previous, next) {
      _applyInvoices(ref.read(invoicesProvider));
    });

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
              onChanged: (v) =>
                  ref.read(invoicesStatusProvider.notifier).state = v,
            ),
            DateRangeFilter(
              width: 120,
              fromProvider: invoicesFromDateProvider,
              toProvider: invoicesToDateProvider,
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
                  invoices.isLoading || _filteredRows(invoices).isEmpty
                  ? null
                  : () => saveCsv(
                      context,
                      suggestedName: csvSuggestedName('invoices'),
                      csv: buildInvoicesCsv(l10n, _filteredRows(invoices)),
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
          child: _summaryStrip(l10n, invoices),
        ),
        Expanded(child: _buildBody(invoices)),
      ],
    );
  }
}

/// Full-pane error state with a retry — same pattern as the items screen.
