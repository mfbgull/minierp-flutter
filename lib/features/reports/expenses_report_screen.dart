// Expenses report — GET /reports/expenses (PORTING.md §11).
// Port of the web `ExpensesReport.tsx`: a read-only grid of expenses
// with a KPI strip (total / records / average), category breakdown
// chips and From/To date + category filters. The web page's vendor
// filter is a no-op server-side (`getExpenseReport` takes only
// from/to/category), so it is omitted — same call as the other report
// ports. The web's detail sheet is mobile-only, so the desktop grid
// shows the full row with no double-tap dialog.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/expense_status.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/report.dart'
    show
        ExpensesReport,
        ExpensesReportRow,
        ExpensesReportSummary,
        ExpenseCategoryBreakdown;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/date_picker_helpers.dart' show DateRangeFilter;
import '../../widgets/pluto_grid_screen.dart' show serialGridColumn;
import '../../widgets/screen_error_panel.dart';
import '../../widgets/screen_toolbar.dart' show ScreenToolbar;
import '../../widgets/searchable_select.dart';
import '../../widgets/status_badge.dart';
import '../expenses/expense_providers.dart' show expenseCategoriesProvider;
import 'report_providers.dart';

class ExpensesReportScreen extends ConsumerStatefulWidget {
  const ExpensesReportScreen({super.key});

  @override
  ConsumerState<ExpensesReportScreen> createState() =>
      _ExpensesReportScreenState();
}

class _ExpensesReportScreenState extends ConsumerState<ExpensesReportScreen> {
  /// Grid manager — rows are fed through the manager (clear + append) on
  /// provider changes, the same pattern as the other report screens
  /// (PlutoGrid only reads its `rows` prop in initState). The `rows:`
  /// list must stay **mutable** — PlutoGrid wraps the passed list and
  /// `appendRows` mutates it.
  PlutoGridStateManager? _manager;

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

  /// Pushes the provider state into the grid manager (clear + append,
  /// with the loading overlay toggled). No-op until `onLoaded`.
  void _applyReport(AsyncValue<ExpensesReport> value) {
    final manager = _manager;
    if (manager == null) return;
    manager.setShowLoading(value.isLoading);
    if (value.hasValue) {
      final loaded = value.value?.rows ?? const <ExpensesReportRow>[];
      manager.removeAllRows();
      manager.appendRows([for (final row in loaded) _rowFor(row)]);
    }
  }

  PlutoRow _rowFor(ExpensesReportRow row) {
    return PlutoRow(
      cells: {
        'serial': PlutoCell(value: 0),
        'expenseNo': PlutoCell(value: row.expenseNo),
        'category': PlutoCell(value: row.expenseCategory),
        'description': PlutoCell(value: row.description),
        'amount': PlutoCell(value: row.amount),
        'expenseDate': PlutoCell(value: row.expenseDate),
        'paymentMethod': PlutoCell(value: row.paymentMethod),
        'referenceNo': PlutoCell(value: row.referenceNo),
        'vendor': PlutoCell(value: row.vendorName),
        'project': PlutoCell(value: row.project),
        'status': PlutoCell(value: row.status),
      },
    );
  }

  static PlutoColumn _moneyColumn(String field, String title, double width) =>
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
          child: Text(Formatters.currency(ctx.cell.value as num? ?? 0)),
        ),
      );

  static List<PlutoColumn> _buildColumns(AppLocalizations l10n) => [
    serialGridColumn(),
    PlutoColumn(
      title: l10n.expensesExpenseno,
      field: 'expenseNo',
      type: PlutoColumnType.text(),
      width: 130,
      readOnly: true,
      enableContextMenu: false,
      renderer: (ctx) => Align(
        alignment: Alignment.centerLeft,
        child: Text(
          ctx.cell.value as String? ?? '',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    ),
    PlutoColumn(
      title: l10n.fieldsCategory,
      field: 'category',
      type: PlutoColumnType.text(),
      width: 130,
      readOnly: true,
      enableContextMenu: false,
    ),
    PlutoColumn(
      title: l10n.expensesDescription,
      field: 'description',
      type: PlutoColumnType.text(),
      width: 240,
      readOnly: true,
      enableContextMenu: false,
    ),
    _moneyColumn('amount', l10n.fieldsAmount, 120),
    PlutoColumn(
      title: l10n.fieldsDate,
      field: 'expenseDate',
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
      title: l10n.expensesPaymentmethod,
      field: 'paymentMethod',
      type: PlutoColumnType.text(),
      width: 140,
      readOnly: true,
      enableContextMenu: false,
    ),
    PlutoColumn(
      title: l10n.expensesReferenceno,
      field: 'referenceNo',
      type: PlutoColumnType.text(),
      width: 130,
      readOnly: true,
      enableContextMenu: false,
    ),
    PlutoColumn(
      title: l10n.expensesVendor,
      field: 'vendor',
      type: PlutoColumnType.text(),
      width: 180,
      readOnly: true,
      enableContextMenu: false,
    ),
    PlutoColumn(
      title: l10n.expensesProject,
      field: 'project',
      type: PlutoColumnType.text(),
      width: 150,
      readOnly: true,
      enableContextMenu: false,
    ),
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
            child: StatusBadge(status: expenseStatusLabel(l10n, status)),
          );
        },
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(expensesReportProvider);
    final l10n = AppLocalizations.of(context)!;

    ref.listen(expensesReportProvider, (previous, next) => _applyReport(next));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(l10n, report),
        Expanded(child: _body(report)),
      ],
    );
  }

  Widget _header(AppLocalizations l10n, AsyncValue<ExpensesReport> report) {
    final loaded = report.valueOrNull;
    final summary = loaded?.summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            l10n.reportsExpensesreport,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        ScreenToolbar(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          filters: [
            _categoryDropdown(l10n),
            DateRangeFilter(
              fromProvider: reportExpensesFromDateProvider,
              toProvider: reportExpensesToDateProvider,
            ),
          ],
          onRefresh: () => ref.invalidate(expensesReportProvider),
          actions: [
            TextButton.icon(
              onPressed: report.isLoading || (loaded?.rows.isEmpty ?? true)
                  ? null
                  : () => saveCsv(
                      context,
                      suggestedName: csvSuggestedName('expenses-report'),
                      csv: buildExpensesReportCsv(l10n, loaded!),
                      successMessage: l10n.reportsExported,
                      errorMessage: l10n.reportsExportfailed,
                    ),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: Text(l10n.reportsExportcsv),
            ),
          ],
        ),
        if (summary != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: _summaryStrip(l10n, summary),
          ),
          if ((loaded?.categoryBreakdown ?? const []).isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: _breakdown(l10n, loaded!.categoryBreakdown),
            ),
          ],
        ],
      ],
    );
  }

  /// Category dropdown — options from the expenses feature's provider
  /// (`GET /expenses/categories`), selection in
  /// [reportExpensesCategoryProvider] so any change refetches.
  Widget _categoryDropdown(AppLocalizations l10n) {
    return SizedBox(
      width: 160,
      height: 40,
      child: SearchableSelect<String?>(
        key: const ValueKey('expenses-report-category-filter'),
        items: [
          null,
          for (final category
              in ref.watch(expenseCategoriesProvider).valueOrNull ?? const [])
            category.categoryName,
        ],
        selected: ref.watch(reportExpensesCategoryProvider),
        hint: l10n.expensesAllcategories,
        labelBuilder: (v) => v ?? l10n.expensesAllcategories,
        isDense: true,
        onChanged: (v) =>
            ref.read(reportExpensesCategoryProvider.notifier).state = v,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  /// Total Expenses | Total Records | Average Expense — the server's own
  /// summary numbers, rendered verbatim.
  Widget _summaryStrip(AppLocalizations l10n, ExpensesReportSummary summary) {
    final scheme = Theme.of(context).colorScheme;
    Widget cell(String label, String value) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
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
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          cell(
            l10n.reportsTotalexpenses,
            Formatters.currency(summary.totalAmount),
          ),
          const SizedBox(width: 8),
          cell(
            l10n.reportsTotalrecords,
            Formatters.number(summary.totalExpenses),
          ),
          const SizedBox(width: 8),
          cell(
            l10n.reportsAverageexpense,
            Formatters.currency(summary.averageAmount),
          ),
        ],
      ),
    );
  }

  /// Category breakdown — a wrapping row of chips (name, total, count)
  /// under the summary strip.
  Widget _breakdown(
    AppLocalizations l10n,
    List<ExpenseCategoryBreakdown> breakdown,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final chips = breakdown
        .map(
          (b) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Text(
              '${b.category} — ${Formatters.currency(b.totalAmount)} (${Formatters.number(b.count)})',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.reportsExpensesbycategory,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: chips),
      ],
    );
  }

  Widget _body(AsyncValue<ExpensesReport> report) {
    final l10n = AppLocalizations.of(context)!;
    final errorMessage = switch (report) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };
    if (errorMessage != null) {
      return ScreenErrorPanel(
        message: errorMessage,
        onRetry: () => ref.invalidate(expensesReportProvider),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: PlutoGrid(
        columns: _columns,
        rows: <PlutoRow>[],
        onLoaded: (event) {
          _manager = event.stateManager;
          _applyReport(ref.read(expensesReportProvider));
        },
        noRowsWidget: Center(
          child: Text(
            l10n.commonNoresults,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ),
      ),
    );
  }
}
