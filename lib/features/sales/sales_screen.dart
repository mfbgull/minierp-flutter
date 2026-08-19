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
import '../../core/utils/formatters.dart';
import '../../core/utils/invoice_status.dart';
import '../../core/utils/print_utils.dart' show printPdfBytes;
import '../../data/models/invoice.dart' show Invoice, InvoicePaymentRecord;
import '../../data/repositories/api_result.dart' show ApiError, ApiFailure, ApiSuccess;
import '../../data/repositories/invoice_repository.dart'
    show invoiceRepositoryProvider;
import '../../data/repositories/paged_request.dart' show PagedResponse;
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/date_range_picker.dart' show DateRangeFilter;
import '../../widgets/pagination_bar.dart' show ServerPaginationBar;
import '../../widgets/pluto_grid_screen.dart'
    show plutoGridConfigurationFor, serialGridColumn, withSerialCell;
import '../../widgets/screen_error_panel.dart';
import '../../widgets/screen_toolbar.dart';
import '../../widgets/status_badge.dart';
import 'calculations/invoice_rules.dart'
    show canReturnInvoice, canShowDeleteAction;
import 'invoice_pdf.dart' show buildA4InvoicePdf;
import 'invoice_payment_dialog.dart' show showInvoicePaymentDialog;
import 'invoice_providers.dart';
import 'invoice_return_dialog.dart' show showInvoiceReturnDialog;
import 'package:minierp_app/core/theme/app_border_radius.dart';

/// Invoice-status options for the filter dropdown (display → server
/// value; `All` = null = param omitted).
const List<(String, String?)> _statusOptions = [
  ('All', null),
  ('Paid', 'Paid'),
  ('Unpaid', 'Unpaid'),
  ('Partially Paid', 'Partially Paid'),
  ('Overdue', 'Overdue'),
];

/// The per-row ⋮ menu actions for an invoice row.
enum _InvoiceRowAction { view, edit, payment, returnItem, print, delete }

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
  }

  Future<void> _refresh() => ref.refresh(invoicesProvider.future);

  /// Opens the row-actions menu anchored at [cellContext] (the ⋮ cell),
  /// mirroring the customers grid: a raw Listener receives the tap even
  /// though PlutoGrid's gesture handler competes in the arena.
  Future<void> _openRowMenu(
    BuildContext cellContext,
    Invoice? invoice,
  ) async {
    if (invoice == null || !mounted) return;
    final box = cellContext.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final overlay = Overlay.of(cellContext, rootOverlay: true);
    final l10n = AppLocalizations.of(cellContext)!;

    // Payment is offered while anything is still owed (Unpaid /
    // Partially Paid / Overdue / Sent / Draft with a balance); Return
    // follows the shared rule (hidden for Draft / Cancelled / fully
    // Returned); Delete follows the shared rule (Draft/Unpaid with no
    // money moved).
    final canPay = invoice.balanceAmount > 0 &&
        invoice.status != 'Cancelled' &&
        invoice.status != 'Returned';
    final canReturn = canReturnInvoice(invoice);
    final canDelete = canShowDeleteAction(invoice);

    final action = await showMenu<_InvoiceRowAction>(
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
          value: _InvoiceRowAction.view,
          child: Row(
            children: [
              const Icon(Icons.visibility_outlined, size: 18),
              const SizedBox(width: 8),
              Text(l10n.commonView),
            ],
          ),
        ),
        PopupMenuItem(
          value: _InvoiceRowAction.edit,
          child: Row(
            children: [
              const Icon(Icons.edit_outlined, size: 18),
              const SizedBox(width: 8),
              Text(l10n.commonEdit),
            ],
          ),
        ),
        if (canPay)
          PopupMenuItem(
            value: _InvoiceRowAction.payment,
            child: Row(
              children: [
                const Icon(Icons.payments_outlined, size: 18),
                const SizedBox(width: 8),
                Text(l10n.paymentsRecordpayment),
              ],
            ),
          ),
        if (canReturn)
          PopupMenuItem(
            value: _InvoiceRowAction.returnItem,
            child: Row(
              children: [
                const Icon(Icons.assignment_return_outlined, size: 18),
                const SizedBox(width: 8),
                // Flexible so the label shrinks instead of overflowing
                // the popup (same as the shared grid row-action menu).
                Flexible(child: Text(l10n.salesreturnsProcessreturn)),
              ],
            ),
          ),
        PopupMenuItem(
          value: _InvoiceRowAction.print,
          child: Row(
            children: [
              const Icon(Icons.print_outlined, size: 18),
              const SizedBox(width: 8),
              Text(l10n.salesPrinta4),
            ],
          ),
        ),
        if (canDelete)
          PopupMenuItem(
            value: _InvoiceRowAction.delete,
            child: Row(
              children: [
                Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: Theme.of(cellContext).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.customersDeleteinvoice,
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
      switch (action) {
        case _InvoiceRowAction.view:
          // The read-only document view (same as the customer tab).
          context.push('/sales/print-preview', extra: invoice);
        case _InvoiceRowAction.edit:
          context.push('/sales/form', extra: invoice);
        case _InvoiceRowAction.payment:
          await showInvoicePaymentDialog(context, invoice: invoice);
        case _InvoiceRowAction.returnItem:
          // The return dialog fetches the fresh invoice detail itself
          // (so returned_qty is current) — same entry the print-preview
          // page's Process Return button uses.
          await showInvoiceReturnDialog(context, invoiceId: invoice.id);
        case _InvoiceRowAction.print:
          _printInvoice(invoice);
        case _InvoiceRowAction.delete:
          await _deleteInvoice(invoice);
      }
    }
  }

  /// A4 print from the row menu — reuses the same PDF pipeline as the
  /// print-preview page (fresh detail + payments → A4 bytes → native
  /// print), without leaving the list.
  Future<void> _printInvoice(Invoice invoice) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final repo = ref.read(invoiceRepositoryProvider);
      final detailResult = await repo.invoice(invoice.id);
      final detail = switch (detailResult) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
      final paymentsResult = await repo.invoicePayments(invoice.id);
      final payments = switch (paymentsResult) {
        ApiSuccess(:final data) => data,
        ApiFailure() => const <InvoicePaymentRecord>[],
      };
      final bytes = await buildA4InvoicePdf(
        invoice: detail,
        payments: payments,
      );
      if (!mounted) return;
      await printPdfBytes(bytes, '${invoice.invoiceNo}.pdf', context);
    } catch (error) {
      if (mounted) {
        showAppToast(context, '${l10n.errorsFailed}: $error', isError: true);
      }
    }
  }

  /// Delete with confirm — mirrors the customer tab (guarded by
  /// `canShowDeleteAction` above).
  Future<void> _deleteInvoice(Invoice invoice) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.customersDeleteinvoice,
      message: '${l10n.customersConfirmdeleteinvoice} "${invoice.invoiceNo}"?',
      confirmLabel: l10n.customersDeleteinvoice,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    final result = await ref.read(invoiceRepositoryProvider).delete(invoice.id);
    if (!mounted) return;
    switch (result) {
      case ApiSuccess():
        showAppToast(context, l10n.customersInvoicedeleted);
        ref.invalidate(invoicesProvider);
      case ApiFailure(:final error):
        showAppToast(context, error.message, isError: true);
    }
  }

  Widget _summaryStrip(AppLocalizations l10n, List<Invoice> rows) {
    final scheme = Theme.of(context).colorScheme;
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
        borderRadius: AppBorderRadius.smRadius,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.receipt_long_outlined, size: 18, color: scheme.primary),
          const SizedBox(width: 14),
          stat(l10n.salesTotalsales, totalSales, scheme.primary),
          stat(l10n.salesTotalpaid, totalPaid, scheme.primary),
          stat(l10n.salesTotaldue, totalDue, scheme.error),
        ],
      ),
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
        configuration: plutoGridConfigurationFor(context),
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
        onSorted: _onGridSorted,
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

  /// Column set — dense data-screen conventions (PORTING.md §6), read-only
  /// with the id column hidden (it carries the row's invoice id to the
  /// double-tap handler). Instance (not static) because the actions
  /// column's renderer opens the per-row menu on `this` State.
  List<PlutoColumn> _buildColumns(AppLocalizations l10n) {
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
                color: invoiceStatusColor(Theme.of(cellContext).colorScheme, status),
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
      // Per-row actions menu — the ⋮ dropdown (View / Edit / Payment /
      // Print / Delete), same Listener + showMenu pattern as the
      // customers grid. The full Invoice rides in the hidden `data`
      // cell so the menu can guard on status + amounts.
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
          final invoice = ctx.cell.row.cells['data']?.value as Invoice?;
          return Builder(
            builder: (cellContext) => Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) =>
                  _openRowMenu(cellContext, invoice),
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
          child: _summaryStrip(l10n, filtered.valueOrNull ?? const []),
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
