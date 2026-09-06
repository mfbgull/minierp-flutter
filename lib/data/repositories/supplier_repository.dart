// Supplier repository — typed against docs/API.md §Suppliers and the
// server `suppliersController` shapes (PORTING.md §2).
//
// Envelope variants observed on the server:
// - `GET /suppliers` → `{success, data: [...], pagination: {...}}`
//   (server-paginated, same contract as customers)
// - `GET /suppliers/:id` → `{success, data: Supplier}`

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart' show ApiEndpoints;
import '../models/json_helpers.dart' show asInt, asNum, asString;
import '../models/ledger_entry.dart' show LedgerEntry;
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
  ///
  /// [fromDate]/[toDate] are an optional inclusive range (the endpoint's
  /// exact query-param names, ISO `YYYY-MM-DD`); null = full history
  /// (parameters omitted — unified-detail-date-picker-spec §5.3).
  Future<ApiResult<List<LedgerEntry>>> ledger(
    int id, {
    String? fromDate,
    String? toDate,
  }) => _api.getList(
    '${ApiEndpoints.suppliers}/$id/ledger',
    queryParameters: {'fromDate': ?fromDate, 'toDate': ?toDate},
    parseItem: (Object? json) =>
        LedgerEntry.fromJson(json as Map<String, dynamic>),
  );

  /// Soft delete (deactivates); fails server-side if the supplier has
  /// purchase orders.
  Future<ApiResult<void>> delete(int id) =>
      _api.delete('${ApiEndpoints.suppliers}/$id');

  /// `GET /suppliers/:id/balance` — enveloped `{data: {supplierId,
  /// supplierName, currentBalance}}` (the web SupplierDetailPage header's
  /// Balance quick-stat source).
  Future<ApiResult<SupplierBalance>> balance(int id) => _api.get(
    '${ApiEndpoints.suppliers}/$id/balance',
    parse: (Object? json) =>
        SupplierBalance.fromJson(json as Map<String, dynamic>),
  );

  /// `POST /suppliers/recalculate-balances` — recomputes every supplier's
  /// `current_balance` from its AP ledger (the web "Recalculate" action,
  /// the suppliers-screen Fix Balances equivalent).
  Future<ApiResult<void>> recalculateBalances() => _api.post(
    '${ApiEndpoints.suppliers}/recalculate-balances',
    body: const <String, dynamic>{},
    parse: (_) {},
  );

  /// `GET /suppliers/:id/statement?fromDate&toDate` — the date-ranged AP
  /// statement (web SupplierStatement page; `fromDate`/`toDate` are the
  /// server's exact query-param names, sent as ISO `YYYY-MM-DD`).
  /// Transactions are ordered oldest-first; the server computes the
  /// closing balance.
  Future<ApiResult<SupplierStatement>> statement(
    int id, {
    String? fromDate,
    String? toDate,
  }) => _api.get(
    '${ApiEndpoints.suppliers}/$id/statement',
    queryParameters: {'fromDate': ?fromDate, 'toDate': ?toDate},
    parse: (Object? json) =>
        SupplierStatement.fromJson(json as Map<String, dynamic>),
  );
}

/// `GET /suppliers/:id/balance` response DTO — the web SupplierBalanceData
/// shape (`supplierId`, `supplierName`, `currentBalance`).
class SupplierBalance {
  const SupplierBalance({
    required this.supplierId,
    required this.supplierName,
    required this.currentBalance,
  });

  factory SupplierBalance.fromJson(Map<String, dynamic> json) =>
      SupplierBalance(
        supplierId: asInt(json['supplierId']) ?? 0,
        supplierName: asString(json['supplierName']) ?? '',
        currentBalance: asNum(json['currentBalance']) ?? 0,
      );

  final int supplierId;
  final String supplierName;
  final num currentBalance;
}

/// `GET /suppliers/:id/statement` response DTO — supplier + period,
/// opening/closing balances and the period's transactions (each parsed as
/// a [LedgerEntry]; the server computes the closing balance server-side).
class SupplierStatement {
  const SupplierStatement({
    required this.supplierId,
    required this.supplierName,
    required this.openingBalance,
    required this.closingBalance,
    required this.transactions,
    this.fromDate,
    this.toDate,
  });

  factory SupplierStatement.fromJson(Map<String, dynamic> json) {
    final supplier = json['supplier'] is Map<String, dynamic>
        ? json['supplier'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final period = json['period'] is Map<String, dynamic>
        ? json['period'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final tx = json['transactions'];
    return SupplierStatement(
      supplierId: asInt(supplier['id']) ?? 0,
      supplierName: asString(supplier['supplier_name']) ?? '',
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

  final int supplierId;
  final String supplierName;
  final String? fromDate;
  final String? toDate;
  final num openingBalance;
  final num closingBalance;
  final List<LedgerEntry> transactions;
}

final supplierRepositoryProvider = Provider<SupplierRepository>(
  (ref) => SupplierRepository(ref.watch(repositoryClientProvider)),
);
