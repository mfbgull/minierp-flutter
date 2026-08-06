// Supplier repository — typed against docs/API.md §Suppliers and the
// server `suppliersController` shapes (PORTING.md §2).
//
// Envelope variants observed on the server:
// - `GET /suppliers` → `{success, data: [...], pagination: {...}}`
//   (server-paginated, same contract as customers)
// - `GET /suppliers/:id` → `{success, data: Supplier}`

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart' show dioProvider;
import '../../core/api/endpoints.dart' show ApiEndpoints;
import '../models/ledger_entry.dart' show LedgerEntry;
import '../models/statement.dart' show StatementData;
import '../models/supplier.dart' show Supplier;
import 'api_result.dart';
import 'paged_request.dart';
import 'repository_client.dart';

class SupplierRepository {
  SupplierRepository(this._api);

  final RepositoryClient _api;

  Future<ApiResult<PagedResponse<Supplier>>> list(PagedRequest request) =>
      _api.getPaged(
        ApiEndpoints.suppliers,
        queryParameters: request.toQuery(),
        parseItem: (Object? json) =>
            Supplier.fromJson(json as Map<String, dynamic>),
      );

  Future<ApiResult<Supplier>> get(int id) => _api.get(
    '${ApiEndpoints.suppliers}/$id',
    parse: (Object? json) => Supplier.fromJson(json as Map<String, dynamic>),
  );

  /// `POST /suppliers` — `supplier_code` is user-entered (unlike the
  /// auto-generated customer code); body uses snake_case API keys.
  Future<ApiResult<Supplier>> create(Map<String, dynamic> body) => _api.post(
    ApiEndpoints.suppliers,
    body: body,
    parse: (Object? json) => Supplier.fromJson(json as Map<String, dynamic>),
  );

  /// `PUT /suppliers/:id` — accepts `is_active`; `supplier_code` is not
  /// updatable server-side.
  Future<ApiResult<Supplier>> update(int id, Map<String, dynamic> body) =>
      _api.put(
        '${ApiEndpoints.suppliers}/$id',
        body: body,
        parse: (Object? json) =>
            Supplier.fromJson(json as Map<String, dynamic>),
      );

  /// `GET /suppliers/:id/ledger` — enveloped array. The server sorts
  /// newest-first by default (`transaction_date DESC`, no sort params sent
  /// here), so ledger UIs treat the first row's `balance` as the closing
  /// balance.
  Future<ApiResult<List<LedgerEntry>>> ledger(int id) => _api.getList(
    '${ApiEndpoints.suppliers}/$id/ledger',
    parseItem: (Object? json) =>
        LedgerEntry.fromJson(json as Map<String, dynamic>),
  );

  /// `GET /suppliers/:id/statement` — enveloped `{data: {supplier, period,
  /// openingBalance, closingBalance, transactions}}`; transactions are
  /// ordered oldest-first. Called without date filters (all history).
  Future<ApiResult<StatementData>> statement(int id) => _api.get(
    '${ApiEndpoints.suppliers}/$id/statement',
    parse: (Object? json) =>
        StatementData.fromJson(json as Map<String, dynamic>),
  );
}

final supplierRepositoryProvider = Provider<SupplierRepository>(
  (ref) => SupplierRepository(RepositoryClient(ref.watch(dioProvider))),
);
