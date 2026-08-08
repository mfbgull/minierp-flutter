// Production + BOM repository — typed against the server controllers
// (`productionController.ts` / `bomController.ts`, PORTING.md §2).
//
// Envelope variants on the server — note BOMs and productions are
// **bare** (no `{success, data}` envelope):
// - `GET /boms` → bare `[Bom]`
// - `GET /boms/:id` → bare `BomDetail` (includes `items`)
// - `GET /boms/by-item/:itemId` → bare `[Bom]` (active only)
// - `POST /boms` → bare `BomDetail` (201)
// - `PUT /boms/:id` → bare `BomDetail`
// - `PATCH /boms/:id/toggle-active` → bare `BomDetail`
// - `DELETE /boms/:id` → bare `{ message }` (rejects when the BOM is
//   referenced by productions)
// - `GET /productions` → bare `[Production]` (filters below)
// - `GET /productions/:id` → bare `Production` (includes `inputs`)
// - `POST /productions` → bare `Production` (201)
// - `GET /productions/summary/item/:itemId` → bare `{...}`
// - `DELETE /productions/:id` → `{ success, message }` (enveloped)

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart' show dioProvider;
import '../../core/api/endpoints.dart' show ApiEndpoints;
import '../models/bom.dart';
import '../models/production.dart';
import 'api_result.dart';
import 'repository_client.dart';

/// Filters for `GET /productions` (all optional server-side).
class ProductionFilters {
  const ProductionFilters({
    this.startDate,
    this.endDate,
    this.outputItemId,
    this.warehouseId,
    this.limit,
  });

  final String? startDate;
  final String? endDate;
  final int? outputItemId;
  final int? warehouseId;
  final int? limit;

  Map<String, dynamic> toQuery() => {
    if (startDate != null) 'start_date': startDate,
    if (endDate != null) 'end_date': endDate,
    if (outputItemId != null) 'output_item_id': outputItemId,
    if (warehouseId != null) 'warehouse_id': warehouseId,
    if (limit != null) 'limit': limit,
  };
}

class ProductionRepository {
  ProductionRepository(this._api);

  final RepositoryClient _api;

  // ---- BOMs ----

  Future<ApiResult<List<Bom>>> boms() => _api.getRawList(
    ApiEndpoints.boms,
    parseItem: (Object? json) => Bom.fromJson(json as Map<String, dynamic>),
  );

  Future<ApiResult<BomDetail>> bom(int id) => _api.getRaw(
    '${ApiEndpoints.boms}/$id',
    parse: (Object? json) => BomDetail.fromJson(json as Map<String, dynamic>),
  );

  Future<ApiResult<List<Bom>>> bomsByFinishedItem(int itemId) =>
      _api.getRawList(
        '${ApiEndpoints.boms}/by-item/$itemId',
        parseItem: (Object? json) => Bom.fromJson(json as Map<String, dynamic>),
      );

  Future<ApiResult<BomDetail>> createBom(Map<String, dynamic> body) =>
      _api.postRaw(
        ApiEndpoints.boms,
        body: body,
        parse: (Object? json) =>
            BomDetail.fromJson(json as Map<String, dynamic>),
      );

  Future<ApiResult<BomDetail>> updateBom(int id, Map<String, dynamic> body) =>
      _api.putRaw(
        '${ApiEndpoints.boms}/$id',
        body: body,
        parse: (Object? json) =>
            BomDetail.fromJson(json as Map<String, dynamic>),
      );

  Future<ApiResult<BomDetail>> toggleBomActive(int id) => _api.patchRaw(
    '${ApiEndpoints.boms}/$id/toggle-active',
    parse: (Object? json) => BomDetail.fromJson(json as Map<String, dynamic>),
  );

  Future<ApiResult<void>> deleteBom(int id) =>
      _api.deleteRaw('${ApiEndpoints.boms}/$id');

  // ---- Productions ----

  Future<ApiResult<Production>> createProduction(Map<String, dynamic> body) =>
      _api.postRaw(
        ApiEndpoints.productions,
        body: body,
        parse: (Object? json) =>
            Production.fromJson(json as Map<String, dynamic>),
      );

  Future<ApiResult<List<Production>>> productions([
    ProductionFilters filters = const ProductionFilters(),
  ]) => _api.getRawList(
    ApiEndpoints.productions,
    queryParameters: filters.toQuery(),
    parseItem: (Object? json) =>
        Production.fromJson(json as Map<String, dynamic>),
  );

  Future<ApiResult<Production>> production(int id) => _api.getRaw(
    '${ApiEndpoints.productions}/$id',
    parse: (Object? json) => Production.fromJson(json as Map<String, dynamic>),
  );

  Future<ApiResult<void>> deleteProduction(int id) =>
      _api.delete('${ApiEndpoints.productions}/$id');
}

final productionRepositoryProvider = Provider<ProductionRepository>(
  (ref) => ProductionRepository(RepositoryClient(ref.watch(dioProvider))),
);
