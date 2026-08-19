import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../preferences/preference_providers.dart' show initialRange;

import '../../core/utils/date_utils.dart' show isoDate;
import '../../data/models/customer.dart' show Customer;
import '../../data/models/invoice.dart' show Invoice;
import '../../data/models/item.dart' show Item;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/customer_repository.dart'
    show customerRepositoryProvider;
import '../../data/repositories/inventory_repository.dart'
    show inventoryRepositoryProvider;
import '../../data/repositories/invoice_repository.dart'
    show invoiceRepositoryProvider;
import '../../data/repositories/paged_request.dart'
    show PagedRequest, PagedResponse;

/// Server-side status filter for the invoices grid (`?status=Paid,...`).
/// null → all statuses (param omitted).
final invoicesStatusProvider = StateProvider<String?>((ref) => null);

/// Server-side search term (invoice no / customer name); empty omits the
/// param. The endpoint gained a `search` param (grid-pagination §5).
final invoicesSearchProvider = StateProvider<String>((ref) => '');

/// Server-side date-range filters (ISO strings, applied to
/// `invoice_date` via `start_date`/`end_date`).
final invoicesFromDateProvider = StateProvider<DateTime?>((ref) => initialRange(ref).from);
final invoicesToDateProvider = StateProvider<DateTime?>((ref) => initialRange(ref).to);

/// Current page (1-based) for the server-side pagination.
final invoicesPageProvider = StateProvider<int>((ref) => 1);

/// Rows per page; changing it resets to page 1 (the screen does that).
final invoicesLimitProvider = StateProvider<int>((ref) => 10);

/// Server-side sort — the API column name (from the server's
/// `INVOICE_SORT_COLUMNS` whitelist) plus the order.
class InvoiceSort {
  const InvoiceSort(this.column, this.order);

  final String column;

  /// `ASC` or `DESC`.
  final String order;
}

/// Active server-side sort; null = server default (invoice_date DESC).
final invoicesSortProvider = StateProvider<InvoiceSort?>((ref) => null);

/// One page of invoices — server-paginated like customers/suppliers
/// (`GET /invoices` returns a `pagination` block). Re-runs when any of
/// the paging/filter state changes; the screen invalidates it on
/// refresh.
final invoicesProvider = FutureProvider<PagedResponse<Invoice>>((ref) async {
  final status = ref.watch(invoicesStatusProvider);
  final search = ref.watch(invoicesSearchProvider);
  final from = ref.watch(invoicesFromDateProvider);
  final to = ref.watch(invoicesToDateProvider);
  final page = ref.watch(invoicesPageProvider);
  final limit = ref.watch(invoicesLimitProvider);
  final sort = ref.watch(invoicesSortProvider);

  final result = await ref.watch(invoiceRepositoryProvider).invoicesPaged(
    PagedRequest(
      page: page,
      limit: limit,
      search: search.isEmpty ? null : search,
      sortBy: sort?.column,
      sortOrder: sort?.order ?? 'ASC',
      // Endpoint-specific filters: status (CSV) + date range.
      extra: {
        'status': status == null || status.isEmpty ? null : status,
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

/// The full *filtered* invoice list (one large page) — the summary strip
/// and CSV export must total over every row matching the active
/// filters, not just the current page. Watches the same filters as
/// [invoicesProvider] but ignores page/limit/sort.
final filteredInvoicesProvider = FutureProvider<List<Invoice>>((ref) async {
  final status = ref.watch(invoicesStatusProvider);
  final search = ref.watch(invoicesSearchProvider);
  final from = ref.watch(invoicesFromDateProvider);
  final to = ref.watch(invoicesToDateProvider);

  final result = await ref.watch(invoiceRepositoryProvider).invoicesPaged(
    PagedRequest(
      page: 1,
      limit: 10000,
      search: search.isEmpty ? null : search,
      // Endpoint-specific filters: status (CSV) + date range.
      extra: {
        'status': status == null || status.isEmpty ? null : status,
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

/// All customers for the invoice form's customer select (the customers
/// endpoint paginates; the form needs the full list in one dropdown).
final invoiceCustomersProvider = FutureProvider<List<Customer>>((ref) async {
  final result = await ref
      .watch(customerRepositoryProvider)
      .list(const PagedRequest(page: 1, limit: 1000, sortBy: 'customer_name'));
  return switch (result) {
    ApiSuccess(:final data) => data.items,
    ApiFailure(:final error) => throw error,
  };
});

/// All active items for the invoice form's line-item selects. Uses the
/// repository directly (the shared `itemsProvider` is bound to the
/// inventory screen's search filter and paging state) — fetched as one
/// large page so the dropdown holds the full list.
final invoiceItemsProvider = FutureProvider<List<Item>>((ref) async {
  final result = await ref
      .watch(inventoryRepositoryProvider)
      .items(const PagedRequest(limit: 10000));
  return switch (result) {
    ApiSuccess(:final data) => data.items,
    ApiFailure(:final error) => throw error,
  };
});
