import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../models/price_history.dart' show ItemPriceHistory;
import '../models/invoice.dart' show Invoice, InvoicePaymentRecord;
import '../models/sales_return.dart' show SalesReturn, SalesReturnResult;
import 'api_result.dart';
import 'repository_client.dart';

/// Filters for `GET /invoices`. Only `status` is a server-side filter
/// (comma-separated values); search/date filtering happens client-side
/// over the full list (the endpoint has no search/date params).
class InvoiceFilters {
  const InvoiceFilters({this.status});

  /// Comma-separated status values (`Paid,Partially Paid`).
  final String? status;

  Map<String, dynamic> toQuery() => {
    if (status != null && status!.isNotEmpty) 'status': status,
  };
}

/// `GET /invoices` list rows embed `items`, but POST/PUT/DELETE return
/// bare bodies (no envelope) — see [RepositoryClient] docs.
class InvoiceRepository {
  InvoiceRepository(this._api);

  final RepositoryClient _api;

  Future<ApiResult<List<Invoice>>> invoices({InvoiceFilters? filters}) =>
      _api.getList(
        ApiEndpoints.invoices,
        queryParameters: filters?.toQuery(),
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

  /// Invoice-return history — bare array (the endpoint has no search or
  /// page; the grid keeps sorting/filtering client-side like items).
  Future<ApiResult<List<SalesReturn>>> returns() => _api.getRawList(
    '${ApiEndpoints.invoices}/returns',
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
  }) => _api.post(
    '${ApiEndpoints.invoices}/$id/return',
    body: {
      'items': items,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
      'disposition': ?disposition,
    },
    parse: (Object? json) =>
        SalesReturnResult.fromJson(json as Map<String, dynamic>),
  );
}

final invoiceRepositoryProvider = Provider<InvoiceRepository>(
  (ref) => InvoiceRepository(RepositoryClient(ref.watch(dioProvider))),
);
