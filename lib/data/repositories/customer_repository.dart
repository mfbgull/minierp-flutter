// Customer repository — typed against docs/API.md §Customers and the
// server `customersController` shapes (PORTING.md §2).
//
// Envelope variants observed on the server:
// - `GET /customers` → `{success, data: [...], pagination: {...}}`
// - `GET /customers/:id` → `{success, data: Customer}`
// - `POST/PUT /customers(/:id)` → `{success, data: Customer, message}`
// - `DELETE /customers/:id` → `{success, message}` (soft delete)
// - `GET /customers/:id/ledger` → `{success, data: [LedgerEntry]}`
// - `GET /customers/:id/balance` → `{success, data: {customerId,
//   customerName, currentBalance}}`

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart' show ApiEndpoints;
import '../../core/cache/cached_repository.dart'
    show cachedRepositoryClientProvider;
import '../models/customer.dart' show Customer;
import '../models/json_helpers.dart';
import '../models/ledger_entry.dart' show LedgerEntry;
import 'api_result.dart';
import 'paged_request.dart';
import 'repository_client.dart';

/// `GET /customers/:id/balance` response DTO.
class CustomerBalance {
  const CustomerBalance({
    required this.customerId,
    required this.customerName,
    required this.currentBalance,
  });

  factory CustomerBalance.fromJson(Map<String, dynamic> json) =>
      CustomerBalance(
        customerId: json['customerId'] as int? ?? 0,
        customerName: json['customerName'] as String? ?? '',
        currentBalance: (json['currentBalance'] as num?) ?? 0,
      );

  final int customerId;
  final String customerName;
  final num currentBalance;
}

/// `GET /customers/:id/statement` response DTO — customer + period,
/// opening/closing balances and the period's transactions (each parsed as
/// a [LedgerEntry]; the server computes the closing balance server-side).
class CustomerStatement {
  const CustomerStatement({
    required this.customerId,
    required this.customerName,
    required this.openingBalance,
    required this.closingBalance,
    required this.transactions,
    this.fromDate,
    this.toDate,
  });

  factory CustomerStatement.fromJson(Map<String, dynamic> json) {
    final customer = json['customer'] is Map<String, dynamic>
        ? json['customer'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final period = json['period'] is Map<String, dynamic>
        ? json['period'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final tx = json['transactions'];
    return CustomerStatement(
      customerId: asInt(customer['id']) ?? 0,
      customerName: asString(customer['customer_name']) ?? '',
      fromDate: asString(period['fromDate']),
      toDate: asString(period['toDate']),
      openingBalance: asNum(json['openingBalance']) ?? 0,
      closingBalance: asNum(json['closingBalance']) ?? 0,
      transactions: [
        for (final t in tx is List ? tx : const <dynamic>[])
          if (t is Map<String, dynamic>) LedgerEntry.fromJson(t),
      ],
    );
  }

  final int customerId;
  final String customerName;
  final String? fromDate;
  final String? toDate;
  final num openingBalance;
  final num closingBalance;
  final List<LedgerEntry> transactions;
}

class CustomerRepository {
  CustomerRepository(this._api);

  final RepositoryClient _api;

  Future<ApiResult<PagedResponse<Customer>>> list(PagedRequest request) =>
      _api.getPaged(
        ApiEndpoints.customers,
        queryParameters: request.toQuery(),
        parseItem: (Object? json) =>
            Customer.fromJson(json as Map<String, dynamic>),
      );

  Future<ApiResult<Customer>> get(int id) => _api.get(
    '${ApiEndpoints.customers}/$id',
    parse: (Object? json) => Customer.fromJson(json as Map<String, dynamic>),
  );

  /// `POST /customers` — `customer_code` is auto-generated server-side
  /// (`CUSTnnn`); body uses snake_case API keys.
  Future<ApiResult<Customer>> create(Map<String, dynamic> body) => _api.post(
    ApiEndpoints.customers,
    body: body,
    parse: (Object? json) => Customer.fromJson(json as Map<String, dynamic>),
  );

  Future<ApiResult<Customer>> update(int id, Map<String, dynamic> body) =>
      _api.put(
        '${ApiEndpoints.customers}/$id',
        body: body,
        parse: (Object? json) =>
            Customer.fromJson(json as Map<String, dynamic>),
      );

  /// Soft delete (stamps `deleted_at`, deactivates); fails server-side if
  /// the customer has invoices/payments. Reversible via [restore].
  Future<ApiResult<void>> delete(int id) =>
      _api.delete('${ApiEndpoints.customers}/$id');

  /// `POST /customers/:id/restore` — reverts a soft delete.
  Future<ApiResult<void>> restore(int id) => _api.post(
    '${ApiEndpoints.customers}/$id/restore',
    parse: (_) {},
  );

  /// `GET /customers/:id/ledger` — enveloped array. The server sorts
  /// newest-first by default (`transaction_date DESC`, no sort params sent
  /// here), so ledger UIs treat the first row's `balance` as the closing
  /// balance.
  ///
  /// Optional inclusive [fromDate]/[toDate] bounds (ISO `YYYY-MM-DD`,
  /// same names as the statement endpoint) narrow the visible rows; null
  /// omits the parameter → full history. Per-row running balances are
  /// always the server's full-history values.
  Future<ApiResult<List<LedgerEntry>>> ledger(
    int id, {
    String? fromDate,
    String? toDate,
  }) => _api.getList(
    '${ApiEndpoints.customers}/$id/ledger',
    queryParameters: {'fromDate': ?fromDate, 'toDate': ?toDate},
    parseItem: (Object? json) =>
        LedgerEntry.fromJson(json as Map<String, dynamic>),
  );

  Future<ApiResult<CustomerBalance>> balance(int id) => _api.get(
    '${ApiEndpoints.customers}/$id/balance',
    parse: (Object? json) =>
        CustomerBalance.fromJson(json as Map<String, dynamic>),
  );

  /// `POST /customers/recalculate-balances` — recomputes every customer's
  /// `current_balance` from unpaid invoices (the web "Fix Balances"
  /// action). Enveloped `{success, message}` — no data payload.
  Future<ApiResult<void>> recalculateBalances() => _api.post(
    '${ApiEndpoints.customers}/recalculate-balances',
    body: const <String, dynamic>{},
    parse: (_) {},
  );

  /// `GET /customers/:id/statement?fromDate&toDate` — the date-ranged AR
  /// statement (web CustomerStatement page; `fromDate`/`toDate` are the
  /// server's exact query-param names, sent as ISO `YYYY-MM-DD`).
  Future<ApiResult<CustomerStatement>> statement(
    int id, {
    String? fromDate,
    String? toDate,
  }) => _api.get(
    '${ApiEndpoints.customers}/$id/statement',
    queryParameters: {'fromDate': ?fromDate, 'toDate': ?toDate},
    parse: (Object? json) =>
        CustomerStatement.fromJson(json as Map<String, dynamic>),
  );
}

final customerRepositoryProvider = Provider<CustomerRepository>(
  (ref) => CustomerRepository(ref.watch(cachedRepositoryClientProvider)),
);
