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
import '../models/purchase_order.dart'
    show GoodsReceipt, PurchaseOrder, PurchaseOrderDetail, PurchaseOrderItem;
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

  /// Create — bare 201 PO response (`{...po, items}`); the body carries
  /// the header plus the `items` array ({item_id, quantity, unit_price}).
  Future<ApiResult<PurchaseOrder>> create(Map<String, dynamic> body) =>
      _api.postRaw(
        ApiEndpoints.purchaseOrders,
        body: body,
        parse: (Object? json) =>
            PurchaseOrder.fromJson(json as Map<String, dynamic>),
      );

  /// Update the PO header — bare updated PO. The server accepts only
  /// header fields here (items go through the item routes below).
  Future<ApiResult<PurchaseOrder>> updateHeader(
    int id,
    Map<String, dynamic> body,
  ) => _api.putRaw(
    '${ApiEndpoints.purchaseOrders}/$id',
    body: body,
    parse: (Object? json) =>
        PurchaseOrder.fromJson(json as Map<String, dynamic>),
  );

  /// Add a line item — bare 201 `purchase_order_items` row.
  Future<ApiResult<PurchaseOrderItem>> addItem(
    int poId,
    Map<String, dynamic> body,
  ) => _api.postRaw(
    '${ApiEndpoints.purchaseOrders}/$poId/items',
    body: body,
    parse: (Object? json) =>
        PurchaseOrderItem.fromJson(json as Map<String, dynamic>),
  );

  /// Update a line item's quantity/unit price — bare updated row.
  Future<ApiResult<PurchaseOrderItem>> updateItem(
    int poId,
    int itemId,
    Map<String, dynamic> body,
  ) => _api.putRaw(
    '${ApiEndpoints.purchaseOrders}/$poId/items/$itemId',
    body: body,
    parse: (Object? json) =>
        PurchaseOrderItem.fromJson(json as Map<String, dynamic>),
  );

  /// Remove a line item — bare `{success, message}` (deleteRaw ignores
  /// the body).
  Future<ApiResult<void>> removeItem(int poId, int itemId) =>
      _api.deleteRaw('${ApiEndpoints.purchaseOrders}/$poId/items/$itemId');

  /// Transition the PO's workflow status — bare updated PO. The server
  /// enforces the valid transitions (Draft → Submitted / Cancelled, …)
  /// and posts the AP supplier-ledger entry on Submit.
  Future<ApiResult<PurchaseOrder>> updateStatus(int id, String status) =>
      _api.postRaw(
        '${ApiEndpoints.purchaseOrders}/$id/status',
        body: {'status': status},
        parse: (Object? json) =>
            PurchaseOrder.fromJson(json as Map<String, dynamic>),
      );

  /// Delete a Draft PO — enveloped `{success, message}`. The server only
  /// allows Draft deletions (and cascades the line items).
  Future<ApiResult<void>> deletePo(int id) =>
      _api.delete('${ApiEndpoints.purchaseOrders}/$id');

  /// Goods-receipt history for a PO — **bare array** of `GoodsReceipt`
  /// (receipt_no, date, warehouse, per-receipt qty/value aggregates).
  Future<ApiResult<List<GoodsReceipt>>> receipts(int poId) =>
      _api.getRawList(
        '${ApiEndpoints.purchaseOrders}/$poId/receipts',
        parseItem: (Object? json) =>
            GoodsReceipt.fromJson(json as Map<String, dynamic>),
      );

  /// Record a goods receipt — **bare 201** `GoodsReceipt`. The body is
  /// `{receipt_date, warehouse_id, remarks?, items: [{po_item_id,
  /// received_quantity}]}`; the server validates each quantity against
  /// the line's pending balance, posts the stock movement, and updates
  /// the PO status (Partially Received / Completed) itself.
  Future<ApiResult<GoodsReceipt>> createReceipt(
    int poId,
    Map<String, dynamic> body,
  ) => _api.postRaw(
    '${ApiEndpoints.purchaseOrders}/$poId/receipts',
    body: body,
    parse: (Object? json) =>
        GoodsReceipt.fromJson(json as Map<String, dynamic>),
  );
}

final purchaseOrderRepositoryProvider = Provider<PurchaseOrderRepository>(
  (ref) => PurchaseOrderRepository(RepositoryClient(ref.watch(dioProvider))),
);
