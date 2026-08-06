import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/item.dart' show Item;
import '../../data/models/purchase_order.dart'
    show PurchaseOrder, PurchaseOrderDetail;
import '../../data/models/supplier.dart' show Supplier;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/inventory_repository.dart'
    show inventoryRepositoryProvider;
import '../../data/repositories/paged_request.dart' show PagedRequest;
import '../../data/repositories/purchase_order_repository.dart'
    show purchaseOrderRepositoryProvider;
import '../../data/repositories/supplier_repository.dart'
    show supplierRepositoryProvider;

/// All purchase orders (`GET /purchase-orders`, **bare array** — the
/// endpoint has no search/page params, so the grid keeps sorting/filtering
/// client-side like the items screen). The screen invalidates it on
/// refresh.
final purchaseOrdersProvider = FutureProvider<List<PurchaseOrder>>((ref) async {
  final result = await ref.watch(purchaseOrderRepositoryProvider).list();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// All suppliers for the PO form's supplier picker — the screen's
/// `suppliersProvider` only holds one page, so the form pulls a large
/// page directly (the endpoint caps the page size server-side).
final poSupplierOptionsProvider = FutureProvider<List<Supplier>>((ref) async {
  final result = await ref
      .watch(supplierRepositoryProvider)
      .list(const PagedRequest(limit: 500));
  return switch (result) {
    ApiSuccess(:final data) => data.items,
    ApiFailure(:final error) => throw error,
  };
});

/// All items for the PO form's line-item selects. Uses the repository
/// directly (the shared `itemsProvider` is bound to the inventory
/// screen's search filter).
final poItemsProvider = FutureProvider<List<Item>>((ref) async {
  final result = await ref.watch(inventoryRepositoryProvider).items();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// Detail for one PO (`GET /purchase-orders/:id`, bare object with the
/// `items` array). autoDispose: each dialog instance owns its fetch, so
/// closing it frees the state.
final purchaseOrderDetailProvider = FutureProvider.autoDispose
    .family<PurchaseOrderDetail, int>((ref, poId) async {
      final result = await ref
          .watch(purchaseOrderRepositoryProvider)
          .detail(poId);
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });
