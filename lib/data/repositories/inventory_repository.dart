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

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart' show dioProvider;
import '../../core/api/endpoints.dart' show ApiEndpoints;
import '../models/item.dart' show Item;
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
    // Tolerant like the rest of the models: a missing/malformed breakdown
    // degrades to an empty list instead of throwing (the list endpoints
    // surface parse errors as failures; here the item itself is the core).
    final raw = json['stock_by_warehouse'];
    return ItemDetail(
      item: Item.fromJson(json),
      stockByWarehouse: raw is List
          ? [
              for (final row in raw)
                if (row is Map<String, dynamic>)
                  StockByWarehouse.fromJson(row),
            ]
          : const [],
    );
  }

  final Item item;
  final List<StockByWarehouse> stockByWarehouse;
}

class InventoryRepository {
  InventoryRepository(this._api);

  final RepositoryClient _api;

  /// All active items; supports the server's category/search/flag filters.
  Future<ApiResult<List<Item>>> items({
    String? category,
    String? search,
    bool? isRawMaterial,
    bool? isFinishedGood,
  }) =>
      _api.getList(
        ApiEndpoints.items,
        queryParameters: {
          if (category != null && category.isNotEmpty) 'category': category,
          if (search != null && search.isNotEmpty) 'search': search,
          'is_raw_material': ?isRawMaterial,
          'is_finished_good': ?isFinishedGood,
        },
        parseItem: (Object? json) => Item.fromJson(json as Map<String, dynamic>),
      );

  /// Item detail — bare response; the extra `stock_by_warehouse` array is
  /// ignored by the tolerant `Item.fromJson`.
  Future<ApiResult<Item>> item(int id) => _api.getRaw(
        '${ApiEndpoints.items}/$id',
        parse: (Object? json) => Item.fromJson(json as Map<String, dynamic>),
      );

  /// Item detail including the per-warehouse stock breakdown.
  Future<ApiResult<ItemDetail>> itemDetail(int id) => _api.getRaw(
        '${ApiEndpoints.items}/$id',
        parse: (Object? json) =>
            ItemDetail.fromJson(json as Map<String, dynamic>),
      );

  /// Bare-object create (`item_code` must be unique; body uses
  /// snake_case API keys).
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

  /// Soft delete; fails server-side if the item still has stock.
  Future<ApiResult<void>> delete(int id) =>
      _api.delete('${ApiEndpoints.items}/$id');

  /// Distinct item categories — bare `[{category}]` rows.
  Future<ApiResult<List<String>>> categories() => _api.getRawList(
        ApiEndpoints.itemsCategories,
        parseItem: (Object? json) =>
            (json as Map<String, dynamic>)['category'] as String? ?? '',
      );

  /// Distinct units of measure (standard list + in-use values) — bare
  /// array of strings.
  Future<ApiResult<List<String>>> unitsOfMeasure() => _api.getRawList(
        ApiEndpoints.itemsUom,
        parseItem: (Object? json) => json?.toString() ?? '',
      );

  /// Items below reorder level — bare `[Item]`.
  Future<ApiResult<List<Item>>> lowStock() => _api.getRawList(
        ApiEndpoints.itemsLowStock,
        parseItem: (Object? json) => Item.fromJson(json as Map<String, dynamic>),
      );
}

final inventoryRepositoryProvider = Provider<InventoryRepository>(
  (ref) => InventoryRepository(RepositoryClient(ref.watch(dioProvider))),
);
