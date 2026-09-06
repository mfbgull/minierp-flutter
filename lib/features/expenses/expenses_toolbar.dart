import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/csv_export.dart';
import '../../core/utils/expense_status.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/date_range_picker.dart' show DateRangeFilter;
import '../../widgets/screen_toolbar.dart';
import 'expense_form_dialog.dart';
import 'expense_providers.dart';

/// Toolbar for the Expenses grid — search + category/status/sort filters +
/// date range + CSV export + New Expense (extracted from
/// expenses_screen.dart, spec 1.3). The screen owns the search debounce;
/// everything else reads/writes the expenses filter providers directly.
class ExpensesToolbar extends ConsumerWidget {
  const ExpensesToolbar({
    super.key,
    required this.searchController,
    required this.onSearchChanged,
    required this.onClearFilters,
    required this.hasActiveFilters,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearFilters;
  final bool hasActiveFilters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return ScreenToolbar(
      searchController: searchController,
      searchHint: l10n.commonSearch,
      onSearchChanged: onSearchChanged,
      onClearSearch: () {
        searchController.clear();
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
          onClear: onClearFilters,
          showClear: () => hasActiveFilters,
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
}