// Owner equity repository — typed against the server ownerEquityController
// shapes (capital + withdrawals under `/owner-equity`).
//
// Endpoint shapes (verified against the server routes):
// - `GET /owner-equity/capital|withdrawals?page&limit&search&status&kind&
//   from_date&to_date` → `{success, data: [...], pagination}` (the
//   PagedResponse convention).
// - `POST /owner-equity/capital`, `PUT|DELETE .../capital/:id`
// - `POST /owner-equity/withdrawals` (goods `amount` is server-calculated —
//   never send it), `PUT|DELETE .../withdrawals/:id`
// - `POST /owner-equity/withdrawals/quote` → `{success, data:
//   {lines, totalCost}}` (informational only; POST recalculates)
// - `GET /owner-equity/summary` → `{success, data: EquitySummary}`
// - `GET /owner-equity/payment-method-options` → `{success,
//   data: [{value, label}]}`

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart' show dioProvider;
import '../../core/api/endpoints.dart' show ApiEndpoints;
import '../models/expense.dart' show ExpenseOption;
import '../models/owner_equity.dart'
    show
        EquitySummary,
        OwnerCapitalEntry,
        OwnerWithdrawal,
        OwnerWithdrawalDetail,
        WithdrawalQuote;
import 'api_result.dart';
import 'paged_request.dart' show PagedRequest, PagedResponse;
import 'repository_client.dart';

class OwnerEquityRepository {
  OwnerEquityRepository(this._client);

  final RepositoryClient _client;

  Future<ApiResult<PagedResponse<OwnerCapitalEntry>>> capital(
    PagedRequest request,
  ) => _client.getPaged(
    ApiEndpoints.ownerEquityCapital,
    queryParameters: request.toQuery(),
    parseItem: (Object? json) =>
        OwnerCapitalEntry.fromJson(json! as Map<String, dynamic>),
  );

  Future<ApiResult<PagedResponse<OwnerWithdrawal>>> withdrawals(
    PagedRequest request,
  ) => _client.getPaged(
    ApiEndpoints.ownerEquityWithdrawals,
    queryParameters: request.toQuery(),
    parseItem: (Object? json) =>
        OwnerWithdrawal.fromJson(json! as Map<String, dynamic>),
  );

  /// `POST /owner-equity/withdrawals/quote` — per-batch cost preview for
  /// the goods form. The create call re-runs costing server-side.
  Future<ApiResult<WithdrawalQuote>> quoteWithdrawal(
    List<Map<String, dynamic>> items,
  ) => _client.post(
    ApiEndpoints.ownerEquityWithdrawalsQuote,
    body: {'items': items},
    parse: (Object? json) =>
        WithdrawalQuote.fromJson(json! as Map<String, dynamic>),
  );

  Future<ApiResult<OwnerWithdrawalDetail>> withdrawalDetail(int id) =>
      _client.get(
        '${ApiEndpoints.ownerEquityWithdrawals}/$id',
        parse: (Object? json) =>
            OwnerWithdrawalDetail.fromJson(json! as Map<String, dynamic>),
      );

  Future<ApiResult<T>> _create<T>(
    String path,
    Map<String, dynamic> body,
    T Function(Object?) parse,
  ) => _client.post(path, body: body, parse: parse);

  Future<ApiResult<OwnerCapitalEntry>> createCapital(
    Map<String, dynamic> body,
  ) => _create(
    ApiEndpoints.ownerEquityCapital,
    body,
    (Object? json) => OwnerCapitalEntry.fromJson(json! as Map<String, dynamic>),
  );

  Future<ApiResult<OwnerCapitalEntry>> updateCapital(
    int id,
    Map<String, dynamic> body,
  ) => _client.put(
    '${ApiEndpoints.ownerEquityCapital}/$id',
    body: body,
    parse: (Object? json) =>
        OwnerCapitalEntry.fromJson(json! as Map<String, dynamic>),
  );

  /// Soft delete on the server — GL lines are voided with attribution and
  /// the row is marked `voided`, never removed.
  Future<ApiResult<void>> voidCapital(int id) =>
      _client.delete('${ApiEndpoints.ownerEquityCapital}/$id');

  Future<ApiResult<OwnerWithdrawal>> createWithdrawal(
    Map<String, dynamic> body,
  ) => _create(
    ApiEndpoints.ownerEquityWithdrawals,
    body,
    (Object? json) => OwnerWithdrawal.fromJson(json! as Map<String, dynamic>),
  );

  Future<ApiResult<OwnerWithdrawal>> updateWithdrawal(
    int id,
    Map<String, dynamic> body,
  ) => _client.put(
    '${ApiEndpoints.ownerEquityWithdrawals}/$id',
    body: body,
    parse: (Object? json) => OwnerWithdrawal.fromJson(json! as Map<String, dynamic>),
  );

  Future<ApiResult<void>> voidWithdrawal(int id) =>
      _client.delete('${ApiEndpoints.ownerEquityWithdrawals}/$id');

  Future<ApiResult<EquitySummary>> summary() => _client.get(
    ApiEndpoints.ownerEquitySummary,
    parse: (Object? json) => EquitySummary.fromJson(json! as Map<String, dynamic>),
  );

  Future<ApiResult<List<ExpenseOption>>> paymentMethodOptions() =>
      _client.getList(
        ApiEndpoints.ownerEquityPaymentMethodOptions,
        parseItem: (Object? json) =>
            ExpenseOption.fromJson(json! as Map<String, dynamic>),
      );
}

final ownerEquityRepositoryProvider = Provider<OwnerEquityRepository>(
  (ref) => OwnerEquityRepository(RepositoryClient(ref.watch(dioProvider))),
);
