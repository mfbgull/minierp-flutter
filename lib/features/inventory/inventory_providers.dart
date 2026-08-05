import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/item.dart' show Item;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/inventory_repository.dart'
    show ItemDetail, inventoryRepositoryProvider;

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
final itemDetailProvider =
    FutureProvider.autoDispose.family<ItemDetail, int>((ref, itemId) async {
  final result =
      await ref.watch(inventoryRepositoryProvider).itemDetail(itemId);
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
