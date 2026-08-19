import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/invoice.dart' show InvoicePaymentRecord;
import '../../data/models/item.dart' show Item;
import '../../data/models/purchase_order.dart'
    show GoodsReceipt, PurchaseOrder, PurchaseOrderDetail;
import '../../data/models/supplier.dart' show Supplier;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/inventory_repository.dart'
    show inventoryRepositoryProvider;
import '../../data/repositories/paged_request.dart'
    show PagedRequest, PagedResponse;
import '../../data/repositories/purchase_order_repository.dart'
    show purchaseOrderRepositoryProvider;
import '../../data/repositories/supplier_repository.dart'
    show supplierRepositoryProvider;

/// Server-side search term (PO no / supplier name); empty omits the
/// param. The endpoint gained a `search` param (grid-pagination §6).
final purchaseOrdersSearchProvider = StateProvider<String>((ref) => '');

/// Current page (1-based) for the server-side pagination.
final purchaseOrdersPageProvider = StateProvider<int>((ref) => 1);

/// Rows per page; changing it resets to page 1 (the screen does that).
final purchaseOrdersLimitProvider = StateProvider<int>((ref) => 10);

/// Server-side sort — the API column name (from the server's
/// `PURCHASE_ORDER_SORT_COLUMNS` whitelist) plus the order.
class PurchaseOrderSort {
  const PurchaseOrderSort(this.column, this.order);

  final String column;

  /// `ASC` or `DESC`.
  final String order;
}

/// Active server-side sort; null = server default (po_date DESC).
final purchaseOrdersSortProvider = StateProvider<PurchaseOrderSort?>((ref) => null);

/// One page of purchase orders — server-paginated like customers/suppliers
/// (`GET /purchase-orders` returns a `pagination` block). Re-runs when any
/// of the paging/filter state changes; the screen invalidates it on
/// refresh.
final purchaseOrdersProvider = FutureProvider<PagedResponse<PurchaseOrder>>((ref) async {
  final search = ref.watch(purchaseOrdersSearchProvider);
  final page = ref.watch(purchaseOrdersPageProvider);
  final limit = ref.watch(purchaseOrdersLimitProvider);
  final sort = ref.watch(purchaseOrdersSortProvider);

  final result = await ref.watch(purchaseOrderRepositoryProvider).listPaged(
    PagedRequest(
      page: page,
      limit: limit,
      search: search.isEmpty ? null : search,
      sortBy: sort?.column,
      sortOrder: sort?.order ?? 'ASC',
    ),
  );

  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// The full *filtered* PO list (one large page) — the CSV export must
/// run over every row matching the active filters, not just the current
/// page. Watches the same filters as [purchaseOrdersProvider] but ignores
/// page/limit/sort.
final filteredPurchaseOrdersProvider =
    FutureProvider<List<PurchaseOrder>>((ref) async {
      final search = ref.watch(purchaseOrdersSearchProvider);

      final result = await ref.watch(purchaseOrderRepositoryProvider).listPaged(
        PagedRequest(page: 1, limit: 10000, search: search.isEmpty ? null : search),
      );

      return switch (result) {
        ApiSuccess(:final data) => data.items,
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
/// screen's search filter and paging state) — fetched as one large
/// page so the dropdown holds the full list.
final poItemsProvider = FutureProvider<List<Item>>((ref) async {
  final result = await ref
      .watch(inventoryRepositoryProvider)
      .items(const PagedRequest(limit: 10000));
  return switch (result) {
    ApiSuccess(:final data) => data.items,
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

/// Payment history for one PO (`GET /purchase-orders/:id/payments`,
/// enveloped list). autoDispose: each dialog instance owns its fetch, so
/// closing it frees the state.
final purchaseOrderPaymentsProvider = FutureProvider.autoDispose
    .family<List<InvoicePaymentRecord>, int>((ref, poId) async {
      final result = await ref
          .watch(purchaseOrderRepositoryProvider)
          .payments(poId);
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

/// Goods-receipt history for one PO (`GET /purchase-orders/:id/receipts`,
/// bare array). autoDispose: each dialog instance owns its fetch, so
/// closing it frees the state.
final purchaseOrderReceiptsProvider = FutureProvider.autoDispose
    .family<List<GoodsReceipt>, int>((ref, poId) async {
      final result = await ref
          .watch(purchaseOrderRepositoryProvider)
          .receipts(poId);
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });
