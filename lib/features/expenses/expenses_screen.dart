// Expenses list screen — PORTING.md §5/§6: read-only PlutoGrid over
// `GET /expenses` with server-side search + category/status/date filters
// (full dataset, client-side grid sort — the items-screen convention).
//
// Grid state: same pattern as ItemsScreen — rows are fed through the
// PlutoGridStateManager (clear + append) on provider changes; the
// provider is the single source of truth. Double-tapping a row opens the
// edit form; New Expense opens the create form.
//
// Summary strip: total amount + count computed from the *loaded* rows, so
// it always matches the active filters (the server's `/expenses/summary`
// endpoint only supports a date range, not the other filters).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/expense_status.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/expense.dart' show Expense;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../l10n/app_localizations.dart';
import '../../widgets/date_picker_helpers.dart' show DateRangeFilter;
import '../../widgets/screen_error_panel.dart';
import '../../widgets/status_badge.dart';
import 'expense_form_dialog.dart';
import 'expense_providers.dart';

class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
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
      ref.read(expensesSearchProvider.notifier).state = value.trim();
    });
  }

  bool get _hasActiveFilters =>
      ref.read(expensesCategoryProvider) != null ||
      ref.read(expensesStatusProvider) != null ||
      ref.read(expensesFromDateProvider) != null ||
      ref.read(expensesToDateProvider) != null;

  void _clearFilters() {
    ref.read(expensesCategoryProvider.notifier).state = null;
    ref.read(expensesStatusProvider.notifier).state = null;
    ref.read(expensesFromDateProvider.notifier).state = null;
    ref.read(expensesToDateProvider.notifier).state = null;
  }

  /// Pushes the provider state into the grid manager (clear + append,
  /// with the loading overlay toggled). No-op until `onLoaded`.
  void _applyExpenses(AsyncValue<List<Expense>> value) {
    final manager = _stateManager;
    if (manager == null) return;
    manager.setShowLoading(value.isLoading);
    if (value.hasValue) {
      manager.removeAllRows();
      manager.appendRows([
        for (final expense in value.value ?? const <Expense>[])
          _rowFor(expense),
      ]);
    }
  }

  static PlutoRow _rowFor(Expense expense) => PlutoRow(
    cells: {
      'id': PlutoCell(value: expense.id),
      'expense_no': PlutoCell(value: expense.expenseNo),
      'expense_date': PlutoCell(value: expense.expenseDate),
      'category': PlutoCell(value: expense.expenseCategory),
      'description': PlutoCell(value: expense.description ?? ''),
      'vendor': PlutoCell(value: expense.vendorName ?? ''),
      'reference_no': PlutoCell(value: expense.referenceNo ?? ''),
      'payment_method': PlutoCell(value: expense.paymentMethod ?? ''),
      'project': PlutoCell(value: expense.project ?? ''),
      'amount': PlutoCell(value: expense.amount),
      'status': PlutoCell(value: expense.status),
      'created_by': PlutoCell(value: expense.createdByName ?? ''),
    },
  );

  @override
  Widget build(BuildContext context) {
    final expenses = ref.watch(expensesProvider);
    final l10n = AppLocalizations.of(context)!;

    ref.listen(expensesProvider, (previous, next) => _applyExpenses(next));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _toolbar(l10n, expenses),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: _summaryStrip(l10n, expenses),
        ),
        Expanded(child: _buildBody(expenses)),
      ],
    );
  }

  Widget _toolbar(AppLocalizations l10n, AsyncValue<List<Expense>> expenses) {
    return Row(
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
                            _searchController.clear();
                            ref.read(expensesSearchProvider.notifier).state =
                                '';
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
        _filterDropdown<String?>(
          key: const ValueKey('expense-category-filter'),
          value: ref.watch(expensesCategoryProvider),
          items: [
            null,
            for (final category
                in ref.watch(expenseCategoriesProvider).valueOrNull ?? const [])
              category.categoryName,
          ],
          labelBuilder: (v) => v ?? l10n.expensesAllcategories,
          onChanged: (v) =>
              ref.read(expensesCategoryProvider.notifier).state = v,
          width: 170,
        ),
        const SizedBox(width: 8),
        _filterDropdown<String?>(
          key: const ValueKey('expense-status-filter'),
          value: ref.watch(expensesStatusProvider),
          items: [
            null,
            for (final option
                in ref.watch(expenseStatusOptionsProvider).valueOrNull ??
                    const [])
              option.value,
          ],
          labelBuilder: (v) => v == null
              ? l10n.expensesAllstatuses
              : expenseStatusLabel(l10n, v),
          onChanged: (v) => ref.read(expensesStatusProvider.notifier).state = v,
          width: 150,
        ),
        const SizedBox(width: 8),
        DateRangeFilter(
          height: 40,
          fromProvider: expensesFromDateProvider,
          toProvider: expensesToDateProvider,
          onClear: _clearFilters,
          showClear: () => _hasActiveFilters,
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: expenses.isLoading || _hasNoRows
              ? null
              : () => saveCsv(
                  context,
                  suggestedName: csvSuggestedName('expenses'),
                  csv: buildExpensesCsv(l10n, _filteredRows),
                  successMessage: l10n.expensesExported,
                  errorMessage: l10n.expensesExportfailed,
                ),
          icon: const Icon(Icons.file_download_outlined, size: 18),
          label: Text(l10n.expensesExportcsv),
        ),
        const SizedBox(width: 8),
        FilledButton.tonalIcon(
          onPressed: () => showExpenseFormDialog(context),
          icon: const Icon(Icons.add, size: 18),
          label: Text(l10n.expensesNewexpense),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: l10n.commonRefresh,
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(expensesProvider),
        ),
      ],
    );
  }

  /// Compact filter dropdown (All-category / All-status / form selects).
  Widget _filterDropdown<T>({
    required Key key,
    required T value,
    required List<T> items,
    required String Function(T) labelBuilder,
    required ValueChanged<T?> onChanged,
    required double width,
  }) {
    return SizedBox(
      width: width,
      height: 40,
      child: DropdownButtonFormField<T>(
        key: key,
        initialValue: value,
        isDense: true,
        // Without isExpanded the internal selected-value Row keeps its
        // intrinsic width and overflows the SizedBox on narrow toolbar
        // layouts (and in widget tests at 1600px).
        isExpanded: true,
        items: [
          for (final item in items)
            DropdownMenuItem(value: item, child: Text(labelBuilder(item))),
        ],
        onChanged: onChanged,
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

  /// Rows currently visible in the grid — the provider's loaded value
  /// (empty while loading or on error). The export mirrors exactly what
  /// the grid shows under the active filters.
  List<Expense> get _filteredRows =>
      ref.read(expensesProvider).valueOrNull ?? const <Expense>[];

  bool get _hasNoRows => _filteredRows.isEmpty;

  Widget _summaryStrip(
    AppLocalizations l10n,
    AsyncValue<List<Expense>> expenses,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final rows = expenses.valueOrNull ?? const <Expense>[];
    final total = rows.fold<num>(0, (sum, e) => sum + e.amount);
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
          const SizedBox(width: 8),
          Text(l10n.commonTotal, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(width: 6),
          Text(
            Formatters.currency(total),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Text(
            '${rows.length} ${l10n.expensesCount}',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(AsyncValue<List<Expense>> expenses) {
    final errorMessage = switch (expenses) {
      AsyncError(:final error) => error is ApiError ? error.message : null,
      _ => null,
    };
    if (errorMessage != null) {
      _stateManager = null;
      return ScreenErrorPanel(
        message: errorMessage,
        onRetry: () => ref.invalidate(expensesProvider),
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
        rows: <PlutoRow>[],
        onLoaded: (event) {
          _stateManager = event.stateManager;
          _stateManager?.hideColumn(
            _columns.firstWhere((c) => c.field == 'id'),
            true,
            notify: false,
          );
          _applyExpenses(ref.read(expensesProvider));
        },
        onRowDoubleTap: (event) {
          final id = event.row.cells['id']?.value as int?;
          if (id == null || id <= 0) return;
          // The grid row only exists when the provider has data, so the
          // lookup always succeeds (defensive no-op otherwise).
          final expenses =
              ref.read(expensesProvider).valueOrNull ?? const <Expense>[];
          final matches = expenses.where((e) => e.id == id);
          if (matches.isEmpty) return;
          showExpenseFormDialog(context, expense: matches.first);
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
  /// with the id column hidden (it carries the row's expense id to the
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
      textColumn('expense_no', l10n.expensesExpenseno, 140),
      PlutoColumn(
        title: l10n.fieldsDate,
        field: 'expense_date',
        type: PlutoColumnType.text(),
        width: 110,
        readOnly: true,
        enableContextMenu: false,
        renderer: (ctx) => Align(
          alignment: Alignment.centerLeft,
          child: Text(Formatters.date(ctx.cell.value as String? ?? '')),
        ),
      ),
      textColumn('category', l10n.fieldsCategory, 140),
      textColumn('description', l10n.expensesDescription, 220),
      textColumn('vendor', l10n.expensesVendor, 140),
      textColumn('reference_no', l10n.expensesReferenceno, 120),
      textColumn('payment_method', l10n.expensesPaymentmethod, 140),
      textColumn('project', l10n.expensesProject, 110),
      PlutoColumn(
        title: l10n.fieldsAmount,
        field: 'amount',
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
                status: expenseStatusLabel(l10n, status),
                color: expenseStatusColor(status),
              ),
            );
          },
        ),
      ),
      textColumn('created_by', l10n.expensesCreatedby, 130),
    ];
  }
}

/// Full-pane error state with a retry — same pattern as the items screen.
