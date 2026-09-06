import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart' show isoDate;
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
import '../reports/report_providers.dart'
    show
        globalReportFromDateProvider,
        globalReportToDateProvider,
        setGlobalReportRange;

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
/// newest-first by transaction_date) — **full history, no date filter**.
/// autoDispose: each ledger UI owns its fetch, so leaving it frees the
/// state.
///
/// This deliberately stays an unfiltered int-keyed feed: the detail
/// quick-stats and Overview consume it and must never re-key to the page
/// range (standing metrics stay lifetime — spec D2/D14). The date-ranged
/// ledger the Ledger tab shows is [customerLedgerRangedProvider].
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

/// Ranged-ledger fetch args — the family key. The effective range is part
/// of the identity so one range's rows can never render under another
/// (spec §9). Null dates = full history (parameters omitted).
class CustomerLedgerArgs {
  const CustomerLedgerArgs({
    required this.customerId,
    this.fromDate,
    this.toDate,
  });

  final int customerId;

  /// Optional inclusive range (ISO `YYYY-MM-DD`), sent as `fromDate` /
  /// `toDate` (the ledger endpoint's names — spec §14 Rule 4).
  final String? fromDate;
  final String? toDate;

  @override
  bool operator ==(Object other) =>
      other is CustomerLedgerArgs &&
      other.customerId == customerId &&
      other.fromDate == fromDate &&
      other.toDate == toDate;

  @override
  int get hashCode => Object.hash(customerId, fromDate, toDate);
}

/// Bumped by [invalidateCustomerQueries] so the open Ledger tab refetches
/// its current range after a mutation (the ranged key — dates — is
/// invisible to the mutating code).
final customerLedgerVersionProvider = StateProvider<int>((ref) => 0);

/// The date-ranged AR ledger (`GET /customers/:id/ledger?fromDate&toDate`;
/// the Ledger tab's feed under the unified detail-page range). autoDispose:
/// owned by the Ledger tab.
final customerLedgerRangedProvider = FutureProvider.autoDispose
    .family<List<LedgerEntry>, CustomerLedgerArgs>((ref, args) async {
      ref.watch(customerLedgerVersionProvider);
      final result = await ref.watch(customerRepositoryProvider).ledger(
        args.customerId,
        fromDate: args.fromDate,
        toDate: args.toDate,
      );
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
/// is the (customerId, page, limit, range) tuple so each page owns its
/// state and the effective range is part of the identity (a range change
/// is therefore a new provider key, never a stale cached page —
/// unified-detail-date-picker-spec §9).
class CustomerInvoicesArgs {
  const CustomerInvoicesArgs({
    required this.customerId,
    required this.page,
    required this.limit,
    this.fromDate,
    this.toDate,
  });

  final int customerId;
  final int page;
  final int limit;

  /// Optional inclusive range (ISO `YYYY-MM-DD`) sent as the invoice
  /// endpoint's own parameter names (`start_date`/`end_date` — spec
  /// §14 Rule 4). Null = no date filter.
  final String? fromDate;
  final String? toDate;

  @override
  bool operator ==(Object other) =>
      other is CustomerInvoicesArgs &&
      other.customerId == customerId &&
      other.page == page &&
      other.limit == limit &&
      other.fromDate == fromDate &&
      other.toDate == toDate;

  @override
  int get hashCode => Object.hash(customerId, page, limit, fromDate, toDate);
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
          // PagedRequest.toQuery omits null extras, so a null range sends
          // no date parameters (spec §5.3: never empty strings / "null").
          extra: {
            'customer_id': args.customerId,
            'start_date': args.fromDate,
            'end_date': args.toDate,
          },
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
    this.fromDate,
    this.toDate,
  });

  final int customerId;
  final int page;
  final int limit;

  /// Optional inclusive range (ISO `YYYY-MM-DD`) sent as the payments
  /// endpoint's own parameter names (`fromDate`/`toDate` — spec §14
  /// Rule 4). Null = no date filter; nulls are omitted by
  /// [PagedRequest.toQuery].
  final String? fromDate;
  final String? toDate;

  @override
  bool operator ==(Object other) =>
      other is CustomerPaymentsArgs &&
      other.customerId == customerId &&
      other.page == page &&
      other.limit == limit &&
      other.fromDate == fromDate &&
      other.toDate == toDate;

  @override
  int get hashCode => Object.hash(customerId, page, limit, fromDate, toDate);
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
          // Payments route schema allows fromDate/toDate (dateRange); nulls
          // are omitted (spec §5.3).
          extra: {
            'customerId': args.customerId,
            'fromDate': args.fromDate,
            'toDate': args.toDate,
          },
        ),
      );
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

/// Statement fetch arguments — the family key (customer id + date range).
/// Null [fromDate]/[toDate] = full-history statement (both date
/// parameters omitted — spec §6.5; the server returns the complete
/// statement with opening 0 after the Phase-2 fix).
class CustomerStatementArgs {
  const CustomerStatementArgs({
    required this.customerId,
    this.fromDate,
    this.toDate,
  });

  final int customerId;

  /// Optional inclusive range (ISO `YYYY-MM-DD`).
  final String? fromDate;
  final String? toDate;

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

// ── Detail-page unified date range (unified-detail-date-picker-spec) ──
//
// The customer detail page owns ONE date range that drives every data tab
// (spec D1/§4). The range is scoped to a detail-page *instance* via a
// session id (§3.1): two customers open at once (or a stack of detail
// pages) each keep their own pair, so one page's local "All dates" can
// never leak into another (§13 matrix). Family keys are `int` session ids
// handed out by [nextCustomerDetailSession] — the detail screen asks for
// one when its State is created.

int _customerDetailSessionSeq = 0;

/// A fresh, stable session id for one customer detail-page instance.
/// Each opened page gets its own id, so its range state is page-scoped.
int nextCustomerDetailSession() => ++_customerDetailSessionSeq;

/// From/to of the detail page's unified range (spec §4.2.1): seeded ONCE,
/// at first read, from the current app-wide global range (ref.read — not
/// ref.watch — so an already-open page keeps its snapshot and never
/// live-follows a dashboard range change; a newly opened page's fresh
/// session seeds from the then-current global value, §3.2/§13).
///
/// Two providers rather than one state object (§3.1 Option B): the shared
/// [DateRangeFilter] writes an explicit `StateProvider<DateTime?>` pair
/// and always commits both sides together, so a half-range state cannot be
/// produced through the picker. Ranged commits are synchronized to the
/// global range by [commitCustomerDetailRange]; "All dates" (null/null)
/// stays local to the page instance (§3.3).
final customerDetailFromDateProvider =
    StateProvider.family<DateTime?, int>((ref, sessionId) {
      return ref.read(globalReportFromDateProvider);
    });
final customerDetailToDateProvider =
    StateProvider.family<DateTime?, int>((ref, sessionId) {
      return ref.read(globalReportToDateProvider);
    });

/// The detail page's single range-commit rule (spec §3.3, Rule 3) — the
/// pill's `onChanged` after ANY picker action (preset / custom range /
/// arrows / All dates / clear) has written the session pair:
///
/// - a complete ranged pair also becomes the app-wide range (dashboard +
///   every report screen follow — D4),
/// - "All dates" (null/null) never touches the global range (D5/D8),
/// - a half range is unreachable through the picker and asserted away.
void commitCustomerDetailRange(WidgetRef ref, int sessionId) {
  final from = ref.read(customerDetailFromDateProvider(sessionId));
  final to = ref.read(customerDetailToDateProvider(sessionId));
  assert(
    (from == null) == (to == null),
    'customer detail range must be complete (both or neither set)',
  );
  if (from != null && to != null) {
    setGlobalReportRange(ref, from, to);
  }
}

/// The detail page's active range as the endpoint-ready ISO strings, or
/// (null, null) for "All dates" (spec §5.3: null = omit the parameters).
/// Watches the page-session pair, so a ranged commit re-runs every tab
/// that derives its fetch args from this (spec §9: the range is part of
/// the provider identity).
({String? from, String? to}) customerDetailRangeIso(
  WidgetRef ref,
  int sessionId,
) {
  final from = ref.watch(customerDetailFromDateProvider(sessionId));
  final to = ref.watch(customerDetailToDateProvider(sessionId));
  return (
    from: from == null ? null : isoDate(from),
    to: to == null ? null : isoDate(to),
  );
}

/// Invalidates every customer-scoped query after a mutation (record/edit/
/// delete payment, delete/cancel invoice), so every detail tab refetches.
/// The mutating tabs additionally invalidate the global payments/invoices
/// lists themselves.
void invalidateCustomerQueries(WidgetRef ref, int customerId) {
  ref.invalidate(customerDetailProvider(customerId));
  ref.invalidate(customerLedgerProvider(customerId));
  ref.invalidate(customerInvoicesProvider(customerId));
  ref.invalidate(customerPaymentsProvider(customerId));
  // The paged tab + ranged-ledger + statement providers watch these
  // versions, so the range the user is currently on refetches after any
  // mutation (the ranged keys — page/dates — are invisible to mutators).
  ref.read(customerTabsVersionProvider.notifier).state++;
  ref.read(customerLedgerVersionProvider.notifier).state++;
  ref.read(customerStatementVersionProvider.notifier).state++;
}
