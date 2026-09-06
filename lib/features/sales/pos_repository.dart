// POS repository — thin typed layer over `POST /api/pos/sale` and
// `GET /api/pos/transactions` (PORTING.md §5 `/pos`). The catalog (items +
// warehouses) is served by the existing inventory endpoints, so the POS
// screen reuses `InventoryRepository` for browsing and only this file
// handles the POS-specific sale + history calls.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart' show ApiEndpoints;
import '../../data/repositories/api_result.dart';
import '../../data/repositories/repository_client.dart';
import 'pos_models.dart';

class PosRepository {
  PosRepository(this._api);

  final RepositoryClient _api;

  /// `POST /api/pos/sale` — commits a POS sale (invoice + stock movements +
  /// payment + GL) inside a server transaction. Returns the completed sale.
  Future<ApiResult<PosSale>> createSale({
    required int warehouseId,
    required String saleDate,
    required List<Map<String, dynamic>> items,
    required double cashReceived,
    String? customerName,
  }) async {
    return _api.postEnvelope(
      '${ApiEndpoints.pos}/sale',
      body: <String, dynamic>{
        'warehouse_id': warehouseId,
        'sale_date': saleDate,
        'items': items,
        'cash_received': cashReceived,
        if (customerName != null && customerName.isNotEmpty)
          'customer_name': customerName,
      },
      parse: (json) => PosSale.fromJson(
        json['data'] as Map<String, dynamic>,
      ),
    );
  }

  /// `GET /api/pos/transactions` — recent POS sales (read-only history).
  /// `limit` defaults to 50 server-side.
  Future<ApiResult<List<PosTransaction>>> listTransactions({
    String? startDate,
    String? endDate,
    int limit = 50,
  }) async {
    return _api.getList(
      '${ApiEndpoints.pos}/transactions',
      queryParameters: <String, dynamic>{
        'start_date': ?startDate,
        'end_date': ?endDate,
        'limit': '$limit',
      },
      parseItem: (json) => PosTransaction.fromJson(json as Map<String, dynamic>),
    );
  }
}

final posRepositoryProvider = Provider<PosRepository>(
  (ref) => PosRepository(ref.watch(repositoryClientProvider)),
);