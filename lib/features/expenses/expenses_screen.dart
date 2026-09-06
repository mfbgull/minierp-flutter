// Expenses list screen — PORTING.md §5/§6: read-only PlutoGrid over
// `GET /expenses` with server-side paging + search + category/status/date
// filters (`PagedResponse<Expense>` + `ServerPaginationBar`, like
// suppliers/customers). The grid renders one page; the summary strip and
// CSV export run over the full filtered list (10k fetch — same pattern as
// the sales screen).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../data/models/expense.dart' show Expense;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../data/repositories/paged_request.dart' show PagedResponse;
import '../../l10n/app_localizations.dart';
import '../../widgets/grid_column_widths.dart';
import '../../widgets/pagination_bar.dart' show ServerPaginationBar;
import '../../widgets/pluto_grid_screen.dart'
    show autoFitPlutoColumns, plutoGridConfigurationFor, withSerialCell;
import '../../widgets/screen_error_panel.dart';
import 'expense_form_dialog.dart';
import 'expenses_grid_columns.dart';
import 'expenses_row_actions.dart';
import 'expenses_summary_strip.dart';
import 'expenses_toolbar.dart';
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

  GridColumnWidths? _widthTracker;

  @override
  void dispose() {
    _widthTracker?.dispose();
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
  void _applyExpenses(AsyncValue<PagedResponse<Expense>> value) {
    final manager = _stateManager;
    if (manager == null) return;
    manager.setShowLoading(value.isLoading);
    if (value.hasValue) {
      manager.removeAllRows();
      manager.appendRows([
        for (final (index, expense)
            in (value.value!.items).indexed)
          _rowFor(expense, index),
      ]);
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
  }

  /// Row-actions menu lives in `expenses_row_actions.dart` (spec 1.3);
  /// the grid's ⋮ cell only forwards the tap.
  Future<void> _openRowMenu(BuildContext cellContext, Expense? expense) async {
    if (expense == null || !mounted) return;
    await openExpenseRowMenu(context: cellContext, expense: expense);
  }

  PlutoRow _rowFor(Expense expense, int index) => withSerialCell(
    PlutoRow(
      cells: {
        'data': PlutoCell(value: expense),
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
    ),
    index,
  );

  @override
  Widget build(BuildContext context) {
    final expenses = ref.watch(expensesProvider);
    final page = expenses.valueOrNull;
    final l10n = AppLocalizations.of(context)!;

    ref.listen(expensesProvider, (previous, next) => _applyExpenses(next));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: ExpensesToolbar(
            searchController: _searchController,
            onSearchChanged: _onSearchChanged,
            onClearFilters: _clearFilters,
            hasActiveFilters: _hasActiveFilters,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: ExpensesSummaryStrip(rows: _filteredRows),
        ),
        Expanded(child: _buildBody(expenses)),
        if (page != null)
          ServerPaginationBar(
            page: page.currentPage,
            totalPages: page.totalPages,
            totalItems: page.totalItems,
            hasNext: page.hasNext,
            hasPrev: page.hasPrev,
            limit: ref.watch(expensesLimitProvider),
            itemLabel: l10n.expensesExpenses,
            onPageChanged: (p) =>
                ref.read(expensesPageProvider.notifier).state = p,
            onLimitChanged: (limit) {
              ref.read(expensesLimitProvider.notifier).state = limit;
              if (ref.read(expensesPageProvider) != 1) {
                ref.read(expensesPageProvider.notifier).state = 1;
              }
            },
          ),
      ],
    );
  }

  /// The full filtered list (10k fetch) — feeds the summary strip and
  /// CSV export. Mirrors the sales screen's [filteredInvoicesProvider].
  List<Expense> get _filteredRows =>
      ref.read(allExpensesProvider).valueOrNull ?? const <Expense>[];

  Widget _buildBody(AsyncValue<PagedResponse<Expense>> expenses) {
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
        configuration: plutoGridConfigurationFor(context, compact: true),
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
          _widthTracker?.dispose();
          _widthTracker = GridColumnWidths.attach(
            stateManager: event.stateManager,
            screenKey: 'expenses',
          );
        },
        onRowDoubleTap: (event) {
          final id = event.row.cells['id']?.value as int?;
          if (id == null || id <= 0) return;
          final expenses =
              ref.read(expensesProvider).valueOrNull ??
              const PagedResponse<Expense>(
                items: [],
                totalItems: 0,
                currentPage: 1,
                totalPages: 1,
                hasNext: false,
                hasPrev: false,
              );
          final matches = expenses.items.where((e) => e.id == id);
          if (matches.isEmpty) return;
          showExpenseFormDialog(context, expense: matches.first);
        },
        onSorted: _onGridSorted,
        noRowsWidget: Center(
          child: Text(
            l10n.commonNoresults,
            style: TextStyle(color: scheme.outline),
          ),
        ),
      ),
    );
  }

  String? _sortColumnFor(String field) {
    switch (field) {
      case 'expense_no':
        return 'e.expense_no';
      case 'expense_date':
        return 'e.expense_date';
      case 'category':
        return 'e.expense_category';
      case 'amount':
        return 'e.amount';
      case 'status':
        return 'e.status';
      case 'vendor':
        return 'e.vendor_name';
      case 'payment_method':
        return 'e.payment_method';
      case 'project':
        return 'e.project';
      case 'created_by':
        return 'e.created_at';
      default:
        return null;
    }
  }

  /// Server-side sort — maps the grid header click to the whitelist and
  /// resets to page 1.
  void _onGridSorted(PlutoGridOnSortedEvent event) {      final sortBy = _sortColumnFor(event.column.field);
      if (sortBy == null) return;
      final sort = event.column.sort;
      final order = sort == PlutoColumnSort.ascending ? 'ASC' : 'DESC';
    ref.read(expensesSortProvider.notifier).state = ExpenseSort(sortBy, order);
    if (ref.read(expensesPageProvider) != 1) {
      ref.read(expensesPageProvider.notifier).state = 1;
    }
  }

  /// Column set — dense data-screen conventions (PORTING.md §6), read-only
  /// with the id column hidden.
  /// Column definitions live in `expenses_grid_columns.dart` (spec 1.3);
  /// this method only wires the row-menu callback into the shared builder.
  List<PlutoColumn> _buildColumns(AppLocalizations l10n) {
    return buildExpenseColumns(l10n: l10n, onOpenRowMenu: _openRowMenu);
  }
}

