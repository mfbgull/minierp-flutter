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

import '../../core/api/api_client.dart' show dioProvider;
import '../../core/api/endpoints.dart' show ApiEndpoints;
import '../models/customer.dart' show Customer;
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

  /// Soft delete (deactivates); fails server-side if the customer has
  /// invoices/payments.
  Future<ApiResult<void>> delete(int id) =>
      _api.delete('${ApiEndpoints.customers}/$id');

  /// `GET /customers/:id/ledger` — enveloped array. The server sorts
  /// newest-first by default (`transaction_date DESC`, no sort params sent
  /// here), so ledger UIs treat the first row's `balance` as the closing
  /// balance.
  Future<ApiResult<List<LedgerEntry>>> ledger(int id) => _api.getList(
    '${ApiEndpoints.customers}/$id/ledger',
    parseItem: (Object? json) =>
        LedgerEntry.fromJson(json as Map<String, dynamic>),
  );

  Future<ApiResult<CustomerBalance>> balance(int id) => _api.get(
    '${ApiEndpoints.customers}/$id/balance',
    parse: (Object? json) =>
        CustomerBalance.fromJson(json as Map<String, dynamic>),
  );
}

final customerRepositoryProvider = Provider<CustomerRepository>(
  (ref) => CustomerRepository(RepositoryClient(ref.watch(dioProvider))),
);
