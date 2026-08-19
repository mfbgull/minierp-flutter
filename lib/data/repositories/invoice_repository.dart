import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../models/price_history.dart' show ItemPriceHistory;
import '../models/invoice.dart' show Invoice, InvoicePaymentRecord;
import '../models/payment.dart' show Payment;
import '../models/sales_return.dart' show SalesReturn, SalesReturnResult;
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

  /// All invoices — the full-list `GET /invoices` response (the grid now
  /// uses [invoicesPaged]; this stays for pickers/dialogs that need the
  /// whole list in one fetch, e.g. the Record Payment allocation list
  /// and the Process Return picker).
  Future<ApiResult<List<Invoice>>> invoices({InvoiceFilters? filters}) =>
      _api.getList(
        ApiEndpoints.invoices,
        queryParameters: filters?.toQuery(),
        parseItem: (Object? json) =>
            Invoice.fromJson(json as Map<String, dynamic>),
      );

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

  /// Process a return — enveloped `{success, message, data:
  /// {returnedItems, totalItems, disposition, returnAmount, netReturn,
  /// deduction}}`. The server rejects (400) cancelled invoices, unknown
  /// invoice items, and non-positive or over-available quantities, and
  /// rejects monetary over-return beyond the invoice total.
  Future<ApiResult<SalesReturnResult>> processReturn(
    int id, {
    required List<Map<String, dynamic>> items,
    String? reason,
    String? disposition,

    /// The warehouse the returned goods are restocked into
    /// (`warehouse_id`). When omitted the server restocks into the
    /// warehouse the sale was dispatched from.
    int? warehouseId,
  }) => _api.post(
    '${ApiEndpoints.invoices}/$id/return',
    body: {
      'items': items,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
      'disposition': ?disposition,
      'warehouse_id': ?warehouseId,
    },
    parse: (Object? json) =>
        SalesReturnResult.fromJson(json as Map<String, dynamic>),
  );
}

final invoiceRepositoryProvider = Provider<InvoiceRepository>(
  (ref) => InvoiceRepository(RepositoryClient(ref.watch(dioProvider))),
);
