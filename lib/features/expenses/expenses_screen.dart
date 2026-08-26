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

import '../../core/utils/csv_export.dart';
import '../../core/utils/expense_status.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/expense.dart' show Expense;
import '../../data/repositories/api_result.dart' show ApiError;
import '../../data/repositories/paged_request.dart' show PagedResponse;
import '../../l10n/app_localizations.dart';
import '../../widgets/date_range_picker.dart' show DateRangeFilter;
import '../../widgets/grid_column_widths.dart';
import '../../widgets/pagination_bar.dart' show ServerPaginationBar;
import '../../widgets/pluto_grid_screen.dart'
    show autoFitPlutoColumns, plutoGridConfigurationFor, serialGridColumn, withSerialCell;
import '../../widgets/screen_error_panel.dart';
import '../../widgets/screen_toolbar.dart';
import '../../widgets/status_badge.dart';
import 'expense_form_dialog.dart';
import 'expense_providers.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';

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

  /// Opens the row-actions menu (Edit) anchored at [cellContext].
  Future<void> _openRowMenu(
    BuildContext cellContext,
    Expense? expense,
  ) async {
    if (expense == null || !mounted) return;
    final box = cellContext.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final overlay = Overlay.of(cellContext, rootOverlay: true);
    final l10n = AppLocalizations.of(cellContext)!;
    final action = await showMenu<_ExpenseRowAction>(
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
          value: _ExpenseRowAction.edit,
          child: Row(
            children: [
              const Icon(Icons.edit_outlined, size: 18),
              const SizedBox(width: 8),
              Text(l10n.commonEdit),
            ],
          ),
        ),
      ],
    );
    if (action != null && mounted) {
      showExpenseFormDialog(context, expense: expense);
    }
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
          child: _toolbar(l10n, expenses),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: _summaryStrip(l10n),
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

  Widget _toolbar(AppLocalizations l10n, AsyncValue<PagedResponse<Expense>> expenses) {
    return ScreenToolbar(
      searchController: _searchController,
      searchHint: l10n.commonSearch,
      onSearchChanged: _onSearchChanged,
      onClearSearch: () {
        _searchController.clear();
        ref.read(expensesSearchProvider.notifier).state = '';
      },
      filters: [
        ScreenToolbarDropdown<String?>(
          key: const ValueKey('expense-category-filter'),
          value: ref.watch(expensesCategoryProvider),
          hint: l10n.expensesAllcategories,
          items: [
            null,
            for (final category
                in ref.watch(expenseCategoriesProvider).valueOrNull ?? const [])
              category.categoryName,
          ],
          labelBuilder: (v) => v ?? l10n.expensesAllcategories,
          width: 170,
          onChanged: (v) {
            ref.read(expensesCategoryProvider.notifier).state = v;
            if (ref.read(expensesPageProvider) != 1) {
              ref.read(expensesPageProvider.notifier).state = 1;
            }
          },
        ),
        ScreenToolbarDropdown<String?>(
          key: const ValueKey('expense-status-filter'),
          value: ref.watch(expensesStatusProvider),
          hint: l10n.expensesAllstatuses,
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
          width: 150,
          onChanged: (v) {
            ref.read(expensesStatusProvider.notifier).state = v;
            if (ref.read(expensesPageProvider) != 1) {
              ref.read(expensesPageProvider.notifier).state = 1;
            }
          },
        ),
        ScreenToolbarDropdown<String?>(
          key: const ValueKey('expense-sort-filter'),
          value: ref.watch(expensesSortProvider)?.column,
          hint: 'Sort',
          items: const [
            null,
            'e.expense_date',
            'e.amount',
            'e.expense_category',
            'e.status',
            'e.vendor_name',
            'e.created_at',
          ],
          labelBuilder: (v) {
            switch (v) {
              case 'e.expense_date':
                return 'Date';
              case 'e.amount':
                return 'Amount';
              case 'e.expense_category':
                return 'Category';
              case 'e.status':
                return 'Status';
              case 'e.vendor_name':
                return 'Vendor';
              case 'e.created_at':
                return 'Created';
              default:
                return 'Sort';
            }
          },
          width: 130,
          onChanged: (v) {
            final current = ref.read(expensesSortProvider);
            final next = v == null
                ? null
                : ExpenseSort(
                    v,
                    current == null || current.column != v
                        ? 'DESC'
                        : (current.order == 'ASC' ? 'DESC' : 'ASC'),
                  );
            ref.read(expensesSortProvider.notifier).state = next;
            if (ref.read(expensesPageProvider) != 1) {
              ref.read(expensesPageProvider.notifier).state = 1;
            }
          },
        ),
        DateRangeFilter(
          height: 40,
          fromProvider: expensesFromDateProvider,
          toProvider: expensesToDateProvider,
          onClear: _clearFilters,
          showClear: () => _hasActiveFilters,
        ),
      ],
      onRefresh: () => ref.invalidate(expensesProvider),
      actions: [
        TextButton.icon(
          onPressed: () {
            final all = ref.read(allExpensesProvider);
            final rows = all.valueOrNull;
            if (rows == null || rows.isEmpty) return;
            saveCsv(
              context,
              suggestedName: csvSuggestedName('expenses'),
              csv: buildExpensesCsv(l10n, rows),
              successMessage: l10n.expensesExported,
              errorMessage: l10n.expensesExportfailed,
            );
          },
          icon: const Icon(Icons.file_download_outlined, size: 18),
          label: Text(l10n.expensesExportcsv),
        ),
      ],
      primaryActions: [
        FilledButton.tonalIcon(
          onPressed: () => showExpenseFormDialog(context),
          icon: const Icon(Icons.add, size: 18),
          label: Text(l10n.expensesNewexpense),
        ),
      ],
    );
  }

  /// The full filtered list (10k fetch) — feeds the summary strip and
  /// CSV export. Mirrors the sales screen's [filteredInvoicesProvider].
  List<Expense> get _filteredRows =>
      ref.read(allExpensesProvider).valueOrNull ?? const <Expense>[];

  bool get _hasNoRows => _filteredRows.isEmpty;

  Widget _summaryStrip(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final rows = _filteredRows;
    final total = rows.fold<num>(0, (sum, e) => sum + e.amount);
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
  void _onGridSorted(PlutoGridOnSortedEvent event) {
    final sortBy = _sortColumnFor(event.column.field);
    if (sortBy == null) return;
    final sort = event.column.sort;
    if (sort == null) return;
    final order = sort == PlutoColumnSort.ascending ? 'ASC' : 'DESC';
    ref.read(expensesSortProvider.notifier).state = ExpenseSort(sortBy, order);
    if (ref.read(expensesPageProvider) != 1) {
      ref.read(expensesPageProvider.notifier).state = 1;
    }
  }

  /// Column set — dense data-screen conventions (PORTING.md §6), read-only
  /// with the id column hidden.
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
                color: expenseStatusColor(Theme.of(cellContext).colorScheme, status),
              ),
            );
          },
        ),
      ),
      textColumn('created_by', l10n.expensesCreatedby, 130),
      PlutoColumn(
        title: l10n.commonActions,
        field: 'actions',
        frozen: PlutoColumnFrozen.end,
        type: PlutoColumnType.text(),
        width: 64,
        readOnly: true,
        enableContextMenu: false,
        enableFilterMenuItem: false,
        enableHideColumnMenuItem: false,
        enableSetColumnsMenuItem: false,
        renderer: (ctx) {
          final expense = ctx.cell.row.cells['data']?.value as Expense?;
          return Builder(
            builder: (cellContext) => Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => _openRowMenu(cellContext, expense),
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
}

/// The per-row ⋮ menu actions for an expense row.
enum _ExpenseRowAction { edit }
