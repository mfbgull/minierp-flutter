import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/supplier_bill.dart';
import '../models/supplier_prepayment.dart';
import 'api_result.dart';
import 'repository_client.dart';
import 'paged_request.dart';

class SupplierAccountingRepository {
  SupplierAccountingRepository(this._client);
  final RepositoryClient _client;

  Future<ApiResult<PagedResponse<SupplierPrepayment>>> prepayments(
    int supplierId, {
    int page = 1,
    int limit = 25,
  }) => _client.getPaged(
    '/supplier-prepayments',
    queryParameters: {'supplier_id': supplierId, 'page': page, 'limit': limit},
    parseItem: (Object? json) =>
        SupplierPrepayment.fromJson(json! as Map<String, dynamic>),
  );

  Future<ApiResult<List<SupplierPaymentTarget>>> prepaymentTargets(
    int id, {
    String search = '',
  }) => _client.getList(
    '/supplier-prepayments/$id/targets',
    queryParameters: {'search': search},
    parseItem: (Object? json) =>
        SupplierPaymentTarget.fromJson(json! as Map<String, dynamic>),
  );

  Future<ApiResult<SupplierPrepayment>> createPrepayment(
    Map<String, dynamic> body, {
    required String idempotencyKey,
  }) => _client.post(
    '/supplier-prepayments',
    body: body,
    headers: {'Idempotency-Key': idempotencyKey},
    parse: (Object? json) =>
        SupplierPrepayment.fromJson(json! as Map<String, dynamic>),
  );

  Future<ApiResult<int>> applyPrepayment(
    int id,
    Map<String, dynamic> body, {
    required String idempotencyKey,
  }) => _client.post(
    '/supplier-prepayments/$id/apply',
    body: body,
    headers: {'Idempotency-Key': idempotencyKey},
    parse: (Object? json) => (json! as Map<String, dynamic>)['id'] as int,
  );

  Future<ApiResult<SupplierPrepayment>> voidPrepayment(int id, String reason) =>
      _client.post(
        '/supplier-prepayments/$id/void',
        body: {'reason': reason},
        parse: (Object? json) =>
            SupplierPrepayment.fromJson(json! as Map<String, dynamic>),
      );

  Future<ApiResult<PagedResponse<SupplierBill>>> bills(
    int supplierId, {
    int page = 1,
    int limit = 25,
  }) => _client.getPaged(
    '/supplier-bills',
    queryParameters: {'supplier_id': supplierId, 'page': page, 'limit': limit},
    parseItem: (Object? json) =>
        SupplierBill.fromJson(json! as Map<String, dynamic>),
  );

  Future<ApiResult<SupplierBill>> createBill(
    Map<String, dynamic> body, {
    required String idempotencyKey,
  }) => _client.post(
    '/supplier-bills',
    body: body,
    headers: {'Idempotency-Key': idempotencyKey},
    parse: (Object? json) =>
        SupplierBill.fromJson(json! as Map<String, dynamic>),
  );

  Future<ApiResult<int>> payBill(
    int id,
    Map<String, dynamic> body, {
    required String idempotencyKey,
  }) => _client.post(
    '/supplier-bills/$id/payments',
    body: body,
    headers: {'Idempotency-Key': idempotencyKey},
    parse: (Object? json) => (json! as Map<String, dynamic>)['id'] as int,
  );

  Future<ApiResult<SupplierBill>> voidBill(int id, String reason) =>
      _client.post(
        '/supplier-bills/$id/void',
        body: {'reason': reason},
        parse: (Object? json) =>
            SupplierBill.fromJson(json! as Map<String, dynamic>),
      );
}

final supplierAccountingRepositoryProvider =
    Provider<SupplierAccountingRepository>(
      (ref) =>
          SupplierAccountingRepository(ref.watch(repositoryClientProvider)),
    );

final supplierBillsProvider = FutureProvider.autoDispose
    .family<
      PagedResponse<SupplierBill>,
      ({int supplierId, int page, int limit})
    >((ref, args) async {
      final result = await ref
          .watch(supplierAccountingRepositoryProvider)
          .bills(args.supplierId, page: args.page, limit: args.limit);
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

final supplierPrepaymentsProvider = FutureProvider.autoDispose
    .family<
      PagedResponse<SupplierPrepayment>,
      ({int supplierId, int page, int limit})
    >((ref, args) async {
      final result = await ref
          .watch(supplierAccountingRepositoryProvider)
          .prepayments(args.supplierId, page: args.page, limit: args.limit);
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });
