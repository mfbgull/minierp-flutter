import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/customer.dart' show Customer;
import '../../data/models/sales_order.dart' show SalesOrder, SalesOrderDetail;
import '../../data/models/item.dart' show Item;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/customer_repository.dart'
    show customerRepositoryProvider;
import '../../data/repositories/inventory_repository.dart'
    show inventoryRepositoryProvider;
import '../../data/repositories/paged_request.dart' show PagedRequest;
import '../../data/repositories/sales_order_repository.dart'
    show salesOrderRepositoryProvider;

/// Client-side status filter for the SO grid (raw status value). null →
/// all statuses.
final salesOrdersStatusProvider = StateProvider<String?>((ref) => null);

/// Client-side search term (SO no / customer name) — the sales-orders
/// endpoint has no `search` param, so filtering happens in the screen.
final salesOrdersSearchProvider = StateProvider<String>((ref) => '');

/// Client-side date-range filters (ISO strings, applied to `so_date`).
/// The endpoint has no date params.
final salesOrdersFromDateProvider = StateProvider<DateTime?>((ref) => null);
final salesOrdersToDateProvider = StateProvider<DateTime?>((ref) => null);

/// All sales orders (`GET /sales-orders`, **bare array** — the endpoint
/// has no search/page params, so the grid keeps sorting/filtering
/// client-side like the items screen). The screen invalidates it on
/// refresh.
final salesOrdersProvider = FutureProvider<List<SalesOrder>>((ref) async {
  final result = await ref.watch(salesOrderRepositoryProvider).list();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// Detail for one SO (`GET /sales-orders/:id`, bare object with the
/// `items` array). autoDispose: each dialog instance owns its fetch, so
/// closing it frees the state.
final salesOrderDetailProvider = FutureProvider.autoDispose
    .family<SalesOrderDetail, int>((ref, soId) async {
      final result = await ref.watch(salesOrderRepositoryProvider).detail(soId);
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

/// All customers for the SO form's customer picker (the customers
/// endpoint paginates; the form needs the full list in one dropdown —
/// same pattern as the invoice form's `invoiceCustomersProvider`).
final salesOrderCustomerOptionsProvider = FutureProvider<List<Customer>>((
  ref,
) async {
  final result = await ref
      .watch(customerRepositoryProvider)
      .list(const PagedRequest(page: 1, limit: 1000, sortBy: 'customer_name'));
  return switch (result) {
    ApiSuccess(:final data) => data.items,
    ApiFailure(:final error) => throw error,
  };
});

/// All items for the SO form's line-item selects. Uses the repository
/// directly (the shared `itemsProvider` is bound to the inventory
/// screen's search filter).
final soItemsProvider = FutureProvider<List<Item>>((ref) async {
  final result = await ref.watch(inventoryRepositoryProvider).items();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});
