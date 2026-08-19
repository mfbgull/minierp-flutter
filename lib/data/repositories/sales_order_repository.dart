// Sales order repository — typed against docs/API.md §Sales Orders and
// the server `salesController` shapes (PORTING.md §2).
//
// Envelope variants observed on the server — note sales orders are
// **bare**, like purchase orders:
// - `GET /sales-orders` → bare `[SalesOrder]` (no envelope, no
//   pagination; filters: status, customer_id, customer_name, start_date,
//   end_date, warehouse_id, source_type, limit)
// - `GET /sales-orders/:id` → bare `{...so, items}`
// - `POST /sales-orders/:id/cancel` → bare updated SO
// - `DELETE /sales-orders/:id` → bare `{message}` (deleteRaw ignores the
//   body)

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart' show dioProvider;
import '../../core/api/endpoints.dart' show ApiEndpoints;
import '../models/sales_order.dart' show SalesOrder, SalesOrderDetail;
import 'api_result.dart';
import 'paged_request.dart' show PagedRequest, PagedResponse;
import 'repository_client.dart';

class SalesOrderRepository {
  SalesOrderRepository(this._api);

  final RepositoryClient _api;

  /// All sales orders — full list (the grid now uses [listPaged]; this
  /// stays for any consumer that needs the whole list in one fetch).
  Future<ApiResult<List<SalesOrder>>> list({
    Map<String, dynamic>? queryParameters,
  }) => _api.getRawList(
    ApiEndpoints.salesOrders,
    queryParameters: queryParameters,
    parseItem: (Object? json) =>
        SalesOrder.fromJson(json as Map<String, dynamic>),
  );

  /// One page of sales orders (`GET /sales-orders`) — server-paginated
  /// like the other converted lists. `status` rides in `extra`.
  Future<ApiResult<PagedResponse<SalesOrder>>> listPaged(
    PagedRequest request,
  ) => _api.getPaged(
    ApiEndpoints.salesOrders,
    queryParameters: request.toQuery(),
    parseItem: (Object? json) =>
        SalesOrder.fromJson(json as Map<String, dynamic>),
  );

  /// SO detail — bare `{...so, items}` response.
  Future<ApiResult<SalesOrderDetail>> detail(int id) => _api.getRaw(
    '${ApiEndpoints.salesOrders}/$id',
    parse: (Object? json) =>
        SalesOrderDetail.fromJson(json as Map<String, dynamic>),
  );

  /// Create — bare 201 SO response (`{...so, items}`); the body carries
  /// the header plus the `items` array ({item_id, quantity, unit_price}).
  Future<ApiResult<SalesOrder>> create(Map<String, dynamic> body) =>
      _api.postRaw(
        ApiEndpoints.salesOrders,
        body: body,
        parse: (Object? json) =>
            SalesOrder.fromJson(json as Map<String, dynamic>),
      );

  /// Update the SO header + items — bare updated SO.
  Future<ApiResult<SalesOrder>> update(int id, Map<String, dynamic> body) =>
      _api.putRaw(
        '${ApiEndpoints.salesOrders}/$id',
        body: body,
        parse: (Object? json) =>
            SalesOrder.fromJson(json as Map<String, dynamic>),
      );

  /// Cancel an SO — enveloped `{success, message, invoiceId?, invoiceNo?}`
  /// (the server reverses any linked-invoice stock for Invoiced/Completed
  /// orders and rejects an already-Cancelled order).
  Future<ApiResult<void>> cancel(int id) => _api.post(
    '${ApiEndpoints.salesOrders}/$id/cancel',
    parse: (_) {}, // no data payload
  );

  /// Delete — bare `{message}` body (deleteRaw ignores the body).
  Future<ApiResult<void>> delete(int id) =>
      _api.deleteRaw('${ApiEndpoints.salesOrders}/$id');
}

final salesOrderRepositoryProvider = Provider<SalesOrderRepository>(
  (ref) => SalesOrderRepository(RepositoryClient(ref.watch(dioProvider))),
);
