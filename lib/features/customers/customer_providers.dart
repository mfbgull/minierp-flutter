import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/customer.dart' show Customer;
import '../../data/models/invoice.dart' show Invoice;
import '../../data/models/ledger_entry.dart' show LedgerEntry;
import '../../data/models/payment.dart' show Payment;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/customer_repository.dart'
    show CustomerStatement, customerRepositoryProvider;
import '../../data/repositories/invoice_repository.dart'
    show InvoiceFilters, invoiceRepositoryProvider;
import '../../data/repositories/paged_request.dart'
    show PagedRequest, PagedResponse;

/// Server-side sort — the API column name (from the server's
/// `CUSTOMER_SORT_COLUMNS` whitelist) plus the order.
class CustomerSort {
  const CustomerSort(this.column, this.order);

  final String column;

  /// `ASC` or `DESC`.
  final String order;
}

/// Server-side status filter (`?status=active` / `?status=inactive`);
/// null → all customers (param omitted). Mirrors the web customers
/// page's All/Active/Inactive tabs (the controller's `statusParam`).
final customersStatusProvider = StateProvider<String?>((ref) => null);

/// Server-side search term; empty omits the param.
final customersSearchProvider = StateProvider<String>((ref) => '');

/// Current page (1-based) for the server-side pagination.
final customersPageProvider = StateProvider<int>((ref) => 1);

/// Rows per page; changing it resets to page 1 (the screen does that).
final customersLimitProvider = StateProvider<int>((ref) => 10);

/// Active server-side sort; null = server default (customer_name ASC).
final customersSortProvider = StateProvider<CustomerSort?>((ref) => null);

/// One page of customers — the project's only server-paginated list
/// (PORTING.md §2: `page, limit, search, sortBy, sortOrder` on
/// `GET /customers`, which returns a `pagination` block). Re-runs when any
/// of the paging state changes; the screen invalidates it on refresh.
final customersProvider = FutureProvider<PagedResponse<Customer>>((ref) async {
  final search = ref.watch(customersSearchProvider);
  final page = ref.watch(customersPageProvider);
  final limit = ref.watch(customersLimitProvider);
  final sort = ref.watch(customersSortProvider);
  final status = ref.watch(customersStatusProvider);

  final result = await ref
      .watch(customerRepositoryProvider)
      .list(
        PagedRequest(
          page: page,
          limit: limit,
          search: search.isEmpty ? null : search,
          sortBy: sort?.column,
          sortOrder: sort?.order ?? 'ASC',
          // Endpoint-specific filter: the customers list endpoint accepts
          // `?status=active|inactive` (whitelisted server-side).
          extra: status == null ? null : {'status': status},
        ),
      );

  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// Detail for one customer (`GET /customers/:id`, bare object). autoDispose:
/// each detail page owns its fetch, so leaving it frees the state.
final customerDetailProvider = FutureProvider.autoDispose.family<Customer, int>(
  (ref, customerId) async {
    final result = await ref.watch(customerRepositoryProvider).get(customerId);
    return switch (result) {
      ApiSuccess(:final data) => data,
      ApiFailure(:final error) => throw error,
    };
  },
);

/// The customer's AR ledger (`GET /customers/:id/ledger`, enveloped array,
/// newest-first by transaction_date). autoDispose: each ledger UI owns
/// its fetch, so leaving it frees the state.
final customerLedgerProvider = FutureProvider.autoDispose
    .family<List<LedgerEntry>, int>((ref, customerId) async {
      final result = await ref
          .watch(customerRepositoryProvider)
          .ledger(customerId);
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

/// The customer's invoices (`GET /invoices?customer_id=<id>` — the server
/// accepts `customer_id`; the customer metrics use it). Full list.
/// autoDispose: owned by the detail page.
final customerInvoicesProvider = FutureProvider.autoDispose
    .family<List<Invoice>, int>((ref, customerId) async {
      final result = await ref.watch(invoiceRepositoryProvider).invoices(
        filters: InvoiceFilters(customerId: customerId),
      );
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

/// Paged fetch args for [customerInvoicesPagedProvider] — the family key
/// is the (customerId, page, limit) triple so each page owns its state.
class CustomerInvoicesArgs {
  const CustomerInvoicesArgs({
    required this.customerId,
    required this.page,
    required this.limit,
  });

  final int customerId;
  final int page;
  final int limit;

  @override
  bool operator ==(Object other) =>
      other is CustomerInvoicesArgs &&
      other.customerId == customerId &&
      other.page == page &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(customerId, page, limit);
}

/// Bumped by [invalidateCustomerQueries] so an open paged tab refetches
/// its current page after a mutation (the family key — page/limit — is
/// invisible to the mutating code).
final customerTabsVersionProvider = StateProvider<int>((ref) => 0);

/// One page of the customer's invoices (`GET /invoices?customer_id=<id>`
/// + `page`/`limit` — the endpoint is server-paginated). The Invoices
/// tab renders this with a [ServerPaginationBar].
final customerInvoicesPagedProvider = FutureProvider.autoDispose
    .family<PagedResponse<Invoice>, CustomerInvoicesArgs>((ref, args) async {
      ref.watch(customerTabsVersionProvider);
      final result = await ref.watch(invoiceRepositoryProvider).invoicesPaged(
        PagedRequest(
          page: args.page,
          limit: args.limit,
          extra: {'customer_id': args.customerId},
        ),
      );
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

/// The customer's payments (`GET /payments?customerId=<id>` — the web
/// Payments tab's query). Full list. autoDispose: owned by the detail page.
final customerPaymentsProvider = FutureProvider.autoDispose
    .family<List<Payment>, int>((ref, customerId) async {
      final result = await ref
          .watch(invoiceRepositoryProvider)
          .paymentsForCustomer(customerId);
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

/// Paged fetch args for [customerPaymentsPagedProvider].
class CustomerPaymentsArgs {
  const CustomerPaymentsArgs({
    required this.customerId,
    required this.page,
    required this.limit,
  });

  final int customerId;
  final int page;
  final int limit;

  @override
  bool operator ==(Object other) =>
      other is CustomerPaymentsArgs &&
      other.customerId == customerId &&
      other.page == page &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(customerId, page, limit);
}

/// One page of the customer's payments (`GET /payments?customerId=<id>`
/// + `page`/`limit` — server-paginated like the payments module; default
/// sort `payment_date DESC` matches the module). The Payments tab renders
/// this with a [ServerPaginationBar].
final customerPaymentsPagedProvider = FutureProvider.autoDispose
    .family<PagedResponse<Payment>, CustomerPaymentsArgs>((ref, args) async {
      ref.watch(customerTabsVersionProvider);
      final result = await ref.watch(invoiceRepositoryProvider).payments(
        PagedRequest(
          page: args.page,
          limit: args.limit,
          sortOrder: 'DESC',
          extra: {'customerId': args.customerId},
        ),
      );
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

/// Statement fetch arguments — the family key (customer id + date range).
class CustomerStatementArgs {
  const CustomerStatementArgs({
    required this.customerId,
    required this.fromDate,
    required this.toDate,
  });

  final int customerId;
  final String fromDate;
  final String toDate;

  @override
  bool operator ==(Object other) =>
      other is CustomerStatementArgs &&
      other.customerId == customerId &&
      other.fromDate == fromDate &&
      other.toDate == toDate;

  @override
  int get hashCode => Object.hash(customerId, fromDate, toDate);
}

/// Bumped by [invalidateCustomerQueries] so an open Statement tab refetches
/// after a payment/invoice mutation (the statement's own key — the date
/// range — is invisible to the mutating code).
final customerStatementVersionProvider = StateProvider<int>((ref) => 0);

/// One customer statement (`GET /customers/:id/statement?fromDate&toDate`).
/// autoDispose: owned by the Statement tab.
final customerStatementProvider = FutureProvider.autoDispose
    .family<CustomerStatement, CustomerStatementArgs>((ref, args) async {
      ref.watch(customerStatementVersionProvider);
      final result = await ref.watch(customerRepositoryProvider).statement(
        args.customerId,
        fromDate: args.fromDate,
        toDate: args.toDate,
      );
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

/// Invalidates every customer-scoped query after a mutation (record/edit/
/// delete payment, delete/cancel invoice), so every detail tab refetches.
/// The mutating tabs additionally invalidate the global payments/invoices
/// lists themselves.
void invalidateCustomerQueries(WidgetRef ref, int customerId) {
  ref.invalidate(customerDetailProvider(customerId));
  ref.invalidate(customerLedgerProvider(customerId));
  ref.invalidate(customerInvoicesProvider(customerId));
  ref.invalidate(customerPaymentsProvider(customerId));
  // The paged tab providers watch this version, so the page the user is
  // currently on refetches after any mutation.
  ref.read(customerTabsVersionProvider.notifier).state++;
  ref.read(customerStatementVersionProvider.notifier).state++;
}
