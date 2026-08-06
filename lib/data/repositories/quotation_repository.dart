// Quotation repository — typed against docs/API.md §Quotations and the
// server `salesController` shapes (PORTING.md §2).
//
// Envelope variants observed on the server — quotations are **bare**,
// like sales orders:
// - `GET /quotations` → bare `[Quotation]` (no envelope, no pagination;
//   filters: status, customer_id, customer_name, start_date, end_date,
//   warehouse_id, limit)
// - `GET /quotations/:id` → bare `{...quotation, items}`
// - `DELETE /quotations/:id` → enveloped `{success, message}` (the
//   server's deleteQuotation uses sendSuccess — use the enveloped delete)

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart' show dioProvider;
import '../../core/api/endpoints.dart' show ApiEndpoints;
import '../models/quotation.dart'
    show Quotation, QuotationConvertResult, QuotationDetail;
import 'api_result.dart';
import 'repository_client.dart';

class QuotationRepository {
  QuotationRepository(this._api);

  final RepositoryClient _api;

  /// All quotations — bare array (no search/page params used; the grid
  /// keeps sorting/filtering client-side like the SO/items screens).
  Future<ApiResult<List<Quotation>>> list({
    Map<String, dynamic>? queryParameters,
  }) => _api.getRawList(
    ApiEndpoints.quotations,
    queryParameters: queryParameters,
    parseItem: (Object? json) =>
        Quotation.fromJson(json as Map<String, dynamic>),
  );

  /// Quotation detail — bare `{...quotation, items}` response.
  Future<ApiResult<QuotationDetail>> detail(int id) => _api.getRaw(
    '${ApiEndpoints.quotations}/$id',
    parse: (Object? json) =>
        QuotationDetail.fromJson(json as Map<String, dynamic>),
  );

  /// Create — bare 201 quotation response; the body carries the header
  /// plus the `items` array ({item_id, quantity, unit_price, …}).
  Future<ApiResult<Quotation>> create(Map<String, dynamic> body) =>
      _api.postRaw(
        ApiEndpoints.quotations,
        body: body,
        parse: (Object? json) =>
            Quotation.fromJson(json as Map<String, dynamic>),
      );

  /// Update — bare updated quotation.
  Future<ApiResult<Quotation>> update(int id, Map<String, dynamic> body) =>
      _api.putRaw(
        '${ApiEndpoints.quotations}/$id',
        body: body,
        parse: (Object? json) =>
            Quotation.fromJson(json as Map<String, dynamic>),
      );

  /// Delete — enveloped `{success, message}`.
  Future<ApiResult<void>> delete(int id) =>
      _api.delete('${ApiEndpoints.quotations}/$id');

  /// Convert to a sales order — the response is a **flat**
  /// `{success, message, salesOrderId, salesOrderNo}` body (no `data`
  /// field), so it is parsed from the raw body. The server creates a
  /// Confirmed sales order from the quotation's header + items and marks
  /// the quotation Converted; it rejects an already-Converted or Expired
  /// quotation with a 400 `{error}` body.
  Future<ApiResult<QuotationConvertResult>> convert(int id) => _api.postRaw(
    '${ApiEndpoints.quotations}/$id/convert',
    parse: (Object? json) =>
        QuotationConvertResult.fromJson(json as Map<String, dynamic>),
  );
}

final quotationRepositoryProvider = Provider<QuotationRepository>(
  (ref) => QuotationRepository(RepositoryClient(ref.watch(dioProvider))),
);
