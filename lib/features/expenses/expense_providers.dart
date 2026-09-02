import 'package:flutter_riverpod/flutter_riverpod.dart';


import '../../core/utils/date_utils.dart' show isoDate;
import '../../data/models/expense.dart'
    show Expense, ExpenseCategory, ExpenseOption;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../preferences/preference_providers.dart' show initialRange;
import '../../data/repositories/expense_repository.dart'
    show expenseRepositoryProvider;
import '../../data/repositories/paged_request.dart'
    show PagedRequest, PagedResponse;

/// Debounced search term for the expenses grid (description/category/
/// vendor on the server). Empty value omits the param.
final expensesSearchProvider = StateProvider<String>((ref) => '');

/// Active category filter — null means "all categories".
final expensesCategoryProvider = StateProvider<String?>((ref) => null);

/// Active status filter — null means "all statuses".
final expensesStatusProvider = StateProvider<String?>((ref) => null);

/// Inclusive date-range filter — null means unbounded.
final expensesFromDateProvider = StateProvider<DateTime?>((ref) => initialRange(ref).from);
final expensesToDateProvider = StateProvider<DateTime?>((ref) => initialRange(ref).to);

/// Current page (1-based) for the expenses grid.
final expensesPageProvider = StateProvider<int>((ref) => 1);

/// Rows per page for the expenses grid (default 10).
final expensesLimitProvider = StateProvider<int>((ref) => 10);

/// Active server-side sort; null = server default (expense_date DESC).
final expensesSortProvider = StateProvider<ExpenseSort?>((ref) => null);

/// Rows for the expenses grid. Re-runs when any filter/sort/page changes;
/// the screen invalidates it on refresh and after create/edit/delete.
final expensesProvider = FutureProvider<PagedResponse<Expense>>((ref) async {
  final search = ref.watch(expensesSearchProvider);
  final category = ref.watch(expensesCategoryProvider);
  final status = ref.watch(expensesStatusProvider);
  final from = ref.watch(expensesFromDateProvider);
  final to = ref.watch(expensesToDateProvider);
  final page = ref.watch(expensesPageProvider);
  final limit = ref.watch(expensesLimitProvider);
  final sort = ref.watch(expensesSortProvider);
  final repo = ref.watch(expenseRepositoryProvider);

  final result = await repo.expenses(
    PagedRequest(
      page: page,
      limit: limit,
      search: search.isEmpty ? null : search,
      sortBy: sort?.column,
      sortOrder: sort?.order ?? 'DESC',
      extra: {
        'category': category,
        'status': status,
        'from_date': from != null ? isoDate(from) : null,
        'to_date': to != null ? isoDate(to) : null,
      },
    ),
  );
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// The full filtered list — same filters as [expensesProvider] but with
/// `limit: 10000` so the summary strip and CSV export reflect every
/// matching row, not just the current server-rendered page. Mirrors the
/// sales screen's [filteredInvoicesProvider] pattern.
final allExpensesProvider = FutureProvider<List<Expense>>((ref) async {
  final search = ref.watch(expensesSearchProvider);
  final category = ref.watch(expensesCategoryProvider);
  final status = ref.watch(expensesStatusProvider);
  final from = ref.watch(expensesFromDateProvider);
  final to = ref.watch(expensesToDateProvider);
  final repo = ref.watch(expenseRepositoryProvider);

  final result = await repo.expenses(
    PagedRequest(limit: 10000, extra: {
      'search': search.isEmpty ? null : search,
      'category': category,
      'status': status,
      'from_date': from != null ? isoDate(from) : null,
      'to_date': to != null ? isoDate(to) : null,
    }),
  );
  return switch (result) {
    ApiSuccess(:final data) => data.items,
    ApiFailure(:final error) => throw error,
  };
});

/// Categories for the filter dropdown and the expense form
/// (`GET /expenses/categories`).
final expenseCategoriesProvider = FutureProvider<List<ExpenseCategory>>((
  ref,
) async {
  final result = await ref.watch(expenseRepositoryProvider).categories();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// Status options (Draft/Submitted/Approved/Paid/Cancelled).
final expenseStatusOptionsProvider = FutureProvider<List<ExpenseOption>>((
  ref,
) async {
  final result = await ref.watch(expenseRepositoryProvider).statusOptions();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// Payment method options (Cash/Check/Bank Transfer/…).
final expensePaymentMethodsProvider = FutureProvider<List<ExpenseOption>>((
  ref,
) async {
  final result = await ref
      .watch(expenseRepositoryProvider)
      .paymentMethodOptions();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// Sort column/order (mirrors [InvoiceSort] in sales).
class ExpenseSort {
  const ExpenseSort(this.column, this.order);
  final String column;
  final String order;
}
