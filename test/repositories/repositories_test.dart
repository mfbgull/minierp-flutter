// Data-layer tests: `RepositoryClient` envelope machinery + the two
// ported repositories, driven by a fake Dio `HttpClientAdapter` that
// returns canned JSON per route (no live server needed).

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/data/repositories/api_result.dart';
import 'package:minierp_app/data/repositories/auth_repository.dart';
import 'package:minierp_app/data/repositories/customer_repository.dart';
import 'package:minierp_app/data/repositories/dashboard_repository.dart';
import 'package:minierp_app/data/repositories/expense_repository.dart';
import 'package:minierp_app/data/repositories/inventory_repository.dart';
import 'package:minierp_app/data/repositories/invoice_repository.dart';
import 'package:minierp_app/data/repositories/production_repository.dart';
import 'package:minierp_app/data/repositories/paged_request.dart';
import 'package:minierp_app/data/repositories/repository_client.dart';

/// Canned handler per request: route on method + URI path.
typedef RouteHandler = ResponseBody Function(RequestOptions options);

class FakeHttpAdapter implements HttpClientAdapter {
  FakeHttpAdapter(this.handler);

  final RouteHandler handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => handler(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(Object body, {int status = 200}) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

void main() {
  late Dio dio;
  late RepositoryClient api;

  RouteHandler handler = (_) => jsonBody({'success': true, 'data': null});

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://localhost:3011/api'));
    dio.httpClientAdapter = FakeHttpAdapter((options) => handler(options));
    api = RepositoryClient(dio);
  });

  group('RepositoryClient envelope machinery', () {
    test('get unwraps {success: true, data}', () async {
      handler = (o) => jsonBody({
        'success': true,
        'data': {'id': 1, 'name': 'Acme'},
      });
      final result = await api.get<Map<String, dynamic>>(
        '/customers/1',
        parse: (Object? json) => json! as Map<String, dynamic>,
      );
      expect(result, isA<ApiSuccess<Map<String, dynamic>>>());
      expect(result.requireData['name'], 'Acme');
    });

    test('get maps {success: false, error} to failure', () async {
      handler = (o) => jsonBody({
        'success': false,
        'error': 'Customer not found',
      }, status: 404);
      final result = await api.get<Object>('/customers/99', parse: (o) => o!);
      final failure = result as ApiFailure<Object>;
      expect(failure.error.message, 'Customer not found');
      expect(failure.error.statusCode, 404);
      expect(failure.error.isNetwork, false);
    });

    test(
      'get maps object-shaped {error: {code, message}} (sendError)',
      () async {
        handler = (o) => jsonBody({
          'success': false,
          'error': {
            'code': 'UNAUTHORIZED',
            'message': 'Invalid username or password',
          },
        }, status: 401);
        final result = await api.get<Object>('/auth/me', parse: (o) => o!);
        final failure = result as ApiFailure<Object>;
        expect(failure.error.message, 'Invalid username or password');
        expect(failure.error.statusCode, 401);
      },
    );

    test('getRaw passes bare objects through', () async {
      handler = (o) => jsonBody({'id': 7, 'item_name': 'Soap'});
      final result = await api.getRaw<Map<String, dynamic>>(
        '/inventory/items/7',
        parse: (Object? json) => json! as Map<String, dynamic>,
      );
      expect(result.requireData['item_name'], 'Soap');
    });

    test('getList unwraps an enveloped array', () async {
      handler = (o) => jsonBody({
        'success': true,
        'data': [
          {'id': 1, 'item_name': 'Soap'},
          {'id': 2, 'item_name': 'Rice'},
        ],
      });
      final result = await api.getList<Map<String, dynamic>>(
        '/inventory/items',
        parseItem: (Object? json) => json! as Map<String, dynamic>,
      );
      expect(result.requireData.length, 2);
    });

    test('getPaged parses items + pagination block', () async {
      handler = (o) => jsonBody({
        'success': true,
        'data': [
          {'id': 1, 'customer_name': 'A'},
          {'id': 2, 'customer_name': 'B'},
        ],
        'pagination': {
          'currentPage': 2,
          'totalPages': 5,
          'totalItems': 42,
          'hasNext': true,
          'hasPrev': true,
        },
      });
      final result = await api.getPaged<Map<String, dynamic>>(
        '/customers',
        parseItem: (Object? json) => json! as Map<String, dynamic>,
      );
      final page = result.requireData;
      expect(page.items.length, 2);
      expect(page.totalItems, 42);
      expect(page.currentPage, 2);
      expect(page.totalPages, 5);
      expect(page.hasNext, true);
      expect(page.hasPrev, true);
    });

    test('getPaged fails when pagination block is missing', () async {
      handler = (o) => jsonBody({'success': true, 'data': []});
      final result = await api.getPaged<Map<String, dynamic>>(
        '/customers',
        parseItem: (Object? json) => json! as Map<String, dynamic>,
      );
      expect((result as ApiFailure).error.message, 'Missing pagination block');
    });

    test('HTTP error body surfaces the server message', () async {
      handler = (o) =>
          jsonBody({'error': 'Item code already exists'}, status: 400);
      final result = await api.postRaw<Object>(
        '/inventory/items',
        body: {'item_code': 'X'},
        parse: (o) => o!,
      );
      final failure = result as ApiFailure<Object>;
      expect(failure.error.message, 'Item code already exists');
      expect(failure.error.statusCode, 400);
    });

    test('network failure is flagged isNetwork', () async {
      handler = (o) => throw DioException.connectionError(
        requestOptions: o,
        reason: 'connection refused',
      );
      final result = await api.get<Object>('/customers', parse: (o) => o!);
      final failure = result as ApiFailure<Object>;
      expect(failure.error.isNetwork, true);
      expect(failure.error.statusCode, null);
    });

    test('delete accepts {success: true, message}', () async {
      handler = (o) => jsonBody({'success': true, 'message': 'Deleted'});
      final result = await api.delete('/customers/1');
      expect(result, isA<ApiSuccess<void>>());
    });

    test(
      'list with a malformed (non-map) row becomes a failure, not a crash',
      () async {
        handler = (o) => jsonBody({
          'success': true,
          'data': [
            {'id': 1, 'item_name': 'Soap'},
            'junk',
          ],
        });
        final result = await api.getList<Map<String, dynamic>>(
          '/inventory/items',
          parseItem: (Object? json) => json! as Map<String, dynamic>,
        );
        expect(result, isA<ApiFailure<List<Map<String, dynamic>>>>());
        expect(
          (result as ApiFailure).error.message,
          contains('Failed to parse'),
        );
      },
    );

    test('get with {success: true, data: null} becomes a failure', () async {
      handler = (o) => jsonBody({'success': true, 'data': null});
      final result = await api.get<Map<String, dynamic>>(
        '/customers/1',
        parse: (Object? json) => json! as Map<String, dynamic>,
      );
      expect(result, isA<ApiFailure<Map<String, dynamic>>>());
    });

    test('postRaw parses a bare created object', () async {
      handler = (o) => jsonBody({'id': 9, 'item_code': 'FG1'});
      final result = await api.postRaw<Map<String, dynamic>>(
        '/inventory/items',
        body: {'item_code': 'FG1'},
        parse: (Object? json) => json! as Map<String, dynamic>,
      );
      expect(result.requireData['id'], 9);
    });
  });

  group('CustomerRepository', () {
    late CustomerRepository repo;

    setUp(() => repo = CustomerRepository(api));

    test(
      'list parses customers + pagination and forwards query params',
      () async {
        Map<String, dynamic>? seenQuery;
        handler = (o) {
          seenQuery = o.queryParameters;
          return jsonBody({
            'success': true,
            'data': [
              {
                'id': 1,
                'customer_code': 'CUST001',
                'customer_name': 'Acme Corp',
                'current_balance': 120.5,
                'is_active': 1,
              },
              {
                'id': 2,
                'customer_code': 'CUST002',
                'customer_name': 'Beta Ltd',
                'current_balance': 0,
                'is_active': 1,
              },
            ],
            'pagination': {
              'currentPage': 1,
              'totalPages': 1,
              'totalItems': 2,
              'hasNext': false,
              'hasPrev': false,
            },
          });
        };

        final result = await repo.list(
          const PagedRequest(
            page: 1,
            limit: 25,
            search: 'acme',
            sortBy: 'customer_name',
            sortOrder: 'ASC',
          ),
        );
        final page = result.requireData;
        expect(page.items.length, 2);
        expect(page.items.first.customerName, 'Acme Corp');
        expect(page.items.first.currentBalance, 120.5);
        expect(page.totalItems, 2);
        expect(seenQuery!['search'], 'acme');
        expect(seenQuery!['limit'], 25);
        expect(seenQuery!['sortOrder'], 'ASC');
      },
    );

    test('get parses a customer detail', () async {
      handler = (o) => jsonBody({
        'success': true,
        'data': {
          'id': 1,
          'customer_code': 'CUST001',
          'customer_name': 'Acme Corp',
          'credit_limit': 50000,
          'is_active': 1,
        },
      });
      final result = await repo.get(1);
      expect(result.requireData.customerName, 'Acme Corp');
      expect(result.requireData.creditLimit, 50000);
    });

    test('ledger parses ledger rows', () async {
      handler = (o) => jsonBody({
        'success': true,
        'data': [
          {
            'id': 1,
            'transaction_date': '2026-07-01',
            'transaction_type': 'INVOICE',
            'reference_no': 'INV-1',
            'description': 'Sale',
            'debit': 100,
            'credit': 0,
            'balance': 100,
          },
        ],
      });
      final result = await repo.ledger(1);
      expect(result.requireData.single.transactionType, 'INVOICE');
      expect(result.requireData.single.debit, 100);
    });

    test('balance parses the camelCase DTO', () async {
      handler = (o) => jsonBody({
        'success': true,
        'data': {
          'customerId': 1,
          'customerName': 'Acme Corp',
          'currentBalance': 120.5,
        },
      });
      final result = await repo.balance(1);
      final balance = result.requireData;
      expect(balance.customerId, 1);
      expect(balance.currentBalance, 120.5);
    });

    test('create posts snake_case body and parses created customer', () async {
      Map<String, dynamic>? seenBody;
      handler = (o) {
        seenBody = o.data as Map<String, dynamic>;
        return jsonBody({
          'success': true,
          'data': {
            'id': 3,
            'customer_code': 'CUST003',
            'customer_name': 'New Co',
            'is_active': 1,
          },
          'message': 'Customer created successfully',
        }, status: 201);
      };
      final result = await repo.create({
        'customer_name': 'New Co',
        'phone': '555-0100',
      });
      expect(result.requireData.customerName, 'New Co');
      expect(seenBody!['customer_name'], 'New Co');
    });

    test('delete forwards to DELETE /customers/:id', () async {
      String? seenPath;
      handler = (o) {
        seenPath = o.path;
        return jsonBody({
          'success': true,
          'message': 'Customer deactivated successfully',
        });
      };
      final result = await repo.delete(5);
      expect(result, isA<ApiSuccess<void>>());
      expect(seenPath, '/customers/5');
    });
  });

  group('AuthRepository', () {
    late AuthRepository repo;

    setUp(() => repo = AuthRepository(api));

    test(
      'changePassword posts camelCase body and accepts the success envelope',
      () async {
        Map<String, dynamic>? seenBody;
        handler = (o) {
          seenBody = o.data as Map<String, dynamic>;
          return jsonBody({
            'success': true,
            'data': {'message': 'Password changed successfully'},
          });
        };
        final result = await repo.changePassword(
          currentPassword: 'old123',
          newPassword: 'newpass123',
        );
        expect(result, isA<ApiSuccess<void>>());
        expect(seenBody!['currentPassword'], 'old123');
        expect(seenBody!['newPassword'], 'newpass123');
      },
    );

    test(
      'changePassword maps a 401 (wrong current password) to failure',
      () async {
        handler = (o) => jsonBody({
          'success': false,
          'error': {
            'code': 'UNAUTHORIZED',
            'message': 'Current password is incorrect',
          },
        }, status: 401);
        final result = await repo.changePassword(
          currentPassword: 'nope',
          newPassword: 'newpass123',
        );
        final failure = result as ApiFailure<void>;
        expect(failure.error.statusCode, 401);
        expect(failure.error.message, 'Current password is incorrect');
      },
    );
  });

  group('InventoryRepository', () {
    late InventoryRepository repo;

    setUp(() => repo = InventoryRepository(api));

    test('items parses the enveloped array and forwards filters', () async {
      Map<String, dynamic>? seenQuery;
      handler = (o) {
        seenQuery = o.queryParameters;
        return jsonBody({
          'success': true,
          'data': [
            {
              'id': 1,
              'item_code': 'FG1',
              'item_name': 'Soap',
              'unit_of_measure': 'pcs',
              'current_stock': 10,
              'is_raw_material': 0,
              'is_finished_good': 1,
              'sale_type': 'packed',
            },
          ],
        });
      };
      final result = await repo.items(search: 'soap', isFinishedGood: true);
      final items = result.requireData;
      expect(items.single.itemName, 'Soap');
      expect(items.single.isFinishedGood, true);
      expect(items.single.saleType.value, 'packed');
      expect(seenQuery!['search'], 'soap');
      expect(seenQuery!['is_finished_good'], true);
    });

    test('itemDetail parses the stock_by_warehouse breakdown', () async {
      handler = (o) => jsonBody({
        'id': 1,
        'item_code': 'FG1',
        'item_name': 'Soap',
        'unit_of_measure': 'pcs',
        'current_stock': 5,
        'is_raw_material': 0,
        'is_finished_good': 1,
        'stock_by_warehouse': [
          {
            'warehouse_id': 1,
            'warehouse_code': 'WH1',
            'warehouse_name': 'Main',
            'quantity': 3,
          },
          {
            'warehouse_id': 2,
            'warehouse_code': 'WH2',
            'warehouse_name': 'Secondary',
            'quantity': 2,
          },
        ],
      });
      final result = await repo.itemDetail(1);
      final detail = result.requireData;
      expect(detail.item.itemName, 'Soap');
      expect(detail.item.currentStock, 5);
      expect(detail.stockByWarehouse.length, 2);
      expect(detail.stockByWarehouse.first.warehouseName, 'Main');
      expect(detail.stockByWarehouse.first.quantity, 3);
    });

    test('item parses the bare detail object', () async {
      handler = (o) => jsonBody({
        'id': 7,
        'item_code': 'FG1',
        'item_name': 'Soap',
        'unit_of_measure': 'pcs',
        'current_stock': 5,
        'is_raw_material': 0,
        'is_finished_good': 1,
        'stock_by_warehouse': [
          {'warehouse_id': 1, 'warehouse_code': 'WH1', 'quantity': 5},
        ],
      });
      final result = await repo.item(7);
      expect(result.requireData.itemName, 'Soap');
      expect(result.requireData.currentStock, 5);
    });

    test('create parses the bare created object', () async {
      handler = (o) => jsonBody({
        'id': 9,
        'item_code': 'FG9',
        'item_name': 'Cream',
        'unit_of_measure': 'pcs',
        'current_stock': 0,
        'is_raw_material': 0,
        'is_finished_good': 1,
      }, status: 201);
      final result = await repo.create({
        'item_code': 'FG9',
        'item_name': 'Cream',
      });
      expect(result.requireData.itemName, 'Cream');
      expect(result.requireData.id, 9);
    });

    test('categories parses bare [{category}] rows', () async {
      handler = (o) => jsonBody([
        {'category': 'Raw Materials'},
        {'category': 'Finished Goods'},
      ]);
      final result = await repo.categories();
      expect(result.requireData, ['Raw Materials', 'Finished Goods']);
    });

    test('unitsOfMeasure parses a bare string array', () async {
      handler = (o) => jsonBody(['Nos', 'Kg', 'Ltr']);
      final result = await repo.unitsOfMeasure();
      expect(result.requireData, ['Nos', 'Kg', 'Ltr']);
    });

    test('lowStock parses bare item rows', () async {
      handler = (o) => jsonBody([
        {
          'id': 2,
          'item_code': 'RM2',
          'item_name': 'Flour',
          'unit_of_measure': 'kg',
          'current_stock': 1,
          'is_raw_material': 1,
        },
      ]);
      final result = await repo.lowStock();
      expect(result.requireData.single.currentStock, 1);
    });
  });

  group('ExpenseRepository', () {
    late ExpenseRepository repo;

    setUp(() => repo = ExpenseRepository(api));

    test(
      'expenses parses rows and forwards filters as snake_case query params',
      () async {
        Map<String, dynamic>? seenQuery;
        handler = (o) {
          seenQuery = o.queryParameters;
          return jsonBody({
            'success': true,
            'data': [
              {
                'id': 1,
                'expense_no': 'EXP-2605-0001',
                'expense_category': 'Fuel',
                'description': '',
                'amount': 1000,
                'expense_date': '2026-05-22',
                'payment_method': 'Cash',
                'reference_no': '34f3f33',
                'vendor_name': 'abc',
                'project': null,
                'status': 'Approved',
                'created_at': '2026-05-22 15:55:17',
                'created_by_name': 'Fawad',
              },
            ],
            'pagination': {
              'current_page': 1,
              'total_pages': 1,
              'total_expenses': 1,
              'per_page': 1000,
            },
          });
        };
        final result = await repo.expenses(
          ExpenseFilters(
            search: 'fuel',
            category: 'Fuel',
            status: 'Approved',
            fromDate: DateTime(2026, 5, 1),
            toDate: DateTime(2026, 5, 31),
          ),
        );

        expect(result.requireData.single.expenseNo, 'EXP-2605-0001');
        expect(result.requireData.single.amount, 1000);
        expect(seenQuery!['limit'], 1000);
        expect(seenQuery!['search'], 'fuel');
        expect(seenQuery!['category'], 'Fuel');
        expect(seenQuery!['status'], 'Approved');
        expect(seenQuery!['from_date'], '2026-05-01');
        expect(seenQuery!['to_date'], '2026-05-31');
      },
    );

    test('expenses omits empty filters', () async {
      Map<String, dynamic>? seenQuery;
      handler = (o) {
        seenQuery = o.queryParameters;
        return jsonBody({
          'success': true,
          'data': [],
          'pagination': {
            'current_page': 1,
            'total_pages': 0,
            'total_expenses': 0,
            'per_page': 1000,
          },
        });
      };
      final result = await repo.expenses(const ExpenseFilters());

      expect(result.requireData, isEmpty);
      expect(seenQuery!.containsKey('search'), isFalse);
      expect(seenQuery!.containsKey('category'), isFalse);
      expect(seenQuery!.containsKey('status'), isFalse);
      expect(seenQuery!.containsKey('from_date'), isFalse);
      expect(seenQuery!.containsKey('to_date'), isFalse);
    });

    test('categories parses enveloped category rows', () async {
      handler = (o) => jsonBody({
        'success': true,
        'data': [
          {
            'id': 12,
            'category_name': 'Equipment',
            'description': 'Purchase of equipment and tools',
            'is_active': 1,
          },
          {'id': 13, 'category_name': 'Fuel', 'is_active': 1},
        ],
      });
      final result = await repo.categories();
      expect(result.requireData, hasLength(2));
      expect(result.requireData.first.categoryName, 'Equipment');
      expect(result.requireData.first.isActive, isTrue);
    });

    test('statusOptions parses value/label rows', () async {
      handler = (o) => jsonBody({
        'success': true,
        'data': [
          {'value': 'Draft', 'label': 'Draft'},
          {'value': 'Approved', 'label': 'Approved'},
        ],
      });
      final result = await repo.statusOptions();
      expect(result.requireData.map((o) => o.value), ['Draft', 'Approved']);
    });

    test('paymentMethodOptions parses value/label rows', () async {
      handler = (o) => jsonBody({
        'success': true,
        'data': [
          {'value': 'Cash', 'label': 'Cash'},
          {'value': 'Bank Transfer', 'label': 'Bank Transfer'},
        ],
      });
      final result = await repo.paymentMethodOptions();
      expect(result.requireData.last.label, 'Bank Transfer');
    });

    test(
      'create posts snake_case body and parses the created expense',
      () async {
        Map<String, dynamic>? seenBody;
        handler = (o) {
          seenBody = o.data as Map<String, dynamic>;
          return jsonBody({
            'success': true,
            'message': 'Expense created successfully',
            'data': {
              'id': 7,
              'expense_no': 'EXP-2608-0001',
              'expense_category': seenBody!['expense_category'],
              'description': seenBody!['description'],
              'amount': seenBody!['amount'],
              'expense_date': seenBody!['expense_date'],
              'payment_method': seenBody!['payment_method'],
              'status': seenBody!['status'],
            },
          }, status: 201);
        };
        final result = await repo.create({
          'expense_category': 'Fuel',
          'description': 'Generator diesel',
          'amount': 500,
          'expense_date': '2026-08-04',
          'payment_method': 'Cash',
          'status': 'Approved',
        });

        expect(seenBody!['expense_category'], 'Fuel');
        expect(seenBody!['amount'], 500);
        expect(seenBody!['expense_date'], '2026-08-04');
        expect(result.requireData.expenseNo, 'EXP-2608-0001');
        expect(result.requireData.amount, 500);
      },
    );

    test('update PUTs to /expenses/:id', () async {
      String? seenPath;
      handler = (o) {
        seenPath = o.path;
        return jsonBody({
          'success': true,
          'message': 'Expense updated successfully',
          'data': {'id': 7, 'expense_no': 'EXP-2608-0001', 'status': 'Paid'},
        });
      };
      final result = await repo.update(7, {'status': 'Paid'});
      expect(seenPath, '/expenses/7');
      expect(result.requireData.status, 'Paid');
    });

    test('delete forwards to DELETE /expenses/:id', () async {
      String? seenPath;
      handler = (o) {
        seenPath = o.path;
        return jsonBody({
          'success': true,
          'message': 'Expense deleted successfully',
        });
      };
      final result = await repo.delete(7);
      expect(seenPath, '/expenses/7');
      expect(result, isA<ApiSuccess<void>>());
    });
  });

  group('InvoiceRepository', () {
    late InvoiceRepository repo;

    setUp(() => repo = InvoiceRepository(api));

    Map<String, dynamic> row(int id, String invoiceNo) => {
      'id': id,
      'invoice_no': invoiceNo,
      'customer_id': 3,
      'so_id': null,
      'invoice_date': '2026-05-22',
      'due_date': '2026-06-21',
      'status': 'Unpaid',
      'total_amount': 1500,
      'paid_amount': 0,
      'balance_amount': 1500,
      'notes': null,
      'created_by': 1,
      'created_at': '2026-05-22 10:00:00',
      'updated_at': '2026-05-22 10:00:00',
      'source_type': 'manual',
      'quotation_id': null,
      'customer_name': 'Acme Corp',
      'discount_scope': 'invoice',
      'discount_type': 'flat',
      'discount_value': 0,
      'terms': null,
      'returned_amount': 0,
      'return_fee': 0,
      'so_no': null,
      'quotation_no': null,
      'created_by_username': 'Fawad',
    };

    test(
      'invoices parses rows and forwards status as CSV query param',
      () async {
        Map<String, dynamic>? seenQuery;
        handler = (o) {
          seenQuery = o.queryParameters;
          return jsonBody({
            'success': true,
            'data': [row(1, 'INV-2026-440955'), row(2, 'INV-2026-440956')],
          });
        };
        final result = await repo.invoices(
          filters: const InvoiceFilters(status: 'Paid,Overdue'),
        );

        expect(result.requireData, hasLength(2));
        expect(result.requireData.first.invoiceNo, 'INV-2026-440955');
        expect(result.requireData.first.customerName, 'Acme Corp');
        expect(result.requireData.first.status, 'Unpaid');
        expect(result.requireData.first.totalAmount, 1500);
        expect(result.requireData.first.balanceAmount, 1500);
        expect(result.requireData.first.createdByUsername, 'Fawad');
        expect(seenQuery!['status'], 'Paid,Overdue');
      },
    );

    test('invoices omits the status param when unfiltered', () async {
      Map<String, dynamic>? seenQuery;
      handler = (o) {
        seenQuery = o.queryParameters;
        return jsonBody({
          'success': true,
          'data': [row(1, 'INV-2026-440955')],
        });
      };
      final result = await repo.invoices();

      expect(result.requireData, hasLength(1));
      expect(seenQuery!.containsKey('status'), isFalse);
    });

    test('invoice gets the bare detail object with items', () async {
      handler = (o) => jsonBody({
        ...row(1, 'INV-2026-440955'),
        'items': [
          {
            'id': 10,
            'invoice_id': 1,
            'item_id': 4,
            'item_code': 'FUEL',
            'item_name': 'Diesel',
            'quantity': 10,
            'unit_price': 100,
            'amount': 1000,
            'tax_rate': 0,
            'discount_type': 'none',
            'discount_value': 0,
            'returned_qty': 0,
          },
        ],
      });
      final result = await repo.invoice(1);

      expect(result.requireData.invoiceNo, 'INV-2026-440955');
      expect(result.requireData.items, hasLength(1));
      expect(result.requireData.items!.single.itemName, 'Diesel');
      expect(result.requireData.items!.single.quantity, 10);
      expect(result.requireData.items!.single.unitPrice, 100);
    });

    test(
      'create posts snake_case body and parses the bare created invoice',
      () async {
        Map<String, dynamic>? seenBody;
        handler = (o) {
          seenBody = o.data as Map<String, dynamic>;
          return jsonBody({
            'id': 9,
            'invoice_no': seenBody!['invoice_no'],
            'customer_id': seenBody!['customer_id'],
            'invoice_date': seenBody!['invoice_date'],
            'status': 'Unpaid',
            'total_amount': seenBody!['total_amount'],
            'paid_amount': 0,
            'balance_amount': seenBody!['total_amount'],
            'customer_name': 'Acme Corp',
            'created_by_username': 'Fawad',
            'items': seenBody!['items'],
          }, status: 201);
        };
        final result = await repo.create({
          'invoice_no': 'INV-2026-999001',
          'customer_id': 3,
          'invoice_date': '2026-08-04',
          'due_date': '2026-09-03',
          'status': 'Unpaid',
          'discount_scope': 'invoice',
          'discount_type': 'flat',
          'discount_value': 0,
          'items': [
            {
              'item_id': 4,
              'quantity': 10,
              'unit_price': 100,
              'tax_rate': 0,
              'discount_type': 'none',
              'discount_value': 0,
            },
          ],
          'total_amount': 1000,
        });

        expect(seenBody!['customer_id'], 3);
        expect(seenBody!['items'], hasLength(1));
        expect((seenBody!['items'] as List).first['item_id'], 4);
        expect(seenBody!['total_amount'], 1000);
        expect(result.requireData.invoiceNo, 'INV-2026-999001');
        expect(result.requireData.status, 'Unpaid');
        expect(result.requireData.items, hasLength(1));
      },
    );

    test('update PUTs to /invoices/:id', () async {
      String? seenPath;
      handler = (o) {
        seenPath = o.path;
        return jsonBody({
          'id': 7,
          'invoice_no': 'INV-2026-440955',
          'status': 'Paid',
        });
      };
      final result = await repo.update(7, {'status': 'Paid'});
      expect(seenPath, '/invoices/7');
      expect(result.requireData.status, 'Paid');
    });

    test('delete tolerates the bare {message} body (no envelope)', () async {
      String? seenPath;
      handler = (o) {
        seenPath = o.path;
        return jsonBody({'message': 'Invoice deleted successfully'});
      };
      final result = await repo.delete(7);
      expect(seenPath, '/invoices/7');
      expect(result, isA<ApiSuccess<void>>());
    });

    test(
      'cancel PUTs to /invoices/:id/cancel and unwraps the envelope',
      () async {
        String? seenPath;
        handler = (o) {
          seenPath = o.path;
          return jsonBody({
            'success': true,
            'message': 'Invoice cancelled successfully',
            'data': {
              'id': 7,
              'invoice_no': 'INV-2026-440955',
              'status': 'Cancelled',
            },
          });
        };
        final result = await repo.cancel(7);
        expect(seenPath, '/invoices/7/cancel');
        expect(result.requireData.status, 'Cancelled');
      },
    );
  });

  group('DashboardRepository', () {
    late DashboardRepository repo;

    setUp(() => repo = DashboardRepository(api));

    test('topCustomers parses the array and forwards limit', () async {
      Map<String, dynamic>? seenQuery;
      handler = (o) {
        seenQuery = o.queryParameters;
        return jsonBody({
          'success': true,
          'data': [
            {
              'customer_name': 'Alpha Traders',
              'total_revenue': 452300.50,
              'invoice_count': 18,
            },
            {
              'customer_name': 'Beta Stores',
              'total_revenue': 99000,
              'invoice_count': 5,
            },
          ],
        });
      };
      final result = await repo.topCustomers(limit: 5);
      final rows = result.requireData;
      expect(rows, hasLength(2));
      expect(rows.first.customerName, 'Alpha Traders');
      expect(rows.first.totalRevenue, 452300.50);
      expect(rows.last.invoiceCount, 5);
      expect(seenQuery!['limit'], 5);
    });

    test('salesSummary forwards period and parses totals', () async {
      Map<String, dynamic>? seenQuery;
      handler = (o) {
        seenQuery = o.queryParameters;
        return jsonBody({
          'success': true,
          'data': {'period_total': 123456.75, 'count': 9},
        });
      };
      final result = await repo.salesSummary(period: 'week');
      expect(result.requireData.periodTotal, 123456.75);
      expect(result.requireData.count, 9);
      expect(seenQuery!['period'], 'week');
    });

    test('expenseSummary forwards period', () async {
      Map<String, dynamic>? seenQuery;
      handler = (o) {
        seenQuery = o.queryParameters;
        return jsonBody({
          'success': true,
          'data': {'period_total': 6543.25, 'count': 4},
        });
      };
      final result = await repo.expenseSummary(period: 'month');
      expect(result.requireData.periodTotal, 6543.25);
      expect(seenQuery!['period'], 'month');
    });

    test('productionStatus parses the status counts', () async {
      handler = (o) => jsonBody({
        'success': true,
        'data': {'total': 20, 'active': 5, 'completed': 12, 'cancelled': 3},
      });
      final row = (await repo.productionStatus()).requireData;
      expect(row.total, 20);
      expect(row.active, 5);
      expect(row.completed, 12);
      expect(row.cancelled, 3);
    });

    test('stockMovementSummary forwards days and parses qty', () async {
      Map<String, dynamic>? seenQuery;
      handler = (o) {
        seenQuery = o.queryParameters;
        return jsonBody({
          'success': true,
          'data': {'inbound_qty': 850, 'outbound_qty': 320, 'net': 530},
        });
      };
      final row = (await repo.stockMovementSummary(days: 14)).requireData;
      expect(row.inboundQty, 850);
      expect(row.outboundQty, 320);
      expect(row.net, 530);
      expect(seenQuery!['days'], 14);
    });

    test('kpi forwards metric and parses the gauge', () async {
      Map<String, dynamic>? seenQuery;
      handler = (o) {
        seenQuery = o.queryParameters;
        return jsonBody({
          'success': true,
          'data': {
            'metric': 'stock_health',
            'value': 87.5,
            'unit': '%',
            'label': 'Stock Health',
          },
        });
      };
      final row = (await repo.kpi(metric: 'stock_health')).requireData;
      expect(row.metric, 'stock_health');
      expect(row.value, 87.5);
      expect(row.unit, '%');
      expect(seenQuery!['metric'], 'stock_health');
    });

    test('arSummary parses total + aging buckets', () async {
      handler = (o) => jsonBody({
        'success': true,
        'data': {
          'total_ar': 250000,
          'current_amount': 80000,
          'amount_1_30': 60000,
          'amount_31_60': 50000,
          'amount_61_90': 40000,
          'amount_over_90': 20000,
          'customer_count': 7,
        },
      });
      final row = (await repo.arSummary()).requireData;
      expect(row.totalAr, 250000);
      expect(row.currentAmount, 80000);
      expect(row.amount130, 60000);
      expect(row.amount3160, 50000);
      expect(row.amount6190, 40000);
      expect(row.amountOver90, 20000);
      expect(row.customerCount, 7);
    });
  });

  group('ProductionRepository', () {
    late ProductionRepository repo;

    setUp(() {
      repo = ProductionRepository(api);
    });

    test('productions GETs /productions with the optional filters', () async {
      Map<String, dynamic>? seenQuery;
      handler = (o) {
        seenQuery = o.queryParameters;
        return jsonBody([
          {
            'id': 9,
            'production_no': 'PROD-2026-005',
            'output_item_id': 4,
            'output_quantity': 10,
            'warehouse_id': 2,
            'production_date': '2026-08-10',
          },
        ]);
      };
      final result = await repo.productions(
        const ProductionFilters(
          startDate: '2026-08-01',
          endDate: '2026-08-31',
          outputItemId: 4,
          warehouseId: 2,
          limit: 50,
        ),
      );
      expect(seenQuery, {
        'start_date': '2026-08-01',
        'end_date': '2026-08-31',
        'output_item_id': 4,
        'warehouse_id': 2,
        'limit': 50,
      });
      expect(result.requireData.single.productionNo, 'PROD-2026-005');
    });

    test('productions without filters sends no query parameters', () async {
      Map<String, dynamic>? seen;
      handler = (o) {
        seen = o.queryParameters;
        return jsonBody(const []);
      };
      final result = await repo.productions();
      expect(seen, isEmpty);
      expect(result.requireData, isEmpty);
    });

    test('production GETs /productions/:id with inputs', () async {
      String? seenPath;
      handler = (o) {
        seenPath = o.path;
        return jsonBody({
          'id': 9,
          'production_no': 'PROD-2026-005',
          'output_item_id': 1,
          'output_quantity': 10,
          'warehouse_id': 2,
          'production_date': '2026-08-10',
          'batch_no': 'BATCH-26-PRD-0005',
          'unit_cost': 12.5,
          'total_material_cost': 100,
          'total_batch_cost': 125,
          'inputs': [
            {
              'id': 1,
              'production_id': 9,
              'item_id': 7,
              'quantity': 4,
              'warehouse_id': 2,
              'item_name': 'Flour',
              'unit_of_measure': 'kg',
            },
          ],
        });
      };
      final result = await repo.production(9);
      expect(seenPath, '/productions/9');
      final p = result.requireData;
      expect(p.batchNo, 'BATCH-26-PRD-0005');
      expect(p.unitCost, 12.5);
      expect(p.inputs.single.itemName, 'Flour');
      expect(p.inputs.single.quantity, 4);
    });

    test(
      'createProduction POSTs to /productions with a bare 201 body',
      () async {
        String? seenPath;
        Map<String, dynamic>? seenBody;
        handler = (o) {
          seenPath = o.path;
          seenBody = o.data as Map<String, dynamic>;
          return jsonBody({
            'id': 10,
            'production_no': 'PROD-2026-006',
            'output_item_id': 1,
            'output_quantity': 10,
            'warehouse_id': 2,
            'production_date': '2026-08-11',
          }, status: 201);
        };
        final result = await repo.createProduction({
          'output_item_id': 1,
          'output_quantity': 10,
          'warehouse_id': 2,
          'production_date': '2026-08-11',
          'input_items': [
            {'item_id': 7, 'quantity': 4},
          ],
        });
        expect(seenPath, '/productions');
        expect(seenBody!['output_quantity'], 10);
        expect((seenBody!['input_items'] as List).first['item_id'], 7);
        expect(result.requireData.productionNo, 'PROD-2026-006');
      },
    );

    test('deleteProduction unwraps the enveloped {success, message}', () async {
      String? seenPath;
      handler = (o) {
        seenPath = o.path;
        return jsonBody({'success': true, 'message': 'Production deleted'});
      };
      final result = await repo.deleteProduction(9);
      expect(seenPath, '/productions/9');
      expect(result, isA<ApiSuccess<void>>());
    });

    test('boms GETs the bare BOM list', () async {
      String? seenPath;
      handler = (o) {
        seenPath = o.path;
        return jsonBody([
          {
            'id': 1,
            'bom_no': 'BOM-2026-001',
            'bom_name': 'Widget Kit',
            'finished_item_id': 3,
            'quantity': 10,
            'is_active': 1,
            'item_count': 2,
            'total_material_cost': 55,
          },
        ]);
      };
      final result = await repo.boms();
      expect(seenPath, '/boms');
      expect(result.requireData.single.bomName, 'Widget Kit');
      expect(result.requireData.single.itemCount, 2);
      expect(result.requireData.single.isActive, true);
    });

    test('bom GETs /boms/:id and parses items + total material cost', () async {
      String? seenPath;
      handler = (o) {
        seenPath = o.path;
        return jsonBody({
          'id': 1,
          'bom_no': 'BOM-2026-001',
          'bom_name': 'Widget Kit',
          'finished_item_id': 3,
          'quantity': 10,
          'is_active': 1,
          'total_material_cost': 55,
          'items': [
            {
              'id': 11,
              'item_id': 7,
              'item_name': 'Flour',
              'unit_of_measure': 'kg',
              'current_stock': 40,
              'quantity': 2,
              'standard_cost': 5,
              'line_cost': 10,
            },
          ],
        });
      };
      final result = await repo.bom(1);
      expect(seenPath, '/boms/1');
      final bom = result.requireData;
      expect(bom.totalMaterialCost, 55);
      expect(bom.items.single.itemName, 'Flour');
      expect(bom.items.single.lineCost, 10);
    });

    test('bomsByFinishedItem GETs the by-item endpoint', () async {
      String? seenPath;
      handler = (o) {
        seenPath = o.path;
        return jsonBody([
          {
            'id': 2,
            'bom_no': 'BOM-2026-002',
            'bom_name': 'Big Kit',
            'finished_item_id': 3,
            'quantity': 20,
          },
        ]);
      };
      final result = await repo.bomsByFinishedItem(3);
      expect(seenPath, '/boms/by-item/3');
      expect(result.requireData.single.bomNo, 'BOM-2026-002');
    });

    test('createBom POSTs with a bare BomDetail 201 body', () async {
      Map<String, dynamic>? seenBody;
      handler = (o) {
        seenBody = o.data as Map<String, dynamic>;
        return jsonBody({
          'id': 5,
          'bom_no': 'BOM-2026-005',
          'bom_name': 'New Kit',
          'finished_item_id': 3,
          'quantity': 8,
          'is_active': 1,
          'items': [
            {'id': 51, 'item_id': 7, 'quantity': 2},
          ],
        }, status: 201);
      };
      final result = await repo.createBom({
        'bom_name': 'New Kit',
        'finished_item_id': 3,
        'quantity': 8,
        'items': [
          {'item_id': 7, 'quantity': 2},
        ],
      });
      expect(seenBody!['bom_name'], 'New Kit');
      expect((seenBody!['items'] as List).length, 1);
      expect(result.requireData.id, 5);
      expect(result.requireData.items, hasLength(1));
    });

    test('updateBom PUTs and toggleBomActive PATCHes', () async {
      final seen = <String>[];
      handler = (o) {
        seen.add('${o.method} ${o.path}');
        return jsonBody({
          'id': 5,
          'bom_no': 'BOM-2026-005',
          'bom_name': 'New Kit',
          'finished_item_id': 3,
          'quantity': 8,
        });
      };
      await repo.updateBom(5, {'quantity': 12});
      await repo.toggleBomActive(5);
      expect(seen, ['PUT /boms/5', 'PATCH /boms/5/toggle-active']);
    });

    test('deleteBom tolerates the bare {message} body', () async {
      String? seenPath;
      handler = (o) {
        seenPath = o.path;
        return jsonBody({'message': 'BOM deleted successfully'});
      };
      final result = await repo.deleteBom(1);
      expect(seenPath, '/boms/1');
      expect(result, isA<ApiSuccess<void>>());
    });
  });
}
