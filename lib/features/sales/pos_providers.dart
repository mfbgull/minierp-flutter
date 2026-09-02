// POS providers — Riverpod state for the POS catalog, cart, and sale
// history. The catalog (items + warehouses) is read from the inventory
// endpoints so the POS screen shares one source of truth with the rest
// of the app; only the sale commit and transaction history are POS-specific.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/inventory_repository.dart'
    show inventoryRepositoryProvider;
import '../../data/repositories/paged_request.dart' show PagedRequest;
import 'pos_models.dart';
import 'pos_repository.dart';

// ── Catalog ────────────────────────────────────────────────────────────────

/// Sellable items for the POS catalog — active, non-raw-material items
/// with a standard selling price, fetched once per screen visit.
final posCatalogProvider = FutureProvider<List<PosItem>>((ref) async {
  final result = await ref
      .watch(inventoryRepositoryProvider)
      .items(const PagedRequest(limit: 10000));
  return switch (result) {
    ApiSuccess(:final data) => data.items
        .where((i) =>
            i.isActive &&
            !i.isRawMaterial &&
            (i.standardSellingPrice ?? 0) > 0)
        .map((i) => PosItem(
              id: i.id,
              itemCode: i.itemCode,
              itemName: i.itemName,
              unitOfMeasure: i.unitOfMeasure,
              standardSellingPrice: i.standardSellingPrice,
              currentStock: i.currentStock.toInt(),
              category: i.category,
            ))
        .toList(),
    ApiFailure(:final error) => throw error,
  };
});

/// Warehouses selectable on the POS screen — all active warehouses.
final posWarehousesProvider = FutureProvider<List<PosWarehouse>>(
  (ref) async {
    final result = await ref.watch(inventoryRepositoryProvider).warehouses();
    return switch (result) {
      ApiSuccess(:final data) => data
          .where((w) => w.isActive)
          .map((w) => PosWarehouse(
                id: w.id,
                warehouseCode: w.warehouseCode,
                warehouseName: w.warehouseName,
              ))
          .toList(),
      ApiFailure(:final error) => throw error,
    };
  },
);

// ── Cart state ──────────────────────────────────────────────────────────────

/// The POS shopping cart — a list of [PosCartItem]. Null-safe: an empty
/// list means "no items yet", never null.
final posCartProvider =
    StateProvider<List<PosCartItem>>((ref) => const []);

/// The selected warehouse (null until the user picks one).
final posWarehouseProvider = StateProvider<int?>((ref) => null);

/// The sale date for the current transaction (defaults to today).
final posSaleDateProvider = StateProvider<DateTime?>((ref) => null);

/// Cash received by the customer (the amount tendered).
final posCashReceivedProvider = StateProvider<double>((ref) => 0);

/// Customer name override (defaults to the walk-in customer on the server).
final posCustomerNameProvider = StateProvider<String>((ref) => '');

/// Whether the sale commit is in flight.
final posSubmittingProvider = StateProvider<bool>((ref) => false);

/// The last completed sale (for the receipt/print flow).
final posLastSaleProvider = StateProvider<PosSale?>((ref) => null);

// ── Transaction history ─────────────────────────────────────────────────────

/// Recent POS sales — `GET /api/pos/transactions`.
final posTransactionsProvider =
    FutureProvider<List<PosTransaction>>((ref) async {
  final repo = ref.watch(posRepositoryProvider);
  final result = await repo.listTransactions();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});
