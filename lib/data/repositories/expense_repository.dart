// Expenses repository — typed against docs/API.md §Expenses and the
// server expenseController shapes (PORTING.md §2).
//
// Endpoint shapes (verified against the live server):
// - `GET /expenses?page&limit&search&category&status&vendor&from_date&to_date`
//   → `{success, data: [Expense], pagination: {current_page, total_pages,
//   total_expenses, per_page}}` (snake_case here vs camelCase on
//   /customers — the client treats the list as a full dataset, limit 1000,
//   and sorts/filters the grid client-side like the items screen).
// - `GET /expenses/categories` → `{success, data: [ExpenseCategory]}`
// - `GET /expenses/status-options`, `/payment-method-options` →
//   `{success, data: [{value, label}]}`
// - `POST /expenses` → `{success, message, data: Expense}`
// - `PUT /expenses/:id` → `{success, message, data: Expense}`
// - `DELETE /expenses/:id` → `{success, message}`

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart' show dioProvider;
import '../../core/api/endpoints.dart' show ApiEndpoints;
import '../models/expense.dart' show Expense, ExpenseCategory, ExpenseOption;
import 'api_result.dart';
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
    // The expenses controller defaults to 10 rows/page; the client
    // wants the full dataset for client-side grid sort (items-screen
    // convention), so cap at the server's practical list ceiling.
    'limit': 1000,
    if (search != null && search!.isNotEmpty) 'search': search,
    if (category != null && category!.isNotEmpty) 'category': category,
    if (status != null && status!.isNotEmpty) 'status': status,
    if (fromDate != null) 'from_date': _isoDate(fromDate!),
    if (toDate != null) 'to_date': _isoDate(toDate!),
  };

  static String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

class ExpenseRepository {
  ExpenseRepository(this._client);

  final RepositoryClient _client;

  Future<ApiResult<List<Expense>>> expenses(ExpenseFilters filters) =>
      _client.getList(
        ApiEndpoints.expenses,
        queryParameters: filters.toQuery(),
        parseItem: (Object? json) =>
            Expense.fromJson(json! as Map<String, dynamic>),
      );

  Future<ApiResult<List<ExpenseCategory>>> categories() => _client.getList(
    '${ApiEndpoints.expenses}/categories',
    parseItem: (Object? json) =>
        ExpenseCategory.fromJson(json! as Map<String, dynamic>),
  );

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
        parse: (Object? json) =>
            Expense.fromJson(json! as Map<String, dynamic>),
      );

  Future<ApiResult<void>> delete(int id) =>
      _client.delete('${ApiEndpoints.expenses}/$id');
}

final expenseRepositoryProvider = Provider<ExpenseRepository>(
  (ref) => ExpenseRepository(RepositoryClient(ref.watch(dioProvider))),
);
