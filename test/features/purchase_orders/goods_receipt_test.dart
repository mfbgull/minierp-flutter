// Goods-receipt model + repository tests (PORTING.md §14 / server
// `purchaseOrderController.createGoodsReceipt` + `getGoodsReceipts`):
// parses the bare `GoodsReceipt` rows the receipts GET/POST return and
// verifies the create body matches the server DTO.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/data/models/purchase_order.dart'
    show GoodsReceipt, PurchaseOrderDetail;
import 'package:minierp_app/data/repositories/api_result.dart'
    show ApiFailure, ApiSuccess;
import 'package:minierp_app/data/repositories/purchase_order_repository.dart'
    show PurchaseOrderRepository;
import 'package:minierp_app/data/repositories/repository_client.dart';

import '../../repositories/repositories_test.dart'
    show FakeHttpAdapter, RouteHandler, jsonBody;

void main() {
  late Dio dio;
  late RepositoryClient api;
  late PurchaseOrderRepository repo;

  RouteHandler handler = (_) => jsonBody({'success': true, 'data': null});

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://localhost:3011/api'));
    dio.httpClientAdapter = FakeHttpAdapter((options) => handler(options));
    api = RepositoryClient(dio);
    repo = PurchaseOrderRepository(api);
  });

  group('GoodsReceipt.fromJson', () {
    test('parses the full receipt row', () {
      final receipt = GoodsReceipt.fromJson({
        'id': 10,
        'receipt_no': 'GR-2026-001',
        'po_id': 1,
        'receipt_date': '2026-08-10',
        'warehouse_id': 1,
        'remarks': 'First delivery',
        'created_at': '2026-08-10 10:00:00',
        'warehouse_name': 'Main Warehouse',
        'created_by_username': 'admin',
        'total_quantity': 100.0,
        'total_amount': 1000.0,
      });

      expect(receipt.id, 10);
      expect(receipt.receiptNo, 'GR-2026-001');
      expect(receipt.receiptDate, '2026-08-10');
      expect(receipt.warehouseId, 1);
      expect(receipt.warehouseName, 'Main Warehouse');
      expect(receipt.remarks, 'First delivery');
      expect(receipt.createdByUsername, 'admin');
      expect(receipt.totalQuantity, 100);
      expect(receipt.totalAmount, 1000);
    });

    test('tolerates missing/string numeric fields', () {
      final receipt = GoodsReceipt.fromJson({
        'id': 1,
        'receipt_no': 'GR-2026-002',
        // SQLite SUM aggregates can arrive as strings.
        'total_quantity': '50',
        'total_amount': '250.5',
      });

      expect(receipt.receiptDate, '');
      expect(receipt.warehouseName, isNull);
      expect(receipt.totalQuantity, 50);
      expect(receipt.totalAmount, 250.5);
    });
  });

  group('PurchaseOrderRepository receipts', () {
    test('receipts() GETs the bare array', () async {
      String? seenPath;
      handler = (o) {
        seenPath = o.path;
        return jsonBody([
          {
            'id': 10,
            'receipt_no': 'GR-2026-001',
            'receipt_date': '2026-08-10',
            'warehouse_name': 'Main Warehouse',
            'total_quantity': 100,
            'total_amount': 1000,
          },
        ]);
      };

      final result = await repo.receipts(1);

      expect(seenPath, '/purchase-orders/1/receipts');
      expect(result, isA<ApiSuccess<List<GoodsReceipt>>>());
      final data = (result as ApiSuccess<List<GoodsReceipt>>).data;
      expect(data.single.receiptNo, 'GR-2026-001');
      expect(data.single.totalQuantity, 100);
    });

    test('createReceipt() POSTs the schema-shaped body', () async {
      Map<String, dynamic>? seenBody;
      String? seenPath;
      handler = (o) {
        seenPath = o.path;
        seenBody = o.data as Map<String, dynamic>;
        return jsonBody({
          'id': 10,
          'receipt_no': 'GR-2026-001',
          'receipt_date': '2026-08-10',
          'warehouse_id': 1,
          'total_quantity': 100,
          'total_amount': 1000,
        }, status: 201);
      };

      final result = await repo.createReceipt(1, {
        'receipt_date': '2026-08-10',
        'warehouse_id': 1,
        'items': [
          {'po_item_id': 1, 'received_quantity': 100},
        ],
      });

      expect(seenPath, '/purchase-orders/1/receipts');
      expect(seenBody!['warehouse_id'], 1);
      expect(seenBody!['items'], [
        {'po_item_id': 1, 'received_quantity': 100},
      ]);
      expect(result, isA<ApiSuccess<GoodsReceipt>>());
      expect((result as ApiSuccess<GoodsReceipt>).data.receiptNo, 'GR-2026-001');
    });

    test('createReceipt() surfaces the server error', () async {
      handler = (o) =>
          jsonBody({'error': 'Cannot receive more than pending quantity'}, status: 400);

      final result = await repo.createReceipt(1, {
        'receipt_date': '2026-08-10',
        'warehouse_id': 1,
        'items': [
          {'po_item_id': 1, 'received_quantity': 999},
        ],
      });

      final failure = result as ApiFailure<GoodsReceipt>;
      expect(failure.error.statusCode, 400);
      expect(failure.error.message, 'Cannot receive more than pending quantity');
    });
  });

  group('PurchaseOrderDetail.warehouseId', () {
    test('parses warehouse_id from the detail payload', () {
      final detail = PurchaseOrderDetail.fromJson({
        'id': 1,
        'po_no': 'PO-2026-001',
        'po_date': '2026-01-20',
        'supplier_id': 1,
        'supplier_name': 'Alpha Traders',
        'warehouse_id': 1,
        'status': 'Submitted',
        'items': const [],
      });

      expect(detail.warehouseId, 1);
    });
  });
}
