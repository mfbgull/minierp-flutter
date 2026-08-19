// Quotation repository — typed against docs/API.md §Quotations and the
// server `salesController` shapes (PORTING.md §2).
//
// Envelope variants observed on the server — quotations are **bare**, like
// sales orders for the detail/create/update routes:
// - `GET /quotations` → **enveloped + `pagination` block** (server-paged
//   since grid-pagination Phase 5; filters: status, customer_id,
//   customer_name, search, start_date, end_date, warehouse_id,
//   page, limit, sortBy, sortOrder)
// - `GET /quotations/:id` → bare `{...quotation, items}`
// - `DELETE /quotations/:id` → enveloped `{success, message}` (the
//   server's deleteQuotation uses sendSuccess — use the enveloped delete)

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart' show dioProvider;
import '../../core/api/endpoints.dart' show ApiEndpoints;
import '../models/quotation.dart'
    show Quotation, QuotationConvertResult, QuotationDetail;
import 'api_result.dart';
import 'paged_request.dart' show PagedRequest, PagedResponse;
import 'repository_client.dart';

class QuotationRepository {
  QuotationRepository(this._api);

  final RepositoryClient _api;

  /// All quotations — full list (the grid now uses [listPaged]; this
  /// stays for any consumer that needs the whole list in one fetch).
  Future<ApiResult<List<Quotation>>> list({
    Map<String, dynamic>? queryParameters,
  }) => _api.getRawList(
    ApiEndpoints.quotations,
    queryParameters: queryParameters,
    parseItem: (Object? json) =>
        Quotation.fromJson(json as Map<String, dynamic>),
  );

  /// One page of quotations (`GET /quotations`) — server-paginated like
  /// the other converted lists. `status` rides in `extra`.
  Future<ApiResult<PagedResponse<Quotation>>> listPaged(
    PagedRequest request,
  ) => _api.getPaged(
    ApiEndpoints.quotations,
    queryParameters: request.toQuery(),
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
