import 'package:flutter_riverpod/flutter_riverpod.dart';


import '../../core/utils/date_utils.dart' show isoDate;
import '../../data/models/invoice.dart' show Invoice;
import '../../data/models/sales_return.dart' show SalesReturn;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../preferences/preference_providers.dart' show initialRange;
import '../../data/repositories/invoice_repository.dart'
    show invoiceRepositoryProvider;
import '../../data/repositories/paged_request.dart'
    show PagedRequest, PagedResponse;

/// Server-side search term (return no / item / customer); empty omits
/// the param. The endpoint gained a `search` param (grid-pagination §5).
final invoiceReturnsSearchProvider = StateProvider<String>((ref) => '');

/// Server-side warehouse filter for the returns grid (warehouse name).
/// null → all warehouses (param omitted).
final invoiceReturnsWarehouseProvider = StateProvider<String?>((ref) => null);

/// Server-side date-range filters (ISO strings, applied to
/// `return_date` via `start_date`/`end_date`).
final invoiceReturnsFromDateProvider = StateProvider<DateTime?>((ref) => initialRange(ref).from);
final invoiceReturnsToDateProvider = StateProvider<DateTime?>((ref) => initialRange(ref).to);

/// Current page (1-based) for the server-side pagination.
final invoiceReturnsPageProvider = StateProvider<int>((ref) => 1);

/// Rows per page; changing it resets to page 1 (the screen does that).
final invoiceReturnsLimitProvider = StateProvider<int>((ref) => 10);

/// Server-side sort — the API column name (from the server's
/// `INVOICE_RETURN_SORT_COLUMNS` whitelist) plus the order.
class InvoiceReturnSort {
  const InvoiceReturnSort(this.column, this.order);

  final String column;

  /// `ASC` or `DESC`.
  final String order;
}

/// Active server-side sort; null = server default (return_date DESC).
final invoiceReturnsSortProvider = StateProvider<InvoiceReturnSort?>((ref) => null);

/// One page of invoice-return history (`GET /invoices/returns` returns a
/// `pagination` block since grid-pagination §5). Re-runs when any of the
/// paging/filter state changes; the screen invalidates it on refresh and
/// the process-return dialog invalidates it after a successful POST so a
/// new return appears immediately.
final invoiceReturnsProvider =
    FutureProvider<PagedResponse<SalesReturn>>((ref) async {
      final search = ref.watch(invoiceReturnsSearchProvider);
      final warehouse = ref.watch(invoiceReturnsWarehouseProvider);
      final from = ref.watch(invoiceReturnsFromDateProvider);
      final to = ref.watch(invoiceReturnsToDateProvider);
      final page = ref.watch(invoiceReturnsPageProvider);
      final limit = ref.watch(invoiceReturnsLimitProvider);
      final sort = ref.watch(invoiceReturnsSortProvider);

      final result = await ref
          .watch(invoiceRepositoryProvider)
          .returnsPaged(
            PagedRequest(
              page: page,
              limit: limit,
              search: search.isEmpty ? null : search,
              sortBy: sort?.column,
              sortOrder: sort?.order ?? 'ASC',
              // Endpoint-specific filters: warehouse + date range.
              extra: {
                'warehouse_name': ?warehouse,
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

/// The full *filtered* return list (one large page) — the CSV export must
/// run over every row matching the active filters, not just the current
/// page. Watches the same filters as [invoiceReturnsProvider] but ignores
/// page/limit/sort.
final filteredInvoiceReturnsProvider =
    FutureProvider<List<SalesReturn>>((ref) async {
      final search = ref.watch(invoiceReturnsSearchProvider);
      final warehouse = ref.watch(invoiceReturnsWarehouseProvider);
      final from = ref.watch(invoiceReturnsFromDateProvider);
      final to = ref.watch(invoiceReturnsToDateProvider);

      final result = await ref
          .watch(invoiceRepositoryProvider)
          .returnsPaged(
            PagedRequest(
              page: 1,
              limit: 10000,
              search: search.isEmpty ? null : search,
              // Endpoint-specific filters: warehouse + date range.
              extra: {
                'warehouse_name': ?warehouse,
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

/// All invoices for the Process Return picker (unfiltered — returns are
/// created against an invoice, so the picker lists every invoice the
/// user can return against).
final invoiceReturnPickerProvider = FutureProvider<List<Invoice>>((ref) async {
  final result = await ref.watch(invoiceRepositoryProvider).invoices();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});
