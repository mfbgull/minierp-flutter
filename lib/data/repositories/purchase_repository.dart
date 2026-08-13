// Purchase repository — typed against docs/API.md §Direct Purchases and
// the server `purchaseController` shapes (PORTING.md §2).
//
// Envelope variants observed on the server:
// - `GET /purchases` → **bare array** of purchase rows (filters:
//   start_date, end_date, item_id, warehouse_id, supplier_name, limit)
// - `GET /purchases/:id` → **bare object** (same joined shape)
// - `GET /purchases/returns` → **bare array** of return rows (no
//   envelope, no pagination) — `Purchase.getReturnHistory`
// - `POST /purchases/:id/return` → **enveloped** `{success, message,
//   data: {returnedQuantity, totalCost}}`

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart' show dioProvider;
import '../../core/api/endpoints.dart' show ApiEndpoints;
import '../models/purchase.dart' show Purchase, PurchaseReturnResult;
import '../models/purchase_return.dart' show PurchaseReturn;
import 'api_result.dart';
import 'repository_client.dart';

class PurchaseRepository {
  PurchaseRepository(this._api);

  final RepositoryClient _api;

  /// Direct purchases — bare array (the endpoint has no search or page;
  /// the grid keeps sorting/filtering client-side like items).
  Future<ApiResult<List<Purchase>>> list() => _api.getRawList(
    ApiEndpoints.purchases,
    parseItem: (Object? json) =>
        Purchase.fromJson(json as Map<String, dynamic>),
  );

  /// Purchase detail — bare object (same joined shape as the list rows).
  Future<ApiResult<Purchase>> detail(int id) => _api.getRaw(
    '${ApiEndpoints.purchases}/$id',
    parse: (Object? json) => Purchase.fromJson(json as Map<String, dynamic>),
  );

  /// Record a direct purchase (`POST /purchases`). The server writes the
  /// purchase row, posts the stock movement, and returns the new
  /// purchase (bare object). [purchaseDate] is ISO `yyyy-MM-dd`.
  Future<ApiResult<Purchase>> create({
    required int itemId,
    required int warehouseId,
    required num quantity,
    required num unitCost,
    required String purchaseDate,
  }) => _api.post(
    ApiEndpoints.purchases,
    body: {
      'item_id': itemId,
      'warehouse_id': warehouseId,
      'quantity': quantity,
      'unit_cost': unitCost,
      'purchase_date': purchaseDate,
    },
    parse: (Object? json) => Purchase.fromJson(json as Map<String, dynamic>),
  );

  /// Purchase-return history — bare array (the endpoint has no search or
  /// page; the grid keeps sorting/filtering client-side like items).
  Future<ApiResult<List<PurchaseReturn>>> returns() => _api.getRawList(
    '${ApiEndpoints.purchases}/returns',
    parseItem: (Object? json) =>
        PurchaseReturn.fromJson(json as Map<String, dynamic>),
  );

  /// Process a return — enveloped `{success, message, data:
  /// {returnedQuantity, totalCost}}`. The server rejects (400) when the
  /// quantity is non-positive or exceeds the stock available in the
  /// purchase's batch.
  Future<ApiResult<PurchaseReturnResult>> processReturn(
    int id, {
    required num quantity,
    String? reason,
  }) => _api.post(
    '${ApiEndpoints.purchases}/$id/return',
    body: {
      'quantity': quantity,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    },
    parse: (Object? json) =>
        PurchaseReturnResult.fromJson(json as Map<String, dynamic>),
  );
}

final purchaseRepositoryProvider = Provider<PurchaseRepository>(
  (ref) => PurchaseRepository(RepositoryClient(ref.watch(dioProvider))),
);
