// Sales summary report — GET /reports/sales-summary (PORTING.md §11).
// Port of the web `SalesSummaryReport.tsx`: four stat cards over the
// period's summary + a read-only grid of the per-invoice detail rows.
// From/To date buttons refetch via the providers (server default: last
// month → today). The web page's customer/item multi-select filters are
// a follow-up (they need a multi-value select widget).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/invoice_status.dart';
import '../../data/models/report.dart' show SalesSummaryReport;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/date_picker_helpers.dart' show DateRangeFilter;
import '../../widgets/pluto_grid_screen.dart' show serialGridColumn;
import '../../widgets/screen_error_panel.dart';
import '../../widgets/screen_toolbar.dart' show ScreenToolbar;
import '../../widgets/status_badge.dart';
import 'report_providers.dart';

class SalesSummaryReportScreen extends ConsumerStatefulWidget {
  const SalesSummaryReportScreen({super.key});

  @override
  ConsumerState<SalesSummaryReportScreen> createState() =>
      _SalesSummaryReportScreenState();
}

class _SalesSummaryReportScreenState
    extends ConsumerState<SalesSummaryReportScreen> {
  /// Grid manager — rows are fed through the manager (clear + append)
  /// on provider changes, the same pattern as the expenses screen
  /// (PlutoGrid only reads its `rows` prop in initState).
  ///
  /// The grid's `rows:` list must stay **mutable** — PlutoGrid wraps the
  /// passed list and `appendRows` mutates it, so a `const` list throws
  /// "Cannot add to an unmodifiable list".
  PlutoGridStateManager? _manager;

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(salesSummaryProvider);
    final l10n = AppLocalizations.of(context)!;

    ref.listen(salesSummaryProvider, (previous, next) => _applyReport(next));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            l10n.reportsSalessummaryreport,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        ScreenToolbar(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          filters: [
            DateRangeFilter(
              fromProvider: reportSalesFromDateProvider,
              toProvider: reportSalesToDateProvider,
            ),
          ],
          onRefresh: () => ref.invalidate(salesSummaryProvider),
          actions: [
            TextButton.icon(
              onPressed:
                  report.isLoading ||
                      (report.valueOrNull?.sales.isEmpty ?? true)
                  ? null
                  : () => saveCsv(
                      context,
                      suggestedName: csvSuggestedName('sales-summary'),
                      csv: buildSalesSummaryCsv(l10n, report.valueOrNull!),
                      successMessage: l10n.reportsExported,
                      errorMessage: l10n.reportsExportfailed,
                    ),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: Text(l10n.reportsExportcsv),
            ),
          ],
        ),
        if (report.valueOrNull != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _statCards(context, l10n, report.valueOrNull!),
          ),
        ],
        const SizedBox(height: 12),
        Expanded(child: _body(context, ref, report)),
      ],
    );
  }

  Widget _statCards(
    BuildContext context,
    AppLocalizations l10n,
    SalesSummaryReport report,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final s = report.summary;
    Widget card(String label, String value, IconData icon) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: scheme.primary),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    return Row(
      children: [
        card(
          l10n.reportsTotalinvoices,
          Formatters.number(s.totalInvoices),
          Icons.description_outlined,
        ),
        const SizedBox(width: 8),
        card(
          l10n.reportsTotalsales,
          Formatters.currency(s.totalSales),
          Icons.trending_up,
        ),
        const SizedBox(width: 8),
        card(
          l10n.reportsItemssold,
          Formatters.number(s.totalItemsSold),
          Icons.inventory_2_outlined,
        ),
        const SizedBox(width: 8),
        card(
          l10n.reportsAvginvoicevalue,
          Formatters.currency(s.averageInvoiceValue),
          Icons.pie_chart_outline,
        ),
      ],
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<SalesSummaryReport> report,
  ) {
    final errorMessage = switch (report) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };
    if (errorMessage != null) {
      return ScreenErrorPanel(
        message: errorMessage,
        onRetry: () => ref.invalidate(salesSummaryProvider),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: _grid(context),
    );
  }

  /// Pushes the provider state into the grid manager (clear + append,
  /// with the loading overlay toggled). No-op until `onLoaded`.
  void _applyReport(AsyncValue<SalesSummaryReport> value) {
    final manager = _manager;
    if (manager == null) return;
    manager.setShowLoading(value.isLoading);
    if (value.hasValue) {
      final rows = value.value?.sales ?? const [];
      manager.removeAllRows();
      manager.appendRows([
        for (final row in rows)
          PlutoRow(
            cells: {
              'serial': PlutoCell(value: 0),
              'date': PlutoCell(value: row.invoiceDate),
              'invoiceNo': PlutoCell(value: row.invoiceNo),
              'customer': PlutoCell(value: row.customerName),
              'totalSales': PlutoCell(value: row.totalSales),
              'items': PlutoCell(value: row.totalItems),
              'paid': PlutoCell(value: row.paidAmount),
              'balance': PlutoCell(value: row.balanceAmount),
              'status': PlutoCell(value: row.status),
            },
          ),
      ]);
    }
  }

  Widget _grid(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return PlutoGrid(
      columns: [
        serialGridColumn(),
        PlutoColumn(
          title: l10n.fieldsDate,
          field: 'date',
          type: PlutoColumnType.text(),
          width: 110,
          readOnly: true,
          enableContextMenu: false,
          renderer: (ctx) => Align(
            alignment: Alignment.centerLeft,
            child: Text(Formatters.date(ctx.cell.value as String? ?? '')),
          ),
        ),
        PlutoColumn(
          title: l10n.salesInvoiceno,
          field: 'invoiceNo',
          type: PlutoColumnType.text(),
          width: 130,
          readOnly: true,
          enableContextMenu: false,
        ),
        PlutoColumn(
          title: l10n.fieldsCustomer,
          field: 'customer',
          type: PlutoColumnType.text(),
          width: 200,
          readOnly: true,
          enableContextMenu: false,
        ),
        _moneyColumn('totalSales', l10n.salesTotalsales, 130),
        PlutoColumn(
          title: l10n.reportsItems,
          field: 'items',
          type: PlutoColumnType.number(format: '#,###.##'),
          width: 80,
          readOnly: true,
          textAlign: PlutoColumnTextAlign.end,
          titleTextAlign: PlutoColumnTextAlign.end,
          enableContextMenu: false,
          renderer: (ctx) => Align(
            alignment: Alignment.centerRight,
            child: Text(Formatters.number(ctx.cell.value as num? ?? 0)),
          ),
        ),
        _moneyColumn('paid', l10n.salesTotalpaid, 130),
        _moneyColumn('balance', l10n.salesTotaldue, 130),
        PlutoColumn(
          title: l10n.fieldsStatus,
          field: 'status',
          type: PlutoColumnType.text(),
          width: 130,
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
      ],
      rows: <PlutoRow>[],
      onLoaded: (event) {
        _manager = event.stateManager;
        _applyReport(ref.read(salesSummaryProvider));
      },
      noRowsWidget: Center(
        child: Text(
          l10n.commonNoresults,
          style: TextStyle(color: scheme.outline),
        ),
      ),
    );
  }

  PlutoColumn _moneyColumn(String field, String title, double width) =>
      PlutoColumn(
        title: title,
        field: field,
        type: PlutoColumnType.number(format: '#,###.00'),
        width: width,
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
      );
}
