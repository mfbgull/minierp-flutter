// Purchase order repository — typed against docs/API.md §Purchase Orders
// and the server `purchaseOrderController` shapes (PORTING.md §2).
//
// Envelope variants observed on the server — note POs are **bare**:
// - `GET /purchase-orders` → bare `[PurchaseOrder]` (no envelope, no
//   pagination; filters: supplier_id, status, start_date, end_date,
//   limit)
// - `GET /purchase-orders/:id` → bare `{...po, items}`

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart' show dioProvider;
import '../../core/api/endpoints.dart' show ApiEndpoints;
import '../models/purchase_order.dart' show PurchaseOrder, PurchaseOrderDetail;
import 'api_result.dart';
import 'repository_client.dart';

class PurchaseOrderRepository {
  PurchaseOrderRepository(this._api);

  final RepositoryClient _api;

  /// All purchase orders — bare array (the list endpoint has no search or
  /// page; the grid keeps sorting/filtering client-side like items).
  Future<ApiResult<List<PurchaseOrder>>> list() => _api.getRawList(
    ApiEndpoints.purchaseOrders,
    parseItem: (Object? json) =>
        PurchaseOrder.fromJson(json as Map<String, dynamic>),
  );

  /// PO detail — bare `{...po, items}` response.
  Future<ApiResult<PurchaseOrderDetail>> detail(int id) => _api.getRaw(
    '${ApiEndpoints.purchaseOrders}/$id',
    parse: (Object? json) =>
        PurchaseOrderDetail.fromJson(json as Map<String, dynamic>),
  );
}

final purchaseOrderRepositoryProvider = Provider<PurchaseOrderRepository>(
  (ref) => PurchaseOrderRepository(RepositoryClient(ref.watch(dioProvider))),
);
