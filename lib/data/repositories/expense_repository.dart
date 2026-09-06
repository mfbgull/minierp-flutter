// Expenses repository — typed against docs/API.md §Expenses and the
// server expenseController shapes (PORTING.md §2).
//
// Endpoint shape (verified against the live server):
// - `GET /expenses?page&limit&search&category&status&vendor&from_date&to_date`
//   → `{success, data: [Expense], pagination: {currentPage, totalPages,
//   totalItems, hasNext, hasPrev}}` (the PagedResponse convention).
// - `GET /expenses/categories` → `{success, data: [ExpenseCategory]}`
// - `GET /expenses/status-options`, `/payment-method-options` →
//   `{success, data: [{value, label}]}`
// - `POST /expenses` → `{success, message, data: Expense}`
// - `PUT /expenses/:id` → `{success, message, data: Expense}`
// - `DELETE /expenses/:id` → `{success, message}`

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart' show ApiEndpoints;
import '../../core/utils/date_utils.dart' show isoDate;
import '../models/expense.dart' show Expense, ExpenseCategory, ExpenseOption;
import 'api_result.dart';
import 'paged_request.dart' show PagedRequest, PagedResponse;
import 'repository_client.dart';

/// Expenses list filters — mirrors the `getExpenses` controller params.
class ExpenseFilters {
  const ExpenseFilters({
    this.search,
    this.category,
    this.status,
    this.fromDate,
    this.toDate,
  });

  final String? search;

  /// Exact `expense_category` match.
  final String? category;

  /// Exact status match (Draft/Submitted/Approved/Paid/Cancelled).
  final String? status;

  /// Inclusive `from_date` / `to_date` (`YYYY-MM-DD`).
  final DateTime? fromDate;
  final DateTime? toDate;

  Map<String, dynamic> toQuery() => {
    'page': null,
    'limit': null,
    if (search != null && search!.isNotEmpty) 'search': search,
    if (category != null && category!.isNotEmpty) 'category': category,
    if (status != null && status!.isNotEmpty) 'status': status,
    if (fromDate != null) 'from_date': isoDate(fromDate!),
    if (toDate != null) 'to_date': isoDate(toDate!),
  };
}

class ExpenseRepository {
  ExpenseRepository(this._client);

  final RepositoryClient _client;

  Future<ApiResult<PagedResponse<Expense>>> expenses(PagedRequest request) =>
      _client.getPaged(
        ApiEndpoints.expenses,
        queryParameters: request.toQuery(),
        parseItem: (Object? json) =>
            Expense.fromJson(json! as Map<String, dynamic>),
      );

  Future<ApiResult<List<ExpenseCategory>>> categories() => _client.getList(
    '${ApiEndpoints.expenses}/categories',
    parseItem: (Object? json) =>
        ExpenseCategory.fromJson(json! as Map<String, dynamic>),
  );

  /// `POST /expenses/categories` — the quick-add from the expense form.
  Future<ApiResult<ExpenseCategory>> createCategory({
    required String categoryName,
    String? description,
  }) => _client.post(
    ApiEndpoints.expensesCategories,
    body: {
      'category_name': categoryName,
      if (description != null && description.isNotEmpty)
        'description': description,
    },
    parse: (Object? json) =>
        ExpenseCategory.fromJson(json! as Map<String, dynamic>),
  );

  /// `DELETE /expenses/categories/:id` — the server refuses (400) when
  /// the category is still referenced by existing expenses.
  Future<ApiResult<void>> deleteCategory(int id) =>
      _client.delete('${ApiEndpoints.expensesCategories}/$id');

  Future<ApiResult<List<ExpenseOption>>> statusOptions() => _client.getList(
    '${ApiEndpoints.expenses}/status-options',
    parseItem: (Object? json) =>
        ExpenseOption.fromJson(json! as Map<String, dynamic>),
  );

  Future<ApiResult<List<ExpenseOption>>> paymentMethodOptions() =>
      _client.getList(
        '${ApiEndpoints.expenses}/payment-method-options',
        parseItem: (Object? json) =>
            ExpenseOption.fromJson(json! as Map<String, dynamic>),
      );

  /// `POST /expenses` — body keys per the controller's createExpense DTO.
  Future<ApiResult<Expense>> create(Map<String, dynamic> body) => _client.post(
    ApiEndpoints.expenses,
    body: body,
    parse: (Object? json) => Expense.fromJson(json! as Map<String, dynamic>),
  );

  Future<ApiResult<Expense>> update(int id, Map<String, dynamic> body) =>
      _client.put(
        '${ApiEndpoints.expenses}/$id',
        body: body,
        parse: (Object? json) => Expense.fromJson(json! as Map<String, dynamic>),
      );

  Future<ApiResult<void>> delete(int id) =>
      _client.delete('${ApiEndpoints.expenses}/$id');
}

final expenseRepositoryProvider = Provider<ExpenseRepository>(
  (ref) => ExpenseRepository(ref.watch(repositoryClientProvider)),
);
