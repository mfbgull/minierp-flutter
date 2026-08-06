// Inventory repository — typed against docs/API.md §Inventory and the
// server `inventoryController` shapes (PORTING.md §2).
//
// Envelope variants observed on the server — note items are split:
// - `GET /inventory/items` → `{success, data: [Item]}` (no pagination;
//   filters: category, search, is_raw_material, is_finished_good)
// - `GET /inventory/items/:id` → **bare** `{...item, stock_by_warehouse}`
// - `POST/PUT /inventory/items(/:id)` → **bare** `Item`
// - `DELETE /inventory/items/:id` → `{success, message}`
// - `GET /inventory/items-categories` → bare `[{category}]`
// - `GET /inventory/items-low-stock` → bare `[Item]`
// - `GET /inventory/items-uom` → bare `[string]`
// - `GET /inventory/warehouses` → `{success, data: [Warehouse]}`
// - `GET /inventory/warehouses/:id` → **bare** `{...warehouse, stock_summary}`
// - `POST /inventory/warehouses` → **bare** `Warehouse` (201)
// - `PUT /inventory/warehouses/:id` → **bare** `Warehouse`
// - `DELETE /inventory/warehouses/:id` → `{success, message}`
// - `GET /inventory/stock-movements` → bare `[StockMovement]`
// - `POST /inventory/stock-movements` → bare `StockMovement` (201)
// - `GET /inventory/stock-summary` → bare `[{...}]`
// - `GET /inventory/stock-ledger/:itemId` → bare `[{...}]`
// - `GET /inventory/stock-balances` → bare `[StockBalance]`
// - `GET /inventory/physical-counts` → `{success, data: [PhysicalCount]}`
// - `GET /inventory/physical-counts/:id` → `{...count, items}`
// - `POST /inventory/physical-counts` → **bare** `PhysicalCount` (201)
// - `POST /inventory/physical-counts/:id/items` → `PhysicalCountItem`
// - `POST /inventory/physical-counts/:id/complete` → `PhysicalCount`
// - `POST /inventory/physical-counts/:id/cancel` → `PhysicalCount`
// - `DELETE /inventory/physical-counts/:id` → `{success, message}`

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart' show dioProvider;
import '../../core/api/endpoints.dart' show ApiEndpoints;
import '../models/item.dart' show Item;
import '../models/physical_count.dart' show PhysicalCount, PhysicalCountItem;
import '../models/stock_balance.dart' show StockBalance;
import '../models/stock_movement.dart' show StockMovement;
import '../models/warehouse.dart' show Warehouse;
import 'api_result.dart';
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

  Future<ApiResult<List<Item>>> items({
    String? category,
    String? search,
    bool? isRawMaterial,
    bool? isFinishedGood,
  }) => _api.getList(
    ApiEndpoints.items,
    queryParameters: {
      if (category != null && category.isNotEmpty) 'category': category,
      if (search != null && search.isNotEmpty) 'search': search,
      'is_raw_material': ?isRawMaterial,
      'is_finished_good': ?isFinishedGood,
    },
    parseItem: (Object? json) => Item.fromJson(json as Map<String, dynamic>),
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

  Future<ApiResult<void>> delete(int id) =>
      _api.delete('${ApiEndpoints.items}/$id');

  Future<ApiResult<List<String>>> categories() => _api.getRawList(
    ApiEndpoints.itemsCategories,
    parseItem: (Object? json) =>
        (json as Map<String, dynamic>)['category'] as String? ?? '',
  );

  Future<ApiResult<List<String>>> unitsOfMeasure() => _api.getRawList(
    ApiEndpoints.itemsUom,
    parseItem: (Object? json) => json?.toString() ?? '',
  );

  Future<ApiResult<List<Item>>> lowStock() => _api.getRawList(
    ApiEndpoints.itemsLowStock,
    parseItem: (Object? json) => Item.fromJson(json as Map<String, dynamic>),
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

  /// List stock movements, optionally filtered by `movement_type` (the
  /// endpoint also accepts date_from/date_to/item_id — not exposed yet).
  Future<ApiResult<List<StockMovement>>> stockMovements({
    String? movementType,
  }) => _api.getRawList(
    ApiEndpoints.stockMovements,
    queryParameters: {
      if (movementType != null && movementType.isNotEmpty)
        'movement_type': movementType,
    },
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

  Future<ApiResult<List<StockBalance>>> stockBalances() => _api.getRawList(
    ApiEndpoints.stockBalances,
    parseItem: (Object? json) =>
        StockBalance.fromJson(json as Map<String, dynamic>),
  );

  // --- Physical counts ---

  Future<ApiResult<List<PhysicalCount>>> physicalCounts() => _api.getList(
    ApiEndpoints.physicalCounts,
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
}

final inventoryRepositoryProvider = Provider<InventoryRepository>(
  (ref) => InventoryRepository(RepositoryClient(ref.watch(dioProvider))),
);
