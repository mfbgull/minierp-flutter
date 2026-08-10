import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/item.dart' show Item;
import '../../data/models/physical_count.dart' show PhysicalCount;
import '../../data/models/stock_balance.dart' show StockBalance;
import '../../data/models/stock_movement.dart' show StockMovement;
import '../../data/models/warehouse.dart' show Warehouse;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/inventory_repository.dart'
    show ItemDetail, PhysicalCountDetail, inventoryRepositoryProvider;

/// Server-side search term for the items grid (PORTING.md §2: list
/// endpoints accept `search`; the items endpoint filters code/name/desc).
/// Updated with a debounce by the screen; an empty value omits the param.
final itemsSearchProvider = StateProvider<String>((ref) => '');

/// When true, only items at/below their reorder level are shown, backed by
/// the server's `GET /inventory/items-low-stock` endpoint (bare `[Item]`).
final itemsLowStockOnlyProvider = StateProvider<bool>((ref) => false);

/// Rows for the inventory grid. Re-runs when the search term or the
/// low-stock toggle changes; the screen invalidates it on refresh.
final itemsProvider = FutureProvider<List<Item>>((ref) async {
  final lowStockOnly = ref.watch(itemsLowStockOnlyProvider);
  final search = ref.watch(itemsSearchProvider);
  final repo = ref.watch(inventoryRepositoryProvider);

  final result = lowStockOnly
      ? await repo.lowStock()
      : await repo.items(search: search.isEmpty ? null : search);

  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// Detail for one item (`GET /inventory/items/:id`, bare object with the
/// `stock_by_warehouse` breakdown). autoDispose: each dialog instance
/// owns its fetch, so closing it frees the state.
final itemDetailProvider = FutureProvider.autoDispose.family<ItemDetail, int>((
  ref,
  itemId,
) async {
  final result = await ref
      .watch(inventoryRepositoryProvider)
      .itemDetail(itemId);
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// Existing categories for the item form's dropdown
/// (`GET /inventory/items-categories`, bare `[{category}]`).
final itemCategoriesProvider = FutureProvider<List<String>>((ref) async {
  final result = await ref.watch(inventoryRepositoryProvider).categories();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// Units of measure for the item form's dropdown
/// (`GET /inventory/items-uom`, bare `[string]`).
final itemUomsProvider = FutureProvider<List<String>>((ref) async {
  final result = await ref.watch(inventoryRepositoryProvider).unitsOfMeasure();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

// --- Warehouse providers ---

final warehousesProvider = FutureProvider<List<Warehouse>>((ref) async {
  final result = await ref.watch(inventoryRepositoryProvider).warehouses();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

final warehouseSearchProvider = StateProvider<String>((ref) => '');

final warehousesSearchFilteredProvider = Provider<List<Warehouse>>((ref) {
  final warehouses = ref.watch(warehousesProvider);
  final term = ref.watch(warehouseSearchProvider).toLowerCase().trim();

  return switch (warehouses) {
    AsyncData(:final value) when term.isEmpty => value,
    AsyncData(:final value) => value.where((w) {
      final q = term;
      return w.warehouseCode.toLowerCase().contains(q) ||
          (w.warehouseName ?? '').toLowerCase().contains(q) ||
          (w.location ?? '').toLowerCase().contains(q);
    }).toList(),
    _ => const <Warehouse>[],
  };
});

// --- Stock movement providers ---

/// A single stock movement's detail (`GET /inventory/stock-movements/:id`:
/// bare joined movement). autoDispose: owned by the movement detail dialog,
/// so every open refetches fresh data.
final stockMovementDetailProvider = FutureProvider.autoDispose
    .family<StockMovement, int>((ref, movementId) async {
      final result = await ref
          .watch(inventoryRepositoryProvider)
          .stockMovement(movementId);
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

/// Selected movement-type filter for the movements tab (null = all).
final movementTypeFilterProvider = StateProvider<String?>((ref) => null);

/// Stock movements list, keyed by the movement-type filter (null = all).
/// Changing the filter refetches `GET /inventory/stock-movements` with the
/// `movement_type` query param.
final stockMovementsProvider =
    FutureProvider.family<List<StockMovement>, String?>((ref, type) async {
      final repo = ref.watch(inventoryRepositoryProvider);
      final result = await repo.stockMovements(movementType: type);
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

// --- Stock balance providers ---

/// Client-side search term for the stock-balances grid (no search param
/// on the endpoint — the screen filters the loaded rows).
final stockBalancesSearchProvider = StateProvider<String>((ref) => '');

final stockBalancesProvider = FutureProvider<List<StockBalance>>((ref) async {
  final repo = ref.watch(inventoryRepositoryProvider);
  final result = await repo.stockBalances();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// One item's stock ledger (`GET /inventory/stock-ledger/:itemId` — its
/// movement history newest-first, warehouse join only). Keyed on
/// `(itemId, warehouseId)` — a null warehouseId = all warehouses. The
/// dialog owns the filter in local state, so each open refetches fresh.
final stockLedgerProvider = FutureProvider.autoDispose
    .family<List<StockMovement>, (int, int?)>((ref, key) async {
      final (itemId, warehouseId) = key;
      final repo = ref.watch(inventoryRepositoryProvider);
      final result = await repo.stockLedger(itemId, warehouseId: warehouseId);
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

// --- Physical count providers ---

/// Client-side search term for the physical-counts grid (no search
/// param — the screen filters the loaded rows).
final physicalCountsSearchProvider = StateProvider<String>((ref) => '');

final physicalCountsProvider = FutureProvider<List<PhysicalCount>>((ref) async {
  final result = await ref.watch(inventoryRepositoryProvider).physicalCounts();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// A single physical count's detail (`GET /inventory/physical-counts/:id`:
/// header + item lines). autoDispose: owned by the detail dialog.
final physicalCountDetailProvider = FutureProvider.autoDispose
    .family<PhysicalCountDetail, int>((ref, countId) async {
      final result = await ref
          .watch(inventoryRepositoryProvider)
          .physicalCountDetail(countId);
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });
