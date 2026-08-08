import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/expense.dart'
    show Expense, ExpenseCategory, ExpenseOption;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/expense_repository.dart'
    show ExpenseFilters, expenseRepositoryProvider;

/// Debounced search term for the expenses grid (description/category/
/// vendor on the server). Empty value omits the param.
final expensesSearchProvider = StateProvider<String>((ref) => '');

/// Active category filter — null means "all categories".
final expensesCategoryProvider = StateProvider<String?>((ref) => null);

/// Active status filter — null means "all statuses".
final expensesStatusProvider = StateProvider<String?>((ref) => null);

/// Inclusive date-range filter — null means unbounded.
final expensesFromDateProvider = StateProvider<DateTime?>((ref) => null);
final expensesToDateProvider = StateProvider<DateTime?>((ref) => null);

/// Rows for the expenses grid. Re-runs when any filter changes; the
/// screen invalidates it on refresh and after create/edit/delete.
final expensesProvider = FutureProvider<List<Expense>>((ref) async {
  final search = ref.watch(expensesSearchProvider);
  final category = ref.watch(expensesCategoryProvider);
  final status = ref.watch(expensesStatusProvider);
  final from = ref.watch(expensesFromDateProvider);
  final to = ref.watch(expensesToDateProvider);

  final result = await ref
      .watch(expenseRepositoryProvider)
      .expenses(
        ExpenseFilters(
          search: search.isEmpty ? null : search,
          category: category,
          status: status,
          fromDate: from,
          toDate: to,
        ),
      );
  return switch (result) {
    ApiSuccess(:final data) => data,
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
