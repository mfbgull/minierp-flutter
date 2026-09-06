// Production + BOM repository — typed against the server controllers
// (`productionController.ts` / `bomController.ts`, PORTING.md §2).
//
// Envelope variants on the server — list endpoints are **paged** (the
// flat `{success, data, pagination}` envelope from grid-pagination §7),
// details/writes stay **bare**:
// - `GET /boms` → paged `{ data: [Bom], pagination }` (search + sort)
// - `GET /boms/:id` → bare `BomDetail` (includes `items`)
// - `GET /boms/by-item/:itemId` → bare `[Bom]` (active only)
// - `POST /boms` → bare `BomDetail` (201)
// - `PUT /boms/:id` → bare `BomDetail`
// - `PATCH /boms/:id/toggle-active` → bare `BomDetail`
// - `DELETE /boms/:id` → bare `{ message }` (rejects when the BOM is
//   referenced by productions)
// - `GET /productions` → paged `{ data: [Production], pagination }`
//   (search + sort; existing filters preserved)
// - `GET /productions/:id` → bare `Production` (includes `inputs`)
// - `POST /productions` → bare `Production` (201)
// - `GET /productions/summary/item/:itemId` → bare `{...}`
// - `DELETE /productions/:id` → `{ success, message }` (enveloped)

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart' show ApiEndpoints;
import '../models/bom.dart';
import '../models/production.dart';
import 'api_result.dart';
import 'paged_request.dart' show PagedRequest, PagedResponse;
import 'repository_client.dart';

class ProductionRepository {
  ProductionRepository(this._api);

  final RepositoryClient _api;

  // ---- BOMs ----

  /// One page of BOMs — `GET /boms` now returns the flat paged envelope
  /// (grid-pagination §7.2, with `search` + sort).
  Future<ApiResult<PagedResponse<Bom>>> bomsPaged(PagedRequest request) =>
      _api.getPaged(
        ApiEndpoints.boms,
        queryParameters: request.toQuery(),
        parseItem: (Object? json) =>
            Bom.fromJson(json as Map<String, dynamic>),
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

  /// One page of productions — `GET /productions` now returns the flat
  /// paged envelope (grid-pagination §7.1, with `search` + sort).
  Future<ApiResult<PagedResponse<Production>>> productionsPaged(
    PagedRequest request,
  ) => _api.getPaged(
    ApiEndpoints.productions,
    queryParameters: request.toQuery(),
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
  (ref) => ProductionRepository(ref.watch(repositoryClientProvider)),
);
