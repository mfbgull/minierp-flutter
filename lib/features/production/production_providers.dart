// Production module providers — BOMs + productions over the bare
// endpoints (PORTING.md §5 `/bom`, `/production`). List providers are
// plain FutureProviders (no pagination anywhere in the production
// API); detail providers are autoDispose families owned by their
// dialogs. Item options are fetched from the inventory repository so
// the forms can filter by role (finished goods vs raw materials).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/bom.dart';
import '../../data/models/item.dart' show Item;
import '../../data/models/production.dart';
import '../../data/models/warehouse.dart' show Warehouse;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/inventory_repository.dart'
    show inventoryRepositoryProvider;
import '../../data/repositories/production_repository.dart'
    show productionRepositoryProvider;

/// All BOMs (`GET /boms`, bare array). The screen invalidates it on
/// refresh; the BOM form/detail dialogs invalidate it after writes.
/// Client-side search term for the BOM grid (no search param — the
/// screen filters the loaded rows).
final bomsSearchProvider = StateProvider<String>((ref) => '');

final bomsProvider = FutureProvider<List<Bom>>((ref) async {
  final result = await ref.watch(productionRepositoryProvider).boms();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// Detail for one BOM (`GET /boms/:id`, bare object with `items`).
/// autoDispose: each dialog instance owns its fetch.
final bomDetailProvider = FutureProvider.autoDispose.family<BomDetail, int>((
  ref,
  bomId,
) async {
  final result = await ref.watch(productionRepositoryProvider).bom(bomId);
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// All production runs (`GET /productions`, bare array, newest first).
final productionsProvider = FutureProvider<List<Production>>((ref) async {
  final result = await ref.watch(productionRepositoryProvider).productions();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// Detail for one production run (`GET /productions/:id`, bare object
/// with `inputs`). autoDispose: owned by the detail dialog.
final productionDetailProvider = FutureProvider.autoDispose
    .family<Production, int>((ref, productionId) async {
      final result = await ref
          .watch(productionRepositoryProvider)
          .production(productionId);
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

/// Finished goods for the BOM/production output pickers — the server
/// filters `GET /inventory/items?is_finished_good=1`. When that list
/// is empty (a DB without the flag set) the form falls back to every
/// item so a production can still be recorded.
final productionOutputItemsProvider = FutureProvider<List<Item>>((ref) async {
  final repo = ref.watch(inventoryRepositoryProvider);
  final result = await repo.items(isFinishedGood: true);
  return switch (result) {
    ApiSuccess(:final data) =>
      data.isEmpty ? await ref.read(productionAllItemsProvider.future) : data,
    ApiFailure(:final error) => throw error,
  };
});

/// Every item, for the BOM material pickers and the fallback above.
/// The material list must not be filtered — BOMs can consume raw
/// materials, components or semi-finished goods alike.
final productionAllItemsProvider = FutureProvider<List<Item>>((ref) async {
  final result = await ref.watch(inventoryRepositoryProvider).items();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// Warehouses for the production form (finished-goods + raw-materials
/// pickers) — shares the inventory module's provider.
final productionWarehousesProvider = FutureProvider<List<Warehouse>>((
  ref,
) async {
  final result = await ref.watch(inventoryRepositoryProvider).warehouses();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});
