import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart';
import '../models/price_history.dart' show ItemPriceHistory;
import '../models/invoice.dart' show Invoice, InvoicePaymentRecord;
import '../models/payment.dart' show Payment;
import '../models/unified_payment.dart' show UnifiedPayment;
import '../models/sales_return.dart'
    show InvoicePosition, SalesReturn, SalesReturnResult;
import 'api_result.dart';
import 'paged_request.dart' show PagedRequest, PagedResponse;
import 'repository_client.dart';

/// Filters for `GET /invoices`. Only `status` (comma-separated values)
/// and `customer_id` are server-side filters; search/date filtering
/// happens client-side over the full list.
class InvoiceFilters {
  const InvoiceFilters({this.status, this.customerId});

  /// Comma-separated status values (`Paid,Partially Paid`).
  final String? status;

  /// Narrow to one customer's invoices (the Record Payment dialog uses
  /// it to load open invoices for allocation).
  final int? customerId;

  Map<String, dynamic> toQuery() => {
    if (status != null && status!.isNotEmpty) 'status': status,
    if (customerId != null) 'customer_id': customerId,
  };
}

/// `GET /invoices` list rows embed `items`, but POST/PUT/DELETE return
/// bare bodies (no envelope) — see [RepositoryClient] docs.
class InvoiceRepository {
  InvoiceRepository(this._api);

  final RepositoryClient _api;

  /// All invoices for [filters] — the server-paginated list fetched as
  /// one large page (rows ordered `invoice_date DESC` like the grid).
  /// The Record Payment allocation lists, the customer metrics and the
  /// Process Return picker need the whole list in one fetch.
  Future<ApiResult<List<Invoice>>> invoices({InvoiceFilters? filters}) async {
    final result = await invoicesPaged(
      PagedRequest(
        page: 1,
        limit: 1000,
        sortBy: 'invoice_date',
        sortOrder: 'DESC',
        extra: filters?.toQuery(),
      ),
    );
    return result.map((page) => page.items);
  }

  /// One page of invoices (`GET /invoices`) — server-paginated like
  /// customers/suppliers (enveloped + `pagination` block). `search`,
  /// `start_date`/`end_date` and `status` ride in `extra`.
  Future<ApiResult<PagedResponse<Invoice>>> invoicesPaged(
    PagedRequest request,
  ) => _api.getPaged(
    ApiEndpoints.invoices,
    queryParameters: request.toQuery(),
    parseItem: (Object? json) =>
        Invoice.fromJson(json as Map<String, dynamic>),
  );

  /// Bare object with customer details + items (`GET /invoices/:id`).
  Future<ApiResult<Invoice>> invoice(int id) => _api.getRaw(
    '${ApiEndpoints.invoices}/$id',
    parse: (Object? json) => Invoice.fromJson(json as Map<String, dynamic>),
  );

  /// Existing payments for an invoice (`GET /invoices/:id/payments`).
  Future<ApiResult<List<InvoicePaymentRecord>>> invoicePayments(int id) =>
      _api.getList(
        '${ApiEndpoints.invoices}/$id/payments',
        parseItem: (Object? json) =>
            InvoicePaymentRecord.fromJson(json as Map<String, dynamic>),
      );

  /// Create a payment against an invoice (`POST /payments` with an
  /// `invoice_allocations` entry — see `prepareInvoiceData`). Enveloped.
  Future<ApiResult<InvoicePaymentRecord>> createInvoicePayment(
    Map<String, dynamic> body,
  ) => _api.post(
    ApiEndpoints.payments,
    body: body,
    parse: (Object? json) =>
        InvoicePaymentRecord.fromJson(json as Map<String, dynamic>),
  );

  /// Update an existing payment (`PUT /payments/:id`). Enveloped.
  Future<ApiResult<InvoicePaymentRecord>> updatePayment(
    int id,
    Map<String, dynamic> body,
  ) => _api.put(
    '${ApiEndpoints.payments}/$id',
    body: body,
    parse: (Object? json) =>
        InvoicePaymentRecord.fromJson(json as Map<String, dynamic>),
  );

  /// One page of the payments module (`GET /payments`) — server-paginated
  /// like customers/suppliers (enveloped + `pagination` block; PORTING.md
  /// §2). Default sort is `payment_date DESC` server-side.
  Future<ApiResult<PagedResponse<Payment>>> payments(PagedRequest request) =>
      _api.getPaged(
        ApiEndpoints.payments,
        queryParameters: request.toQuery(),
        parseItem: (Object? json) =>
            Payment.fromJson(json as Map<String, dynamic>),
      );

  /// Unified payment / cash-movement hub (`GET /payments/unified`) — a
  /// read-only projection across payments, expenses, salary payments,
  /// owner capital and owner withdrawals. Server-paginated + filtered by
  /// `type` (customer | supplier | expense | salary | owner_capital |
  /// owner_withdrawal) and searchable across ref_no/party/description.
  Future<ApiResult<PagedResponse<UnifiedPayment>>> unifiedPayments(
    PagedRequest request,
  ) =>
      _api.getPaged(
        '${ApiEndpoints.payments}/unified',
        queryParameters: request.toQuery(),
        parseItem: (Object? json) =>
            UnifiedPayment.fromJson(json as Map<String, dynamic>),
      );

  /// All payments for one customer (`GET /payments?customerId=<id>` — the
  /// same enveloped list endpoint; the customer detail Payments tab
  /// ignores the pagination block and takes the full page).
  Future<ApiResult<List<Payment>>> paymentsForCustomer(int customerId) =>
      _api.getList(
        ApiEndpoints.payments,
        queryParameters: {'customerId': customerId},
        parseItem: (Object? json) =>
            Payment.fromJson(json as Map<String, dynamic>),
      );

  /// All payments for one supplier (`GET /payments?supplierId=<id>` — the
  /// supplier detail Payments tab's query; enveloped list).
  Future<ApiResult<List<Payment>>> paymentsForSupplier(int supplierId) =>
      _api.getList(
        ApiEndpoints.payments,
        queryParameters: {'supplierId': supplierId},
        parseItem: (Object? json) =>
            Payment.fromJson(json as Map<String, dynamic>),
      );

  /// Create a supplier payment (`POST /payments` with a `supplier_id` +
  /// `po_allocations` array — see `createSupplierPayment` in the web
  /// SupplierPaymentModal). Enveloped; parses the returned Payment.
  Future<ApiResult<Payment>> createSupplierPayment(
    Map<String, dynamic> body,
  ) => _api.post(
    ApiEndpoints.payments,
    body: body,
    parse: (Object? json) => Payment.fromJson(json as Map<String, dynamic>),
  );

  /// One payment (`GET /payments/:id`, enveloped object).
  Future<ApiResult<Payment>> payment(int id) => _api.get(
    '${ApiEndpoints.payments}/$id',
    parse: (Object? json) => Payment.fromJson(json as Map<String, dynamic>),
  );

  /// Delete a payment (`DELETE /payments/:id`). Enveloped
  /// `{success, message}` — `delete` (not `deleteRaw`).
  Future<ApiResult<void>> deletePayment(int id) =>
      _api.delete('${ApiEndpoints.payments}/$id');

  /// Selling-price history for an item/customer pair, used by the rate
  /// cell's advisory hint. Enveloped; the caller treats any failure as
  /// "no history".
  Future<ApiResult<ItemPriceHistory>> itemCustomerPriceHistory({
    required int itemId,
    required int customerId,
  }) => _api.get(
    '${ApiEndpoints.sales}/item-customer-history',
    queryParameters: {'item_id': itemId, 'customer_id': customerId},
    parse: (Object? json) =>
        ItemPriceHistory.fromJson(json as Map<String, dynamic>),
  );

  Future<ApiResult<Invoice>> create(Map<String, dynamic> body) => _api.postRaw(
    ApiEndpoints.invoices,
    body: body,
    parse: (Object? json) => Invoice.fromJson(json as Map<String, dynamic>),
  );

  Future<ApiResult<Invoice>> update(int id, Map<String, dynamic> body) =>
      _api.putRaw(
        '${ApiEndpoints.invoices}/$id',
        body: body,
        parse: (Object? json) => Invoice.fromJson(json as Map<String, dynamic>),
      );

  /// Bare `{message}` response — `deleteRaw`.
  Future<ApiResult<void>> delete(int id) =>
      _api.deleteRaw('${ApiEndpoints.invoices}/$id');

  /// `POST /invoices/:id/restore` — reverts a soft delete (undo pattern,
  /// SHORTCOMINGS-FIX 4.2/4.4). Enveloped `{success, message, data}`.
  Future<ApiResult<void>> restore(int id) => _api.post(
    '${ApiEndpoints.invoices}/$id/restore',
    parse: (_) {},
  );

  /// Enveloped `{success, message, data}` response — `put`.
  Future<ApiResult<Invoice>> cancel(int id) => _api.put(
    '${ApiEndpoints.invoices}/$id/cancel',
    body: const <String, dynamic>{},
    parse: (Object? json) => Invoice.fromJson(json as Map<String, dynamic>),
  );

  /// Invoice-return history — full list (the grid now uses
  /// [returnsPaged]; this stays for any consumer that needs the whole
  /// list in one fetch).
  Future<ApiResult<List<SalesReturn>>> returns() => _api.getRawList(
    '${ApiEndpoints.invoices}/returns',
    parseItem: (Object? json) =>
        SalesReturn.fromJson(json as Map<String, dynamic>),
  );

  /// One page of invoice-return history (`GET /invoices/returns`) —
  /// server-paginated like the other converted lists. `search`,
  /// `warehouse_name` and the date range ride in `extra`.
  Future<ApiResult<PagedResponse<SalesReturn>>> returnsPaged(
    PagedRequest request,
  ) => _api.getPaged(
    '${ApiEndpoints.invoices}/returns',
    queryParameters: request.toQuery(),
    parseItem: (Object? json) =>
        SalesReturn.fromJson(json as Map<String, dynamic>),
  );
  /// The authoritative money position of an invoice (spec §3.2/§4.2) —
  /// `GET /invoices/:id/position`. The invoice detail embeds the same
  /// object as `data.position`, so most screens read it from there.
  Future<ApiResult<InvoicePosition>> position(int id) => _api.getRaw(
    '${ApiEndpoints.invoices}/$id/position',
    parse: (Object? json) =>
        InvoicePosition.fromJson(json as Map<String, dynamic>),
  );

  /// Process a return (spec §5.1) — enveloped `{success, message,
  /// data: {returnId, returnNo, status, returnedAmount, feeAmount,
  /// netAmount, settledAmount, settlements, position, …legacy aliases}}`.
  ///
  /// The server rejects (400) cancelled invoices, unknown invoice items,
  /// non-positive or over-available quantities, over-settlement beyond
  /// [netAmount], and an invalid `warehouse_id`/`return_date`.
  Future<ApiResult<SalesReturnResult>> processReturn(
    int id, {
    required List<Map<String, dynamic>> items,

    /// 'none' | 'fixed' | 'percentage' — the fee is always charged
    /// (spec D5 revised); defaults to 'none' server-side.
    String? feeType,
    num? feeValue,

    /// 'YYYY-MM-DD'; defaults to today (D14).
    String? returnDate,
    String? reason,

    /// The warehouse the returned goods are restocked into. When omitted
    /// the server restocks into the warehouse the sale was dispatched
    /// from.
    int? warehouseId,

    /// Explicit settlement allocations (Option A, spec §5.1 step 8).
    /// Omit → the return is recorded unsettled (Option B).
    List<Map<String, dynamic>>? settlements,
  }) => _api.post(
    '${ApiEndpoints.invoices}/$id/return',
    body: {
      'items': items,
      if (feeType != null) 'fee_type': feeType,
      if (feeValue != null) 'fee_value': feeValue,
      if (returnDate != null) 'return_date': returnDate,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
      'warehouse_id': ?warehouseId,
      'settlements': ?settlements,
    },
    parse: (Object? json) =>
        SalesReturnResult.fromJson(json as Map<String, dynamic>),
  );

  /// Settle an existing return (spec §5.2) — one or more allocations
  /// against `remainingRefundDue`. `POST /invoice-returns/:id/settle`.
  Future<ApiResult<SalesReturnResult>> settleReturn(
    int returnId, {
    required List<Map<String, dynamic>> settlements,
  }) => _api.post(
    '${ApiEndpoints.invoiceReturns}/$returnId/settle',
    body: {'settlements': settlements},
    parse: (Object? json) =>
        SalesReturnResult.fromJson(json as Map<String, dynamic>),
  );

  /// Void a return and reverse its GL/stock/ledger/settlements (spec
  /// §5.2 / D24). `POST /invoice-returns/:id/void`.
  Future<ApiResult<void>> voidReturn(int returnId, {String? reason}) =>
      _api.post(
        '${ApiEndpoints.invoiceReturns}/$returnId/void',
        body: {
          if (reason != null && reason.isNotEmpty) 'reason': reason,
        },
        parse: (_) {},
      );

  /// Void one settlement allocation, releasing it back to the refund/
  /// credit due (spec §5.2 / D24). `POST /return-settlements/:id/void`.
  Future<ApiResult<void>> voidSettlement(int settlementId, {String? reason}) =>
      _api.post(
        '${ApiEndpoints.returnSettlements}/$settlementId/void',
        body: {
          if (reason != null && reason.isNotEmpty) 'reason': reason,
        },
        parse: (_) {},
      );
}

final invoiceRepositoryProvider = Provider<InvoiceRepository>(
  (ref) => InvoiceRepository(ref.watch(repositoryClientProvider)),
);
