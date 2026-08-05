import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/customer.dart' show Customer;
import '../../data/models/invoice.dart' show Invoice;
import '../../data/models/item.dart' show Item;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/customer_repository.dart'
    show customerRepositoryProvider;
import '../../data/repositories/inventory_repository.dart'
    show inventoryRepositoryProvider;
import '../../data/repositories/invoice_repository.dart'
    show InvoiceFilters, invoiceRepositoryProvider;
import '../../data/repositories/paged_request.dart' show PagedRequest;

/// Server-side status filter for the invoices grid (`?status=Paid,...`).
/// null → all statuses (param omitted).
final invoicesStatusProvider = StateProvider<String?>((ref) => null);

/// Client-side search term (invoice no / customer name) — the invoices
/// endpoint has no `search` param, so filtering happens in the screen.
final invoicesSearchProvider = StateProvider<String>((ref) => '');

/// Client-side date-range filters (ISO strings, applied to
/// `invoice_date`). The endpoint has no date params.
final invoicesFromDateProvider = StateProvider<DateTime?>((ref) => null);
final invoicesToDateProvider = StateProvider<DateTime?>((ref) => null);

/// Rows for the sales grid. Re-runs when the status filter changes; the
/// screen invalidates it on refresh. Search/date filtering happens
/// client-side in the screen (the endpoint has no search/date params).
final invoicesProvider = FutureProvider<List<Invoice>>((ref) async {
  final status = ref.watch(invoicesStatusProvider);
  final repo = ref.watch(invoiceRepositoryProvider);

  final result = await repo.invoices(
    filters: InvoiceFilters(status: status),
  );

  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// All customers for the invoice form's customer select (the customers
/// endpoint paginates; the form needs the full list in one dropdown).
final invoiceCustomersProvider = FutureProvider<List<Customer>>((ref) async {
  final result = await ref.watch(customerRepositoryProvider).list(
        const PagedRequest(
          page: 1,
          limit: 1000,
          sortBy: 'customer_name',
        ),
      );
  return switch (result) {
    ApiSuccess(:final data) => data.items,
    ApiFailure(:final error) => throw error,
  };
});

/// All active items for the invoice form's line-item selects. Uses the
/// repository directly (the shared `itemsProvider` is bound to the
/// inventory screen's search filter).
final invoiceItemsProvider = FutureProvider<List<Item>>((ref) async {
  final result = await ref.watch(inventoryRepositoryProvider).items();
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});
