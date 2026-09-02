import 'package:flutter_riverpod/flutter_riverpod.dart';


import '../../core/utils/date_utils.dart' show isoDate;
import '../../data/models/customer.dart' show Customer;
import '../../data/models/sales_order.dart' show SalesOrder, SalesOrderDetail;
import '../../data/models/item.dart' show Item;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../preferences/preference_providers.dart' show initialRange;
import '../../data/repositories/customer_repository.dart'
    show customerRepositoryProvider;
import '../../data/repositories/inventory_repository.dart'
    show inventoryRepositoryProvider;
import '../../data/repositories/paged_request.dart'
    show PagedRequest, PagedResponse;
import '../../data/repositories/sales_order_repository.dart'
    show salesOrderRepositoryProvider;

/// Server-side status filter for the SO grid (raw status value). null →
/// all statuses (param omitted).
final salesOrdersStatusProvider = StateProvider<String?>((ref) => null);

/// Server-side search term (SO no / customer name); empty omits the
/// param. The endpoint gained a `search` param (grid-pagination §5).
final salesOrdersSearchProvider = StateProvider<String>((ref) => '');

/// Server-side date-range filters (ISO strings, applied to `so_date`
/// via `start_date`/`end_date`).
final salesOrdersFromDateProvider = StateProvider<DateTime?>((ref) => initialRange(ref).from);
final salesOrdersToDateProvider = StateProvider<DateTime?>((ref) => initialRange(ref).to);

/// Current page (1-based) for the server-side pagination.
final salesOrdersPageProvider = StateProvider<int>((ref) => 1);

/// Rows per page; changing it resets to page 1 (the screen does that).
final salesOrdersLimitProvider = StateProvider<int>((ref) => 10);

/// Server-side sort — the API column name (from the server's
/// `SALES_ORDER_SORT_COLUMNS` whitelist) plus the order.
class SalesOrderSort {
  const SalesOrderSort(this.column, this.order);

  final String column;

  /// `ASC` or `DESC`.
  final String order;
}

/// Active server-side sort; null = server default (so_date DESC).
final salesOrdersSortProvider = StateProvider<SalesOrderSort?>((ref) => null);

/// One page of sales orders — server-paginated like customers/suppliers
/// (`GET /sales-orders` returns a `pagination` block). Re-runs when any
/// of the paging/filter state changes; the screen invalidates it on
/// refresh.
final salesOrdersProvider = FutureProvider<PagedResponse<SalesOrder>>((ref) async {
  final status = ref.watch(salesOrdersStatusProvider);
  final search = ref.watch(salesOrdersSearchProvider);
  final from = ref.watch(salesOrdersFromDateProvider);
  final to = ref.watch(salesOrdersToDateProvider);
  final page = ref.watch(salesOrdersPageProvider);
  final limit = ref.watch(salesOrdersLimitProvider);
  final sort = ref.watch(salesOrdersSortProvider);

  final result = await ref.watch(salesOrderRepositoryProvider).listPaged(
    PagedRequest(
      page: page,
      limit: limit,
      search: search.isEmpty ? null : search,
      sortBy: sort?.column,
      sortOrder: sort?.order ?? 'ASC',
      // Endpoint-specific filter: status + date range.
      extra: {
        'status': ?status,
        'start_date': from == null ? null : isoDate(from),
        'end_date': to == null ? null : isoDate(to),
      },
    ),
  );

  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// The full *filtered* sales-order list (one large page) — the CSV
/// export must run over every row matching the active filters, not just
/// the current page. Watches the same filters as [salesOrdersProvider]
/// but ignores page/limit/sort.
final filteredSalesOrdersProvider =
    FutureProvider<List<SalesOrder>>((ref) async {
      final status = ref.watch(salesOrdersStatusProvider);
      final search = ref.watch(salesOrdersSearchProvider);
      final from = ref.watch(salesOrdersFromDateProvider);
      final to = ref.watch(salesOrdersToDateProvider);

      final result = await ref.watch(salesOrderRepositoryProvider).listPaged(
        PagedRequest(
          page: 1,
          limit: 10000,
          search: search.isEmpty ? null : search,
          // Endpoint-specific filter: status + date range.
          extra: {
            'status': ?status,
            'start_date': from == null ? null : isoDate(from),
            'end_date': to == null ? null : isoDate(to),
          },
        ),
      );

      return switch (result) {
        ApiSuccess(:final data) => data.items,
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
/// screen's search filter and paging state) — fetched as one large
/// page so the dropdown holds the full list.
final soItemsProvider = FutureProvider<List<Item>>((ref) async {
  final result = await ref
      .watch(inventoryRepositoryProvider)
      .items(const PagedRequest(limit: 10000));
  return switch (result) {
    ApiSuccess(:final data) => data.items,
    ApiFailure(:final error) => throw error,
  };
});
