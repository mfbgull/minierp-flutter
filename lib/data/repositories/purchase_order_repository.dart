// Purchase order repository — typed against docs/API.md §Purchase Orders
// and the server `purchaseOrderController` shapes (PORTING.md §2).
//
// Envelope variants observed on the server — note POs are **bare** except
// the list endpoint:
// - `GET /purchase-orders` → **enveloped + `pagination` block**
//   (server-paged since grid-pagination Phase 6; filters: supplier_id,
//   status, search, start_date, end_date, page, limit, sortBy,
//   sortOrder)
// - `GET /purchase-orders/:id` → bare `{...po, items}`

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart' show ApiEndpoints;
import '../models/invoice.dart' show InvoicePaymentRecord;
import '../models/json_helpers.dart' show asInt, asNum;
import '../models/purchase_order.dart'
    show GoodsReceipt, PurchaseOrder, PurchaseOrderDetail, PurchaseOrderItem;
import 'api_result.dart';
import 'paged_request.dart' show PagedRequest, PagedResponse;
import 'repository_client.dart';

class PurchaseOrderRepository {
  PurchaseOrderRepository(this._api);

  final RepositoryClient _api;

  /// All purchase orders — full list (the grid now uses [listPaged]; this
  /// stays for consumers that need the whole list in one fetch — the
  /// supplier detail POs tab / payment modal's allocation source, which
  /// filter by `supplier_id`).
  Future<ApiResult<List<PurchaseOrder>>> list({int? supplierId}) =>
      _api.getRawList(
        ApiEndpoints.purchaseOrders,
        queryParameters: supplierId == null
            ? null
            : {'supplier_id': supplierId},
        parseItem: (Object? json) =>
            PurchaseOrder.fromJson(json as Map<String, dynamic>),
      );

  /// One page of purchase orders (`GET /purchase-orders`) —
  /// server-paginated like the other converted lists. `status` rides in
  /// `extra`.
  Future<ApiResult<PagedResponse<PurchaseOrder>>> listPaged(
    PagedRequest request,
  ) => _api.getPaged(
    ApiEndpoints.purchaseOrders,
    queryParameters: request.toQuery(),
    parseItem: (Object? json) =>
        PurchaseOrder.fromJson(json as Map<String, dynamic>),
  );

  /// `GET /purchase-orders/summary/supplier/:supplierId` — **bare object**
  /// `POSummary` (`total_pos`, `total_value`, `draft_pos`, …). The server
  /// returns a zeroed summary when the supplier has no POs.
  ///
  /// [startDate]/[endDate] narrow the summary to POs whose `po_date`
  /// falls in the inclusive range (the purchase-order endpoint's own
  /// param names); null = lifetime summary (parameters omitted).
  Future<ApiResult<POSummary>> summaryBySupplier(
    int supplierId, {
    String? startDate,
    String? endDate,
  }) => _api.getRaw(
    '${ApiEndpoints.purchaseOrders}/summary/supplier/$supplierId',
    queryParameters: {'start_date': ?startDate, 'end_date': ?endDate},
    parse: (Object? json) =>
        POSummary.fromJson(json as Map<String, dynamic>),
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

  /// Payments allocated to this PO (`GET /purchase-orders/:id/payments`
  /// — enveloped list; each row is the payment header plus the per-PO
  /// allocation amount, newest first). Same row shape as the invoice
  /// payments endpoint, so it parses into [InvoicePaymentRecord].
  Future<ApiResult<List<InvoicePaymentRecord>>> payments(int poId) =>
      _api.getList(
        '${ApiEndpoints.purchaseOrders}/$poId/payments',
        parseItem: (Object? json) =>
            InvoicePaymentRecord.fromJson(json as Map<String, dynamic>),
      );

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
  (ref) => PurchaseOrderRepository(ref.watch(repositoryClientProvider)),
);

/// `GET /purchase-orders/summary/supplier/:supplierId` response DTO — the
/// web `POSummary` shape used by the supplier Overview tab.
class POSummary {
  const POSummary({
    required this.totalPos,
    required this.totalValue,
    required this.draftPos,
    required this.submittedPos,
    required this.partiallyReceivedPos,
    required this.completedPos,
  });

  factory POSummary.fromJson(Map<String, dynamic> json) => POSummary(
    totalPos: asInt(json['total_pos']) ?? 0,
    totalValue: asNum(json['total_value']) ?? 0,
    draftPos: asInt(json['draft_pos']) ?? 0,
    submittedPos: asInt(json['submitted_pos']) ?? 0,
    partiallyReceivedPos: asInt(json['partially_received_pos']) ?? 0,
    completedPos: asInt(json['completed_pos']) ?? 0,
  );

  final int totalPos;
  final num totalValue;
  final int draftPos;
  final int submittedPos;
  final int partiallyReceivedPos;
  final int completedPos;
}
