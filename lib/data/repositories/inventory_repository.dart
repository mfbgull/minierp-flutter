// Inventory repository — typed against docs/API.md §Inventory and the
// server `inventoryController` shapes (PORTING.md §2).
//
// Envelope variants observed on the server — note items are split:
// - `GET /inventory/items` → `{success, data: [Item], pagination}`
//   (server-paginated; filters: category, search, low_stock,
//   is_raw_material, is_finished_good)
// - `GET /inventory/items/:id` → **bare** `{...item, stock_by_warehouse}`
// - `POST/PUT /inventory/items(/:id)` → **bare** `Item`
// - `DELETE /inventory/items/:id` → `{success, message}`
// - `GET /inventory/items-categories` → bare `[{category}]`
// - `GET /inventory/items-low-stock` → bare `[Item]` (kept for external
//   consumers; the app routes through the paged `/items?low_stock=1`)
// - `GET /inventory/items-uom` → bare `[string]`
// - `GET /inventory/warehouses` → `{success, data: [Warehouse]}`
// - `GET /inventory/warehouses/:id` → **bare** `{...warehouse, stock_summary}`
// - `POST /inventory/warehouses` → **bare** `Warehouse` (201)
// - `PUT /inventory/warehouses/:id` → **bare** `Warehouse`
// - `DELETE /inventory/warehouses/:id` → `{success, message}`
// - `GET /inventory/stock-movements` → `{success, data: [...],
//   pagination}` (server-paginated, same contract as customers)
// - `POST /inventory/stock-movements` → bare `StockMovement` (201)
// - `GET /inventory/stock-summary` → bare `[{...}]`
// - `GET /inventory/stock-ledger/:itemId` → bare `[{...}]`
// - `GET /inventory/stock-balances` → `{success, data: [...], pagination}`
//   (server-paginated; filters: search, warehouse_code)
// - `GET /inventory/physical-counts` → `{success, data: [...], pagination}`
//   (server-paginated; filter: search)
// - `GET /inventory/physical-counts/:id` → `{...count, items}`
// - `POST /inventory/physical-counts` → **bare** `PhysicalCount` (201)
// - `POST /inventory/physical-counts/:id/items` → `PhysicalCountItem`
// - `POST /inventory/physical-counts/:id/complete` → `PhysicalCount`
// - `POST /inventory/physical-counts/:id/cancel` → `PhysicalCount`
// - `DELETE /inventory/physical-counts/:id` → `{success, message}`

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart' show ApiEndpoints;
import '../../core/cache/cached_repository.dart'
    show cachedRepositoryClientProvider;
import '../models/item.dart' show Item;
import '../models/physical_count.dart' show PhysicalCount, PhysicalCountItem;
import '../models/stock_batch.dart' show StockBatch;
import '../models/stock_balance.dart' show StockBalance;
import '../models/stock_movement.dart' show StockMovement;
import '../models/warehouse.dart' show Warehouse;
import 'api_result.dart';
import 'paged_request.dart';
import 'repository_client.dart';

/// One row of the `stock_by_warehouse` array on `GET /inventory/items/:id`.
class StockByWarehouse {
  const StockByWarehouse({
    required this.warehouseId,
    required this.warehouseCode,
    required this.warehouseName,
    required this.quantity,
  });

  factory StockByWarehouse.fromJson(Map<String, dynamic> json) =>
      StockByWarehouse(
        warehouseId: json['warehouse_id'] as int? ?? 0,
        warehouseCode: json['warehouse_code'] as String? ?? '',
        warehouseName: json['warehouse_name'] as String? ?? '',
        quantity: (json['quantity'] as num?) ?? 0,
      );

  final int warehouseId;
  final String warehouseCode;
  final String warehouseName;
  final num quantity;
}

/// Item detail — the bare `GET /inventory/items/:id` response: the item
/// plus its per-warehouse stock breakdown (the list `Item` has neither).
class ItemDetail {
  const ItemDetail({required this.item, required this.stockByWarehouse});

  factory ItemDetail.fromJson(Map<String, dynamic> json) {
    final raw = json['stock_by_warehouse'];
    return ItemDetail(
      item: Item.fromJson(json),
      stockByWarehouse: raw is List
          ? [
              for (final row in raw)
                if (row is Map<String, dynamic>) StockByWarehouse.fromJson(row),
            ]
          : const [],
    );
  }

  final Item item;
  final List<StockByWarehouse> stockByWarehouse;
}

/// A physical count's detail — the bare `GET /inventory/physical-counts/:id`
/// response: the count header plus its counted item lines (the list
/// `PhysicalCount` has only the header totals).
class PhysicalCountDetail {
  const PhysicalCountDetail({required this.count, required this.items});

  factory PhysicalCountDetail.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    return PhysicalCountDetail(
      count: PhysicalCount.fromJson(json),
      items: raw is List
          ? [
              for (final row in raw)
                if (row is Map<String, dynamic>)
                  PhysicalCountItem.fromJson(row),
            ]
          : const [],
    );
  }

  final PhysicalCount count;
  final List<PhysicalCountItem> items;
}

class InventoryRepository {
  InventoryRepository(this._api);

  final RepositoryClient _api;

  // --- Items (existing) ---

  /// One page of items — server-paginated (`GET /inventory/items` returns
  /// a `pagination` block; filters: category, search, low_stock,
  /// is_raw_material, is_finished_good). The low-stock toggle rides in
  /// `request.extra` as `low_stock=1`.
  Future<ApiResult<PagedResponse<Item>>> items(PagedRequest request) =>
      _api.getPaged(
        ApiEndpoints.items,
        queryParameters: request.toQuery(),
        parseItem: (Object? json) =>
            Item.fromJson(json as Map<String, dynamic>),
      );

  Future<ApiResult<Item>> item(int id) => _api.getRaw(
    '${ApiEndpoints.items}/$id',
    parse: (Object? json) => Item.fromJson(json as Map<String, dynamic>),
  );

  Future<ApiResult<ItemDetail>> itemDetail(int id) => _api.getRaw(
    '${ApiEndpoints.items}/$id',
    parse: (Object? json) => ItemDetail.fromJson(json as Map<String, dynamic>),
  );

  Future<ApiResult<Item>> create(Map<String, dynamic> body) => _api.postRaw(
    ApiEndpoints.items,
    body: body,
    parse: (Object? json) => Item.fromJson(json as Map<String, dynamic>),
  );

  Future<ApiResult<Item>> update(int id, Map<String, dynamic> body) =>
      _api.putRaw(
        '${ApiEndpoints.items}/$id',
        body: body,
        parse: (Object? json) => Item.fromJson(json as Map<String, dynamic>),
      );

  /// Soft delete (stamps `deleted_at`, deactivates). Reversible via
  /// [restore].
  Future<ApiResult<void>> delete(int id) =>
      _api.delete('${ApiEndpoints.items}/$id');

  /// `POST /inventory/items/:id/restore` — reverts a soft delete.
  Future<ApiResult<void>> restore(int id) => _api.post(
    '${ApiEndpoints.items}/$id/restore',
    parse: (_) {},
  );

  Future<ApiResult<List<String>>> categories() => _api.getRawList(
    ApiEndpoints.itemsCategories,
    parseItem: (Object? json) =>
        (json as Map<String, dynamic>)['category'] as String? ?? '',
  );

  Future<ApiResult<List<String>>> unitsOfMeasure() => _api.getRawList(
    ApiEndpoints.itemsUom,
    parseItem: (Object? json) => json?.toString() ?? '',
  );

  // --- Warehouses ---

  Future<ApiResult<List<Warehouse>>> warehouses() => _api.getList(
    ApiEndpoints.warehouses,
    parseItem: (Object? json) =>
        Warehouse.fromJson(json as Map<String, dynamic>),
  );

  Future<ApiResult<Warehouse>> warehouse(int id) => _api.getRaw(
    '${ApiEndpoints.warehouses}/$id',
    parse: (Object? json) => Warehouse.fromJson(json as Map<String, dynamic>),
  );

  Future<ApiResult<Warehouse>> createWarehouse(Map<String, dynamic> body) =>
      _api.postRaw(
        ApiEndpoints.warehouses,
        body: body,
        parse: (Object? json) =>
            Warehouse.fromJson(json as Map<String, dynamic>),
      );

  Future<ApiResult<Warehouse>> updateWarehouse(
    int id,
    Map<String, dynamic> body,
  ) => _api.putRaw(
    '${ApiEndpoints.warehouses}/$id',
    body: body,
    parse: (Object? json) => Warehouse.fromJson(json as Map<String, dynamic>),
  );

  Future<ApiResult<void>> deleteWarehouse(int id) =>
      _api.delete('${ApiEndpoints.warehouses}/$id');

  // --- Stock movements ---

  /// One page of stock movements — server-paginated like customers
  /// (`GET /inventory/stock-movements` returns a `pagination` block). The
  /// screen's movement-type filter rides along in `request.extra` as the
  /// `movement_type` query param; the endpoint also accepts
  /// date_from/date_to/item_id/search — not exposed yet.
  Future<ApiResult<PagedResponse<StockMovement>>> stockMovements(
    PagedRequest request,
  ) => _api.getPaged(
    ApiEndpoints.stockMovements,
    queryParameters: request.toQuery(),
    parseItem: (Object? json) =>
        StockMovement.fromJson(json as Map<String, dynamic>),
  );

  Future<ApiResult<StockMovement>> createStockMovement(
    Map<String, dynamic> body,
  ) => _api.postRaw(
    ApiEndpoints.stockMovements,
    body: body,
    parse: (Object? json) =>
        StockMovement.fromJson(json as Map<String, dynamic>),
  );

  Future<ApiResult<StockMovement>> stockMovement(int id) => _api.getRaw(
    '${ApiEndpoints.stockMovements}/$id',
    parse: (Object? json) =>
        StockMovement.fromJson(json as Map<String, dynamic>),
  );

  /// INV-02: atomic server-side two-warehouse transfer. One call replaces
  /// the old client-orchestrated OUT+IN movement pair; the server consumes
  /// FIFO layers at the source, mirrors a TRANSFER batch at the destination
  /// and writes both movements inside one transaction.
  Future<ApiResult<Map<String, dynamic>>> createStockTransfer(
    Map<String, dynamic> body,
  ) => _api.postRaw(
    ApiEndpoints.stockTransfers,
    body: body,
    parse: (Object? json) => (json ?? <String, dynamic>{}) as Map<String, dynamic>,
  );

  Future<ApiResult<List<dynamic>>> stockSummary() => _api.getRawList(
    ApiEndpoints.stockSummary,
    parseItem: (Object? json) => json,
  );

  /// One item's movement history (`GET /inventory/stock-ledger/:itemId` —
  /// bare array, newest-first by movement_date). The optional
  /// [warehouseId] narrows the ledger via the `warehouse_id` query param
  /// the endpoint already accepts. Each row is a `StockMovement`
  /// (warehouse join; no item join — the item fields are absent and
  /// parse as null).
  Future<ApiResult<List<StockMovement>>> stockLedger(
    int itemId, {
    int? warehouseId,
  }) => _api.getRawList(
    '${ApiEndpoints.stockLedger}/$itemId',
    queryParameters: warehouseId == null ? null : {'warehouse_id': warehouseId},
    parseItem: (Object? json) =>
        StockMovement.fromJson(json as Map<String, dynamic>),
  );

  /// One page of stock balances — server-paginated (`GET
  /// /inventory/stock-balances` returns a `pagination` block; filters:
  /// search, warehouse_code).
  Future<ApiResult<PagedResponse<StockBalance>>> stockBalances(
    PagedRequest request,
  ) => _api.getPaged(
    ApiEndpoints.stockBalances,
    queryParameters: request.toQuery(),
    parseItem: (Object? json) =>
        StockBalance.fromJson(json as Map<String, dynamic>),
  );

  // --- Physical counts ---

  /// One page of physical counts — server-paginated (`GET
  /// /inventory/physical-counts` returns a `pagination` block; filter:
  /// search).
  Future<ApiResult<PagedResponse<PhysicalCount>>> physicalCounts(
    PagedRequest request,
  ) => _api.getPaged(
    ApiEndpoints.physicalCounts,
    queryParameters: request.toQuery(),
    parseItem: (Object? json) =>
        PhysicalCount.fromJson(json as Map<String, dynamic>),
  );

  Future<ApiResult<PhysicalCountDetail>> physicalCountDetail(int id) =>
      _api.getRaw(
        '${ApiEndpoints.physicalCounts}/$id',
        parse: (Object? json) =>
            PhysicalCountDetail.fromJson(json as Map<String, dynamic>),
      );

  Future<ApiResult<PhysicalCount>> createPhysicalCount(
    Map<String, dynamic> body,
  ) => _api.postRaw(
    ApiEndpoints.physicalCounts,
    body: body,
    parse: (Object? json) =>
        PhysicalCount.fromJson(json as Map<String, dynamic>),
  );

  Future<ApiResult<PhysicalCountItem>> recordPhysicalCountItem(
    int countId,
    Map<String, dynamic> body,
  ) => _api.postRaw(
    '${ApiEndpoints.physicalCountItems}/$countId/items',
    body: body,
    parse: (Object? json) =>
        PhysicalCountItem.fromJson(json as Map<String, dynamic>),
  );

  Future<ApiResult<PhysicalCount>> completePhysicalCount(int countId) =>
      _api.postRaw(
        '${ApiEndpoints.physicalCountComplete}/$countId/complete',
        body: const {},
        parse: (Object? json) =>
            PhysicalCount.fromJson(json as Map<String, dynamic>),
      );

  Future<ApiResult<PhysicalCount>> cancelPhysicalCount(int countId) =>
      _api.postRaw(
        '${ApiEndpoints.physicalCountComplete}/$countId/cancel',
        body: const {},
        parse: (Object? json) =>
            PhysicalCount.fromJson(json as Map<String, dynamic>),
      );

  Future<ApiResult<void>> deletePhysicalCount(int id) =>
      _api.delete('${ApiEndpoints.physicalCounts}/$id');

  // --- Stock batches (item expiry tracking) ---

  /// List batches for an optional item/warehouse filter.
  /// `GET /inventory/stock-batches?item_id=&warehouse_id=`.
  Future<ApiResult<List<StockBatch>>> getBatches({
    int? itemId,
    int? warehouseId,
  }) => _api.getRawList(
    ApiEndpoints.stockBatches,
    queryParameters: {
      'item_id': ?itemId,
      'warehouse_id': ?warehouseId,
    },
    parseItem: (Object? json) =>
        StockBatch.fromJson(json as Map<String, dynamic>),
  );

  /// Patch a batch's expiry date (`PATCH /inventory/stock-batches/:id`).
  Future<ApiResult<void>> updateBatchExpiry(
    int batchId,
    String? expiryDate,
  ) => _api.patchRaw(
    '${ApiEndpoints.stockBatches}/$batchId',
    body: {'expiry_date': expiryDate},
    parse: (_) {},
  );

  /// Halt a batch with an optional reason
  /// (`PATCH /inventory/stock-batches/:id/halt`).
  Future<ApiResult<void>> haltBatch(
    int batchId, {
    String? reason,
  }) => _api.patchRaw(
    '${ApiEndpoints.stockBatches}/$batchId/halt',
    body: {if (reason != null && reason.isNotEmpty) 'halted_reason': reason},
    parse: (_) {},
  );

  /// Unhalt a batch (`PATCH /inventory/stock-batches/:id/unhalt`).
  Future<ApiResult<void>> unhaltBatch(int batchId) => _api.patchRaw(
    '${ApiEndpoints.stockBatches}/$batchId/unhalt',
    parse: (_) {},
  );
}

final inventoryRepositoryProvider = Provider<InventoryRepository>(
  (ref) => InventoryRepository(ref.watch(cachedRepositoryClientProvider)),
);
