// Purchase repository — typed against docs/API.md §Direct Purchases and
// the server `purchaseController` / `purchaseReturnController` shapes
// (PORTING.md §2).
//
// Envelope variants observed on the server:
// - `GET /purchases` → **enveloped + `pagination` block** (server-paged
//   since grid-pagination Phase 6; filters: start_date, end_date,
//   item_id, warehouse_id, supplier_name, search, page, limit, sortBy,
//   sortOrder)
// - `GET /purchases/:id` → **bare object** (same joined shape)
// - `GET /purchase-returns` → **enveloped + `pagination` block** —
//   `PurchaseReturnModel.getAll` (headers; filters: search, start_date,
//   end_date, type, status, warehouse_id)
// - `GET /purchase-returns/:id` → **bare object** (header + items)
// - `POST /purchase-returns` → **bare object** `PurchaseReturn` (header)
// - `POST /purchase-returns/:id/void` → **enveloped** `{success,
//   message, data: PurchaseReturn}`
//
// The old return endpoints (`POST /purchases/:id/return`,
// `POST /purchase-orders/:id/return-receipt`, `GET /purchases/returns`)
// were removed with the redesign (spec §7).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart' show ApiEndpoints;
import '../models/invoice.dart' show InvoicePaymentRecord;
import '../models/purchase.dart' show Purchase;
import '../models/purchase_return.dart' show PurchaseReturn;
import 'api_result.dart';
import 'paged_request.dart' show PagedRequest, PagedResponse;
import 'repository_client.dart';

class PurchaseRepository {
  PurchaseRepository(this._api);

  final RepositoryClient _api;

  /// Direct purchases — full list (the grid now uses [listPaged]; this
  /// stays for consumers that need the whole list in one fetch).
  Future<ApiResult<List<Purchase>>> list() => _api.getRawList(
    ApiEndpoints.purchases,
    parseItem: (Object? json) =>
        Purchase.fromJson(json as Map<String, dynamic>),
  );

  /// One page of direct purchases (`GET /purchases`) — server-paginated
  /// like the other converted lists. `supplier_name` rides in `extra`.
  Future<ApiResult<PagedResponse<Purchase>>> listPaged(PagedRequest request) =>
      _api.getPaged(
        ApiEndpoints.purchases,
        queryParameters: request.toQuery(),
        parseItem: (Object? json) =>
            Purchase.fromJson(json as Map<String, dynamic>),
      );

  /// Payments allocated to this purchase (`GET /purchases/:id/payments`
  /// — enveloped list; each row is the payment header plus the
  /// per-purchase allocation amount, newest first). Same row shape as
  /// the invoice payments endpoint, so it parses into
  /// [InvoicePaymentRecord].
  Future<ApiResult<List<InvoicePaymentRecord>>> payments(int purchaseId) =>
      _api.getList(
        '${ApiEndpoints.purchases}/$purchaseId/payments',
        parseItem: (Object? json) =>
            InvoicePaymentRecord.fromJson(json as Map<String, dynamic>),
      );

  /// Purchase detail — bare object (same joined shape as the list rows).
  Future<ApiResult<Purchase>> detail(int id) => _api.getRaw(
    '${ApiEndpoints.purchases}/$id',
    parse: (Object? json) => Purchase.fromJson(json as Map<String, dynamic>),
  );

  /// Record a direct purchase (`POST /purchases`). The server writes the
  /// purchase row, posts the stock movement, and returns the new
  /// purchase (bare object). [purchaseDate] is ISO `yyyy-MM-dd`;
  /// [supplierId] links the purchase to a supplier (the server resolves
  /// the name and posts the AP ledger entry).
  Future<ApiResult<Purchase>> create({
    required int itemId,
    required int warehouseId,
    required num quantity,
    required num unitCost,
    required String purchaseDate,
    int? supplierId,
    String? invoiceNo,
    String? remarks,
    String? expiryDate,
  }) => _api.post(
    ApiEndpoints.purchases,
    body: {
      'item_id': itemId,
      'warehouse_id': warehouseId,
      'quantity': quantity,
      'unit_cost': unitCost,
      'purchase_date': purchaseDate,
      'supplier_id': ?supplierId,
      if (invoiceNo != null && invoiceNo.trim().isNotEmpty)
        'invoice_no': invoiceNo.trim(),
      if (remarks != null && remarks.trim().isNotEmpty)
        'remarks': remarks.trim(),
      'expiry_date': ?expiryDate,
    },
    parse: (Object? json) => Purchase.fromJson(json as Map<String, dynamic>),
  );

  /// Record ONE purchase containing MULTIPLE items (`POST /purchases`
  /// with an `items` array). The server creates one `purchases` row per
  /// line — each with its own doc no, batch, movement, ledger and GL
  /// entries — atomically in one transaction, and returns the created
  /// rows as a **bare array** (order matches [items]). Header fields
  /// apply to every line.
  Future<ApiResult<List<Purchase>>> createMulti({
    required int warehouseId,
    required String purchaseDate,
    int? supplierId,
    String? invoiceNo,
    String? remarks,
    required List<({int itemId, num quantity, num unitCost, String? expiryDate})> items,
  }) => _api.postRaw<List<Purchase>>(
    ApiEndpoints.purchases,
    body: {
      'warehouse_id': warehouseId,
      'purchase_date': purchaseDate,
      'supplier_id': ?supplierId,
      if (invoiceNo != null && invoiceNo.trim().isNotEmpty)
        'invoice_no': invoiceNo.trim(),
      if (remarks != null && remarks.trim().isNotEmpty)
        'remarks': remarks.trim(),
      'items': [
        for (final line in items)
          {
            'item_id': line.itemId,
            'quantity': line.quantity,
            'unit_cost': line.unitCost,
            'expiry_date': ?line.expiryDate,
          },
      ],
    },
    parse: (Object? json) => [
      for (final row in json! as List<dynamic>)
        Purchase.fromJson(row as Map<String, dynamic>),
    ],
  );

  /// One page of purchase-return headers (`GET /purchase-returns`) —
  /// server-paginated like the other converted lists. Search and the
  /// optional date/status/type/warehouse filters ride in `request.extra`.
  Future<ApiResult<PagedResponse<PurchaseReturn>>> returnsPaged(
    PagedRequest request,
  ) => _api.getPaged(
    ApiEndpoints.purchaseReturns,
    queryParameters: request.toQuery(),
    parseItem: (Object? json) =>
        PurchaseReturn.fromJson(json as Map<String, dynamic>),
  );

  /// Create a return (`POST /purchase-returns`) — enveloped
  /// `{success, message, data: PurchaseReturn}`. [sourceType] is
  /// `PURCHASE` (sourceId = purchases.id) or `PURCHASE_ORDER` (sourceId =
  /// purchase_orders.id); each line's `sourceItemId` is `purchases.id`
  /// (direct purchase) or `purchase_order_items.id` (PO receipt) and its
  /// quantity must be positive and ≤ the line's remaining returnable qty.
  Future<ApiResult<PurchaseReturn>> createReturn({
    required String returnDate,
    required String sourceType,
    required int sourceId,
    required int warehouseId,
    String? reason,
    required List<({int sourceItemId, num quantity})> items,
  }) => _api.post(
    ApiEndpoints.purchaseReturns,
    body: {
      'return_date': returnDate,
      'source_type': sourceType,
      'source_id': sourceId,
      'warehouse_id': warehouseId,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      'items': [
        for (final line in items)
          {'source_item_id': line.sourceItemId, 'quantity': line.quantity},
      ],
    },
    parse: (Object? json) =>
        PurchaseReturn.fromJson(json as Map<String, dynamic>),
  );

  /// Return detail — bare object (header + embedded `items`).
  Future<ApiResult<PurchaseReturn>> returnDetail(int id) => _api.getRaw(
    '${ApiEndpoints.purchaseReturns}/$id',
    parse: (Object? json) =>
        PurchaseReturn.fromJson(json as Map<String, dynamic>),
  );

  /// Void a return — full reversal (stock + GL + credit note) —
  /// enveloped `{success, message, data: PurchaseReturn}`. The server
  /// rejects (400) when the return is not POSTED or already VOIDED.
  Future<ApiResult<PurchaseReturn>> voidReturn(
    int id, {
    required String reason,
  }) => _api.post(
    '${ApiEndpoints.purchaseReturns}/$id/void',
    body: {'reason': reason.trim()},
    parse: (Object? json) =>
        PurchaseReturn.fromJson(json as Map<String, dynamic>),
  );

  /// Void a direct purchase (PUR-03) — enveloped `{success, message}` with
  /// no data. The server rejects (400) when stock was already sold/returned
  /// or payments are recorded against the purchase.
  Future<ApiResult<void>> voidPurchase(
    int id, {
    required String reason,
  }) =>
      _api.postEnvelope<void>(
        '${ApiEndpoints.purchases}/$id/void',
        body: {'reason': reason.trim()},
        parse: (_) {},
      );
}

final purchaseRepositoryProvider = Provider<PurchaseRepository>(
  (ref) => PurchaseRepository(ref.watch(repositoryClientProvider)),
);
