import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/customer.dart' show Customer;
import '../../data/models/invoice.dart' show Invoice;
import '../../data/models/payment.dart' show Payment;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/customer_repository.dart'
    show customerRepositoryProvider;
import '../../data/repositories/invoice_repository.dart'
    show InvoiceFilters, invoiceRepositoryProvider;
import '../../data/repositories/paged_request.dart'
    show PagedRequest, PagedResponse;

/// Server-side sort — the API column name (from the server's
/// `PAYMENT_SORT_COLUMNS` whitelist) plus the order.
class PaymentSort {
  const PaymentSort(this.column, this.order);

  final String column;

  /// `ASC` or `DESC`.
  final String order;
}

/// Server-side search term; empty omits the param.
final paymentsSearchProvider = StateProvider<String>((ref) => '');

/// Current page (1-based) for the server-side pagination.
final paymentsPageProvider = StateProvider<int>((ref) => 1);

/// Rows per page; changing it resets to page 1 (the screen does that).
final paymentsLimitProvider = StateProvider<int>((ref) => 10);

/// Active server-side sort; null = server default (payment_date DESC).
final paymentsSortProvider = StateProvider<PaymentSort?>((ref) => null);

/// One page of payments — server-paginated like customers/suppliers
/// (`GET /payments` returns a `pagination` block; PORTING.md §2). Re-runs
/// when any paging state changes; the screen invalidates it after a
/// record/delete so the list refreshes.
final paymentsProvider = FutureProvider<PagedResponse<Payment>>((ref) async {
  final search = ref.watch(paymentsSearchProvider);
  final page = ref.watch(paymentsPageProvider);
  final limit = ref.watch(paymentsLimitProvider);
  final sort = ref.watch(paymentsSortProvider);

  final result = await ref
      .watch(invoiceRepositoryProvider)
      .payments(
        PagedRequest(
          page: page,
          limit: limit,
          search: search.isEmpty ? null : search,
          sortBy: sort?.column,
          sortOrder: sort?.order ?? 'DESC',
        ),
      );

  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// One payment (`GET /payments/:id`, enveloped object). autoDispose: each
/// dialog instance owns its fetch, so closing it frees the state.
final paymentDetailProvider = FutureProvider.autoDispose.family<Payment, int>((
  ref,
  paymentId,
) async {
  final result = await ref.watch(invoiceRepositoryProvider).payment(paymentId);
  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// All customers for the Record Payment customer picker — the screen's
/// `customersProvider` only holds one page, so the dialog pulls a large
/// page directly (the endpoint caps the page size server-side).
final paymentCustomerOptionsProvider = FutureProvider<List<Customer>>((
  ref,
) async {
  final result = await ref
      .watch(customerRepositoryProvider)
      .list(const PagedRequest(limit: 500));
  return switch (result) {
    ApiSuccess(:final data) => data.items,
    ApiFailure(:final error) => throw error,
  };
});

/// The selected customer's open (unpaid) invoices — `GET
/// /invoices?customer_id=…` filtered client-side to `balance_amount > 0`.
/// These are the lines the Record Payment dialog allocates against, each
/// capped at its remaining balance. autoDispose per selection.
final customerOpenInvoicesProvider = FutureProvider.autoDispose
    .family<List<Invoice>, int>((ref, customerId) async {
      final result = await ref
          .watch(invoiceRepositoryProvider)
          .invoices(filters: InvoiceFilters(customerId: customerId));
      return switch (result) {
        ApiSuccess(:final data) => [
          for (final invoice in data)
            if (invoice.balanceAmount > 0) invoice,
        ],
        ApiFailure(:final error) => throw error,
      };
    });
