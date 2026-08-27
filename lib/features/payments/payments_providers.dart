import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/customer.dart' show Customer;
import '../../data/models/invoice.dart' show Invoice;
import '../../data/models/payment.dart' show Payment;
import '../../data/models/unified_payment.dart' show UnifiedPayment;
import '../../data/repositories/api_result.dart' show ApiFailure, ApiSuccess;
import '../../data/repositories/customer_repository.dart'
    show customerRepositoryProvider;
import '../../data/repositories/invoice_repository.dart'
    show InvoiceFilters, invoiceRepositoryProvider;
import '../../data/repositories/paged_request.dart'
    show PagedRequest, PagedResponse;
import '../../features/employees/employee_providers.dart'
    show employeeSalaryHistoryProvider;
import '../../features/expenses/expense_providers.dart' show expensesProvider;
import '../../features/owner_equity/owner_equity_providers.dart'
    show ownerCapitalProvider, ownerWithdrawalsProvider;

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

/// ---------------------------------------------------------------------------
/// Unified payment / cash-movement hub
/// ---------------------------------------------------------------------------

/// Type filter for the unified hub: `all` or one of the backend `type`
/// values (customer | supplier | expense | salary | owner_capital |
/// owner_withdrawal).
final unifiedPaymentsTypeFilterProvider = StateProvider<String>((ref) => 'all');

/// Server-side search term for the unified hub.
final unifiedPaymentsSearchProvider = StateProvider<String>((ref) => '');

/// Current page (1-based) for the unified hub's server-side pagination.
final unifiedPaymentsPageProvider = StateProvider<int>((ref) => 1);

/// Rows per page for the unified hub.
final unifiedPaymentsLimitProvider = StateProvider<int>((ref) => 10);

/// Active server-side sort for the unified hub; null = server default
/// (date DESC). Columns map to the backend whitelist: date | amount |
/// type | party | ref_no.
final unifiedPaymentsSortProvider = StateProvider<PaymentSort?>((ref) => null);

/// One page of the unified hub (`GET /payments/unified`) — server-paginated
/// like the legacy payments list, but across every payment-related source.
/// Re-runs when any paging/search/sort/type state changes; the screen and
/// the `New Payment` menu invalidate it after a write.
final unifiedPaymentsProvider =
    FutureProvider<PagedResponse<UnifiedPayment>>((ref) async {
  final search = ref.watch(unifiedPaymentsSearchProvider);
  final page = ref.watch(unifiedPaymentsPageProvider);
  final limit = ref.watch(unifiedPaymentsLimitProvider);
  final sort = ref.watch(unifiedPaymentsSortProvider);
  final type = ref.watch(unifiedPaymentsTypeFilterProvider);

  final result = await ref
      .watch(invoiceRepositoryProvider)
      .unifiedPayments(
        PagedRequest(
          page: page,
          limit: limit,
          search: search.isEmpty ? null : search,
          sortBy: sort?.column,
          sortOrder: sort?.order ?? 'DESC',
          extra: type != 'all' ? {'type': type} : null,
        ),
      );

  return switch (result) {
    ApiSuccess(:final data) => data,
    ApiFailure(:final error) => throw error,
  };
});

/// Refresh every list a cash movement could appear in, after a successful
/// write. Called only on success so cancel/error paths don't needlessly
/// refetch. [source] is the unified `source` of the recorded transaction.
void invalidateCashMovementProviders(WidgetRef ref, String source) {
  ref.invalidate(unifiedPaymentsProvider);
  ref.invalidate(paymentsProvider);
  switch (source) {
    case 'expense':
      ref.invalidate(expensesProvider);
    case 'salary':
      ref.invalidate(employeeSalaryHistoryProvider);
    case 'owner_capital':
      ref.invalidate(ownerCapitalProvider);
    case 'owner_withdrawal':
      ref.invalidate(ownerWithdrawalsProvider);
  }
}
