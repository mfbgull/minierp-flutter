// Auth-flow widget tests (PORTING.md §3):
//   1. No stored token → splash → redirected to the login screen.
//   2. Login via the real authProvider path (fake dio adapter for the
//      network) → token persisted → router redirects to the dashboard.
//   3. Stored token + valid GET /auth/me → boots straight to the dashboard
//      (session restore).
//
// TokenStorage is overridden with an in-memory fake: the real
// flutter_secure_storage Linux FFI blocks on the system keyring daemon,
// which doesn't exist under `flutter test`.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:minierp_app/app.dart';
import 'package:minierp_app/core/api/api_client.dart';
import 'package:minierp_app/core/auth/token_storage.dart';
import 'package:minierp_app/features/auth/change_password_screen.dart';
import 'package:minierp_app/features/customers/customer_ledger_dialog.dart';
import 'package:minierp_app/features/suppliers/supplier_ledger_dialog.dart';
import 'package:pluto_grid/pluto_grid.dart';

class _FakeTokenStorage implements TokenStorage {
  String? token;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> writeToken(String value) async => token = value;

  @override
  Future<void> clear() async => token = null;
}

class _AuthFakeAdapter implements HttpClientAdapter {
  _AuthFakeAdapter({
    this.failLogin = false,
    this.changePasswordFails = false,
    this.role = 'admin',
  });

  final bool failLogin;
  final bool changePasswordFails;
  final String role;

  /// Mutable so a test can fail once, then retry successfully.
  bool failItems = false;

  /// Captured create/update bodies for the item form tests.
  Map<String, dynamic>? lastItemPostBody;
  Map<String, dynamic>? lastItemPutBody;

  /// Last /customers query params (for pagination/search/sort assertions).
  Map<String, dynamic>? lastCustomersQuery;

  /// Captured create/update bodies for the customer form tests.
  Map<String, dynamic>? lastCustomerPostBody;
  Map<String, dynamic>? lastCustomerPutBody;

  /// Last /suppliers query params (for pagination assertions).
  Map<String, dynamic>? lastSuppliersQuery;

  /// Captured create/update bodies for the supplier form tests.
  Map<String, dynamic>? lastSupplierPostBody;
  Map<String, dynamic>? lastSupplierPutBody;

  /// Captured create/update bodies for the expense form tests.
  Map<String, dynamic>? lastExpensePostBody;
  Map<String, dynamic>? lastExpensePutBody;

  /// Last /invoices query params + captured create/update bodies.
  Map<String, dynamic>? lastInvoicesQuery;
  Map<String, dynamic>? lastInvoicePostBody;
  Map<String, dynamic>? lastInvoicePutBody;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == '/auth/login' && failLogin) {
      return _json({
        'success': false,
        'error': {
          'code': 'UNAUTHORIZED',
          'message': 'Invalid username or password',
        },
      }, status: 401);
    }
    if (options.path == '/auth/login') {
      return _json({
        'success': true,
        'data': {
          'token': 'test-token',
          'user': {
            'id': 1,
            'username': 'admin',
            'full_name': 'Fawad',
            'role': role,
            'is_active': 1,
          },
        },
      });
    }
    if (options.path == '/auth/me') {
      return _json({
        'success': true,
        'data': {
          'id': 1,
          'username': 'admin',
          'full_name': 'Fawad',
          'role': role,
          'is_active': 1,
        },
      });
    }
    if (options.path == '/auth/change-password') {
      if (changePasswordFails) {
        return _json({
          'success': false,
          'error': {
            'code': 'UNAUTHORIZED',
            'message': 'Current password is incorrect',
          },
        }, status: 401);
      }
      return _json({
        'success': true,
        'data': {'message': 'Password changed successfully'},
      });
    }
    if (options.path == '/customers' && options.method == 'GET') {
      final q = options.queryParameters;
      lastCustomersQuery = q;
      const namedCustomers = [
        {
          'id': 1,
          'customer_code': 'CUST001',
          'customer_name': 'Acme Corp',
          'phone': '555-0101',
          'email': 'a@acme.com',
          'current_balance': 120.5,
          'is_active': 1,
        },
        {
          'id': 2,
          'customer_code': 'CUST002',
          'customer_name': 'Beta Ltd',
          'phone': '555-0102',
          'email': 'b@beta.com',
          'current_balance': 0,
          'is_active': 1,
        },
        {
          'id': 3,
          'customer_code': 'CUST003',
          'customer_name': 'Gamma Inc',
          'phone': '555-0103',
          'email': 'g@gamma.com',
          'current_balance': -50,
          'is_active': 0,
        },
        {
          'id': 4,
          'customer_code': 'CUST004',
          'customer_name': 'Delta Co',
          'phone': '555-0104',
          'email': 'd@delta.com',
          'current_balance': 75,
          'is_active': 1,
        },
        {
          'id': 5,
          'customer_code': 'CUST005',
          'customer_name': 'Epsilon LLC',
          'phone': '555-0105',
          'email': 'e@eps.com',
          'current_balance': 200,
          'is_active': 1,
        },
      ];
      // 25 total (5 named + 20 generated) → 3 pages at limit 10.
      final allCustomers = [
        ...namedCustomers,
        for (var i = 6; i <= 25; i++)
          {
            'id': i,
            'customer_code': 'CUST${i.toString().padLeft(3, '0')}',
            'customer_name': 'Customer $i',
            'phone': '555-01${i.toString().padLeft(2, '0')}',
            'email': 'c$i@example.com',
            'current_balance': i * 10.0,
            'is_active': 1,
          },
      ];
      // The server filters on `search` and slices `page/limit`.
      final search = (q['search'] as String?) ?? '';
      final filtered = allCustomers
          .where(
            (c) =>
                search.isEmpty ||
                (c['customer_name'] as String).toLowerCase().contains(
                  search.toLowerCase(),
                ) ||
                (c['customer_code'] as String).toLowerCase().contains(
                  search.toLowerCase(),
                ),
          )
          .toList();
      final limit = int.tryParse('${q['limit']}') ?? 10;
      final page = int.tryParse('${q['page']}') ?? 1;
      final totalPages = (filtered.length / limit).ceil();
      final start = (page - 1) * limit;
      final end = start + limit > filtered.length
          ? filtered.length
          : start + limit;
      final data = start >= filtered.length
          ? <Map<String, dynamic>>[]
          : filtered.sublist(start, end);
      return _json({
        'success': true,
        'data': data,
        'pagination': {
          'currentPage': page,
          'totalPages': totalPages,
          'totalItems': filtered.length,
          'hasNext': page < totalPages,
          'hasPrev': page > 1,
        },
      });
    }
    if (options.path == '/customers/1' && options.method == 'GET') {
      // Bare customer detail object (GET /customers/:id) — the shape the
      // detail dialog renders (the list payload above omits these fields).
      return _json({
        'success': true,
        'data': {
          'id': 1,
          'customer_code': 'CUST001',
          'customer_name': 'Acme Corp',
          'contact_person': 'Jane Doe',
          'phone': '555-0101',
          'email': 'a@acme.com',
          'billing_address': '1 Main St, Springfield',
          'shipping_address': '2 Main St, Springfield',
          'payment_terms': 'Net 30',
          'payment_terms_days': 30,
          'credit_limit': 5000.0,
          'credit_utilization_percent': 2.41,
          'current_balance': 120.5,
          'opening_balance': 0.0,
          'is_active': 1,
          'created_at': '2025-01-15',
          'updated_at': '2026-02-03',
        },
      });
    }
    if (options.path == '/customers' && options.method == 'POST') {
      final body = options.data as Map<String, dynamic>;
      lastCustomerPostBody = body;
      // Enveloped 201 — the real server's createCustomer shape (code is
      // server-generated; the form never sends it).
      return _json({
        'success': true,
        'data': {
          'id': 99,
          'customer_code': 'CUST099',
          'customer_name': body['customer_name'],
          'phone': body['phone'],
          'current_balance': 0,
          'is_active': 1,
        },
        'message': 'Customer created successfully',
      }, status: 201);
    }
    if (options.path == '/customers/1' && options.method == 'PUT') {
      final body = options.data as Map<String, dynamic>;
      lastCustomerPutBody = body;
      return _json({
        'success': true,
        'data': {
          'id': 1,
          'customer_code': 'CUST001',
          'customer_name': body['customer_name'],
          'phone': body['phone'],
          'current_balance': 120.5,
          'is_active': 1,
        },
        'message': 'Customer updated successfully',
      });
    }
    if (options.path == '/customers/1/ledger' && options.method == 'GET') {
      // Enveloped array — the real getCustomerLedger shape, newest-first
      // (first row carries the latest running balance = closing balance).
      return _json({
        'success': true,
        'data': [
          {
            'id': 1,
            'transaction_date': '2026-01-20',
            'transaction_type': 'INVOICE',
            'reference_no': 'INV-2026-001',
            'description': 'Invoice for goods',
            'debit': 500.0,
            'credit': 0.0,
            'balance': 620.5,
          },
          {
            'id': 2,
            'transaction_date': '2026-01-10',
            'transaction_type': 'PAYMENT',
            'reference_no': 'PAY-2026-005',
            'description': 'Payment received',
            'debit': 0.0,
            'credit': 200.0,
            'balance': 120.5,
          },
        ],
      });
    }
    if (options.path == '/suppliers' && options.method == 'GET') {
      final q = options.queryParameters;
      lastSuppliersQuery = q;
      const namedSuppliers = [
        {
          'id': 1,
          'supplier_code': 'SUP001',
          'supplier_name': 'Alpha Traders',
          'phone': '555-0201',
          'email': 'a@alpha.com',
          'current_balance': 250.0,
          'is_active': 1,
        },
        {
          'id': 2,
          'supplier_code': 'SUP002',
          'supplier_name': 'Beta Supplies',
          'phone': '555-0202',
          'email': 'b@beta.com',
          'current_balance': 0,
          'is_active': 1,
        },
        {
          'id': 3,
          'supplier_code': 'SUP003',
          'supplier_name': 'Gamma Goods',
          'phone': '555-0203',
          'email': 'g@gamma.com',
          'current_balance': -50.0,
          'is_active': 0,
        },
        {
          'id': 4,
          'supplier_code': 'SUP004',
          'supplier_name': 'Delta Wholesale',
          'phone': '555-0204',
          'email': 'd@delta.com',
          'current_balance': 75.0,
          'is_active': 1,
        },
        {
          'id': 5,
          'supplier_code': 'SUP005',
          'supplier_name': 'Epsilon Mart',
          'phone': '555-0205',
          'email': 'e@eps.com',
          'current_balance': 200.0,
          'is_active': 1,
        },
      ];
      // 25 total (5 named + 20 generated) → 3 pages at limit 10.
      final allSuppliers = [
        ...namedSuppliers,
        for (var i = 6; i <= 25; i++)
          {
            'id': i,
            'supplier_code': 'SUP${i.toString().padLeft(3, '0')}',
            'supplier_name': 'Supplier $i',
            'phone': '555-02${i.toString().padLeft(2, '0')}',
            'email': 's$i@example.com',
            'current_balance': i * 10.0,
            'is_active': 1,
          },
      ];
      final limit = int.tryParse('${q['limit']}') ?? 10;
      final page = int.tryParse('${q['page']}') ?? 1;
      final totalPages = (allSuppliers.length / limit).ceil();
      final start = (page - 1) * limit;
      final end = start + limit > allSuppliers.length
          ? allSuppliers.length
          : start + limit;
      final data = start >= allSuppliers.length
          ? <Map<String, dynamic>>[]
          : allSuppliers.sublist(start, end);
      return _json({
        'success': true,
        'data': data,
        'pagination': {
          'currentPage': page,
          'totalPages': totalPages,
          'totalItems': allSuppliers.length,
          'hasNext': page < totalPages,
          'hasPrev': page > 1,
        },
      });
    }
    if (options.path == '/suppliers/1' && options.method == 'GET') {
      // Bare supplier detail object (GET /suppliers/:id).
      return _json({
        'success': true,
        'data': {
          'id': 1,
          'supplier_code': 'SUP001',
          'supplier_name': 'Alpha Traders',
          'contact_person': 'Ali Raza',
          'phone': '555-0201',
          'email': 'a@alpha.com',
          'address': '12 Industrial Rd',
          'payment_terms': 'Net 30',
          'current_balance': 250.0,
          'credit_utilization_percent': 5.0,
          'is_active': 1,
        },
      });
    }
    if (options.path == '/suppliers/1/ledger' && options.method == 'GET') {
      // Enveloped array — the real getSupplierLedger shape, newest-first
      // (first row carries the latest running balance = closing balance).
      return _json({
        'success': true,
        'data': [
          {
            'id': 1,
            'transaction_date': '2026-01-20',
            'transaction_type': 'PURCHASE',
            'reference_no': 'PO-2026-001',
            'description': 'Purchase goods',
            'debit': 500.0,
            'credit': 0.0,
            'balance': 620.5,
          },
          {
            'id': 2,
            'transaction_date': '2026-01-10',
            'transaction_type': 'PAYMENT',
            'reference_no': 'PAY-2026-005',
            'description': 'Payment made',
            'debit': 0.0,
            'credit': 200.0,
            'balance': 120.5,
          },
        ],
      });
    }
    if (options.path == '/purchase-orders' && options.method == 'GET') {
      // Bare array — the real getPurchaseOrders shape (no envelope, no
      // pagination; the client grid sorts/filters client-side).
      return _json([
        {
          'id': 1,
          'po_no': 'PO-2026-001',
          'po_date': '2026-01-20',
          'supplier_id': 1,
          'supplier_name': 'Alpha Traders',
          'warehouse_name': 'Main Warehouse',
          'total_amount': 1500.0,
          'paid_amount': 500.0,
          'balance_amount': 1000.0,
          'status': 'Draft',
          'expected_delivery_date': '2026-02-01',
        },
        {
          'id': 2,
          'po_no': 'PO-2026-002',
          'po_date': '2026-01-25',
          'supplier_id': 2,
          'supplier_name': 'Beta Suppliers',
          'warehouse_name': 'Raw Materials',
          'total_amount': 2500.0,
          'paid_amount': 2500.0,
          'balance_amount': 0.0,
          'status': 'Completed',
          'expected_delivery_date': null,
        },
      ]);
    }
    if (options.path == '/purchase-orders/1' && options.method == 'GET') {
      // Bare object with items — the real getPurchaseOrder shape.
      return _json({
        'id': 1,
        'po_no': 'PO-2026-001',
        'po_date': '2026-01-20',
        'supplier_id': 1,
        'supplier_name': 'Alpha Traders',
        'warehouse_name': 'Main Warehouse',
        'total_amount': 1500.0,
        'paid_amount': 500.0,
        'balance_amount': 1000.0,
        'status': 'Draft',
        'expected_delivery_date': '2026-02-01',
        'items': [
          {
            'id': 1,
            'item_code': 'RM001',
            'item_name': 'Raw Material A',
            'unit_of_measure': 'kg',
            'quantity': 100.0,
            'unit_price': 10.0,
            'amount': 1000.0,
            'received_quantity': 0.0,
          },
          {
            'id': 2,
            'item_code': 'FG002',
            'item_name': 'Finished Good B',
            'unit_of_measure': 'pcs',
            'quantity': 10.0,
            'unit_price': 50.0,
            'amount': 500.0,
            'received_quantity': 10.0,
          },
        ],
      });
    }
    if (options.path == '/suppliers' && options.method == 'POST') {
      final body = options.data as Map<String, dynamic>;
      lastSupplierPostBody = body;
      // Enveloped 201 — the real server's createSupplier shape (the form
      // always sends supplier_code for suppliers, unlike customers).
      return _json({
        'success': true,
        'data': {
          'id': 99,
          'supplier_code': body['supplier_code'],
          'supplier_name': body['supplier_name'],
          'phone': body['phone'],
          'is_active': 1,
        },
        'message': 'Supplier created successfully',
      }, status: 201);
    }
    if (options.path == '/suppliers/1' && options.method == 'PUT') {
      final body = options.data as Map<String, dynamic>;
      lastSupplierPutBody = body;
      return _json({
        'success': true,
        'data': {
          'id': 1,
          'supplier_code': 'SUP001',
          'supplier_name': body['supplier_name'],
          'phone': body['phone'],
          'is_active': body['is_active'],
        },
        'message': 'Supplier updated successfully',
      });
    }
    if (options.path == '/inventory/items' && options.method == 'POST') {
      final body = options.data as Map<String, dynamic>;
      lastItemPostBody = body;
      return _json({
        'id': 99,
        'item_code': body['item_code'],
        'item_name': body['item_name'],
        'unit_of_measure': body['unit_of_measure'] ?? 'pcs',
        'current_stock': 0,
        'is_active': 1,
      }, status: 201);
    }
    if (options.path == '/inventory/items') {
      if (failItems) {
        return _json({
          'success': false,
          'error': {'code': 'SERVER_ERROR', 'message': 'Failed to fetch items'},
        }, status: 500);
      }
      const allItems = [
        {
          'id': 1,
          'item_code': 'FG001',
          'item_name': 'Widget A',
          'category': 'Parts',
          'unit_of_measure': 'pcs',
          'current_stock': 5,
          'reorder_level': 10,
          'standard_cost': 25.0,
          'standard_selling_price': 45.0,
          'is_raw_material': 0,
          'is_finished_good': 1,
          'is_active': 1,
        },
        {
          'id': 2,
          'item_code': 'RM002',
          'item_name': 'Bolt',
          'category': 'Raw',
          'unit_of_measure': 'box',
          'current_stock': 120,
          'reorder_level': 50,
          'standard_cost': 2.5,
          'standard_selling_price': 5.0,
          'is_raw_material': 1,
          'is_finished_good': 0,
          'is_active': 1,
        },
        {
          'id': 3,
          'item_code': 'FG003',
          'item_name': 'Old Item',
          'category': 'Parts',
          'unit_of_measure': 'pcs',
          'current_stock': 0,
          'reorder_level': null,
          'is_raw_material': 0,
          'is_finished_good': 1,
          'is_active': 0,
        },
      ];
      // The server filters code/name/description on `search`.
      final search = options.queryParameters['search'] as String?;
      final data = (search == null || search.isEmpty)
          ? allItems
          : allItems
                .where(
                  (i) =>
                      (i['item_code'] as String).toLowerCase().contains(
                        search.toLowerCase(),
                      ) ||
                      (i['item_name'] as String).toLowerCase().contains(
                        search.toLowerCase(),
                      ),
                )
                .toList();
      return _json({'success': true, 'data': data});
    }
    if (options.path == '/inventory/items/1' && options.method == 'PUT') {
      final body = options.data as Map<String, dynamic>;
      lastItemPutBody = body;
      // Full detail shape (incl. stock_by_warehouse) so the detail dialog
      // beneath the form refetches realistically after the save.
      return _json({
        'id': 1,
        'item_code': 'FG001',
        'item_name': body['item_name'],
        'unit_of_measure': body['unit_of_measure'],
        'current_stock': 5,
        'reorder_level': 10,
        'standard_cost': 25.0,
        'standard_selling_price': 45.0,
        'is_raw_material': 0,
        'is_finished_good': 1,
        'is_active': 1,
        'stock_by_warehouse': [
          {
            'warehouse_id': 1,
            'warehouse_code': 'WH-MAIN',
            'warehouse_name': 'Main Warehouse',
            'quantity': 3,
          },
          {
            'warehouse_id': 2,
            'warehouse_code': 'WH-SEC',
            'warehouse_name': 'Secondary Warehouse',
            'quantity': 2,
          },
        ],
      });
    }
    if (options.path == '/inventory/items/1') {
      // Bare detail object with the per-warehouse stock breakdown.
      return _json({
        'id': 1,
        'item_code': 'FG001',
        'item_name': 'Widget A',
        'category': 'Parts',
        'unit_of_measure': 'pcs',
        'current_stock': 5,
        'reorder_level': 10,
        'standard_cost': 25.0,
        'standard_selling_price': 45.0,
        'purchase_price': 20.0,
        'is_raw_material': 0,
        'is_finished_good': 1,
        'is_purchased': 1,
        'is_manufactured': 0,
        'is_active': 1,
        'stock_by_warehouse': [
          {
            'warehouse_id': 1,
            'warehouse_code': 'WH-MAIN',
            'warehouse_name': 'Main Warehouse',
            'quantity': 3,
          },
          {
            'warehouse_id': 2,
            'warehouse_code': 'WH-SEC',
            'warehouse_name': 'Secondary Warehouse',
            'quantity': 2,
          },
        ],
      });
    }
    if (options.path == '/inventory/items-categories') {
      return _json([
        {'category': 'Parts'},
        {'category': 'Raw'},
      ]);
    }
    if (options.path == '/inventory/items-uom') {
      return _json(['Nos', 'Kg', 'Ltr']);
    }
    if (options.path == '/inventory/items-low-stock') {
      // Bare [Item] array — only Widget A is below its reorder level.
      return _json([
        {
          'id': 1,
          'item_code': 'FG001',
          'item_name': 'Widget A',
          'category': 'Parts',
          'unit_of_measure': 'pcs',
          'current_stock': 5,
          'reorder_level': 10,
          'standard_cost': 25.0,
          'standard_selling_price': 45.0,
          'is_raw_material': 0,
          'is_finished_good': 1,
          'is_active': 1,
        },
      ]);
    }
    if (options.path == '/expenses' && options.method == 'POST') {
      final body = options.data as Map<String, dynamic>;
      lastExpensePostBody = body;
      return _json({
        'success': true,
        'message': 'Expense created successfully',
        'data': {
          'id': 99,
          'expense_no': 'EXP-2608-0099',
          'expense_category': body['expense_category'],
          'description': body['description'] ?? '',
          'amount': body['amount'],
          'expense_date': body['expense_date'],
          'payment_method': body['payment_method'],
          'status': body['status'],
        },
      }, status: 201);
    }
    if (options.path == '/expenses/1' && options.method == 'PUT') {
      final body = options.data as Map<String, dynamic>;
      lastExpensePutBody = body;
      return _json({
        'success': true,
        'message': 'Expense updated successfully',
        'data': {
          'id': 1,
          'expense_no': 'EXP-2605-0001',
          'expense_category': body['expense_category'] ?? 'Fuel',
          'description': body['description'] ?? '',
          'amount': body['amount'],
          'expense_date': body['expense_date'],
          'status': body['status'] ?? 'Approved',
        },
      });
    }
    if (options.path == '/expenses/1' && options.method == 'DELETE') {
      return _json({
        'success': true,
        'message': 'Expense deleted successfully',
      });
    }
    if (options.path == '/expenses') {
      final search =
          (options.queryParameters['search'] as String?)?.toLowerCase() ?? '';
      const all = [
        {
          'id': 1,
          'expense_no': 'EXP-2605-0001',
          'expense_category': 'Fuel',
          'description': 'Generator diesel',
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
        {
          'id': 2,
          'expense_no': 'EXP-2605-0002',
          'expense_category': 'Rent',
          'description': 'May rent',
          'amount': 500.5,
          'expense_date': '2026-05-23',
          'payment_method': 'Bank Transfer',
          'reference_no': null,
          'vendor_name': null,
          'project': 'HQ',
          'status': 'Draft',
          'created_at': '2026-05-23 09:00:00',
          'created_by_name': 'Fawad',
        },
      ];
      final rows = search.isEmpty
          ? all
          : all
                .where(
                  (e) =>
                      (e['description'] as String).toLowerCase().contains(
                        search,
                      ) ||
                      (e['expense_category'] as String).toLowerCase().contains(
                        search,
                      ) ||
                      (e['vendor_name'] as String? ?? '')
                          .toLowerCase()
                          .contains(search),
                )
                .toList();
      return _json({
        'success': true,
        'data': rows,
        'pagination': {
          'current_page': 1,
          'total_pages': 1,
          'total_expenses': rows.length,
          'per_page': 1000,
        },
      });
    }
    if (options.path == '/expenses/categories') {
      return _json({
        'success': true,
        'data': [
          {
            'id': 12,
            'category_name': 'Equipment',
            'description': '',
            'is_active': 1,
          },
          {
            'id': 13,
            'category_name': 'Fuel',
            'description': '',
            'is_active': 1,
          },
          {
            'id': 14,
            'category_name': 'Rent',
            'description': '',
            'is_active': 1,
          },
        ],
      });
    }
    if (options.path == '/expenses/status-options') {
      return _json({
        'success': true,
        'data': [
          {'value': 'Draft', 'label': 'Draft'},
          {'value': 'Submitted', 'label': 'Submitted'},
          {'value': 'Approved', 'label': 'Approved'},
          {'value': 'Paid', 'label': 'Paid'},
          {'value': 'Cancelled', 'label': 'Cancelled'},
        ],
      });
    }
    if (options.path == '/expenses/payment-method-options') {
      return _json({
        'success': true,
        'data': [
          {'value': 'Cash', 'label': 'Cash'},
          {'value': 'Bank Transfer', 'label': 'Bank Transfer'},
          {'value': 'Credit Card', 'label': 'Credit Card'},
        ],
      });
    }
    if (options.path == '/invoices' && options.method == 'POST') {
      final body = options.data as Map<String, dynamic>;
      lastInvoicePostBody = body;
      return _json({
        'id': 99,
        'invoice_no': body['invoice_no'],
        'customer_id': body['customer_id'],
        'invoice_date': body['invoice_date'],
        'due_date': body['due_date'],
        'status': body['status'],
        'total_amount': body['total_amount'],
        'paid_amount': 0,
        'balance_amount': body['total_amount'],
        'customer_name': 'Acme Corp',
        'created_by_username': 'Fawad',
        'items': body['items'],
      }, status: 201);
    }
    if (options.path == '/invoices/1' && options.method == 'PUT') {
      final body = options.data as Map<String, dynamic>;
      lastInvoicePutBody = body;
      return _json({
        'id': 1,
        'invoice_no': 'INV-2026-440955',
        'customer_id': body['customer_id'],
        'invoice_date': body['invoice_date'],
        'due_date': body['due_date'],
        'status': body['status'],
        'total_amount': body['total_amount'],
        'paid_amount': 0,
        'balance_amount': body['total_amount'],
        'customer_name': 'Acme Corp',
        'created_by_username': 'Fawad',
        'items': body['items'],
      });
    }
    if (options.path == '/invoices/1' && options.method == 'DELETE') {
      return _json({'message': 'Invoice deleted successfully'});
    }
    if (options.path == '/invoices/1') {
      // Bare detail object with items + customer contact block.
      return _json({
        'id': 1,
        'invoice_no': 'INV-2026-440955',
        'customer_id': 1,
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
        'customer_email': 'a@acme.com',
        'customer_phone': '555-0101',
        'customer_address': '1 Acme Way',
        'discount_scope': 'invoice',
        'discount_type': 'flat',
        'discount_value': 0,
        'terms': null,
        'returned_amount': 0,
        'return_fee': 0,
        'so_no': null,
        'quotation_no': null,
        'created_by_username': 'Fawad',
        'items': [
          {
            'id': 10,
            'invoice_id': 1,
            'item_id': 1,
            'item_code': 'FG001',
            'item_name': 'Widget A',
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
    }
    if (options.path == '/invoices') {
      final q = options.queryParameters;
      lastInvoicesQuery = q;
      const all = [
        {
          'id': 1,
          'invoice_no': 'INV-2026-440955',
          'customer_id': 1,
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
        },
        {
          'id': 2,
          'invoice_no': 'INV-2026-440956',
          'customer_id': 2,
          'so_id': null,
          'invoice_date': '2026-05-10',
          'due_date': '2026-05-31',
          'status': 'Paid',
          'total_amount': 800,
          'paid_amount': 800,
          'balance_amount': 0,
          'notes': null,
          'created_by': 1,
          'created_at': '2026-05-10 11:00:00',
          'updated_at': '2026-05-31 09:00:00',
          'source_type': 'manual',
          'quotation_id': null,
          'customer_name': 'Beta Ltd',
          'discount_scope': 'invoice',
          'discount_type': 'flat',
          'discount_value': 0,
          'terms': null,
          'returned_amount': 0,
          'return_fee': 0,
          'so_no': null,
          'quotation_no': null,
          'created_by_username': 'Fawad',
        },
        {
          'id': 3,
          'invoice_no': 'INV-2026-440957',
          'customer_id': 3,
          'so_id': null,
          'invoice_date': '2026-04-30',
          'due_date': '2026-05-15',
          'status': 'Overdue',
          'total_amount': 300,
          'paid_amount': 100,
          'balance_amount': 200,
          'notes': null,
          'created_by': 1,
          'created_at': '2026-04-30 14:00:00',
          'updated_at': '2026-05-14 10:00:00',
          'source_type': 'manual',
          'quotation_id': null,
          'customer_name': 'Gamma Inc',
          'discount_scope': 'invoice',
          'discount_type': 'flat',
          'discount_value': 0,
          'terms': null,
          'returned_amount': 0,
          'return_fee': 0,
          'so_no': null,
          'quotation_no': null,
          'created_by_username': 'Fawad',
        },
      ];
      // The server filters by the CSV `status` param only.
      final statuses = (q['status'] as String?)?.split(',') ?? const [];
      final rows = statuses.isEmpty
          ? all
          : all.where((i) => statuses.contains(i['status'])).toList();
      return _json({'success': true, 'data': rows});
    }
    if (options.path == '/dashboard/summary') {
      return _json({
        'success': true,
        'data': {
          'totalItems': 150,
          'totalStockValue': 245000.50,
          'totalSalesRevenue': 890000.00,
          'totalPurchases': 560000.00,
          'warehouseStockCount': 312,
          'lowStockItems': [
            {
              'id': 1,
              'item_code': 'ITM001',
              'item_name': 'Widget',
              'current_stock': 5,
              'reorder_level': 10,
              'category': 'Parts',
            },
          ],
          'stockByCategory': [
            {'category': 'Parts', 'total_stock': 500},
          ],
          'salesByDay': [
            {'date': '2026-08-01', 'total': 15000},
          ],
          'purchasesByDay': [
            {'date': '2026-08-01', 'total': 8000},
          ],
          'recentProductions': 12,
        },
      });
    }
    return _json({
      'success': false,
      'error': {'code': 'NOT_FOUND', 'message': 'Not found'},
    }, status: 404);
  }

  ResponseBody _json(Object body, {int status = 200}) =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

void main() {
  testWidgets('boots to the login screen when no stored token exists', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(_FakeTokenStorage()),
        ],
        child: const MiniErpApp(),
      ),
    );
    await tester.pumpAndSettle();

    // restoreSession() finds no token → unauthenticated → /login.
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.widgetWithText(FilledButton, 'Login'), findsOneWidget);
  });

  testWidgets('login persists the token and navigates to the dashboard shell', (
    tester,
  ) async {
    final storage = _FakeTokenStorage();
    final dio = Dio(BaseOptions(baseUrl: ApiClient.baseUrl));
    dio.httpClientAdapter = _AuthFakeAdapter();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          dioProvider.overrideWithValue(dio),
        ],
        child: const MiniErpApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'admin');
    await tester.enterText(find.byType(TextField).at(1), 'admin123');
    await tester.tap(find.widgetWithText(FilledButton, 'Login'));
    await tester.pumpAndSettle();

    // authProvider flipped to authenticated → router redirects to the
    // authenticated shell ('/'), which loads the dashboard summary.
    expect(find.text('Dashboard'), findsWidgets); // rail item + app bar title
    expect(find.text('890,000.00'), findsOneWidget); // sales revenue KPI
    expect(find.text('Fawad'), findsOneWidget); // logged-in user shown
    expect(find.byIcon(Icons.logout), findsOneWidget);
    expect(storage.token, 'test-token'); // JWT persisted
  });

  testWidgets('stored token + valid /auth/me restores the session at boot', (
    tester,
  ) async {
    final storage = _FakeTokenStorage()..token = 'test-token';
    final dio = Dio(BaseOptions(baseUrl: ApiClient.baseUrl));
    dio.httpClientAdapter = _AuthFakeAdapter();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          dioProvider.overrideWithValue(dio),
        ],
        child: const MiniErpApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Splash → restore → authenticated → straight to the shell dashboard.
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('890,000.00'), findsOneWidget);
    expect(find.text('Fawad'), findsOneWidget);
  });

  testWidgets(
    'non-admin user: admin rail items hidden and direct URL blocked',
    (tester) async {
      final storage = _FakeTokenStorage()..token = 'test-token';
      final dio = Dio(BaseOptions(baseUrl: ApiClient.baseUrl));
      dio.httpClientAdapter = _AuthFakeAdapter(role: 'user');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(storage),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MiniErpApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Restored as a non-admin: boots to the dashboard, admin rail items
      // are filtered out of the shell navigation.
      expect(find.text('Dashboard'), findsWidgets);
      expect(find.text('Users'), findsNothing);
      expect(find.text('Integrations'), findsNothing);

      // Typing an admin-only URL directly redirects back to the dashboard
      // instead of showing a branch the rail doesn't list. The context must
      // be below MaterialApp.router, so use a rendered dashboard element.
      final routerContext = tester.element(find.text('Dashboard').first);
      GoRouter.of(routerContext).go('/admin');
      await tester.pumpAndSettle();
      expect(find.text('Dashboard'), findsWidgets);
      expect(find.text('Users'), findsNothing);
    },
  );

  testWidgets('change password: success pops back to the shell', (
    tester,
  ) async {
    final storage = _FakeTokenStorage();
    final dio = Dio(BaseOptions(baseUrl: ApiClient.baseUrl));
    dio.httpClientAdapter = _AuthFakeAdapter();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          dioProvider.overrideWithValue(dio),
        ],
        child: const MiniErpApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Log in, then open the change-password screen from the shell app bar.
    await tester.enterText(find.byType(TextField).at(0), 'admin');
    await tester.enterText(find.byType(TextField).at(1), 'admin123');
    await tester.tap(find.widgetWithText(FilledButton, 'Login'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.key_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Change Password'), findsWidgets);

    await tester.enterText(find.byType(TextFormField).at(0), 'admin123');
    await tester.enterText(find.byType(TextFormField).at(1), 'newpass123');
    await tester.enterText(find.byType(TextFormField).at(2), 'newpass123');
    await tester.tap(find.widgetWithText(FilledButton, 'Change Password'));
    await tester.pumpAndSettle();

    // Success snackbar, popped back to the dashboard, session kept.
    expect(find.text('Password changed successfully'), findsOneWidget);
    expect(find.text('890,000.00'), findsOneWidget);
    expect(storage.token, 'test-token');
  });

  testWidgets(
    'change password: wrong current password shows a banner and keeps the session',
    (tester) async {
      final storage = _FakeTokenStorage()..token = 'test-token';
      final dio = Dio(BaseOptions(baseUrl: ApiClient.baseUrl));
      dio.httpClientAdapter = _AuthFakeAdapter(changePasswordFails: true);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(storage),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MiniErpApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.key_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'wrong');
      await tester.enterText(find.byType(TextFormField).at(1), 'newpass123');
      await tester.enterText(find.byType(TextFormField).at(2), 'newpass123');
      await tester.tap(find.widgetWithText(FilledButton, 'Change Password'));
      await tester.pumpAndSettle();

      // 401 → server message banner; still on the screen, still authenticated
      // (not bounced to /login), token untouched.
      expect(find.text('Current password is incorrect'), findsOneWidget);
      expect(find.byType(ChangePasswordScreen), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Login'), findsNothing);
      expect(storage.token, 'test-token');
    },
  );

  testWidgets('failed login shows the invalid-credentials banner', (
    tester,
  ) async {
    final storage = _FakeTokenStorage();
    final dio = Dio(BaseOptions(baseUrl: ApiClient.baseUrl));
    dio.httpClientAdapter = _AuthFakeAdapter(failLogin: true);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          dioProvider.overrideWithValue(dio),
        ],
        child: const MiniErpApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'admin');
    await tester.enterText(find.byType(TextField).at(1), 'wrong-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Login'));
    await tester.pumpAndSettle();

    // 401 → loginInvalidCredentials banner; still on /login, no token stored.
    expect(find.text('Invalid username or password'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(storage.token, isNull);
  });

  // Items grid (PORTING.md §5/§6) — the first authenticated data screen.
  // A wider test surface so every PlutoGrid column is built (the grid
  // virtualizes off-screen cells) and column labels can be asserted.
  void useWideSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> bootToItems(WidgetTester tester, {String role = 'admin'}) async {
    final storage = _FakeTokenStorage()..token = 'test-token';
    final dio = Dio(BaseOptions(baseUrl: ApiClient.baseUrl));
    dio.httpClientAdapter = _AuthFakeAdapter(role: role);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          dioProvider.overrideWithValue(dio),
        ],
        child: const MiniErpApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inventory'));
    await tester.pumpAndSettle();
  }

  testWidgets('items screen renders the PlutoGrid with server data', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToItems(tester);

    // Rows + column headers from the fake /inventory/items payload.
    expect(find.text('FG001'), findsOneWidget);
    expect(find.text('Widget A'), findsOneWidget);
    expect(find.text('Bolt'), findsOneWidget);
    expect(find.text('Item Code'), findsOneWidget);
    expect(find.text('Current Stock'), findsOneWidget);
    // Active/Inactive status badges render from is_active.
    expect(find.text('Active'), findsNWidgets(2));
    expect(find.text('Inactive'), findsOneWidget);
    // Stock formatted with thousands separators.
    expect(find.text('120'), findsOneWidget);
  });

  testWidgets('items screen shows the keyboard hint status bar', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToItems(tester);

    // AG-Grid-style status bar beneath the grid: arrow-key cell
    // navigation + the Enter/F2 open-detail shortcuts (the keys bound by
    // rowDetailShortcutActions).
    expect(find.text('↑ ↓ ← →'), findsOneWidget);
    expect(find.text('Enter / F2'), findsOneWidget);
    expect(find.text('Navigate'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('items screen search sends the server search param', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToItems(tester);

    await tester.enterText(find.byType(TextField), 'bolt');
    // Debounce (350ms) fires → provider refetches with ?search=bolt.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('RM002'), findsOneWidget);
    expect(find.text('Widget A'), findsNothing);
  });

  testWidgets('items screen low-stock toggle loads items-low-stock', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToItems(tester);

    await tester.tap(find.widgetWithText(FilterChip, 'Low Stock'));
    await tester.pumpAndSettle();

    // Only the below-reorder item remains (bare array endpoint).
    expect(find.text('FG001'), findsOneWidget);
    expect(find.text('Bolt'), findsNothing);
  });

  testWidgets('items screen error shows a retry and recovers', (tester) async {
    useWideSurface(tester);
    final storage = _FakeTokenStorage()..token = 'test-token';
    final dio = Dio(BaseOptions(baseUrl: ApiClient.baseUrl));
    final adapter = _AuthFakeAdapter()..failItems = true;
    dio.httpClientAdapter = adapter;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          dioProvider.overrideWithValue(dio),
        ],
        child: const MiniErpApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inventory'));
    await tester.pumpAndSettle();

    // Error panel with the server message, grid replaced (its state
    // manager is disposed here — the retry path must not touch it).
    expect(find.text('Failed to fetch items'), findsOneWidget);

    adapter.failItems = false;
    await tester.tap(find.widgetWithText(FilledButton, 'Refresh'));
    await tester.pumpAndSettle();

    // Recovers into a populated grid.
    expect(find.text('FG001'), findsOneWidget);
    expect(find.text('Widget A'), findsOneWidget);
  });

  testWidgets('items screen double-tap opens the item detail dialog', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToItems(tester);

    // Double-tap the Widget A row (within the double-tap window).
    await tester.tap(find.text('Widget A'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Widget A'));
    await tester.pumpAndSettle();

    // Detail dialog with the header + warehouse breakdown from the bare
    // /inventory/items/1 response.
    expect(find.text('Item Details'), findsOneWidget);
    expect(find.text('Stock by Warehouse'), findsOneWidget);
    expect(find.text('Main Warehouse'), findsOneWidget);
    expect(find.text('WH-MAIN'), findsOneWidget);
    expect(find.text('Secondary Warehouse'), findsOneWidget);
    // Low Stock badge (the grid's Low Stock FilterChip also matches);
    // 25.00 appears in both the grid's cost column and the dialog tile.
    expect(find.text('Low Stock'), findsWidgets);
    expect(find.text('25.00'), findsWidgets);

    // Close returns to the grid.
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    expect(find.text('Item Details'), findsNothing);
  });

  testWidgets('item form: create posts the schema-shaped body', (tester) async {
    useWideSurface(tester);
    final storage = _FakeTokenStorage()..token = 'test-token';
    final dio = Dio(BaseOptions(baseUrl: ApiClient.baseUrl));
    final adapter = _AuthFakeAdapter();
    dio.httpClientAdapter = adapter;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          dioProvider.overrideWithValue(dio),
        ],
        child: const MiniErpApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inventory'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'New Item'));
    await tester.pumpAndSettle();
    expect(find.text('New Item'), findsWidgets); // title

    // Validation: saving empty shows the zod-message equivalents.
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Item code is required'), findsOneWidget);
    expect(find.text('Item name is required'), findsOneWidget);
    expect(find.text('Unit of measure is required'), findsOneWidget);
    expect(adapter.lastItemPostBody, isNull);

    // Fill the form: code + name are the first two fields in create mode.
    await tester.enterText(find.byType(TextFormField).at(0), 'FG100');
    await tester.enterText(find.byType(TextFormField).at(1), 'New Widget');
    // Pick a unit of measure (2nd dropdown: code/name fields, then
    // category, uom, sale-type).
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nos').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // Dialog closed, POST body matches the zod itemSchema shape.
    expect(find.widgetWithText(Dialog, 'New Item'), findsNothing);
    expect(adapter.lastItemPostBody?['item_code'], 'FG100');
    expect(adapter.lastItemPostBody?['item_name'], 'New Widget');
    expect(adapter.lastItemPostBody?['unit_of_measure'], 'Nos');
    expect(adapter.lastItemPostBody?['is_purchased'], true); // schema default
    expect(adapter.lastItemPostBody?['sale_type'], 'packed');
    expect(adapter.lastItemPostBody?['reorder_level'], 0);
  });

  testWidgets('item form: edit from the detail dialog PUTs and updates', (
    tester,
  ) async {
    useWideSurface(tester);
    final storage = _FakeTokenStorage()..token = 'test-token';
    final dio = Dio(BaseOptions(baseUrl: ApiClient.baseUrl));
    final adapter = _AuthFakeAdapter();
    dio.httpClientAdapter = adapter;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          dioProvider.overrideWithValue(dio),
        ],
        child: const MiniErpApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inventory'));
    await tester.pumpAndSettle();

    // Open the detail dialog, then Edit.
    await tester.tap(find.text('Widget A'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Widget A'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Item'), findsOneWidget);

    // Pre-filled from the detail; change the name (create-mode fields are
    // absent in edit, so the name field is the first TextFormField).
    await tester.enterText(find.byType(TextFormField).at(0), 'Widget A v2');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Item'), findsNothing);
    expect(adapter.lastItemPutBody?['item_name'], 'Widget A v2');
    expect(adapter.lastItemPutBody?.containsKey('item_code'), false);
    expect(adapter.lastItemPutBody?['sale_type'], 'packed');
  });

  // Expenses grid — same toolbar/grid contract as items, driven by the
  // /expenses + options endpoints from PORTING.md §5/§6.
  Future<void> bootToExpenses(WidgetTester tester) async {
    final storage = _FakeTokenStorage()..token = 'test-token';
    final dio = Dio(BaseOptions(baseUrl: ApiClient.baseUrl));
    dio.httpClientAdapter = _AuthFakeAdapter();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          dioProvider.overrideWithValue(dio),
        ],
        child: const MiniErpApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expenses'));
    await tester.pumpAndSettle();
  }

  testWidgets('expenses screen renders the PlutoGrid with server data', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToExpenses(tester);

    // Rows + column headers from the fake /expenses payload.
    expect(find.text('EXP-2605-0001'), findsOneWidget);
    expect(find.text('Generator diesel'), findsOneWidget);
    expect(find.text('EXP-2605-0002'), findsOneWidget);
    expect(find.text('Expense No'), findsOneWidget);
    expect(find.text('Payment Method'), findsOneWidget);
    // Status badges map to localized labels.
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Draft'), findsOneWidget);
    // Summary strip totals the loaded rows (1000 + 500.5).
    expect(find.text('1,500.50'), findsOneWidget);
    expect(find.text('2 expenses'), findsOneWidget);
  });

  testWidgets('expenses screen search sends the server search param', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToExpenses(tester);

    await tester.enterText(find.byType(TextField), 'diesel');
    // Debounce (350ms) fires → provider refetches with ?search=diesel.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('EXP-2605-0001'), findsOneWidget);
    expect(find.text('EXP-2605-0002'), findsNothing);
  });

  testWidgets('expense form: create posts the schema-shaped body', (
    tester,
  ) async {
    useWideSurface(tester);
    final storage = _FakeTokenStorage()..token = 'test-token';
    final dio = Dio(BaseOptions(baseUrl: ApiClient.baseUrl));
    final adapter = _AuthFakeAdapter();
    dio.httpClientAdapter = adapter;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          dioProvider.overrideWithValue(dio),
        ],
        child: const MiniErpApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expenses'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'New Expense'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Dialog, 'New Expense'), findsOneWidget);

    // Saving empty: the amount validator blocks first (category rule is
    // checked after validation passes).
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Amount is required'), findsOneWidget);
    expect(find.text('Category is required'), findsNothing);
    expect(adapter.lastExpensePostBody, isNull);

    // A valid amount then surfaces the missing-category rule.
    await tester.enterText(find.byType(TextFormField).at(0), '750.25');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Category is required'), findsOneWidget);
    expect(adapter.lastExpensePostBody, isNull);

    // Pick the category (first String dropdown; the payment-method
    // dropdown is DropdownButtonFormField<String?> — a different type).
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fuel').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // Dialog closed, POST body matches the expense schema shape.
    expect(find.widgetWithText(Dialog, 'New Expense'), findsNothing);
    expect(adapter.lastExpensePostBody?['expense_category'], 'Fuel');
    expect(adapter.lastExpensePostBody?['amount'], 750.25);
    expect(adapter.lastExpensePostBody?['status'], 'Approved'); // default
    expect(adapter.lastExpensePostBody?['expense_date'], isNotEmpty);
    expect(adapter.lastExpensePostBody?['description'], isNull); // omitted
  });

  testWidgets('expense form: edit prefills and PUTs updates', (tester) async {
    useWideSurface(tester);
    final storage = _FakeTokenStorage()..token = 'test-token';
    final dio = Dio(BaseOptions(baseUrl: ApiClient.baseUrl));
    final adapter = _AuthFakeAdapter();
    dio.httpClientAdapter = adapter;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          dioProvider.overrideWithValue(dio),
        ],
        child: const MiniErpApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expenses'));
    await tester.pumpAndSettle();

    // Double-tap the row opens the edit dialog.
    await tester.tap(find.text('Generator diesel'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Generator diesel'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Dialog, 'Edit Expense'), findsOneWidget);

    // Description (last TextFormField) is prefilled from the row.
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Generator diesel'),
      ),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextFormField).at(4), 'Diesel refill');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(Dialog, 'Edit Expense'), findsNothing);
    expect(adapter.lastExpensePutBody?['description'], 'Diesel refill');
    expect(adapter.lastExpensePutBody?['expense_category'], 'Fuel');
    expect(adapter.lastExpensePutBody?['amount'], 1000);
  });

  // Sales (invoices) — bare-array endpoint with a server CSV status
  // filter + client-side search/date filtering (PORTING.md §5/§6).
  Future<void> bootToSales(
    WidgetTester tester,
    _AuthFakeAdapter adapter,
  ) async {
    final storage = _FakeTokenStorage()..token = 'test-token';
    final dio = Dio(BaseOptions(baseUrl: ApiClient.baseUrl));
    dio.httpClientAdapter = adapter;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          dioProvider.overrideWithValue(dio),
        ],
        child: const MiniErpApp(),
      ),
    );
    await tester.pumpAndSettle();
    // "Sales" also appears on the dashboard KPI card — tap the rail item
    // by its unique icon instead.
    await tester.tap(find.byIcon(Icons.point_of_sale_outlined));
    await tester.pumpAndSettle();
  }

  testWidgets('sales screen renders the PlutoGrid with server data', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToSales(tester, adapter);

    // Rows + column headers from the fake /invoices payload.
    expect(find.text('INV-2026-440955'), findsOneWidget);
    expect(find.text('Acme Corp'), findsOneWidget);
    expect(find.text('INV-2026-440956'), findsOneWidget);
    expect(find.text('Invoice No'), findsOneWidget);
    // Status badges map to localized labels.
    expect(find.text('Unpaid'), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);
    // Summary strip: totals of the loaded rows (1500+800+300, 0+800+100,
    // 1500+0+200).
    expect(find.text('2,600.00'), findsOneWidget);
    expect(find.text('900.00'), findsOneWidget);
    expect(find.text('1,700.00'), findsOneWidget);
  });

  testWidgets('sales screen search filters client-side (no server param)', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToSales(tester, adapter);

    await tester.enterText(find.byType(TextField), 'acme');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    // The endpoint has no search param — the request stays unfiltered.
    expect(adapter.lastInvoicesQuery?.containsKey('search'), isFalse);
    expect(find.text('INV-2026-440955'), findsOneWidget);
    expect(find.text('INV-2026-440956'), findsNothing);
    // Summary re-totals over the filtered rows (the total also appears
    // in the filtered grid row itself).
    expect(find.text('1,500.00'), findsWidgets);
    expect(find.text('2,600.00'), findsNothing);
  });

  testWidgets('sales screen status filter sends the CSV server param', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToSales(tester, adapter);

    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paid').last);
    await tester.pumpAndSettle();

    expect(adapter.lastInvoicesQuery?['status'], 'Paid');
    expect(find.text('INV-2026-440956'), findsOneWidget);
    expect(find.text('INV-2026-440955'), findsNothing);
    expect(find.text('INV-2026-440957'), findsNothing);
  });

  testWidgets('invoice form: create posts the schema-shaped body', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToSales(tester, adapter);

    await tester.tap(find.widgetWithText(FilledButton, 'New Invoice'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Dialog, 'New Invoice'), findsOneWidget);

    // Saving empty: the line qty validator blocks first (the customer
    // rule is checked after validation passes).
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsWidgets);
    expect(find.text('Customer is required'), findsNothing);
    expect(adapter.lastInvoicePostBody, isNull);

    // Pick the customer (first <int> dropdown) and the line item (second).
    await tester.tap(find.byType(DropdownButtonFormField<int>).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acme Corp').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FG001 — Widget A').last);
    await tester.pumpAndSettle();

    // Line fields: qty(0), rate(1), tax(2); totals panel discount(3);
    // notes(4).
    await tester.enterText(find.byType(TextFormField).at(0), '10');
    await tester.enterText(find.byType(TextFormField).at(1), '100');

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // Dialog closed, POST body matches the createInvoice DTO shape.
    expect(find.widgetWithText(Dialog, 'New Invoice'), findsNothing);
    final body = adapter.lastInvoicePostBody!;
    expect(body['customer_id'], 1);
    expect(body['invoice_no'], startsWith('INV-'));
    expect(body['status'], 'Unpaid'); // default
    expect(body['discount_scope'], 'invoice');
    expect(body['discount_type'], 'flat');
    expect(body['discount_value'], 0);
    expect(body['total_amount'], 1000); // qty × rate, no tax/discount
    final items = body['items'] as List;
    expect(items, hasLength(1));
    expect(items.single['item_id'], 1);
    expect(items.single['quantity'], 10);
    expect(items.single['unit_price'], 100);
    expect(items.single['tax_rate'], 0);
    expect(items.single['discount_type'], 'none');
  });

  testWidgets('invoice form: edit prefills items and PUTs updates', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToSales(tester, adapter);

    // Double-tap the row opens the edit dialog.
    await tester.tap(find.text('INV-2026-440955'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('INV-2026-440955'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Dialog, 'Edit Invoice'), findsOneWidget);

    // The line prefills from the bare detail: qty/rate fields + item
    // select label (from /inventory/items lookup).
    expect(find.text('FG001 — Widget A'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(TextFormField),
        matching: find.text('10'),
      ),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextFormField).at(0), '12');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(Dialog, 'Edit Invoice'), findsNothing);
    final body = adapter.lastInvoicePutBody!;
    expect(body.containsKey('invoice_no'), isFalse); // edit keeps the no.
    expect(body['customer_id'], 1);
    expect(body['status'], 'Unpaid');
    expect(body['total_amount'], 1200);
    final items = body['items'] as List;
    expect(items.single['item_id'], 1);
    expect(items.single['quantity'], 12);
    expect(items.single['unit_price'], 100);
  });

  // Customers list (PORTING.md §5/§6) — server-paginated (the project's
  // only paged endpoint), reusing the PlutoGrid scaffold.
  Future<void> bootToCustomers(
    WidgetTester tester,
    _AuthFakeAdapter adapter,
  ) async {
    final storage = _FakeTokenStorage()..token = 'test-token';
    final dio = Dio(BaseOptions(baseUrl: ApiClient.baseUrl));
    dio.httpClientAdapter = adapter;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          dioProvider.overrideWithValue(dio),
        ],
        child: const MiniErpApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Customers'));
    await tester.pumpAndSettle();
  }

  Future<void> bootToSuppliers(
    WidgetTester tester,
    _AuthFakeAdapter adapter,
  ) async {
    final storage = _FakeTokenStorage()..token = 'test-token';
    final dio = Dio(BaseOptions(baseUrl: ApiClient.baseUrl));
    dio.httpClientAdapter = adapter;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          dioProvider.overrideWithValue(dio),
        ],
        child: const MiniErpApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suppliers'));
    await tester.pumpAndSettle();
  }

  Future<void> bootToPurchaseOrders(
    WidgetTester tester,
    _AuthFakeAdapter adapter,
  ) async {
    final storage = _FakeTokenStorage()..token = 'test-token';
    final dio = Dio(BaseOptions(baseUrl: ApiClient.baseUrl));
    dio.httpClientAdapter = adapter;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          dioProvider.overrideWithValue(dio),
        ],
        child: const MiniErpApp(),
      ),
    );
    await tester.pumpAndSettle();
    // The dashboard also renders 'Purchases' (module card + the Sales vs
    // Purchases chart legend), so scope to the nav rail label — it comes
    // first in tree order (rail renders before the content area).
    await tester.tap(find.text('Purchases').first);
    await tester.pumpAndSettle();
  }

  testWidgets('suppliers screen renders the server-paged grid', (tester) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToSuppliers(tester, adapter);

    // Default server-pagination query (page 1, limit 10, no sort).
    expect(adapter.lastSuppliersQuery?['page'], 1);
    expect(adapter.lastSuppliersQuery?['limit'], 10);
    expect(adapter.lastSuppliersQuery?['sort_by'], isNull);

    // Rows + column headers from the fake /suppliers payload.
    expect(find.text('SUP001'), findsOneWidget);
    expect(find.text('Alpha Traders'), findsOneWidget);
    expect(find.text('250.00'), findsOneWidget); // balance formatted
    expect(find.text('Supplier Code'), findsOneWidget); // column header
    expect(find.text('Inactive'), findsOneWidget); // Gamma Goods
    // Server pagination block → bar (25 suppliers at limit 10 = 3 pages).
    expect(find.text('Page 1 of 3'), findsOneWidget);
    expect(find.text('· 25 Suppliers'), findsOneWidget);
    // Keyboard hint status bar (shared GridStatusBar, like the items grid).
    expect(find.text('↑ ↓ ← →'), findsOneWidget);
    expect(find.text('Enter / F2'), findsOneWidget);
  });

  testWidgets('customers screen renders the server-paged grid', (tester) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToCustomers(tester, adapter);

    expect(find.text('CUST001'), findsOneWidget);
    expect(find.text('Acme Corp'), findsOneWidget);
    expect(find.text('120.50'), findsOneWidget); // balance formatted
    expect(find.text('Customer Code'), findsOneWidget); // column header
    expect(find.text('Inactive'), findsOneWidget); // Gamma Inc
    // Server pagination block → bar (25 customers at limit 10 = 3 pages).
    expect(find.text('Page 1 of 3'), findsOneWidget);
    expect(find.text('· 25 Customers'), findsOneWidget);
  });

  testWidgets('customers screen search sends the server search param', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToCustomers(tester, adapter);

    await tester.enterText(find.byType(TextField), 'beta');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(adapter.lastCustomersQuery?['search'], 'beta');
    expect(find.text('Beta Ltd'), findsOneWidget);
    expect(find.text('Acme Corp'), findsNothing);
    expect(find.text('Page 1 of 1'), findsOneWidget);
  });

  testWidgets('customers screen paginates server-side', (tester) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToCustomers(tester, adapter);

    // 25 customers at limit 10 → 3 pages; page 1 shows CUST001-010.
    expect(find.text('Page 1 of 3'), findsOneWidget);
    expect(find.text('CUST001'), findsOneWidget);

    await tester.tap(find.byTooltip('Next'));
    await tester.pumpAndSettle();

    expect(adapter.lastCustomersQuery?['page'], 2);
    expect(find.text('Page 2 of 3'), findsOneWidget);
    expect(find.text('CUST011'), findsOneWidget);
    expect(find.text('CUST001'), findsNothing);

    // Last page, then per-page selector: 25 → one page, back to page 1.
    await tester.tap(find.byTooltip('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Page 3 of 3'), findsOneWidget);
    expect(find.text('CUST021'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('25').last);
    await tester.pumpAndSettle();

    expect(adapter.lastCustomersQuery?['limit'], 25);
    expect(find.text('Page 1 of 1'), findsOneWidget);
  });

  testWidgets('customers screen column sort sends sortBy/sortOrder', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToCustomers(tester, adapter);

    // Tap the Customer Name column header — PlutoGrid cycles to ASC.
    await tester.tap(find.text('Customer Name'));
    await tester.pumpAndSettle();

    expect(adapter.lastCustomersQuery?['sortBy'], 'customer_name');
    expect(adapter.lastCustomersQuery?['sortOrder'], 'ASC');
  });

  testWidgets('customers screen F2 opens the customer detail dialog', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToCustomers(tester, adapter);

    // Select the first row and give the grid keyboard focus — the exact
    // state a user reaches by clicking a cell (PlutoGrid's own tap
    // handler calls setKeepFocus(true) → gridFocusNode.requestFocus()).
    final sm = tester
        .state<PlutoGridState>(find.byType(PlutoGrid))
        .stateManager;
    sm.setCurrentCell(sm.firstCell, 0);
    sm.gridFocusNode.requestFocus();
    await tester.pump();

    // Fire F2 through the REAL key pipeline: FocusScope.onKeyEvent →
    // keyManager.subject → configuration.shortcut →
    // _OpenCustomerDetailAction (verified on the items grid).
    await tester.sendKeyDownEvent(LogicalKeyboardKey.f2);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();

    // Detail dialog renders the fetched customer (header label, contact
    // person, payment terms, credit limit tile).
    expect(find.text('Customer Details'), findsOneWidget);
    expect(find.text('Jane Doe'), findsOneWidget);
    expect(find.text('Net 30'), findsOneWidget);
    expect(find.text('5,000.00'), findsOneWidget); // credit limit tile

    // Close returns to the grid.
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    expect(find.text('Customer Details'), findsNothing);
  });

  testWidgets('customers screen Enter opens the customer detail dialog', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToCustomers(tester, adapter);

    // Same current-cell + focus setup as the F2 test, Enter variant —
    // sent through the real key pipeline.
    final sm = tester
        .state<PlutoGridState>(find.byType(PlutoGrid))
        .stateManager;
    sm.setCurrentCell(sm.firstCell, 0);
    sm.gridFocusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('Customer Details'), findsOneWidget);
    expect(find.text('Jane Doe'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    expect(find.text('Customer Details'), findsNothing);
  });

  testWidgets('customers screen F2 with no selected row is a no-op', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToCustomers(tester, adapter);

    // Focus the grid but never set a current cell — `currentRow` stays
    // null, so the open-detail action must bail without opening anything.
    final sm = tester
        .state<PlutoGridState>(find.byType(PlutoGrid))
        .stateManager;
    sm.gridFocusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.f2);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();

    expect(find.text('Customer Details'), findsNothing);
  });

  testWidgets('customer form: create posts the schema-shaped body', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToCustomers(tester, adapter);

    await tester.tap(find.widgetWithText(FilledButton, 'New Customer'));
    await tester.pumpAndSettle();
    expect(find.text('New Customer'), findsWidgets); // title

    // Validation: saving empty shows the zod-message equivalents.
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Customer name is required'), findsOneWidget);
    expect(find.text('Phone number is required'), findsOneWidget);
    expect(adapter.lastCustomerPostBody, isNull);

    // Fill name + phone (fields 0 and 2 — contact person sits between).
    await tester.enterText(find.byType(TextFormField).at(0), 'Zenith Traders');
    await tester.enterText(find.byType(TextFormField).at(2), '555-0199');

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // Dialog closed; POST body matches the zod customerSchema shape
    // (defaults sent; customer_code never included — server-generated).
    expect(find.widgetWithText(Dialog, 'New Customer'), findsNothing);
    expect(adapter.lastCustomerPostBody?['customer_name'], 'Zenith Traders');
    expect(adapter.lastCustomerPostBody?['phone'], '555-0199');
    expect(adapter.lastCustomerPostBody?['payment_terms_days'], 14);
    expect(adapter.lastCustomerPostBody?['credit_limit'], 0);
    expect(adapter.lastCustomerPostBody?['opening_balance'], 0);
    expect(adapter.lastCustomerPostBody?.containsKey('customer_code'), false);
  });

  testWidgets('customer form: edit from the detail dialog PUTs and updates', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToCustomers(tester, adapter);

    // Open the detail dialog (double-tap the row), then Edit.
    await tester.tap(find.text('Acme Corp'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Acme Corp'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Customer'), findsOneWidget);

    // Pre-filled from the detail; change the name (first TextFormField).
    await tester.enterText(find.byType(TextFormField).at(0), 'Acme Corp Ltd');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Customer'), findsNothing);
    // The PUT body carries the prefilled values (proving the form seeded
    // from the detail fetch) plus the edited name.
    expect(adapter.lastCustomerPutBody?['customer_name'], 'Acme Corp Ltd');
    expect(adapter.lastCustomerPutBody?['phone'], '555-0101');
    expect(adapter.lastCustomerPutBody?['email'], 'a@acme.com');
    expect(adapter.lastCustomerPutBody?['contact_person'], 'Jane Doe');
    expect(adapter.lastCustomerPutBody?['payment_terms'], 'Net 30');
    expect(adapter.lastCustomerPutBody?['payment_terms_days'], 30);
    expect(adapter.lastCustomerPutBody?['credit_limit'], 5000);
    expect(adapter.lastCustomerPutBody?.containsKey('customer_code'), false);
  });

  testWidgets('customer detail Ledger button opens the ledger dialog', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToCustomers(tester, adapter);

    // Open the detail dialog (double-tap the row), then Ledger.
    await tester.tap(find.text('Acme Corp'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Acme Corp'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Ledger'));
    await tester.pumpAndSettle();

    // Entries from the fake /customers/1/ledger payload (description +
    // reference subtext). Scoped to the ledger dialog by type — the
    // customers grid behind it renders its own balance values, and the
    // detail dialog's own Close/Edit buttons are also in the tree.
    final ledgerDialog = find.byType(CustomerLedgerDialog);
    Finder inLedger(String text) =>
        find.descendant(of: ledgerDialog, matching: find.text(text));
    expect(inLedger('Invoice for goods'), findsOneWidget);
    expect(inLedger('INV-2026-001'), findsOneWidget);
    expect(inLedger('Payment received'), findsOneWidget);
    // Totals row: total debit 500, total credit 200, closing balance
    // 620.50 — each value also appears in its entry row (debit/credit/
    // balance columns), so two matches each.
    expect(inLedger('500.00'), findsNWidgets(2));
    expect(inLedger('200.00'), findsNWidgets(2));
    expect(inLedger('620.50'), findsNWidgets(2));

    // Close the ledger (the detail dialog's own Close is also in the
    // tree, so scope to the ledger dialog) — returns to the detail dialog.
    await tester.tap(
      find.descendant(
        of: ledgerDialog,
        matching: find.widgetWithText(TextButton, 'Close'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Payment received'), findsNothing);
  });

  testWidgets('suppliers screen F2 opens the supplier detail dialog', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToSuppliers(tester, adapter);

    // Same current-cell + focus setup as the items/customers F2 tests —
    // fired through the REAL key pipeline (FocusScope → keyManager →
    // configuration.shortcut → rowDetailShortcutActions).
    final sm = tester
        .state<PlutoGridState>(find.byType(PlutoGrid))
        .stateManager;
    sm.setCurrentCell(sm.firstCell, 0);
    sm.gridFocusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.f2);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();

    // Detail dialog renders the fetched supplier (header label + contact
    // person from the fake /suppliers/1 payload).
    expect(find.text('Supplier Details'), findsOneWidget);
    expect(find.text('Ali Raza'), findsOneWidget);

    // Close returns to the grid.
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    expect(find.text('Supplier Details'), findsNothing);
  });

  testWidgets('suppliers screen Enter opens the supplier detail dialog', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToSuppliers(tester, adapter);

    final sm = tester
        .state<PlutoGridState>(find.byType(PlutoGrid))
        .stateManager;
    sm.setCurrentCell(sm.firstCell, 0);
    sm.gridFocusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('Supplier Details'), findsOneWidget);
    expect(find.text('Ali Raza'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    expect(find.text('Supplier Details'), findsNothing);
  });

  testWidgets('suppliers screen F2 with no selected row is a no-op', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToSuppliers(tester, adapter);

    // Focus the grid but never set a current cell — `currentRow` stays
    // null, so the open-detail action must bail without opening anything.
    final sm = tester
        .state<PlutoGridState>(find.byType(PlutoGrid))
        .stateManager;
    sm.gridFocusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.f2);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();

    expect(find.text('Supplier Details'), findsNothing);
  });

  testWidgets('supplier detail Ledger button opens the ledger dialog', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToSuppliers(tester, adapter);

    // Open the detail dialog (double-tap the row), then Ledger.
    await tester.tap(find.text('Alpha Traders'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Alpha Traders'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Ledger'));
    await tester.pumpAndSettle();

    // Entries from the fake /suppliers/1/ledger payload (description +
    // reference subtext). Scoped to the ledger dialog by type — the
    // suppliers grid behind it renders its own balance values, and the
    // detail dialog's own Close/Edit buttons are also in the tree.
    final ledgerDialog = find.byType(SupplierLedgerDialog);
    Finder inLedger(String text) =>
        find.descendant(of: ledgerDialog, matching: find.text(text));
    expect(inLedger('Purchase goods'), findsOneWidget);
    expect(inLedger('PO-2026-001'), findsOneWidget);
    expect(inLedger('Payment made'), findsOneWidget);
    // Totals row: total debit 500, total credit 200, closing balance
    // 620.50 — each value also appears in its entry row (debit/credit/
    // balance columns), so two matches each.
    expect(inLedger('500.00'), findsNWidgets(2));
    expect(inLedger('200.00'), findsNWidgets(2));
    expect(inLedger('620.50'), findsNWidgets(2));

    // Close the ledger (the detail dialog's own Close is also in the
    // tree, so scope to the ledger dialog) — returns to the detail dialog.
    await tester.tap(
      find.descendant(
        of: ledgerDialog,
        matching: find.widgetWithText(TextButton, 'Close'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SupplierLedgerDialog), findsNothing);
    expect(find.text('Purchase goods'), findsNothing);
  });

  testWidgets('supplier form: create posts the schema-shaped body', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToSuppliers(tester, adapter);

    await tester.tap(find.widgetWithText(FilledButton, 'New Supplier'));
    await tester.pumpAndSettle();
    expect(find.text('New Supplier'), findsWidgets); // title

    // Validation: saving empty shows the zod-message equivalents.
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Supplier code is required'), findsOneWidget);
    expect(find.text('Supplier name is required'), findsOneWidget);
    expect(adapter.lastSupplierPostBody, isNull);

    // Fill code + name (fields 0 and 1).
    await tester.enterText(find.byType(TextFormField).at(0), 'SUP099');
    await tester.enterText(find.byType(TextFormField).at(1), 'Zenith Traders');

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // Dialog closed; POST body matches the zod supplierSchema shape
    // (supplier_code is user-entered for suppliers, unlike customers).
    expect(find.widgetWithText(Dialog, 'New Supplier'), findsNothing);
    expect(adapter.lastSupplierPostBody?['supplier_code'], 'SUP099');
    expect(adapter.lastSupplierPostBody?['supplier_name'], 'Zenith Traders');
    // Defaults from the web form: payment_terms 'Net 30'.
    expect(adapter.lastSupplierPostBody?['payment_terms'], 'Net 30');
    // Optional fields are omitted when empty (POST never sends them).
    expect(adapter.lastSupplierPostBody?.containsKey('contact_person'), false);
    expect(adapter.lastSupplierPostBody?.containsKey('email'), false);
    expect(adapter.lastSupplierPostBody?.containsKey('phone'), false);
    expect(adapter.lastSupplierPostBody?.containsKey('address'), false);
    expect(adapter.lastSupplierPostBody?.containsKey('is_active'), false);
  });

  testWidgets('supplier form: edit from the detail dialog PUTs and updates', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToSuppliers(tester, adapter);

    // Open the detail dialog (double-tap the row), then Edit.
    await tester.tap(find.text('Alpha Traders'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Alpha Traders'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Supplier'), findsOneWidget); // form title

    // Pre-filled from the detail; the code field is read-only on edit, so
    // change the name (field 1).
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'Alpha Traders Ltd',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Supplier'), findsNothing);
    // The PUT body carries the prefilled values (proving the form seeded
    // from the detail fetch) plus the edited name; supplier_code is not
    // updatable server-side.
    expect(adapter.lastSupplierPutBody?['supplier_name'], 'Alpha Traders Ltd');
    expect(adapter.lastSupplierPutBody?['phone'], '555-0201');
    expect(adapter.lastSupplierPutBody?['email'], 'a@alpha.com');
    expect(adapter.lastSupplierPutBody?['contact_person'], 'Ali Raza');
    expect(adapter.lastSupplierPutBody?['address'], '12 Industrial Rd');
    expect(adapter.lastSupplierPutBody?['payment_terms'], 'Net 30');
    expect(adapter.lastSupplierPutBody?['is_active'], 1);
    expect(adapter.lastSupplierPutBody?.containsKey('supplier_code'), false);
  });

  testWidgets('purchase orders screen renders the grid', (tester) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToPurchaseOrders(tester, adapter);

    // Rows from the bare-array fake (PO no + supplier), the status badge
    // labels (l10n), and the currency-formatted totals.
    expect(find.text('PO-2026-001'), findsOneWidget);
    expect(find.text('PO-2026-002'), findsOneWidget);
    // The supplier cell of the PO row (offstage branches — the eagerly
    // built suppliers grid — are skipped by the default finders).
    expect(find.text('Alpha Traders'), findsOneWidget);
    expect(find.text('Beta Suppliers'), findsOneWidget);
    expect(find.text('Draft'), findsOneWidget); // status badge
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('1,500.00'), findsOneWidget); // total column
    expect(find.text('2,500.00'), findsOneWidget);
    // Grid column headers.
    expect(find.text('PO No'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Expected Delivery'), findsOneWidget);
  });

  testWidgets('purchase orders screen F2 opens the PO detail dialog', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToPurchaseOrders(tester, adapter);

    // Same current-cell + focus setup as the items/customers F2 tests —
    // fired through the REAL key pipeline (FocusScope → keyManager →
    // configuration.shortcut → rowDetailShortcutActions).
    final sm = tester
        .state<PlutoGridState>(find.byType(PlutoGrid))
        .stateManager;
    sm.setCurrentCell(sm.firstCell, 0);
    sm.gridFocusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.f2);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();

    // Detail dialog renders the fetched PO (header label + an item row
    // from the fake /purchase-orders/1 payload).
    expect(find.text('Purchase Order Details'), findsOneWidget);
    expect(find.text('Raw Material A'), findsOneWidget);
    expect(find.text('RM001'), findsOneWidget);
    expect(find.text('1,500.00'), findsWidgets); // total tile + item amounts

    // Close returns to the grid.
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    expect(find.text('Purchase Order Details'), findsNothing);
  });

  testWidgets('purchase orders screen F2 with no selected row is a no-op', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToPurchaseOrders(tester, adapter);

    // Focus the grid but never set a current cell — `currentRow` stays
    // null, so the open-detail action must bail without opening anything.
    final sm = tester
        .state<PlutoGridState>(find.byType(PlutoGrid))
        .stateManager;
    sm.gridFocusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.f2);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();

    expect(find.text('Purchase Order Details'), findsNothing);
  });

  testWidgets('items screen F2 opens the item detail dialog', (tester) async {
    useWideSurface(tester);
    await bootToItems(tester);

    // Select the first row and give the grid keyboard focus — the exact
    // state a user reaches by clicking a cell (PlutoGrid's own tap
    // handler calls setKeepFocus(true) → gridFocusNode.requestFocus()).
    // `firstCell` is the same initialized cell PlutoGrid itself selects
    // in select mode (raw row cells aren't initialized for currentCell).
    final sm = tester
        .state<PlutoGridState>(find.byType(PlutoGrid))
        .stateManager;
    sm.setCurrentCell(sm.firstCell, 0);
    sm.gridFocusNode.requestFocus();
    await tester.pump();

    // Fire F2 through the REAL key pipeline: FocusScope.onKeyEvent →
    // keyManager.subject → configuration.shortcut → _OpenDetailAction.
    // (Verified: the grid FocusScope consumes the key, and the shortcut
    // map preserves the F2/Enter/NumpadEnter bindings after the default
    // actions merge.)
    await tester.sendKeyDownEvent(LogicalKeyboardKey.f2);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();

    expect(find.text('Item Details'), findsOneWidget);
    expect(find.text('Main Warehouse'), findsOneWidget);

    // Close returns to the grid.
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    expect(find.text('Item Details'), findsNothing);
  });

  testWidgets('items screen Enter opens the item detail dialog', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToItems(tester);

    // Same current-cell + focus setup as the F2 test (see above), Enter
    // variant — sent through the real key pipeline.
    final sm = tester
        .state<PlutoGridState>(find.byType(PlutoGrid))
        .stateManager;
    sm.setCurrentCell(sm.firstCell, 0);
    sm.gridFocusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('Item Details'), findsOneWidget);
    expect(find.text('Main Warehouse'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    expect(find.text('Item Details'), findsNothing);
  });

  testWidgets('items screen F2 with no selected row is a no-op', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToItems(tester);

    // Focus the grid but never set a current cell — `currentRow` stays
    // null, so the open-detail action must bail without opening anything.
    final sm = tester
        .state<PlutoGridState>(find.byType(PlutoGrid))
        .stateManager;
    sm.gridFocusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.f2);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();

    expect(find.text('Item Details'), findsNothing);
  });
}
