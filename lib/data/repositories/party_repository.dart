import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/party.dart';
import 'api_result.dart';
import 'paged_request.dart';
import 'repository_client.dart';

class PartyRepository {
  PartyRepository(this._client);
  final RepositoryClient _client;

  Future<ApiResult<PartyPosition>> position(int id) => _client.getOnline(
    '/parties/$id/position', parse: (json) => PartyPosition.fromJson(json! as Map<String, dynamic>));
  Future<ApiResult<PartyAdjustmentTargets>> targets(int id) => _client.getOnline(
    '/parties/$id/adjustment-targets', parse: (json) => PartyAdjustmentTargets.fromJson(json! as Map<String, dynamic>));
  Future<ApiResult<PagedResponse<PartyAdjustment>>> history(int id, {int page = 1}) => _client.getPaged(
    '/parties/$id/adjustments', queryParameters: {'page': page, 'limit': 25},
    parseItem: (json) => PartyAdjustment.fromJson(json! as Map<String, dynamic>));
  Future<ApiResult<PartyAdjustment>> detail(int partyId, int id) => _client.getOnline(
    '/parties/$partyId/adjustments/$id', parse: (json) => PartyAdjustment.fromJson(json! as Map<String, dynamic>));
  Future<ApiResult<PartyAdjustment>> post(int id, Map<String, dynamic> body, String key) => _client.post(
    '/parties/$id/adjustments', body: body, headers: {'Idempotency-Key': key},
    parse: (json) => PartyAdjustment.fromJson(json! as Map<String, dynamic>));
  Future<ApiResult<PartyAdjustment>> reverse(int partyId, int id, {required String reason, required String date}) => _client.post(
    '/parties/$partyId/adjustments/$id/reverse', body: {'reason': reason, 'reversal_date': date},
    parse: (json) => PartyAdjustment.fromJson(json! as Map<String, dynamic>));
  Future<ApiResult<PartyPosition>> link({required int customerId, required int supplierId}) => _client.post(
    '/parties/link', body: {'customer_id': customerId, 'supplier_id': supplierId, 'confirmed': true},
    parse: (json) => PartyPosition.fromJson(json! as Map<String, dynamic>));
  Future<ApiResult<PartyPosition>> unlink(int id) => _client.post(
    '/parties/$id/unlink', body: <String, dynamic>{},
    parse: (json) => PartyPosition.fromJson(json! as Map<String, dynamic>));
  Future<ApiResult<PartyPosition>> addRole(int id, {required bool customer, required Map<String, dynamic> body}) => _client.post(
    '/parties/$id/${customer ? 'customer' : 'supplier'}', body: body,
    parse: (json) => PartyPosition.fromJson(json! as Map<String, dynamic>));

  Future<void> invalidateAccounts() => _client.invalidatePaths([
    '/parties', '/customers', '/suppliers', '/invoices', '/purchases', '/purchase-orders',
    '/supplier-bills', '/supplier-prepayments', '/reports', '/dashboard',
  ]);
}

final partyRepositoryProvider = Provider<PartyRepository>((ref) => PartyRepository(ref.watch(repositoryClientProvider)));
final partyPositionProvider = FutureProvider.autoDispose.family<PartyPosition, int>((ref, id) async {
  final result = await ref.watch(partyRepositoryProvider).position(id);
  return switch (result) { ApiSuccess(:final data) => data, ApiFailure(:final error) => throw error };
});
