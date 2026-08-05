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
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/invoice.dart' show Invoice;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/screen_error_panel.dart';
import '../../widgets/status_badge.dart';
import 'invoice_providers.dart';
import 'sales_form_dialog.dart';

/// Localized label for an invoice status value, falling back to the raw
/// server value when there's no key (defensive — the server owns the
/// status vocabulary).
String _statusLabel(AppLocalizations l10n, String status) => switch (status) {
      'Draft' => l10n.statusDraft,
      'Sent' => l10n.statusSent,
      'Paid' => l10n.statusPaid,
      'Unpaid' => l10n.statusUnpaid,
      'Overdue' => l10n.statusOverdue,
      'Cancelled' => l10n.statusCancelled,
      'Partially Paid' => l10n.statusPartiallypaid,
      'Returned' => l10n.statusReturned,
      'Partially Returned' => l10n.statusPartiallyreturned,
      _ => status,
    };

/// Status chip color (light) — port of the statusColors conventions in
/// PORTING.md §6.
Color _statusColor(String status) => switch (status) {
      'Draft' => Colors.blueGrey,
      'Sent' => Colors.lightBlue,
      'Unpaid' => Colors.orange,
      'Partially Paid' => Colors.amber,
      'Paid' => Colors.green,
      'Overdue' => Colors.red,
      'Cancelled' => Colors.grey,
      'Returned' => Colors.purple,
      'Partially Returned' => Colors.deepPurple,
      _ => Colors.blueGrey,
    };

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
      if (from != null && iso.compareTo(_isoDate(from)) < 0) return false;
      if (to != null && iso.compareTo(_isoDate(to)) > 0) return false;
      return true;
    }).toList();
  }

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate({required bool isFrom}) async {
    final current = isFrom
        ? ref.read(invoicesFromDateProvider)
        : ref.read(invoicesToDateProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    ref
        .read((isFrom ? invoicesFromDateProvider : invoicesToDateProvider)
            .notifier)
        .state = picked;
  }

  /// Pushes the provider state into the grid manager (clear + append,
  /// with the loading overlay toggled). No-op until `onLoaded`.
  void _applyInvoices(AsyncValue<List<Invoice>> value) {
    final manager = _stateManager;
    if (manager == null) return;

    final rows = _filteredRows(value);
    manager.removeAllRows();
    manager.appendRows([
      for (final inv in rows)
        PlutoRow(cells: {
          'id': PlutoCell(value: inv.id),
          'invoice_no': PlutoCell(value: inv.invoiceNo),
          'invoice_date': PlutoCell(value: inv.invoiceDate),
          'customer_name': PlutoCell(value: inv.customerName ?? ''),
          'status': PlutoCell(value: inv.status),
          'total_amount': PlutoCell(value: inv.totalAmount),
          'paid_amount': PlutoCell(value: inv.paidAmount),
          'balance_amount': PlutoCell(value: inv.balanceAmount),
          'created_by': PlutoCell(value: inv.createdByUsername ?? ''),
        }),
    ]);
    manager.setShowLoading(value.isLoading);
  }

  Future<void> _refresh() => ref.refresh(invoicesProvider.future);

  Widget _statusDropdown(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final current = ref.watch(invoicesStatusProvider);
    return Container(
      width: 170,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: DropdownButtonFormField<String?>(
        initialValue: current,
        isExpanded: true,
        decoration: const InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 10),
        ),
        items: [
          for (final (label, value) in _statusOptions)
            DropdownMenuItem<String?>(value: value, child: Text(label)),
        ],
        onChanged: (value) {
          ref.read(invoicesStatusProvider.notifier).state = value;
        },
      ),
    );
  }

  Widget _dateButton({required String label, required VoidCallback onTap}) {
    return SizedBox(
      width: 120,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.calendar_today_outlined, size: 15),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          textStyle: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }

  Widget _summaryStrip(AppLocalizations l10n, AsyncValue<List<Invoice>> invoices) {
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
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: scheme.onSurfaceVariant),
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
          showSalesFormDialog(context, invoice: matches.first);
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
                status: _statusLabel(l10n, status),
                color: _statusColor(status),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    hintText: l10n.salesSearchplaceholder,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    suffixIcon: _hasActiveFilters
                        ? IconButton(
                            icon: const Icon(Icons.filter_alt_off, size: 18),
                            tooltip: l10n.commonClear,
                            onPressed: _clearFilters,
                          )
                        : null,
                  ),
                  onChanged: _onSearchChanged,
                ),
              ),
              _statusDropdown(l10n),
              _dateButton(
                label: ref.watch(invoicesFromDateProvider) == null
                    ? l10n.commonFrom
                    : Formatters.date(_isoDate(ref.watch(invoicesFromDateProvider)!)),
                onTap: () => _pickDate(isFrom: true),
              ),
              _dateButton(
                label: ref.watch(invoicesToDateProvider) == null
                    ? l10n.commonTo
                    : Formatters.date(_isoDate(ref.watch(invoicesToDateProvider)!)),
                onTap: () => _pickDate(isFrom: false),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: l10n.commonRefresh,
                onPressed: _refresh,
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () =>
                    showSalesFormDialog(context, invoice: null),
                icon: const Icon(Icons.add, size: 18),
                label: Text(l10n.salesNewinvoice),
              ),
            ],
          ),
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
