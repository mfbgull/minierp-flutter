import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../models/invoice.dart' show Invoice;
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
        parse: (Object? json) =>
            Invoice.fromJson(json as Map<String, dynamic>),
      );

  Future<ApiResult<Invoice>> create(Map<String, dynamic> body) => _api.postRaw(
        ApiEndpoints.invoices,
        body: body,
        parse: (Object? json) =>
            Invoice.fromJson(json as Map<String, dynamic>),
      );

  Future<ApiResult<Invoice>> update(int id, Map<String, dynamic> body) =>
      _api.putRaw(
        '${ApiEndpoints.invoices}/$id',
        body: body,
        parse: (Object? json) =>
            Invoice.fromJson(json as Map<String, dynamic>),
      );

  /// Bare `{message}` response — `deleteRaw`.
  Future<ApiResult<void>> delete(int id) =>
      _api.deleteRaw('${ApiEndpoints.invoices}/$id');

  /// Enveloped `{success, message, data}` response — `put`.
  Future<ApiResult<Invoice>> cancel(int id) => _api.put(
        '${ApiEndpoints.invoices}/$id/cancel',
        body: const <String, dynamic>{},
        parse: (Object? json) =>
            Invoice.fromJson(json as Map<String, dynamic>),
      );
}

final invoiceRepositoryProvider = Provider<InvoiceRepository>(
  (ref) => InvoiceRepository(RepositoryClient(ref.watch(dioProvider))),
);
