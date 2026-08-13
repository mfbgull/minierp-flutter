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
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:minierp_app/app.dart';
import 'package:minierp_app/core/api/api_client.dart';
import 'package:minierp_app/core/auth/token_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:minierp_app/features/activity_log/activity_log_providers.dart'
    show activityLogFromDateProvider, activityLogToDateProvider;
import 'package:minierp_app/features/activity_log/activity_log_screen.dart'
    show ActivityLogScreen;
import 'package:minierp_app/features/auth/change_password_screen.dart';
import 'package:minierp_app/features/admin/admin_models.dart' show Role;
import 'package:minierp_app/features/reports/reports_dashboard_screen.dart';
import 'package:minierp_app/widgets/date_picker_helpers.dart' show DateFilterButton;
import 'package:minierp_app/core/utils/date_utils.dart' show isoDate;
import 'package:minierp_app/widgets/status_badge.dart' show StatusBadge;
import 'package:minierp_app/widgets/searchable_select.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:printing/printing.dart' show PdfPreview;

class _FakeTokenStorage implements TokenStorage {
  String? token;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> writeToken(String value) async => token = value;

  @override
  Future<void> clear() async => token = null;
}

/// Joined stock-movement rows shared by the list GET fake and the detail
/// GET fake (a detail fetch returns the same joined shape as a list row).
Map<String, dynamic> _movementPurchaseRow() => {
  'id': 1,
  'movement_no': 'SM-2026-0100',
  'item_id': 4,
  'warehouse_id': 1,
  'movement_type': 'PURCHASE',
  'quantity': 100.0,
  'unit_cost': 10.0,
  'reference_doctype': 'PURCHASE',
  'reference_docno': 'PUR-2026-001',
  'remarks': 'Goods received',
  'movement_date': '2026-02-01',
  'created_by': 1,
  'created_at': '2026-02-01 09:00:00',
  'item_code': 'RM001',
  'item_name': 'Raw Material A',
  'unit_of_measure': 'kg',
  'warehouse_code': 'WH-MAIN',
  'warehouse_name': 'Main Warehouse',
  'created_by_name': 'admin',
};

Map<String, dynamic> _movementSaleRow() => {
  'id': 2,
  'movement_no': 'SM-2026-0101',
  'item_id': 1,
  'warehouse_id': 1,
  'movement_type': 'SALE',
  'quantity': -5.0,
  'unit_cost': 25.0,
  'reference_doctype': 'SALE',
  'reference_docno': 'INV-2026-001',
  'remarks': 'POS sale',
  'movement_date': '2026-02-02',
  'created_by': 1,
  'created_at': '2026-02-02 12:30:00',
  'item_code': 'FG001',
  'item_name': 'Widget A',
  'unit_of_measure': 'pcs',
  'warehouse_code': 'WH-MAIN',
  'warehouse_name': 'Main Warehouse',
  'created_by_name': 'admin',
};

Map<String, dynamic> _movementAdjustmentRow() => {
  'id': 3,
  'movement_no': 'SM-2026-0102',
  'item_id': 4,
  'warehouse_id': 1,
  'movement_type': 'ADJUSTMENT',
  'quantity': -10.0,
  'unit_cost': 10.0,
  'reference_doctype': 'ADJUSTMENT',
  'reference_docno': 'ADJ-2026-001',
  'remarks': 'Broken stock',
  'movement_date': '2026-02-03',
  'created_by': 1,
  'created_at': '2026-02-03 10:00:00',
  'item_code': 'RM001',
  'item_name': 'Raw Material A',
  'unit_of_measure': 'kg',
  'warehouse_code': 'WH-MAIN',
  'warehouse_name': 'Main Warehouse',
  'created_by_name': 'admin',
};

/// Transfer OUT leg (no reference — the IN leg names its movement_no).
Map<String, dynamic> _movementTransferOutRow() => {
  'id': 4,
  'movement_no': 'SM-2026-0103',
  'item_id': 4,
  'warehouse_id': 1,
  'movement_type': 'TRANSFER',
  'quantity': -5.0,
  'unit_cost': 10.0,
  'reference_doctype': 'TRANSFER',
  'reference_docno': null,
  'remarks': 'Transfer to raw',
  'movement_date': '2026-02-04',
  'created_by': 1,
  'created_at': '2026-02-04 09:00:00',
  'item_code': 'RM001',
  'item_name': 'Raw Material A',
  'unit_of_measure': 'kg',
  'warehouse_code': 'WH-MAIN',
  'warehouse_name': 'Main Warehouse',
  'created_by_name': 'admin',
};

/// Transfer IN leg — its `reference_docno` names the OUT leg's number.
Map<String, dynamic> _movementTransferInRow() => {
  'id': 5,
  'movement_no': 'SM-2026-0104',
  'item_id': 4,
  'warehouse_id': 2,
  'movement_type': 'TRANSFER',
  'quantity': 5.0,
  'unit_cost': 10.0,
  'reference_doctype': 'TRANSFER',
  'reference_docno': 'SM-2026-0103',
  'remarks': 'Transfer to raw',
  'movement_date': '2026-02-04',
  'created_by': 1,
  'created_at': '2026-02-04 09:00:00',
  'item_code': 'RM001',
  'item_name': 'Raw Material A',
  'unit_of_measure': 'kg',
  'warehouse_code': 'WH-RAW',
  'warehouse_name': 'Raw Materials',
  'created_by_name': 'admin',
};

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

  /// How many times the items list GET ran (Ctrl+R refresh assertion).
  int itemsFetchCount = 0;

  /// When true, `GET /inventory/stock-ledger/1` returns an empty array.
  bool emptyStockLedger = false;

  /// Captured query parameters of the last stock-ledger fetch.
  Map<String, dynamic>? lastLedgerQuery;

  /// Captured create/update bodies for the item form tests.
  Map<String, dynamic>? lastItemPostBody;
  Map<String, dynamic>? lastItemPutBody;

  /// Captured create/update bodies for the warehouse form tests.
  Map<String, dynamic>? lastWarehousePostBody;
  Map<String, dynamic>? lastWarehousePutBody;

  /// When true, the warehouse create POST rejects with a 400 (failure
  /// path test).
  bool rejectWarehouseCreate = false;

  /// Warehouse #1 delete flow — the DELETE fake flips this so the list
  /// GET drops WH-MAIN on refetch.
  bool warehouse1Deleted = false;

  int warehouseDeleteCount = 0;

  /// When true, the warehouse DELETE rejects with a 404 (failure-path
  /// test).
  bool rejectWarehouseDelete = false;

  /// Captured stock-adjustment POST body (stock-movements tab tests).
  Map<String, dynamic>? lastMovementPostBody;

  /// Every movement POST body, in order (the transfer flow posts two).
  final List<Map<String, dynamic>> movementPostBodies = [];
  int movementPostCount = 0;

  /// When true, the stock-movements POST rejects with a 400 (failure-path
  /// test).
  bool rejectMovementCreate = false;

  /// When true, only the SECOND movement POST rejects with a 400 (the
  /// transfer flow's incoming leg).
  bool rejectSecondMovement = false;

  /// How many times the movement detail GET ran (dialog fetch assertions).
  int movementDetailFetchCount = 0;

  /// Production module capture + state fields.
  Map<String, dynamic>? lastProductionPostBody;
  int productionDeleteCount = 0;
  bool production4Deleted = false;
  int productionDetailFetchCount = 0;
  Map<String, dynamic>? lastBomPostBody;
  Map<String, dynamic>? lastBomPutBody;
  Map<String, dynamic>? lastBomToggleBody;
  int bomDeleteCount = 0;
  int bomDetailFetchCount = 0;

  /// Captured query params of the last movements list GET (filter tests).
  Map<String, dynamic>? lastMovementQuery;

  /// Captured purchase-order mutation bodies (form create/edit tests).
  Map<String, dynamic>? lastPoPostBody;
  Map<String, dynamic>? lastPoPutBody;
  Map<String, dynamic>? lastPoItemPostBody;
  Map<String, dynamic>? lastPoItemPutBody;
  Map<String, dynamic>? lastPoStatusBody;
  int poItemDeleteCount = 0;
  int poDeleteCount = 0;

  /// Captured goods-receipt POST body (receive-goods flow tests).
  Map<String, dynamic>? lastPoReceiptBody;

  /// Stateful goods receipts for PO #1 — the /purchase-orders/1/receipts
  /// GET returns this list, and a receipt POST appends to it so the
  /// detail dialog's history table refetches the new row.
  final List<Map<String, dynamic>> po1Receipts = [];

  /// When true, the receipt POST rejects with a 400 (failure-path test).
  bool rejectPoReceipt = false;

  /// Stateful PO #1 workflow status — the detail fake reads it so a
  /// submit POST flips the badge in subsequent GETs.
  String po1Status = 'Draft';

  /// When true, the status POST rejects with a 400 (failure-path test).
  bool rejectPoStatus = false;

  /// Captured process-return body + stateful returned qty for purchase
  /// #1 — the /purchases GET fakes read it so a return POST flips the
  /// list/detail rows.
  Map<String, dynamic>? lastPurchaseReturnBody;
  num purchase1ReturnedQty = 0;

  /// When true, the return POST rejects with a 400 (failure-path test).
  bool rejectPurchaseReturn = false;

  /// Stateful physical-count #1 workflow status — the /physical-counts
  /// fakes read it so a complete/cancel POST flips the badge on refetch.
  String pc1Status = 'Draft';

  /// When true, the physical-count complete POST rejects with a 400
  /// (failure-path test).
  bool rejectPcComplete = false;

  /// System quantities for PC-2026-001's item lines (fake variance calc).
  static const Map<int, num> pc1SystemQty = {4: 100.0, 5: 50.0};

  /// Stateful counted quantities per item for physical-count #1 (seeded
  /// with RM001's existing count) — the detail/items fakes read it so a
  /// record POST flips the table on refetch.
  final Map<int, num> pc1CountedQty = {4: 95.0};

  /// Last recorded item body for the physical-count record tests.
  Map<String, dynamic>? lastPcRecordBody;

  /// When true, the items POST rejects with a 400 (failure-path test).
  bool rejectPcRecord = false;

  /// Last /customers query params (for pagination/search/sort assertions).
  Map<String, dynamic>? lastCustomersQuery;

  /// Captured create/update bodies for the customer form tests.
  Map<String, dynamic>? lastCustomerPostBody;
  Map<String, dynamic>? lastCustomerPutBody;

  /// Last customer id the row-menu Delete flow DELETEed.
  int? lastCustomerDeleteId;

  /// True once the Fix Balances recalculate POST fires.
  bool recalculateBalancesCalled = false;

  /// Last /suppliers query params (for pagination assertions).
  Map<String, dynamic>? lastSuppliersQuery;

  /// Captured create/update bodies for the supplier form tests.
  Map<String, dynamic>? lastSupplierPostBody;
  Map<String, dynamic>? lastSupplierPutBody;
  int supplierDeleteCount = 0;

  /// Captured create/update bodies for the expense form tests.
  Map<String, dynamic>? lastExpensePostBody;
  Map<String, dynamic>? lastExpensePutBody;

  /// Captured body of the last /activity-logs/cleanup POST.
  Map<String, dynamic>? lastCleanupBody;

  /// When true, the cleanup POST rejects with a 400 (failure-path test).
  bool rejectCleanup = false;

  /// When true, the /settings/bulk POST rejects with a 400 (failure-path
  /// test).
  bool rejectSettingsSave = false;

  /// Captured body of the last /settings/bulk POST (bare key → value map).
  Map<String, dynamic>? lastSettingsBulkBody;

  /// When true, POST /forecasts/compute-accuracy rejects with a 400
  /// (failure-path test).
  bool rejectComputeAccuracy = false;

  /// How many times POST /forecasts/compute-accuracy ran.
  int computeAccuracyCount = 0;

  /// Captured query params of the last /forecasts/demand fetch (filter
  /// assertions).
  Map<String, dynamic>? lastForecastDemandQuery;

  /// Captured itemId of the last /forecasts/trends fetch.
  int? lastTrendsItemId;

  /// When true, the demand GET rejects with a 500 (failure-path test).
  bool failForecastDemand = false;

  /// When true, the accuracy GET rejects with a 500 (failure-path test).
  bool failForecastAccuracy = false;

  /// Mutable settings store backing GET /settings + POST /settings/bulk
  /// (bare `{key: {value, description, updated_at}}` — no envelope).
  Map<String, dynamic> settingsStore = {
    'company_name': {
      'value': 'Mini ERP',
      'description': 'Company name',
      'updated_at': '2026-08-09 10:00:00',
    },
    'company_email': {
      'value': 'support@minierp.com',
      'description': 'Company email',
      'updated_at': '2026-08-09 10:00:00',
    },
    'company_phone': {
      'value': '+1234567890',
      'description': 'Company phone',
      'updated_at': '2026-08-09 10:00:00',
    },
    'company_address': {
      'value': '123 Main St',
      'description': 'Company address',
      'updated_at': '2026-08-09 10:00:00',
    },
    'company_tax_id': {
      'value': 'TAX-123456789',
      'description': 'Company tax ID for invoices',
      'updated_at': '2026-08-09 10:00:00',
    },
    'currency_symbol': {
      'value': 'Rs.',
      'description': 'Currency symbol displayed throughout the application',
      'updated_at': '2026-08-09 10:00:00',
    },
    'currency_code': {
      'value': 'PKR',
      'description': 'Currency code (e.g., USD, EUR, PKR)',
      'updated_at': '2026-08-09 10:00:00',
    },
    'decimal_places': {
      'value': '2',
      'description': 'Number of decimal places for currency',
      'updated_at': '2026-08-09 10:00:00',
    },
    'date_format': {
      'value': 'MM/DD/YYYY',
      'description': 'Date format preference',
      'updated_at': '2026-08-09 10:00:00',
    },
    'tooltip_timeout': {
      'value': '1',
      'description': 'Tooltip timeout (seconds)',
      'updated_at': '2026-08-09 10:00:00',
    },
    'tax_rate': {
      'value': '0',
      'description': 'Default tax rate (%)',
      'updated_at': '2026-08-09 10:00:00',
    },
    'STK_last_no_2026': {
      'value': '114',
      'description': null,
      'updated_at': '2026-08-09 10:00:00',
    },
    'PAY_last_no': {
      'value': '35',
      'description': null,
      'updated_at': '2026-08-09 10:00:00',
    },
    // Integration key — must NOT surface on the settings screen (it
    // belongs to the Integrations module).
    'sendgrid_enabled': {
      'value': 'false',
      'description': 'Enable SendGrid email service',
      'updated_at': '2026-08-09 10:00:00',
    },
  };

  /// Per-service `{enabled, configured}` flags backing the bare
  /// `GET /integrations/settings` body (keys are never returned).
  Map<String, dynamic> integrationsStore = {
    'email': {'enabled': false, 'configured': true},
    'notifications': {'enabled': true, 'configured': false},
    'weather': {'enabled': false, 'configured': false},
    'validation': {'enabled': false, 'configured': false},
    'currency': {'enabled': false, 'configured': false},
    'tax': {'enabled': false, 'configured': false},
  };

  /// Captured body of the last `PUT /integrations/settings/:service`.
  Map<String, dynamic>? lastIntegrationPutBody;
  String? lastIntegrationPutService;

  /// When true, the integration PUT rejects with a 400 (failure-path
  /// test).
  bool rejectIntegrationSave = false;

  /// Captured multipart document upload: the raw FormData, its string
  /// fields, whether a file part was attached, and the file's filename.
  FormData? lastDocumentPostForm;
  Map<String, String>? lastDocumentPostFields;
  bool lastDocumentPostHasFile = false;
  String? lastDocumentPostFileName;

  /// When true, the document upload POST rejects with a 500 (failure-
  /// path test).
  bool rejectDocumentUpload = false;

  /// Captured query params of the last /activity-logs list GET.
  Map<String, dynamic>? lastActivityLogsQuery;

  /// Captured query params of the four newly ported report GETs.
  Map<String, dynamic>? lastSalesByItemQuery;
  Map<String, dynamic>? lastSupplierAnalysisQuery;
  Map<String, dynamic>? lastProductionSummaryQuery;
  Map<String, dynamic>? lastBomUsageQuery;

  /// When true, the report GETs reject with a 500 (failure-path tests).
  bool failSalesByItem = false;
  bool failSupplierAnalysis = false;
  bool failProductionSummary = false;
  bool failBomUsage = false;

  /// Last /invoices query params + captured create/update bodies.
  Map<String, dynamic>? lastInvoicesQuery;
  Map<String, dynamic>? lastInvoicePostBody;
  Map<String, dynamic>? lastInvoicePutBody;
  Map<String, dynamic>? lastInvoiceReturnBody;
  num invoice1ReturnedQty = 0;
  bool rejectInvoiceReturn = false;

  /// Captured dashboard/report state: summary request count (refresh
  /// button) and the last summary/sales-summary query params (global
  /// date range).
  int dashboardSummaryCalls = 0;
  Map<String, dynamic>? lastDashboardSummaryQuery;
  Map<String, dynamic>? lastSalesSummaryQuery;

  /// Captured PUT body of the last /dashboard/cash-opening-balances
  /// save (opening-balance editor test).
  Map<String, dynamic>? lastOpeningBalancesPutBody;

  /// Captured payments-module request state: paged list query, create/
  /// update bodies, and a delete counter.
  Map<String, dynamic>? lastPaymentsQuery;
  Map<String, dynamic>? lastPaymentPostBody;
  Map<String, dynamic>? lastPaymentPutBody;
  int paymentDeleteCount = 0;

  /// Last /sales-orders query params (sales-orders grid tests).
  Map<String, dynamic>? lastSalesOrdersQuery;

  /// Last /quotations query params + captured create/update bodies.
  Map<String, dynamic>? lastQuotationsQuery;
  Map<String, dynamic>? lastQuotationPostBody;
  Map<String, dynamic>? lastQuotationPutBody;
  int quotationDeleteCount = 0;
  int quotationConvertCount = 0;

  /// Stateful quotation #1 status — the list + detail fakes read it so a
  /// delete POST removes the row and a convert POST flips the badge to
  /// Converted on refetch.
  String quotation1Status = 'Sent';

  /// Captured create/update bodies for the sales-order form tests.
  Map<String, dynamic>? lastSalesOrderPostBody;
  Map<String, dynamic>? lastSalesOrderPutBody;
  int salesOrderDeleteCount = 0;
  int salesOrderCancelCount = 0;

  /// Stateful SO #1 status — the detail fake reads it so a cancel
  /// POST flips the badge on refetch.
  String so1Status = 'Confirmed';

  /// Employees-module capture + state fields.
  Map<String, dynamic>? lastEmployeesQuery;
  Map<String, dynamic>? lastEmployeePostBody;
  Map<String, dynamic>? lastEmployeePutBody;
  int employeeDeleteCount = 0;
  int salaryPayCount = 0;
  Map<String, dynamic>? lastSalaryPayBody;
  int salaryHistoryFetchCount = 0;
  int employeeNextCodeFetchCount = 0;

  /// When true, the employees list GET rejects with a 500 (failure-path
  /// test).
  bool failEmployees = false;

  /// When true, the salary pay POST rejects with a 422 (failure-path
  /// test).
  bool rejectSalaryPay = false;

  /// User-management capture + state fields.
  Map<String, dynamic>? lastUsersQuery;
  Map<String, dynamic>? lastUserPostBody;
  Map<String, dynamic>? lastUserPutBody;
  int userDeleteCount = 0;
  int userToggleCount = 0;
  Map<String, dynamic>? lastToggleBody;
  String? lastResetPasswordBody;
  Map<String, dynamic>? lastRolePostBody;
  Map<String, dynamic>? lastRolePutBody;
  int roleDeleteCount = 0;
  List<int>? lastRolePermissionsIds;
  int rolePermissionsFetchCount = 0;

  /// When true, the user create POST rejects with a 409 (failure-path
  /// test).
  bool rejectUserCreate = false;

  /// When true, the role permissions PUT rejects with a 400
  /// (failure-path test).
  bool rejectRolePermissionsSave = false;

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
    if (options.path == '/customers/recalculate-balances' &&
        options.method == 'POST') {
      recalculateBalancesCalled = true;
      return _json({
        'success': true,
        'message': 'Recalculated balances for 25 customers',
      });
    }
    // Row-menu Delete — enveloped success, mirrors the real soft-delete.
    if (options.method == 'DELETE' && options.path.startsWith('/customers/')) {
      lastCustomerDeleteId = int.tryParse(options.path.split('/').last);
      return _json({
        'success': true,
        'message': 'Customer deactivated successfully',
      });
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
            'linked_invoice_no': 'INV-2026-001',
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
    if (options.path == '/suppliers/1/statement' && options.method == 'GET') {
      // Enveloped — the real getSupplierStatement shape; transactions are
      // ordered oldest-first and carry no id (unlike the ledger rows).
      // opening 100 + 500 debit - 200 credit = closing 400.
      return _json({
        'success': true,
        'data': {
          'supplier': {'id': 1, 'supplier_name': 'Alpha Traders'},
          'period': {'fromDate': null, 'toDate': null},
          'openingBalance': 100.0,
          'closingBalance': 400.0,
          'transactions': [
            {
              'transaction_date': '2026-01-10',
              'transaction_type': 'PURCHASE',
              'reference_no': 'PO-2026-001',
              'description': 'Purchase goods',
              'debit': 500.0,
              'credit': 0.0,
              'balance': 600.0,
            },
            {
              'transaction_date': '2026-01-20',
              'transaction_type': 'PAYMENT',
              'reference_no': 'PAY-2026-005',
              'description': 'Payment made',
              'debit': 0.0,
              'credit': 200.0,
              'balance': 400.0,
            },
          ],
        },
      });
    }
    if (options.path == '/suppliers/1/balance' && options.method == 'GET') {
      // Enveloped — the real getSupplierBalance shape.
      return _json({
        'success': true,
        'data': {
          'supplierId': 1,
          'supplierName': 'Alpha Traders',
          'currentBalance': 250.0,
        },
      });
    }
    if (options.path == '/purchase-orders/summary/supplier/1' &&
        options.method == 'GET') {
      // Bare object — the real getSummaryBySupplier shape (no envelope).
      return _json({
        'total_pos': 4,
        'total_value': 9000.0,
        'draft_pos': 1,
        'submitted_pos': 1,
        'partially_received_pos': 1,
        'completed_pos': 1,
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
        'warehouse_id': 1,
        'warehouse_name': 'Main Warehouse',
        'total_amount': 1500.0,
        'paid_amount': 500.0,
        'balance_amount': 1000.0,
        'status': po1Status,
        'expected_delivery_date': '2026-02-01',
        'items': [
          {
            'id': 1,
            'item_id': 4,
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
            'item_id': 5,
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
    if (options.path == '/purchase-orders' && options.method == 'POST') {
      final body = options.data as Map<String, dynamic>;
      lastPoPostBody = body;
      // Bare 201 — the real createPurchaseOrder shape (PO no generated).
      return _json({
        'id': 99,
        'po_no': 'PO-2026-099',
        'po_date': body['po_date'],
        'supplier_id': body['supplier_id'],
        'status': body['status'] ?? 'Draft',
        'total_amount': 0,
      }, status: 201);
    }
    if (options.path == '/purchase-orders/1' && options.method == 'PUT') {
      lastPoPutBody = options.data as Map<String, dynamic>;
      return _json({'id': 1, 'po_no': 'PO-2026-001', 'status': 'Draft'});
    }
    if (options.path == '/purchase-orders/1' && options.method == 'DELETE') {
      poDeleteCount++;
      return _json({
        'success': true,
        'message': 'Purchase order deleted successfully',
      });
    }
    if (options.path == '/purchase-orders/1/items' &&
        options.method == 'POST') {
      final body = options.data as Map<String, dynamic>;
      lastPoItemPostBody = body;
      return _json({
        'id': 30,
        'item_id': body['item_id'],
        'item_code': 'FG001',
        'item_name': 'Widget A',
        'unit_of_measure': 'pcs',
        'quantity': body['quantity'],
        'unit_price': body['unit_price'],
        'amount': body['quantity'] * body['unit_price'],
      }, status: 201);
    }
    if (options.path == '/purchase-orders/1/items/1' &&
        options.method == 'PUT') {
      final body = options.data as Map<String, dynamic>;
      lastPoItemPutBody = body;
      return _json({
        'id': 1,
        'item_id': 1,
        'item_code': 'RM001',
        'item_name': 'Raw Material A',
        'unit_of_measure': 'kg',
        'quantity': body['quantity'],
        'unit_price': body['unit_price'],
      });
    }
    if (options.path == '/purchase-orders/1/items/1' &&
        options.method == 'DELETE') {
      poItemDeleteCount++;
      return _json({'success': true, 'message': 'Line item deleted'});
    }
    if (options.path == '/purchase-orders/1/status' &&
        options.method == 'POST') {
      final body = options.data as Map<String, dynamic>;
      lastPoStatusBody = body;
      if (rejectPoStatus) {
        return _json({
          'error': 'Cannot transition from Draft to Submitted',
        }, status: 400);
      }
      po1Status = body['status'] as String;
      return _json({'id': 1, 'po_no': 'PO-2026-001', 'status': po1Status});
    }
    if (options.path == '/purchase-orders/1/receipts' &&
        options.method == 'GET') {
      // Bare array — the real getGoodsReceipts shape.
      return _json(po1Receipts);
    }
    if (options.path == '/purchase-orders/1/receipts' &&
        options.method == 'POST') {
      final body = options.data as Map<String, dynamic>;
      lastPoReceiptBody = body;
      if (rejectPoReceipt) {
        return _json({'error': 'Cannot receive more than pending quantity'}, status: 400);
      }
      // Bare 201 — the real createGoodsReceipt shape (receipt no
      // generated server-side; the quantity/value aggregates echo the
      // posted lines like the SQL SUM does).
      final qty = (body['items'] as List)
          .fold<num>(0, (sum, item) => sum + (item['received_quantity'] as num));
      final receipt = {
        'id': 10,
        'receipt_no': 'GR-2026-001',
        'po_id': 1,
        'receipt_date': body['receipt_date'],
        'warehouse_id': body['warehouse_id'],
        'remarks': body['remarks'],
        'created_at': '2026-08-10 10:00:00',
        'warehouse_name': 'Main Warehouse',
        'created_by_username': 'admin',
        'total_quantity': qty,
        'total_amount': qty * 10.0,
      };
      po1Receipts.add(receipt);
      // The server's calculateStatus flips the PO based on the received
      // quantities (Partially Received when any line still has pending).
      po1Status = 'Partially Received';
      return _json(receipt, status: 201);
    }
    if (options.path == '/purchases' && options.method == 'GET') {
      // Bare array — the real Purchase.getAll shape (joined item/warehouse/
      // user fields; no envelope, no pagination).
      return _json([
        {
          'id': 1,
          'purchase_no': 'PUR-2026-001',
          'purchase_date': '2026-01-15',
          'item_id': 4,
          'item_code': 'RM001',
          'item_name': 'Raw Material A',
          'unit_of_measure': 'kg',
          'quantity': 100.0,
          'unit_cost': 10.0,
          'total_cost': 1000.0,
          'supplier_name': 'Alpha Traders',
          'warehouse_id': 1,
          'warehouse_name': 'Main Warehouse',
          'invoice_no': 'INV-101',
          'remarks': 'Bulk order',
          'returned_quantity': purchase1ReturnedQty,
          'created_by_username': 'admin',
        },
        {
          'id': 2,
          'purchase_no': 'PUR-2026-002',
          'purchase_date': '2026-01-22',
          'item_id': 5,
          'item_code': 'FG002',
          'item_name': 'Finished Good B',
          'unit_of_measure': 'pcs',
          'quantity': 25.0,
          'unit_cost': 40.0,
          'total_cost': 1000.0,
          'supplier_name': 'Beta Supplies',
          'warehouse_id': 1,
          'warehouse_name': 'Main Warehouse',
          'invoice_no': 'INV-102',
          'returned_quantity': 0,
          'created_by_username': 'admin',
        },
      ]);
    }
    if (options.path == '/purchases/1' && options.method == 'GET') {
      // Bare object — the real getPurchase shape (same joined fields).
      return _json({
        'id': 1,
        'purchase_no': 'PUR-2026-001',
        'purchase_date': '2026-01-15',
        'item_id': 4,
        'item_code': 'RM001',
        'item_name': 'Raw Material A',
        'unit_of_measure': 'kg',
        'quantity': 100.0,
        'unit_cost': 10.0,
        'total_cost': 1000.0,
        'supplier_name': 'Alpha Traders',
        'warehouse_id': 1,
        'warehouse_name': 'Main Warehouse',
        'invoice_no': 'INV-101',
        'remarks': 'Bulk order',
        'returned_quantity': purchase1ReturnedQty,
        'created_by_username': 'admin',
      });
    }
    if (options.path == '/purchases/1/return' && options.method == 'POST') {
      final body = options.data as Map<String, dynamic>;
      lastPurchaseReturnBody = body;
      if (rejectPurchaseReturn) {
        return _json({
          'error': 'Insufficient stock remaining to return',
        }, status: 400);
      }
      final qty = (body['quantity'] as num).toDouble();
      purchase1ReturnedQty += qty;
      // Enveloped — the real returnPurchaseItems shape.
      return _json({
        'success': true,
        'message': 'Return processed successfully',
        'data': {'returnedQuantity': qty, 'totalCost': qty * 10.0},
      });
    }
    if (options.path == '/purchases/returns' && options.method == 'GET') {
      // Bare array — the real Purchase.getReturnHistory shape (negative-
      // quantity stock movements; no envelope, no pagination).
      return _json([
        {
          'id': 1,
          'movement_no': 'SM-2026-0018',
          'item_id': 1,
          'warehouse_id': 1,
          'quantity': -5.0,
          'unit_cost': 10.0,
          'reference_doctype': 'PURCHASE_RETURN',
          'reference_docno': 'PUR-2026-011',
          'remarks': 'Damaged on delivery',
          'return_date': '2026-02-10',
          'created_at': '2026-02-10 10:30:00',
          'created_by': 1,
          'item_code': 'RM001',
          'item_name': 'Raw Material A',
          'unit_of_measure': 'kg',
          'warehouse_code': 'WH-MAIN',
          'warehouse_name': 'Main Warehouse',
          'created_by_username': 'admin',
        },
        {
          'id': 2,
          'movement_no': 'SM-2026-0021',
          'item_id': 2,
          'warehouse_id': 2,
          'quantity': -2.0,
          'unit_cost': 40.0,
          'reference_doctype': 'PO_RETURN',
          'reference_docno': 'PO-2026-002',
          'remarks': null,
          'return_date': '2026-02-12',
          'created_at': '2026-02-12 09:15:00',
          'created_by': 1,
          'item_code': 'FG002',
          'item_name': 'Finished Good B',
          'unit_of_measure': 'pcs',
          'warehouse_code': 'WH-SEC',
          'warehouse_name': 'Secondary Warehouse',
          'created_by_username': 'admin',
        },
      ]);
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
    if (options.path == '/suppliers/1' && options.method == 'DELETE') {
      supplierDeleteCount++;
      return _json({
        'success': true,
        'message': 'Supplier deleted successfully',
      });
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
      itemsFetchCount++;
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
        // The purchase-order detail lines reference these (their item_id
        // must resolve in the same list for the PO form's line selects).
        {
          'id': 4,
          'item_code': 'RM001',
          'item_name': 'Raw Material A',
          'category': 'Raw',
          'unit_of_measure': 'kg',
          'current_stock': 30,
          'reorder_level': 0,
          'standard_cost': 10.0,
          'standard_selling_price': 14.0,
          'is_raw_material': 1,
          'is_finished_good': 0,
          'is_active': 1,
        },
        {
          'id': 5,
          'item_code': 'FG002',
          'item_name': 'Finished Good B',
          'category': 'Parts',
          'unit_of_measure': 'pcs',
          'current_stock': 8,
          'reorder_level': 0,
          'standard_cost': 40.0,
          'standard_selling_price': 60.0,
          'is_raw_material': 0,
          'is_finished_good': 1,
          'is_active': 1,
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
    if (options.path == '/inventory/stock-ledger/1') {
      // Bare array — the real StockMovementModel.getItemLedger shape:
      // newest-first by movement_date, warehouse join (no item join),
      // honoring the optional `warehouse_id` query filter.
      lastLedgerQuery = options.queryParameters;
      if (emptyStockLedger) {
        return _json(<Object>[]);
      }
      final ledgerRows = [
        {
          'id': 3,
          'movement_no': 'SM-2026-0102',
          'item_id': 1,
          'warehouse_id': 2,
          'movement_type': 'TRANSFER',
          'quantity': 2.0,
          'unit_cost': 25.0,
          'reference_doctype': 'TRANSFER',
          'reference_docno': 'SM-2026-0099',
          'remarks': 'Transfer in',
          'movement_date': '2026-02-03',
          'created_by': 1,
          'created_at': '2026-02-03 10:00:00',
          // Matches the /inventory/warehouses fake's id-2 entry (the
          // filter dropdown lists warehouses from that endpoint).
          'warehouse_code': 'WH-RAW',
          'warehouse_name': 'Raw Materials',
        },
        {
          'id': 2,
          'movement_no': 'SM-2026-0101',
          'item_id': 1,
          'warehouse_id': 1,
          'movement_type': 'SALE',
          'quantity': -3.0,
          'unit_cost': 25.0,
          'reference_doctype': 'SALE',
          'reference_docno': 'INV-2026-001',
          'remarks': 'POS sale',
          'movement_date': '2026-02-02',
          'created_by': 1,
          'created_at': '2026-02-02 12:30:00',
          'warehouse_code': 'WH-MAIN',
          'warehouse_name': 'Main Warehouse',
        },
        {
          'id': 1,
          'movement_no': 'SM-2026-0100',
          'item_id': 1,
          'warehouse_id': 1,
          'movement_type': 'PURCHASE',
          'quantity': 10.0,
          'unit_cost': 10.0,
          'reference_doctype': 'PURCHASE',
          'reference_docno': 'PUR-2026-001',
          'remarks': 'Goods received',
          'movement_date': '2026-02-01',
          'created_by': 1,
          'created_at': '2026-02-01 09:00:00',
          'warehouse_code': 'WH-MAIN',
          'warehouse_name': 'Main Warehouse',
        },
      ];
      final warehouseFilter = options.queryParameters['warehouse_id'] as int?;
      return _json([
        for (final row in ledgerRows)
          if (warehouseFilter == null || row['warehouse_id'] == warehouseFilter)
            row,
      ]);
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
    if (options.path == '/inventory/warehouses' && options.method == 'GET') {
      // Enveloped array — the real Warehouse.getAll shape.
      // WH-MAIN is dropped after the delete test's DELETE (the server
      // soft-deletes, so the refetched list omits the row).
      return _json({
        'success': true,
        'data': [
          if (!warehouse1Deleted)
            {
              'id': 1,
              'warehouse_code': 'WH-MAIN',
              'warehouse_name': 'Main Warehouse',
              'location': 'Sector 14',
              'is_active': 1,
              'total_items': 125,
              'unique_items': 12,
            },
          {
            'id': 2,
            'warehouse_code': 'WH-RAW',
            'warehouse_name': 'Raw Materials',
            'location': 'Sector 9',
            'is_active': 0,
            'total_items': 40,
            'unique_items': 8,
          },
        ],
      });
    }
    if (options.path == '/inventory/warehouses/1' &&
        options.method == 'DELETE') {
      warehouseDeleteCount++;
      if (rejectWarehouseDelete) {
        return _json({'error': 'Warehouse not found'}, status: 404);
      }
      warehouse1Deleted = true;
      return _json({
        'success': true,
        'message': 'Warehouse deleted successfully',
      });
    }
    if (options.path == '/inventory/warehouses' && options.method == 'POST') {
      final body = options.data as Map<String, dynamic>;
      lastWarehousePostBody = body;
      if (rejectWarehouseCreate) {
        return _json({'error': 'Warehouse code already exists'}, status: 400);
      }
      // Bare 201 — the real createWarehouse shape.
      return _json({
        'id': 99,
        'warehouse_code': body['warehouse_code'],
        'warehouse_name': body['warehouse_name'],
        'location': body['location'],
        'is_active': 1,
        'total_items': 0,
        'unique_items': 0,
      }, status: 201);
    }
    if (options.path == '/inventory/warehouses/1' && options.method == 'PUT') {
      final body = options.data as Map<String, dynamic>;
      lastWarehousePutBody = body;
      // Bare updated warehouse — the real updateWarehouse shape.
      return _json({
        'id': 1,
        'warehouse_code': body['warehouse_code'],
        'warehouse_name': body['warehouse_name'],
        'location': body['location'],
        'is_active': 1,
        'total_items': 125,
        'unique_items': 12,
      });
    }
    if (options.path == '/inventory/stock-movements' &&
        options.method == 'GET') {
      // Bare array — the real StockMovementModel.getAll shape, honoring
      // the `movement_type` query filter like the model's getAll.
      lastMovementQuery = options.queryParameters;
      final type = options.queryParameters['movement_type'] as String?;
      return _json([
        for (final row in [
          _movementPurchaseRow(),
          _movementSaleRow(),
          _movementAdjustmentRow(),
          _movementTransferOutRow(),
          _movementTransferInRow(),
        ])
          if (type == null || type.isEmpty || row['movement_type'] == type) row,
      ]);
    }
    if (options.path == '/inventory/stock-movements' &&
        options.method == 'POST') {
      final body = options.data as Map<String, dynamic>;
      lastMovementPostBody = body;
      movementPostBodies.add(body);
      movementPostCount++;
      if (rejectMovementCreate) {
        // sendError() shape — `{error: 'message'}` — surfaces verbatim.
        return _json({
          'error': 'Insufficient stock for adjustment',
        }, status: 400);
      }
      if (rejectSecondMovement && movementPostCount >= 2) {
        return _json({'error': 'Destination warehouse not found'}, status: 400);
      }
      // Bare movement row — the real createStockMovement shape.
      return _json({
        'id': 3,
        'movement_no': 'SM-2026-0102',
        'item_id': body['item_id'],
        'warehouse_id': body['warehouse_id'],
        'movement_type': body['movement_type'],
        'quantity': body['quantity'],
        'unit_cost': 0,
        'reference_doctype': 'ADJUSTMENT',
        'reference_docno': 'ADJ-2026-001',
        'remarks': body['remarks'] ?? '',
        'movement_date': '2026-02-03',
        'created_by': 1,
        'created_at': '2026-02-03 10:00:00',
      });
    }
    final movementDetailId = RegExp(
      r'^/inventory/stock-movements/(\d+)$',
    ).firstMatch(options.path);
    if (movementDetailId != null && options.method == 'GET') {
      movementDetailFetchCount++;
      final id = int.parse(movementDetailId.group(1)!);
      return _json(switch (id) {
        1 => _movementPurchaseRow(),
        2 => _movementSaleRow(),
        3 => _movementAdjustmentRow(),
        4 => _movementTransferOutRow(),
        5 => _movementTransferInRow(),
        _ => throw StateError('Unexpected movement detail id: $id'),
      });
    }
    if (options.path == '/inventory/stock-balances' &&
        options.method == 'GET') {
      // Bare array — the real stockBalances shape (item×warehouse rows).
      return _json([
        {
          'item_id': 1,
          'item_code': 'FG001',
          'item_name': 'Widget A',
          'warehouse_id': 1,
          'warehouse_code': 'WH-MAIN',
          'warehouse_name': 'Main Warehouse',
          'quantity': 25.0,
        },
        {
          'item_id': 4,
          'item_code': 'RM001',
          'item_name': 'Raw Material A',
          'warehouse_id': 2,
          'warehouse_code': 'WH-RAW',
          'warehouse_name': 'Raw Materials',
          'quantity': 200.0,
        },
      ]);
    }
    if (options.path == '/inventory/physical-counts' &&
        options.method == 'GET') {
      // Enveloped array — the real PhysicalCountModel.getAll shape.
      return _json({
        'success': true,
        'data': [
          {
            'id': 1,
            'count_no': 'PC-2026-001',
            'count_date': '2026-03-01',
            'warehouse_id': 1,
            'warehouse_name': 'Main Warehouse',
            'status': pc1Status,
            'created_by': 1,
            'total_items': 10,
            'counted_items': 0,
            'variance_items': 0,
          },
          {
            'id': 2,
            'count_no': 'PC-2026-002',
            'count_date': '2026-03-05',
            'warehouse_id': 1,
            'warehouse_name': 'Main Warehouse',
            'status': 'Completed',
            'created_by': 1,
            'total_items': 10,
            'counted_items': 10,
            'variance_items': 2,
          },
        ],
      });
    }
    if (options.path == '/inventory/physical-counts/1') {
      // Bare object with the counted item lines — the real
      // getPhysicalCount shape. Status and per-item counted quantities
      // read the stateful pc1Status/pc1CountedQty so a complete/cancel/
      // record POST flips them on refetch.
      final system = _AuthFakeAdapter.pc1SystemQty;
      return _json({
        'id': 1,
        'count_no': 'PC-2026-001',
        'count_date': '2026-03-01',
        'warehouse_id': 1,
        'warehouse_name': 'Main Warehouse',
        'status': pc1Status,
        'created_by': 1,
        'total_items': 2,
        'counted_items': pc1CountedQty.length,
        'variance_items': pc1CountedQty.entries
            .where((e) => e.value != system[e.key])
            .length,
        'items': [
          {
            'id': 1,
            'count_id': 1,
            'item_id': 4,
            'item_code': 'RM001',
            'item_name': 'Raw Material A',
            'unit_of_measure': 'kg',
            'system_quantity': 100.0,
            'counted_quantity': pc1CountedQty[4],
            'variance': pc1CountedQty[4] == null
                ? null
                : pc1CountedQty[4]! - 100.0,
            'adjustment_posted': 0,
          },
          {
            'id': 2,
            'count_id': 1,
            'item_id': 5,
            'item_code': 'RM002',
            'item_name': 'Raw Material B',
            'unit_of_measure': 'kg',
            'system_quantity': 50.0,
            'counted_quantity': pc1CountedQty[5],
            'variance': pc1CountedQty[5] == null
                ? null
                : pc1CountedQty[5]! - 50.0,
            'adjustment_posted': 0,
          },
        ],
      });
    }
    if (options.path == '/inventory/physical-counts/1/items' &&
        options.method == 'POST') {
      final body = options.data as Map<String, dynamic>;
      lastPcRecordBody = body;
      if (rejectPcRecord) {
        return _json({
          'error': 'Cannot record count for Completed session',
        }, status: 400);
      }
      final itemId = body['item_id'] as int;
      final qty = body['counted_quantity'] as num;
      pc1CountedQty[itemId] = qty;
      final system = _AuthFakeAdapter.pc1SystemQty[itemId] ?? 0;
      return _json({
        'id': itemId,
        'count_id': 1,
        'item_id': itemId,
        'item_code': itemId == 4 ? 'RM001' : 'RM002',
        'item_name': itemId == 4 ? 'Raw Material A' : 'Raw Material B',
        'unit_of_measure': 'kg',
        'system_quantity': system,
        'counted_quantity': qty,
        'variance': qty - system,
        'adjustment_posted': 0,
      });
    }
    if (options.path == '/inventory/physical-counts/1/complete' &&
        options.method == 'POST') {
      if (rejectPcComplete) {
        return _json({
          'error': 'Cannot complete Completed session',
        }, status: 400);
      }
      pc1Status = 'Completed';
      return _json({'id': 1, 'count_no': 'PC-2026-001', 'status': pc1Status});
    }
    if (options.path == '/inventory/physical-counts/1/cancel' &&
        options.method == 'POST') {
      pc1Status = 'Cancelled';
      return _json({'id': 1, 'count_no': 'PC-2026-001', 'status': pc1Status});
    }
    if (options.path == '/reports/ar-aging') {
      // Enveloped — the real ReportsModel.getARAgingReport shape.
      return _json({
        'success': true,
        'data': {
          'asOfDate': '2026-08-08',
          'agingBuckets': [
            {
              'customer_name': 'Acme Corp',
              'customer_code': 'CUST001',
              'total_outstanding': 120.5,
              'current_amount': 50.0,
              'days_1_30': 70.5,
              'days_31_60': 0.0,
              'days_61_90': 0.0,
              'days_over_90': 0.0,
            },
            {
              'customer_name': 'Beta Ltd',
              'customer_code': 'CUST002',
              'total_outstanding': 300.0,
              'current_amount': 0.0,
              'days_1_30': 0.0,
              'days_31_60': 100.0,
              'days_61_90': 0.0,
              'days_over_90': 200.0,
            },
          ],
          'summary': {
            'totalReceivables': 420.5,
            'current_amount': 50.0,
            'total_1_30': 70.5,
            'total_31_60': 100.0,
            'total_61_90': 0.0,
            'total_over_90': 200.0,
          },
        },
      });
    }
    if (options.path == '/reports/sales-summary') {
      lastSalesSummaryQuery = options.queryParameters;
      // Enveloped — the real ReportsModel.getSalesSummary shape (stats +
      // per-invoice detail).
      return _json({
        'success': true,
        'data': {
          'period': {'startDate': '2026-07-08', 'endDate': '2026-08-08'},
          'summary': {
            'totalInvoices': 2,
            'totalSales': 1500.0,
            'totalItemsSold': 110.0,
            'averageInvoiceValue': 750.0,
            'totalPaid': 500.0,
            'totalBalance': 1000.0,
          },
          'sales': [
            {
              'invoice_date': '2026-08-01',
              'invoice_no': 'INV-2026-001',
              'customer_name': 'Acme Corp',
              'total_sales': 1000.0,
              'total_items': 100.0,
              'paid_amount': 500.0,
              'balance_amount': 500.0,
              'status': 'Partially Paid',
            },
            {
              'invoice_date': '2026-07-15',
              'invoice_no': 'INV-2026-002',
              'customer_name': 'Beta Ltd',
              'total_sales': 500.0,
              'total_items': 10.0,
              'paid_amount': 0.0,
              'balance_amount': 500.0,
              'status': 'Unpaid',
            },
          ],
        },
      });
    }
    if (options.path == '/reports/low-stock') {
      // Enveloped — the real ReportsModel.getLowStockReport shape.
      return _json({
        'success': true,
        'data': [
          {
            'id': 1,
            'item_code': 'FG001',
            'item_name': 'Widget A',
            'item_category': 'Parts',
            'unit_of_measure': 'pcs',
            'current_stock': 5.0,
            'minimum_stock': 10.0,
            'shortage': 5.0,
            'reorder_level': 8.0,
            'standard_selling_price': 45.0,
            'stock_status': 'Low Stock',
          },
          {
            'id': 2,
            'item_code': 'RM002',
            'item_name': 'Bolt',
            'item_category': 'Raw',
            'unit_of_measure': 'box',
            'current_stock': 0.0,
            'minimum_stock': 50.0,
            'shortage': 50.0,
            'reorder_level': 50.0,
            'standard_selling_price': 5.0,
            'stock_status': 'Out of Stock',
          },
        ],
      });
    }
    if (options.path == '/reports/stock-level') {
      // Enveloped — the real ReportsModel.getStockLevelReport shape.
      return _json({
        'success': true,
        'data': {
          'stockLevels': [
            {
              'id': 1,
              'item_code': 'FG001',
              'item_name': 'Widget A',
              'item_category': 'Parts',
              'unit_of_measure': 'pcs',
              'current_stock': 25.0,
              'minimum_stock': 10.0,
              'reorder_level': 8.0,
              'standard_selling_price': 45.0,
              'stock_status': 'In Stock',
            },
            {
              'id': 2,
              'item_code': 'RM002',
              'item_name': 'Bolt',
              'item_category': 'Raw',
              'unit_of_measure': 'box',
              'current_stock': 0.0,
              'minimum_stock': 50.0,
              'reorder_level': 50.0,
              'standard_selling_price': 5.0,
              'stock_status': 'Out of Stock',
            },
          ],
          'summary': {
            'totalItems': 2,
            'inStock': 1,
            'lowStock': 0,
            'outOfStock': 1,
          },
        },
      });
    }
    if (options.path == '/reports/stock-valuation') {
      // Enveloped — the real ReportsModel.getStockValuationReport shape
      // (the SQL aliases quantity as total_stock and cost as
      // standard_cost, exactly as served).
      return _json({
        'success': true,
        'data': {
          'stockValuation': [
            {
              'id': 1,
              'item_code': 'FG001',
              'item_name': 'Widget A',
              'category': 'Parts',
              'unit_of_measure': 'pcs',
              'total_stock': 25.0,
              'standard_cost': 30.0,
              'total_value': 750.0,
              'valuation_method': 'batch',
            },
            {
              'id': 2,
              'item_code': 'RM002',
              'item_name': 'Bolt',
              'category': 'Raw',
              'unit_of_measure': 'box',
              'total_stock': 40.0,
              'standard_cost': 2.0,
              'total_value': 80.0,
              'valuation_method': 'standard_cost_fallback',
            },
          ],
          'summary': {
            'totalValue': 830.0,
            'totalItems': 2,
            'batchTrackedItems': 1,
            'legacyItems': 1,
          },
        },
      });
    }
    if (options.path == '/reports/sales-by-customer') {
      // Bare array (not wrapped in an object) — the real
      // ReportsModel.getSalesByCustomer shape.
      return _json({
        'success': true,
        'data': [
          {
            'customer_name': 'Acme Corp',
            'customer_code': 'CUST001',
            'email': 'billing@acme.test',
            'phone': '555-0100',
            'total_invoices': 3,
            'total_sales': 2400.0,
            'total_items': 60,
            'average_order_value': 800.0,
            'last_purchase_date': '2026-08-01',
          },
          {
            'customer_name': 'Beta Ltd',
            'customer_code': 'CUST002',
            'email': 'ap@beta.test',
            'phone': '555-0200',
            'total_invoices': 1,
            'total_sales': 500.0,
            'total_items': 10,
            'average_order_value': 500.0,
            'last_purchase_date': '2026-07-15',
          },
        ],
      });
    }
    if (options.path == '/reports/dso') {
      return _json({
        'success': true,
        'data': {
          'dso': 18.65,
          'avgReceivables': 50000,
          'totalCreditSales': 101895,
          'totalSales': 101895,
          'totalAR': 50000,
          'avgInvoiceValue': 33965,
          'period': {'startDate': '2026-07-01', 'endDate': '2026-08-08'},
        },
      });
    }
    if (options.path == '/reports/cash-flow') {
      return _json({
        'success': true,
        'data': {
          'startDate': '2026-07-01',
          'endDate': '2026-08-08',
          'totalInflow': 52895,
          'totalOutflow': 1000,
          'netCashFlow': 51895,
        },
      });
    }
    if (options.path == '/reports/profit-loss') {
      return _json({
        'success': true,
        'data': {
          'startDate': '2026-07-01',
          'endDate': '2026-08-08',
          'totalRevenue': 101895,
          'totalCogs': 271315.5,
          'grossProfit': -169420.5,
          'expenses': [
            {'expense_category': 'Marketing', 'total': 2000},
          ],
          'totalExpenses': 2000,
          'netProfit': -171420.5,
          'grossProfitMargin': -166.27,
          'netProfitMargin': -168.23,
        },
      });
    }
    if (options.path == '/reports/inventory-movement') {
      return _json({
        'success': true,
        'data': {
          'movements': [
            {
              'movement_no': 'STK-2026-0001',
              'movement_type': 'SALE',
              'quantity': -2,
              'unit_cost': 35.5,
              'movement_date': '2026-08-08',
              'reference_doctype': 'INVOICE',
              'reference_docno': 'INV-2026-0001',
              'remarks': 'Sold via invoice',
              'item_code': 'RM-008',
              'item_name': 'Cardboard Box (Small)',
              'warehouse_name': 'Main Warehouse',
            },
          ],
          'summary': {'totalInbound': 0, 'totalOutbound': 1, 'netMovement': -1},
        },
      });
    }
    if (options.path == '/reports/purchase-summary') {
      return _json({
        'success': true,
        'data': {
          'purchases': [
            {
              'po_id': 6,
              'purchase_order_number': 'PO-2026-0004',
              'purchase_date': '2026-08-02',
              'supplier_name': 'Haier Distributors',
              'total_cost': 400000,
              'status': 'Completed',
              'total_items': 1,
              'received_amount': 400000,
              'balance_amount': 0,
            },
          ],
          'summary': {
            'totalOrders': 1,
            'totalCost': 400000,
            'totalItems': 1,
            'averageOrderValue': 400000,
            'returnCount': 0,
            'returnQuantity': 0,
            'returnValue': 0,
          },
        },
      });
    }
    if (options.path == '/reports/expenses') {
      return _json({
        'success': true,
        'data': {
          'summary': {
            'totalAmount': 27500,
            'totalExpenses': 2,
            'averageAmount': 13750,
          },
          'expenses': [
            {
              'id': 3,
              'expense_no': 'EXP-2026-0003',
              'expense_category': 'Utilities',
              'description': 'Electricity bill',
              'amount': 25000,
              'expense_date': '2026-08-05',
              'payment_method': 'Bank Transfer',
              'reference_no': 'TRF-2231',
              'vendor_name': 'LESCO',
              'project': 'Head Office',
              'status': 'Approved',
            },
            {
              'id': 4,
              'expense_no': 'EXP-2026-0004',
              'expense_category': 'Office Supplies',
              'description': 'Printer paper',
              'amount': 2500,
              'expense_date': '2026-08-07',
              'payment_method': 'Cash',
              'reference_no': null,
              'vendor_name': null,
              'project': null,
              'status': 'Draft',
            },
          ],
          'categoryBreakdown': [
            {
              'expense_category': 'Utilities',
              'count': 1,
              'total_amount': 25000,
            },
            {
              'expense_category': 'Office Supplies',
              'count': 1,
              'total_amount': 2500,
            },
          ],
        },
      });
    }
    if (options.path == '/reports/top-debtors') {
      return _json({
        'success': true,
        'data': [
          {
            'customer_name': 'Awees Super Store',
            'customer_code': 'CUST-006',
            'total_outstanding': 50000,
            'outstanding_balance': 50000,
            'total_invoiced': 50000,
            'invoice_count': 1,
          },
          {
            'customer_name': 'Gulhaji Plaza',
            'customer_code': 'CUST-002',
            'total_outstanding': 18000,
            'outstanding_balance': 18000,
            'total_invoiced': 70000,
            'invoice_count': 1,
          },
        ],
      });
    }
    if (options.path == '/reports/sales-by-item') {
      lastSalesByItemQuery = options.queryParameters;
      if (failSalesByItem) {
        return _json({
          'success': false,
          'error': {
            'code': 'SERVER_ERROR',
            'message': 'Failed to fetch sales by item',
          },
        }, status: 500);
      }
      // Bare array (not wrapped in an object) — the real
      // ReportsModel.getSalesByItem shape.
      return _json({
        'success': true,
        'data': [
          {
            'item_code': 'FG001',
            'item_name': 'Widget A',
            'item_category': 'Parts',
            'total_quantity_sold': 120,
            'total_sales': 24000.0,
            'avg_selling_price': 200.0,
          },
          {
            'item_code': 'FG003',
            'item_name': 'Gadget',
            'item_category': 'Assemblies',
            'total_quantity_sold': 40,
            'total_sales': 4000.0,
            'avg_selling_price': 100.0,
          },
        ],
      });
    }
    if (options.path == '/reports/supplier-analysis') {
      lastSupplierAnalysisQuery = options.queryParameters;
      if (failSupplierAnalysis) {
        return _json({
          'success': false,
          'error': {
            'code': 'SERVER_ERROR',
            'message': 'Failed to fetch supplier analysis',
          },
        }, status: 500);
      }
      // Bare array — the real ReportsModel.getSupplierAnalysis shape.
      return _json({
        'success': true,
        'data': [
          {
            'supplier_id': 1,
            'supplier_name': 'Al-Fatah Traders',
            'supplier_code': 'SUP-001',
            'email': 'sales@alfatah.test',
            'phone': '555-0101',
            'total_orders': 4,
            'total_purchase_value': 180000.0,
            'average_order_value': 45000.0,
            'last_purchase_date': '2026-08-05',
            'total_items': 18,
            'on_time_delivery_rate': 100,
          },
          {
            'supplier_id': 2,
            'supplier_name': 'Karachi Steel',
            'supplier_code': 'SUP-002',
            'email': 'orders@karachisteel.test',
            'phone': '555-0102',
            'total_orders': 2,
            'total_purchase_value': 60000.0,
            'average_order_value': 30000.0,
            'last_purchase_date': '2026-07-20',
            'total_items': 9,
            'on_time_delivery_rate': 100,
          },
        ],
      });
    }
    if (options.path == '/reports/production-summary') {
      lastProductionSummaryQuery = options.queryParameters;
      if (failProductionSummary) {
        return _json({
          'success': false,
          'error': {
            'code': 'SERVER_ERROR',
            'message': 'Failed to fetch production summary',
          },
        }, status: 500);
      }
      return _json({
        'success': true,
        'data': {
          'production': [
            {
              'work_order_number': 'WO-001',
              'production_date': '2026-08-01',
              'production_order_number': 'WO-001',
              'output_item_name': 'Widget A',
              'output_quantity': 50,
              'completed_quantity': 50,
              'scrapped_quantity': 0,
              'planned_quantity': 50,
              'item_name': 'Widget A',
              'status': 'Completed',
            },
            {
              'work_order_number': 'WO-002',
              'production_date': '2026-07-15',
              'production_order_number': 'WO-002',
              'output_item_name': 'Gadget',
              'output_quantity': 30,
              'completed_quantity': 30,
              'scrapped_quantity': 2,
              'planned_quantity': 32,
              'item_name': 'Gadget',
              'status': 'Completed',
            },
          ],
          'summary': {
            'totalProductionOrders': 2,
            'totalOutput': 80,
            'totalCompleted': 80,
            'totalScrapped': 2,
          },
        },
      });
    }
    if (options.path == '/reports/bom-usage') {
      lastBomUsageQuery = options.queryParameters;
      if (failBomUsage) {
        return _json({
          'success': false,
          'error': {
            'code': 'SERVER_ERROR',
            'message': 'Failed to fetch BOM usage',
          },
        }, status: 500);
      }
      return _json({
        'success': true,
        'data': {
          'usage': [
            {
              'bom_id': 1,
              'bom_name': 'Widget A BOM',
              'parent_item_name': 'Widget A',
              'usage_count': 3,
              'last_used_date': '2026-08-01',
              'total_components': 4,
              'status': 'Active',
            },
            {
              'bom_id': 2,
              'bom_name': 'Gadget BOM',
              'parent_item_name': 'Gadget',
              'usage_count': 1,
              'last_used_date': '2026-07-15',
              'total_components': 2,
              'status': 'Active',
            },
          ],
        },
      });
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
            'returned_qty': invoice1ReturnedQty,
          },
        ],
      });
    }
    if (options.path == '/invoices/1/payments' && options.method == 'GET') {
      // Bare array — the real getInvoicePayments shape (no envelope).
      return _json(<Object>[]);
    }
    if (options.path == '/invoices/1/return' && options.method == 'POST') {
      final body = options.data as Map<String, dynamic>;
      lastInvoiceReturnBody = body;
      if (rejectInvoiceReturn) {
        return _json({
          'error': 'Cannot return a cancelled invoice',
        }, status: 400);
      }
      final items = body['items'] as List;
      final qty = ((items.single as Map)['return_quantity'] as num).toDouble();
      invoice1ReturnedQty += qty;
      // Enveloped — the real returnInvoiceItems shape.
      return _json({
        'success': true,
        'message': 'Return processed successfully',
        'data': {
          'returnedItems': [
            {
              'invoice_item_id': 10,
              'item_name': 'Widget A',
              'return_quantity': qty,
              'return_amount': qty * 100.0,
            },
          ],
          'totalItems': 1,
          'disposition': body['disposition'],
          'returnAmount': qty * 100.0,
          'netReturn': qty * 100.0,
          'deduction': 0,
        },
      });
    }
    if (options.path == '/invoices/returns' && options.method == 'GET') {
      // Bare array — the real InvoiceModel.getReturnHistory shape
      // (positive-quantity RETURN stock movements; no envelope, no
      // pagination).
      return _json([
        {
          'id': 1,
          'movement_no': 'SM-2026-0031',
          'item_id': 1,
          'item_code': 'FG001',
          'item_name': 'Widget A',
          'unit_of_measure': 'pcs',
          'warehouse_id': 1,
          'warehouse_code': 'WH-MAIN',
          'warehouse_name': 'Main Warehouse',
          'quantity': 4.0,
          'unit_cost': 100.0,
          'reference_doctype': 'RETURN',
          'reference_docno': 'INV-2026-440955',
          'invoice_no': 'INV-2026-440955',
          'remarks': 'Damaged on delivery',
          'return_date': '2026-05-25',
          'created_at': '2026-05-25 14:00:00',
          'created_by': 1,
          'created_by_username': 'Fawad',
          'customer_id': 1,
          'customer_name': 'Acme Corp',
        },
        {
          'id': 2,
          'movement_no': 'SM-2026-0034',
          'item_id': 2,
          'item_code': 'FG002',
          'item_name': 'Widget B',
          'unit_of_measure': 'pcs',
          'warehouse_id': 2,
          'warehouse_code': 'WH-2',
          'warehouse_name': 'Store 2',
          'quantity': 2.0,
          'unit_cost': 45.0,
          'reference_doctype': 'RETURN',
          'reference_docno': 'INV-2026-440956',
          'invoice_no': 'INV-2026-440956',
          'remarks': null,
          'return_date': '2026-05-20',
          'created_at': '2026-05-20 09:00:00',
          'created_by': 1,
          'created_by_username': 'Fawad',
          'customer_id': 2,
          'customer_name': 'Beta Ltd',
        },
      ]);
    }
    if (options.path == '/payments' && options.method == 'GET') {
      final q = options.queryParameters;
      lastPaymentsQuery = q;
      final page = int.tryParse('${q['page']}') ?? 1;
      const all = [
        {
          'id': 1,
          'payment_no': 'PAY-2026-0001',
          'customer_id': 1,
          'customer_name': 'Acme Corp',
          'payment_date': '2026-05-25',
          'amount': 500,
          'payment_method': 'Cash',
          'reference_no': 'CHK-1001',
          'notes': 'Partial payment',
          'created_at': '2026-05-25 10:00:00',
        },
        {
          'id': 2,
          'payment_no': 'PAY-2026-0002',
          'customer_id': 2,
          'customer_name': 'Beta Ltd',
          'payment_date': '2026-05-28',
          'amount': 800,
          'payment_method': 'Bank Transfer',
          'reference_no': null,
          'notes': null,
          'created_at': '2026-05-28 12:00:00',
        },
      ];
      return _json({
        'success': true,
        'data': all,
        'pagination': {
          'currentPage': page,
          'totalPages': 1,
          'totalItems': all.length,
          'hasNext': false,
          'hasPrev': false,
        },
      });
    }
    if (options.path == '/payments/1' && options.method == 'PUT') {
      final body = options.data as Map<String, dynamic>;
      lastPaymentPutBody = body;
      return _json({
        'success': true,
        'data': {
          'id': 1,
          'payment_no': 'PAY-2026-0001',
          'customer_id': 1,
          'customer_name': 'Acme Corp',
          'payment_date': body['payment_date'],
          'amount': 500,
          'payment_method': body['payment_method'],
          'reference_no': body['reference_no'],
          'notes': body['notes'],
        },
      });
    }
    if (options.path == '/payments/1' && options.method == 'DELETE') {
      paymentDeleteCount++;
      return _json({
        'success': true,
        'message': 'Payment deleted successfully',
      });
    }
    if (options.path == '/payments/1') {
      // Enveloped detail — the real getPayment shape.
      return _json({
        'success': true,
        'data': {
          'id': 1,
          'payment_no': 'PAY-2026-0001',
          'customer_id': 1,
          'customer_name': 'Acme Corp',
          'payment_date': '2026-05-25',
          'amount': 500,
          'payment_method': 'Cash',
          'reference_no': 'CHK-1001',
          'notes': 'Partial payment',
          'created_at': '2026-05-25 10:00:00',
        },
      });
    }
    if (options.path == '/payments' && options.method == 'POST') {
      final body = options.data as Map<String, dynamic>;
      lastPaymentPostBody = body;
      return _json({
        'success': true,
        'data': {
          'id': 9,
          'payment_no': 'PAY-2026-0009',
          'customer_id': body['customer_id'],
          'supplier_id': body['supplier_id'],
          'payment_date': body['payment_date'],
          'amount': body['amount'],
          'payment_method': body['payment_method'],
          'reference_no': body['reference_no'],
          'notes': body['notes'],
        },
      }, status: 201);
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
    if (options.path == '/quotations' && options.method == 'GET') {
      // Bare array — the real getQuotations shape (no envelope, no
      // pagination; the client grid sorts/filters client-side).
      lastQuotationsQuery = options.queryParameters;
      return _json([
        {
          'id': 1,
          'quotation_no': 'QT-2026-001',
          'quotation_date': '2026-01-18',
          'customer_id': 1,
          'customer_name': 'Acme Corp',
          'warehouse_id': 1,
          'warehouse_code': 'WH-MAIN',
          'warehouse_name': 'Main Warehouse',
          'expiry_date': '2026-02-18',
          'status': quotation1Status,
          'total_amount': 1200.0,
          'notes': null,
          'created_by': 1,
          'created_by_username': 'admin',
          'created_at': '2026-01-18 09:00:00',
          'updated_at': '2026-01-18 09:00:00',
        },
        {
          'id': 2,
          'quotation_no': 'QT-2026-002',
          'quotation_date': '2026-01-22',
          'customer_id': 2,
          'customer_name': 'Beta Ltd',
          'warehouse_id': 1,
          'warehouse_code': 'WH-MAIN',
          'warehouse_name': 'Main Warehouse',
          'expiry_date': null,
          'status': 'Draft',
          'total_amount': 900.0,
          'notes': null,
          'created_by': 1,
          'created_by_username': 'admin',
          'created_at': '2026-01-22 10:00:00',
          'updated_at': '2026-01-22 10:00:00',
        },
        {
          'id': 3,
          'quotation_no': 'QT-2026-003',
          'quotation_date': '2026-02-02',
          'customer_id': 3,
          'customer_name': 'Gamma Inc',
          'warehouse_id': 1,
          'warehouse_code': 'WH-MAIN',
          'warehouse_name': 'Main Warehouse',
          'expiry_date': '2026-02-15',
          'status': 'Accepted',
          'total_amount': 700.0,
          'notes': 'Follow up',
          'created_by': 1,
          'created_by_username': 'admin',
          'created_at': '2026-02-02 11:00:00',
          'updated_at': '2026-02-02 11:00:00',
        },
      ]);
    }
    if (options.path == '/quotations/1' && options.method == 'GET') {
      // Bare object with items — the real getQuotation shape.
      return _json({
        'id': 1,
        'quotation_no': 'QT-2026-001',
        'quotation_date': '2026-01-18',
        'customer_id': 1,
        'customer_name': 'Acme Corp',
        'warehouse_id': 1,
        'warehouse_code': 'WH-MAIN',
        'warehouse_name': 'Main Warehouse',
        'expiry_date': '2026-02-18',
        'status': quotation1Status,
        'total_amount': 1200.0,
        'notes': 'Follow up',
        'terms': 'Net 30',
        'created_by': 1,
        'created_by_username': 'admin',
        'created_at': '2026-01-18 09:00:00',
        'updated_at': '2026-01-18 09:00:00',
        'items': [
          {
            'id': 1,
            'item_id': 1,
            'item_code': 'FG001',
            'item_name': 'Widget A',
            'quantity': 10.0,
            'unit_price': 100.0,
            'discount_type': 'none',
            'discount_value': 0,
            'tax_rate': 0,
            'amount': 1000.0,
          },
          {
            'id': 2,
            'item_id': 5,
            'item_code': 'FG002',
            'item_name': 'Finished Good B',
            'quantity': 5.0,
            'unit_price': 40.0,
            'discount_type': 'none',
            'discount_value': 0,
            'tax_rate': 0,
            'amount': 200.0,
          },
        ],
      });
    }
    if (options.path == '/quotations' && options.method == 'POST') {
      final body = options.data as Map<String, dynamic>;
      lastQuotationPostBody = body;
      // Bare 201 — the real createQuotation shape (quotation no
      // generated; the response omits items).
      return _json({
        'id': 99,
        'quotation_no': 'QT-2026-099',
        'quotation_date': body['quotation_date'],
        'customer_id': body['customer_id'],
        'status': body['status'] ?? 'Draft',
        'total_amount': 0,
      }, status: 201);
    }
    if (options.path == '/quotations/1' && options.method == 'PUT') {
      final body = options.data as Map<String, dynamic>;
      lastQuotationPutBody = body;
      // Bare updated quotation — the real updateQuotation shape (items
      // replaced server-side; the response omits them).
      return _json({
        'id': 1,
        'quotation_no': 'QT-2026-001',
        'quotation_date': body['quotation_date'],
        'customer_id': body['customer_id'],
        'status': body['status'] ?? quotation1Status,
        'total_amount': 0,
      });
    }
    if (options.path == '/quotations/1' && options.method == 'DELETE') {
      quotationDeleteCount++;
      return _json({
        'success': true,
        'message': 'Quotation deleted successfully',
      });
    }
    if (options.path == '/quotations/1/convert' && options.method == 'POST') {
      quotationConvertCount++;
      quotation1Status = 'Converted';
      // Flat enveloped 201 — the real convertQuotationToSalesOrder shape
      // (message + created-SO ref spread at the top level, NO `data`
      // field, so the repo parses the raw body).
      return _json({
        'success': true,
        'message': 'Quotation converted to sales order',
        'salesOrderId': 7,
        'salesOrderNo': 'SO-2026-007',
      }, status: 201);
    }
    if (options.path == '/sales-orders' && options.method == 'GET') {
      // Bare array — the real getSalesOrders shape (no envelope, no
      // pagination; the client grid sorts/filters client-side).
      lastSalesOrdersQuery = options.queryParameters;
      return _json([
        {
          'id': 1,
          'so_no': 'SO-2026-001',
          'so_date': '2026-01-20',
          'customer_id': 1,
          'customer_name': 'Acme Corp',
          'warehouse_id': 1,
          'warehouse_code': 'WH-MAIN',
          'warehouse_name': 'Main Warehouse',
          'delivery_date': '2026-02-01',
          'status': so1Status,
          'total_amount': 1500.0,
          'notes': null,
          'source_type': 'DIRECT',
          'created_by': 1,
          'created_by_username': 'admin',
          'created_at': '2026-01-20 09:00:00',
          'updated_at': '2026-01-20 09:00:00',
        },
        {
          'id': 2,
          'so_no': 'SO-2026-002',
          'so_date': '2026-01-25',
          'customer_id': 2,
          'customer_name': 'Beta Ltd',
          'warehouse_id': 1,
          'warehouse_code': 'WH-MAIN',
          'warehouse_name': 'Main Warehouse',
          'delivery_date': null,
          'status': 'Completed',
          'total_amount': 2500.0,
          'notes': null,
          'source_type': 'QUOTATION',
          'source_id': 3,
          'quotation_no': 'QT-2026-003',
          'created_by': 1,
          'created_by_username': 'admin',
          'created_at': '2026-01-25 10:00:00',
          'updated_at': '2026-01-25 10:00:00',
        },
        {
          'id': 3,
          'so_no': 'SO-2026-003',
          'so_date': '2026-02-02',
          'customer_id': 3,
          'customer_name': 'Gamma Inc',
          'warehouse_id': 1,
          'warehouse_code': 'WH-MAIN',
          'warehouse_name': 'Main Warehouse',
          'delivery_date': '2026-02-20',
          'status': 'Invoiced',
          'total_amount': 800.0,
          'notes': 'Urgent',
          'source_type': 'DIRECT',
          'created_by': 1,
          'created_by_username': 'admin',
          'created_at': '2026-02-02 11:00:00',
          'updated_at': '2026-02-02 11:00:00',
        },
      ]);
    }
    if (options.path == '/sales-orders' && options.method == 'POST') {
      final body = options.data as Map<String, dynamic>;
      lastSalesOrderPostBody = body;
      // Bare 201 — the real createSalesOrder shape (SO no generated;
      // the response omits items).
      return _json({
        'id': 99,
        'so_no': 'SO-2026-099',
        'so_date': body['so_date'],
        'customer_id': body['customer_id'],
        'status': body['status'] ?? 'Draft',
        'total_amount': 0,
      }, status: 201);
    }
    if (options.path == '/sales-orders/1' && options.method == 'PUT') {
      final body = options.data as Map<String, dynamic>;
      lastSalesOrderPutBody = body;
      // Bare updated SO — the real updateSalesOrder shape (items
      // replaced server-side; the response omits them).
      return _json({
        'id': 1,
        'so_no': 'SO-2026-001',
        'so_date': body['so_date'],
        'customer_id': body['customer_id'],
        'status': body['status'] ?? so1Status,
        'total_amount': 0,
      });
    }
    if (options.path == '/sales-orders/1' && options.method == 'DELETE') {
      salesOrderDeleteCount++;
      return _json({'message': 'Sales order deleted successfully'});
    }
    if (options.path == '/sales-orders/1/cancel' && options.method == 'POST') {
      salesOrderCancelCount++;
      // Enveloped — the real cancelSalesOrder shape (reverses linked-
      // invoice stock server-side and returns the invoice it cancelled).
      so1Status = 'Cancelled';
      return _json({
        'success': true,
        'message': 'Sales order cancelled successfully',
        'invoiceId': 1,
        'invoiceNo': 'INV-2026-440955',
      });
    }
    if (options.path == '/sales-orders/1' && options.method == 'GET') {
      // Bare object with items — the real getSalesOrder shape.
      return _json({
        'id': 1,
        'so_no': 'SO-2026-001',
        'so_date': '2026-01-20',
        'customer_id': 1,
        'customer_name': 'Acme Corp',
        'warehouse_id': 1,
        'warehouse_code': 'WH-MAIN',
        'warehouse_name': 'Main Warehouse',
        'delivery_date': '2026-02-01',
        'status': so1Status,
        'total_amount': 1500.0,
        'notes': null,
        'source_type': 'DIRECT',
        'created_by': 1,
        'created_by_username': 'admin',
        'created_at': '2026-01-20 09:00:00',
        'updated_at': '2026-01-20 09:00:00',
        'items': [
          {
            'id': 1,
            'item_id': 1,
            'item_code': 'FG001',
            'item_name': 'Widget A',
            'quantity': 10.0,
            'delivered_quantity': 0.0,
            'unit_price': 100.0,
            'amount': 1000.0,
          },
          {
            'id': 2,
            'item_id': 5,
            'item_code': 'FG002',
            'item_name': 'Finished Good B',
            'quantity': 5.0,
            'delivered_quantity': 5.0,
            'unit_price': 100.0,
            'amount': 500.0,
          },
        ],
      });
    }
    if (options.path == '/dashboard/summary') {
      dashboardSummaryCalls++;
      lastDashboardSummaryQuery = options.queryParameters;
      return _json({
        'success': true,
        'data': {
          'totalItems': 150,
          'totalStockValue': 245000.50,
          'totalSalesRevenue': 890000.00,
          'totalPurchases': 560000.00,
          'totalProfit': 330000.00,
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
    if (options.path == '/dashboard/top-customers' && options.method == 'GET') {
      // Enveloped array — the real DashboardModel.getTopCustomers shape.
      return _json({
        'success': true,
        'data': [
          {
            'customer_name': 'Acme Corp',
            'total_revenue': 120000.0,
            'invoice_count': 12,
          },
          {
            'customer_name': 'Beta Ltd',
            'total_revenue': 80000.0,
            'invoice_count': 8,
          },
        ],
      });
    }
    if (options.path == '/dashboard/ar-summary' && options.method == 'GET') {
      // Enveloped — the real DashboardModel.getARSummary shape (total +
      // five aging buckets + customer count).
      return _json({
        'success': true,
        'data': {
          'total_ar': 420000.0,
          'current_amount': 120000.0,
          'amount_1_30': 90000.0,
          'amount_31_60': 80000.0,
          'amount_61_90': 60000.0,
          'amount_over_90': 70000.0,
          'customer_count': 25,
        },
      });
    }
    if (options.path == '/dashboard/cash-position') {
      // Enveloped — the real DashboardModel.getCashPosition shape (one
      // closing balance per tracked account + total).
      return _json({
        'success': true,
        'data': {
          'date': '2026-08-12',
          'accounts': [
            {
              'key': 'cash',
              'name': 'Cash',
              'balance': 25000.0,
              'opening': 20000.0,
              'inflow': 12000.0,
              'outflow': 4000.0,
              'net': 8000.0,
              'transactions': [
                {
                  'date': '2026-08-12',
                  'type': 'payment_received',
                  'reference': 'PAY002',
                  'description': 'Invoice INV-2026-152278',
                  'amount': 12000.0,
                },
                {
                  'date': '2026-08-12',
                  'type': 'supplier_payment',
                  'reference': 'PAY001',
                  'description': 'Supplier payment',
                  'amount': -4000.0,
                },
                {
                  'date': '2026-08-13',
                  'type': 'refund',
                  'reference': 'PAY004',
                  'description': 'Refund for return on INV-2026-152278',
                  'amount': -700.0,
                },
              ],
            },
            {'key': 'bank', 'name': 'Bank', 'balance': 180000.0, 'opening': 0, 'inflow': 0, 'outflow': 0, 'net': 0, 'transactions': []},
            {'key': 'easypaisa', 'name': 'Easypaisa', 'balance': 45000.0, 'opening': 0, 'inflow': 0, 'outflow': 0, 'net': 0, 'transactions': []},
            {'key': 'jazzcash', 'name': 'JazzCash', 'balance': 15000.0, 'opening': 0, 'inflow': 0, 'outflow': 0, 'net': 0, 'transactions': []},
            {'key': 'upaisa', 'name': 'UPaisa', 'balance': 8000.0, 'opening': 0, 'inflow': 0, 'outflow': 0, 'net': 0, 'transactions': []},
          ],
          'total': 273000.0,
        },
      });
    }
    if (options.path == '/dashboard/cash-opening-balances' &&
        options.method == 'GET') {
      // Enveloped — the real cashService.getOpeningBalances shape (the
      // per-account seed balances, cash starts at 20,000).
      return _json({
        'success': true,
        'data': {
          'accounts': [
            {'key': 'cash', 'name': 'Cash', 'amount': 20000.0},
            {'key': 'bank', 'name': 'Bank', 'amount': 0},
            {'key': 'easypaisa', 'name': 'Easypaisa', 'amount': 0},
            {'key': 'jazzcash', 'name': 'JazzCash', 'amount': 0},
            {'key': 'upaisa', 'name': 'UPaisa', 'amount': 0},
          ],
        },
      });
    }
    if (options.path == '/dashboard/cash-opening-balances' &&
        options.method == 'PUT') {
      final body = options.data as Map<String, dynamic>;
      lastOpeningBalancesPutBody = body;
      return _json({'success': true, 'data': body});
    }
    if (options.path == '/reports/cash-reconciliation' &&
        options.method == 'GET') {
      // Enveloped — the real Reports.getCashReconciliation shape
      // (per-account opening/day-flow/expected/counted + totals).
      return _json({
        'success': true,
        'data': {
          'date': '2026-08-12',
          'accounts': [
            {
              'key': 'cash',
              'name': 'Cash',
              'opening_balance': 20000.0,
              'inflow': 15000.0,
              'outflow': 10000.0,
              'net': 5000.0,
              'expected_balance': 25000.0,
              'counted_balance': null,
              'variance': null,
              'notes': null,
              'reconciled': false,
              'reconciled_at': null,
            },
            {
              'key': 'bank',
              'name': 'Bank',
              'opening_balance': 170000.0,
              'inflow': 20000.0,
              'outflow': 10000.0,
              'net': 10000.0,
              'expected_balance': 180000.0,
              'counted_balance': 179500.0,
              'variance': -500.0,
              'notes': 'Bank fee',
              'reconciled': true,
              'reconciled_at': '2026-08-12 18:00:00',
            },
          ],
          'totals': {
            'total_opening': 190000.0,
            'total_inflow': 35000.0,
            'total_outflow': 20000.0,
            'total_closing': 205000.0,
          },
        },
      });
    }
    if (options.path == '/reports/cash-reconciliation' &&
        options.method == 'POST') {
      // Enveloped — the real saveCashReconciliation shape.
      return _json({
        'success': true,
        'message': 'Reconciliation saved successfully',
      });
    }
    // ── Production module (PORTING.md §13) ────────────────────────
    if (options.path == '/productions' && options.method == 'GET') {
      // Bare array — the ProductionModel.getAll shape.
      final rows = <Map<String, dynamic>>[
        {
          'id': 4,
          'production_no': 'PROD-2026-0044',
          'output_item_id': 41,
          'output_quantity': 10,
          'warehouse_id': 3,
          'production_date': '2026-08-10',
          'created_by': 1,
          'created_at': '2026-08-10 09:00:00',
          'updated_at': '2026-08-10 09:00:00',
          'raw_materials_warehouse_id': 2,
          'overhead_cost': 100,
          'bom_id': 1,
          'batch_id': 9,
          'batch_no': 'BATCH-26-PRD-0044',
          'unit_cost': 310.5,
          'total_material_cost': 3000,
          'total_batch_cost': 3105,
          'output_item_code': 'AC1.5TON',
          'output_item_name': '1.5 Ton Split AC Carton Box',
          'output_uom': 'Nos',
          'finished_goods_warehouse_code': 'WH-003',
          'finished_goods_warehouse_name': 'UOP Store',
          'raw_materials_warehouse_code': 'WH-002',
          'raw_materials_warehouse_name': 'Karkhano Warehouse',
          'created_by_username': 'admin',
        },
      ];
      if (production4Deleted) rows.removeAt(0);
      return _json(rows);
    }
    if (options.path == '/productions/4' && options.method == 'GET') {
      productionDetailFetchCount++;
      if (production4Deleted) {
        return _json({'error': 'Production not found'}, status: 404);
      }
      return _json({
        'id': 4,
        'production_no': 'PROD-2026-0044',
        'output_item_id': 41,
        'output_quantity': 10,
        'warehouse_id': 3,
        'production_date': '2026-08-10',
        'created_by': 1,
        'created_at': '2026-08-10 09:00:00',
        'updated_at': '2026-08-10 09:00:00',
        'raw_materials_warehouse_id': 2,
        'overhead_cost': 100,
        'bom_id': 1,
        'batch_id': 9,
        'batch_no': 'BATCH-26-PRD-0044',
        'unit_cost': 110.5,
        'total_material_cost': 3000,
        'total_batch_cost': 3105,
        'output_item_code': 'FO1.5TON',
        'output_item_name': '1.5 Ton Split AC Carton Box',
        'output_uom': 'Nos',
        'finished_goods_warehouse_code': 'WH-003',
        'finished_goods_warehouse_name': 'UOP Store',
        'raw_materials_warehouse_code': 'WH-002',
        'raw_materials_warehouse_name': 'Karkhano Warehouse',
        'created_by_username': 'admin',
        'inputs': [
          {
            'id': 4,
            'production_id': 4,
            'item_id': 2,
            'quantity': 20,
            'warehouse_id': 2,
            'item_code': 'RM002',
            'item_name': 'Bolt',
            'unit_of_measure': 'box',
            'warehouse_code': 'WH-002',
            'warehouse_name': 'Karkhano Warehouse',
          },
        ],
      });
    }
    if (options.path == '/productions' && options.method == 'POST') {
      final body = options.data as Map<String, dynamic>;
      lastProductionPostBody = body;
      return _json({
        'id': 42,
        'production_no': 'PROD-2026-0045',
        'output_item_id': body['output_item_id'],
        'output_quantity': body['output_quantity'],
        'warehouse_id': body['warehouse_id'],
        'production_date': body['production_date'],
        'overhead_cost': body['overhead_cost'] ?? 0,
        'input_items': body['input_items'],
        'output_item_name': 'Widget A',
        'output_uom': 'pcs',
      }, status: 201);
    }
    if (RegExp(r'^/productions/\d+$').hasMatch(options.path) &&
        options.method == 'DELETE') {
      productionDeleteCount++;
      production4Deleted = true;
      return _json({'success': true, 'message': 'Production deleted'});
    }

    if (options.path == '/boms' && options.method == 'GET') {
      return _json([
        {
          'id': 1,
          'bom_no': 'BOM-2026-0001',
          'bom_name': 'Box BOM',
          'finished_item_id': 1,
          'finished_item_code': 'FG001',
          'finished_item_name': 'Widget A',
          'finished_uom': 'pcs',
          'quantity': 1,
          'description': 'Standard carton',
          'is_active': 1,
          'created_at': '2026-08-01 10:00:00',
          'updated_at': '2026-08-01 10:00:00',
          'item_count': 2,
          'total_material_cost': 27.5,
        },
      ]);
    }
    if (options.path == '/boms/1' && options.method == 'GET') {
      bomDetailFetchCount++;
      return _json({
        'id': 1,
        'bom_no': 'BOM-2026-0001',
        'bom_name': 'Box BOM',
        'finished_item_id': 1,
        'finished_item_code': 'FG001',
        'finished_item_name': 'Widget A',
        'finished_uom': 'pcs',
        'quantity': 1,
        'description': 'Standard carton',
        'is_active': 1,
        'created_at': '2026-08-01 10:00:00',
        'updated_at': '2026-08-01 10:00:00',
        'total_material_cost': 27.5,
        'items': [
          {
            'id': 2,
            'item_id': 2,
            'item_code': 'RM002',
            'item_name': 'Bolt',
            'unit_of_measure': 'box',
            'current_stock': 120,
            'quantity': 3,
            'standard_cost': 2.5,
            'line_cost': 7.5,
          },
          {
            'id': 3,
            'item_id': 4,
            'item_code': 'RM001',
            'item_name': 'Raw Material A',
            'unit_of_measure': 'kg',
            'current_stock': 30,
            'quantity': 2,
            'standard_cost': 10.0,
            'line_cost': 20.0,
          },
        ],
      });
    }
    if (options.path == '/boms' && options.method == 'POST') {
      final body = options.data as Map<String, dynamic>;
      lastBomPostBody = body;
      return _json({
        'id': 2,
        'bom_no': 'BOM-2026-0002',
        'bom_name': body['bom_name'],
        'finished_item_id': body['finished_item_id'],
        'quantity': body['quantity'],
        'is_active': 1,
        'items': body['items'],
      }, status: 201);
    }
    if (options.path == '/boms/1' && options.method == 'PUT') {
      lastBomPutBody = options.data as Map<String, dynamic>;
      return _json({
        'id': 1,
        'bom_no': 'BOM-2026-0001',
        'bom_name': 'Box BOM',
        'finished_item_id': 1,
        'quantity': 1,
        'is_active': 1,
      });
    }
    if (options.path == '/boms/1/toggle-active' && options.method == 'PATCH') {
      lastBomToggleBody = options.data as Map<String, dynamic>;
      return _json({'id': 1, 'bom_no': 'BOM-2026-0001', 'is_active': 0});
    }
    if (options.path == '/boms/1' && options.method == 'DELETE') {
      bomDeleteCount++;
      return _json({'message': 'BOM deleted successfully'});
    }
    if (options.path == '/activity-logs' && options.method == 'GET') {
      lastActivityLogsQuery = options.queryParameters;
      final search =
          (options.queryParameters['search'] as String?)?.toLowerCase() ?? '';
      final entity = options.queryParameters['entity_type'] as String?;
      final action = options.queryParameters['action'] as String?;
      var rows = <Map<String, dynamic>>[
        {
          'id': 1,
          'user_id': 1,
          'username': 'admin',
          'action': 'CREATE',
          'entity_type': 'Invoice',
          'entity_id': 12,
          'description': 'Created invoice INV-2608-0012',
          'log_level': 'INFO',
          'ip_address': '127.0.0.1',
          'user_agent': 'MiniERP/1.0',
          'metadata': null,
          'duration_ms': 12,
          'created_at': '2026-08-09 10:30:00',
        },
        {
          'id': 2,
          'user_id': null,
          'username': null,
          'action': 'ERROR',
          'entity_type': 'User',
          'entity_id': null,
          'description': 'Failed login attempt from unknown host',
          'log_level': 'ERROR',
          'ip_address': '10.0.0.5',
          'user_agent': null,
          'metadata': null,
          'duration_ms': null,
          'created_at': '2026-08-08 22:15:00',
        },
      ];
      if (search.isNotEmpty) {
        rows = [
          for (final row in rows)
            if ((row['description'] as String).toLowerCase().contains(search) ||
                (row['entity_type'] as String).toLowerCase().contains(search))
              row,
        ];
      }
      if (entity != null && entity.isNotEmpty) {
        rows = [
          for (final row in rows)
            if (row['entity_type'] == entity) row,
        ];
      }
      if (action != null && action.isNotEmpty) {
        rows = [
          for (final row in rows)
            if (row['action'] == action) row,
        ];
      }
      return _json({
        'success': true,
        'data': rows,
        'total': rows.length,
        'limit': options.queryParameters['limit'] ?? 50,
        'offset': options.queryParameters['offset'] ?? 0,
      });
    }
    if (options.path == '/activity-logs/stats') {
      return _json({
        'success': true,
        'data': {
          'totalLogs': 125,
          'actions': [
            {'action': 'LOGIN', 'count': 40},
            {'action': 'CREATE', 'count': 25},
          ],
          'users': [
            {'username': 'admin', 'count': 90},
          ],
          'dailyActivity': [
            {'date': '2026-08-09', 'count': 12},
          ],
        },
      });
    }
    if (options.path == '/activity-logs/entity-types') {
      return _json({
        'success': true,
        'data': ['Invoice', 'Customer'],
      });
    }
    if (options.path == '/activity-logs/actions') {
      return _json({
        'success': true,
        'data': ['LOGIN', 'CREATE', 'ERROR'],
      });
    }
    if (options.path == '/activity-logs/users') {
      return _json({
        'success': true,
        'data': [
          {'id': 1, 'username': 'admin', 'full_name': 'Fawad'},
        ],
      });
    }
    if (options.path == '/activity-logs/cleanup' && options.method == 'POST') {
      lastCleanupBody = options.data as Map<String, dynamic>;
      if (rejectCleanup) {
        return _json({'error': 'Cleanup not permitted'}, status: 400);
      }
      return _json({
        'success': true,
        'message': 'Cleaned up 3 old log entries',
        'deletedCount': 3,
      });
    }
    // ── Forecasts (PORTING.md §12) ────────────────────────────────
    if (options.path == '/forecasts/dashboard') {
      return _json({
        'success': true,
        'data': {
          'summary': {
            'totalItems': 8,
            'itemsNeedingRestock': 3,
            'avgConfidence': 74,
            'criticalAlerts': 2,
          },
          'alerts': [
            {
              'itemId': 1,
              'itemName': 'Widget A',
              'currentStock': 5,
              'predictedDemand': 60,
              'alertLevel': 'critical',
              'recommendation': 'order_now',
            },
            {
              'itemId': 2,
              'itemName': 'Bolt',
              'currentStock': 40,
              'predictedDemand': 20,
              'alertLevel': 'adequate',
              'recommendation': 'monitor',
            },
          ],
          'topGrowing': [
            {
              'itemId': 1,
              'itemCode': 'FG001',
              'itemName': 'Widget A',
              'category': 'Parts',
              'currentStock': 5,
              'predictedDemand': {
                'nextWeek': 12,
                'nextMonth': 60,
                'nextQuarter': 180,
              },
              'trend': 'growing',
              'trendPercentage': 42.0,
              'confidence': 82,
              'recommendation': 'order_now',
              'safetyStock': 20,
              'reorderPoint': 25,
              'isOverride': false,
            },
            {
              'itemId': 3,
              'itemCode': 'FG003',
              'itemName': 'Gadget',
              'category': 'Assemblies',
              'currentStock': 90,
              'predictedDemand': {'nextWeek': 5, 'nextMonth': 10, 'nextQuarter': 30},
              'trend': 'declining',
              'trendPercentage': 12.0,
              'confidence': 70,
              'recommendation': 'adequate',
              'safetyStock': 15,
              'reorderPoint': 20,
              'isOverride': false,
            },
          ],
          'topDeclining': [],
        },
      });
    }
    if (options.path == '/forecasts/demand') {
      lastForecastDemandQuery = options.queryParameters;
      if (failForecastDemand) {
        return _json({
          'success': false,
          'error': {'code': 'SERVER_ERROR', 'message': 'Failed to fetch forecasts'},
        }, status: 500);
      }
      const demandRows = [
        {
          'itemId': 1,
          'itemCode': 'FG001',
          'itemName': 'Widget A',
          'category': 'Parts',
          'currentStock': 5,
          'predictedDemand': {'nextWeek': 12, 'nextMonth': 60, 'nextQuarter': 180},
          'trend': 'growing',
          'trendPercentage': 42.0,
          'confidence': 82,
          'recommendation': 'order_now',
          'safetyStock': 20,
          'reorderPoint': 25,
          'isOverride': false,
        },
        {
          'itemId': 2,
          'itemCode': 'RM002',
          'itemName': 'Bolt',
          'category': 'Raw',
          'currentStock': 40,
          'predictedDemand': {'nextWeek': 4, 'nextMonth': 20, 'nextQuarter': 60},
          'trend': 'stable',
          'trendPercentage': 0,
          'confidence': 91,
          'recommendation': 'monitor',
          'safetyStock': 10,
          'reorderPoint': 15,
          'isOverride': false,
        },
      ];
      final category = lastForecastDemandQuery?['category'];
      final rows = category == 'Parts'
          ? [demandRows.first]
          : demandRows;
      return _json({'success': true, 'data': rows});
    }
    if (options.path == '/forecasts/trends') {
      lastTrendsItemId = (options.queryParameters['itemId'] as num?)?.toInt();
      return _json({
        'success': true,
        'data': {
          'historicalTrends': [
            {'month': '2026-01', 'actual': 120, 'movingAvg': 112.0, 'predicted': null},
            {'month': '2026-02', 'actual': 135, 'movingAvg': 122.0, 'predicted': null},
            {'month': '2026-03', 'actual': null, 'movingAvg': 128.0, 'predicted': 150},
            {'month': '2026-04', 'actual': null, 'movingAvg': null, 'predicted': 162},
          ],
          'itemBreakdown': [
            {'itemName': 'Widget A', 'totalSold': 420, 'trend': 'growing'},
            {'itemName': 'Bolt', 'totalSold': 130, 'trend': 'stable'},
            {'itemName': 'Gadget', 'totalSold': 60, 'trend': 'declining'},
          ],
        },
      });
    }
    if (options.path == '/forecasts/accuracy') {
      if (failForecastAccuracy) {
        return _json({
          'success': false,
          'error': {'code': 'SERVER_ERROR', 'message': 'Failed to fetch accuracy'},
        }, status: 500);
      }
      return _json({
        'success': true,
        'data': [
          {
            'itemId': 1,
            'itemName': 'Widget A',
            'itemCode': 'FG001',
            'mape': 8.0,
            'mae': 3.0,
            'smape': 8.0,
            'sampleSize': 12,
            'modelType': 'linear_regression',
            'trend': 'growing',
          },
          {
            'itemId': 2,
            'itemName': 'Bolt',
            'itemCode': 'RM002',
            'mape': 22.0,
            'mae': 6.0,
            'smape': 21.9,
            'sampleSize': 8,
            'modelType': 'moving_average',
            'trend': null,
          },
        ],
      });
    }
    if (options.path == '/forecasts/compute-accuracy' &&
        options.method == 'POST') {
      computeAccuracyCount++;
      if (rejectComputeAccuracy) {
        return _json({'error': 'Compute rejected'}, status: 400);
      }
      return _json({
        'success': true,
        'message': 'Accuracy computed for 14 records',
        'computed': 14,
        'errors': 0,
      });
    }
    if (RegExp(r'^/forecasts/accuracy/\d+$').hasMatch(options.path)) {
      final itemId = int.parse(options.path.split('/').last);
      final points = itemId == 1
          ? [
              {'forecastDate': '2026-04', 'period': 'next_month', 'predicted': 150, 'actual': 141, 'mape': 6.0, 'mae': 9.0},
              {'forecastDate': '2026-05', 'period': 'next_month', 'predicted': 162, 'actual': 158, 'mape': 2.5, 'mae': 4.0},
            ]
          : [
              {'forecastDate': '2026-04', 'period': 'next_month', 'predicted': 80, 'actual': 95, 'mape': 18.8, 'mae': 15.0},
            ];
      return _json({'success': true, 'data': points});
    }
    if (options.path == '/integrations/settings' && options.method == 'GET') {
      return _json(integrationsStore); // bare object, no envelope
    }
    final integrationService = RegExp(
      r'^/integrations/settings/(\w+)$',
    ).firstMatch(options.path);
    if (integrationService != null && options.method == 'PUT') {
      lastIntegrationPutBody = options.data as Map<String, dynamic>;
      lastIntegrationPutService = integrationService.group(1);
      if (rejectIntegrationSave) {
        return _json({'error': 'Invalid API key'}, status: 400);
      }
      // Adopt the posted `enabled` flag so the refetched status strip
      // reflects the save (configured stays put).
      final row = integrationsStore[integrationService.group(1)];
      if (row is Map<String, dynamic>) {
        row['enabled'] = lastIntegrationPutBody!['enabled'];
      }
      return _json({
        'success': true,
        'message': 'Integration settings updated',
      });
    }
    if (options.path == '/settings' && options.method == 'GET') {
      return _json(settingsStore); // bare object, no envelope
    }
    if (options.path == '/settings/bulk' && options.method == 'POST') {
      lastSettingsBulkBody = options.data as Map<String, dynamic>;
      if (rejectSettingsSave) {
        return _json({'error': 'Settings update rejected'}, status: 400);
      }
      for (final entry in lastSettingsBulkBody!.entries) {
        final row = settingsStore[entry.key];
        if (row is Map<String, dynamic>) row['value'] = entry.value;
      }
      return _json(settingsStore);
    }
    // ── Employees (PORTING.md §5) ───────────────────────────────
    if (options.path == '/employees' && options.method == 'GET') {
      if (failEmployees) {
        return _json({
          'success': false,
          'error': {'code': 'SERVER_ERROR', 'message': 'Failed to fetch employees'},
        }, status: 500);
      }
      lastEmployeesQuery = options.queryParameters;
      const namedEmployees = [
        {
          'id': 1,
          'employee_code': 'EMP-001',
          'first_name': 'Ali',
          'last_name': 'Khan',
          'email': 'ali@example.com',
          'phone': '555-0101',
          'department': 'Production',
          'designation': 'Operator',
          'employment_type': 'Full-time',
          'salary': 45000,
          'date_of_joining': '2025-01-10',
          'is_active': 1,
        },
        {
          'id': 2,
          'employee_code': 'EMP-002',
          'first_name': 'Sana',
          'last_name': 'Ahmed',
          'email': 'sana@example.com',
          'department': 'Sales',
          'designation': 'Sales Rep',
          'employment_type': 'Full-time',
          'salary': 35000,
          'is_active': 1,
        },
        {
          'id': 3,
          'employee_code': 'EMP-003',
          'first_name': 'Bilal',
          'last_name': 'Malik',
          'department': 'Production',
          'salary': 40000,
          'is_active': 0,
        },
      ];
      // The server filters on search/department/status and slices
      // page/limit (defaults: active list, page 1, limit 10).
      final q = options.queryParameters;
      final search = (q['search'] as String?) ?? '';
      final department = q['department'] as String?;
      final status = q['status'] as String?;
      final rows = namedEmployees
          .where(
            (e) =>
                search.isEmpty ||
                (e['first_name'] as String)
                        .toLowerCase()
                        .contains(search.toLowerCase()) ||
                (e['last_name'] as String)
                    .toLowerCase()
                    .contains(search.toLowerCase()),
          )
          .where((e) => department == null || e['department'] == department)
          .where((e) {
        if (status == 'inactive') return e['is_active'] == 0;
        if (status == 'active') return e['is_active'] == 1;
        return e['is_active'] == 1; // server default: active list
      }).toList();
      final limit = int.tryParse('${q['limit']}') ?? 10;
      final page = int.tryParse('${q['page']}') ?? 1;
      final totalPages = (rows.length / limit).ceil();
      final start = (page - 1) * limit;
      final end = start + limit > rows.length ? rows.length : start + limit;
      final data = start >= rows.length
          ? <Map<String, dynamic>>[]
          : rows.sublist(start, end);
      return _json({
        'success': true,
        'data': data,
        'pagination': {
          'page': page,
          'limit': limit,
          'total': rows.length,
          'totalPages': totalPages,
        },
      });
    }
    if (options.path == '/employees/next-code' && options.method == 'GET') {
      employeeNextCodeFetchCount++;
      return _json({'success': true, 'data': {'code': 'EMP-004'}});
    }
    if (options.path == '/employees' && options.method == 'POST') {
      final body = options.data as Map<String, dynamic>;
      lastEmployeePostBody = body;
      return _json({
        'success': true,
        'data': {
          'id': 99,
          'employee_code': 'EMP-099',
          'first_name': body['first_name'],
          'last_name': body['last_name'],
          'email': body['email'],
          'department': body['department'],
          'salary': body['salary'],
          'is_active': body['is_active'],
        },
      }, status: 201);
    }
    final employeeId = RegExp(r'^/employees/(\d+)$').firstMatch(options.path);
    if (employeeId != null) {
      final id = int.parse(employeeId.group(1)!);
      if (options.method == 'GET') {
        return _json({
          'success': true,
          'data': {
            'id': id,
            'employee_code': 'EMP-00$id',
            'first_name': 'Ali',
            'last_name': 'Khan',
            'email': 'ali@example.com',
            'phone': '555-0101',
            'department': 'Production',
            'designation': 'Operator',
            'employment_type': 'Full-time',
            'salary': 45000,
            'date_of_joining': '2025-01-10',
            'is_active': 1,
          },
        });
      }
      if (options.method == 'PUT') {
        lastEmployeePutBody = options.data as Map<String, dynamic>;
        return _json({
          'success': true,
          'data': {
            'id': id,
            'employee_code': 'EMP-00$id',
            'first_name': lastEmployeePutBody?['first_name'] ?? 'Ali',
            'last_name': lastEmployeePutBody?['last_name'] ?? 'Khan',
            'salary': lastEmployeePutBody?['salary'] ?? 45000,
            'is_active': lastEmployeePutBody?['is_active'] ?? true,
          },
        });
      }
      if (options.method == 'DELETE') {
        employeeDeleteCount++;
        return ResponseBody.fromString('', 204);
      }
    }
    final salaryPayId = RegExp(
      r'^/employees/(\d+)/salary/pay$',
    ).firstMatch(options.path);
    if (salaryPayId != null && options.method == 'POST') {
      final body = options.data as Map<String, dynamic>;
      lastSalaryPayBody = body;
      salaryPayCount++;
      if (rejectSalaryPay) {
        return _json({'error': 'Valid amount is required'}, status: 422);
      }
      return _json({
        'success': true,
        'data': {'id': 7, 'journal_entry_id': 12},
      }, status: 201);
    }
    final salaryHistoryId = RegExp(
      r'^/employees/(\d+)/salary/history$',
    ).firstMatch(options.path);
    if (salaryHistoryId != null && options.method == 'GET') {
      salaryHistoryFetchCount++;
      return _json({
        'success': true,
        'data': [
          {
            'id': 7,
            'employee_id': int.parse(salaryHistoryId.group(1)!),
            'amount': 45000,
            'payment_date': '2026-08-01',
            'payment_method': 'bank',
            'reference_no': 'REF-1',
          },
        ],
      });
    }
    final employeeDocsId = RegExp(
      r'^/employees/(\d+)/documents$',
    ).firstMatch(options.path);
    if (employeeDocsId != null && options.method == 'POST') {
      // Multipart upload — dio delivers the FormData as options.data.
      final form = options.data as FormData;
      lastDocumentPostForm = form;
      lastDocumentPostFields = {
        for (final entry in form.fields) entry.key: entry.value,
      };
      lastDocumentPostHasFile = form.files.isNotEmpty;
      lastDocumentPostFileName =
          form.files.isEmpty ? null : form.files.single.value.filename;
      if (rejectDocumentUpload) {
        return _json({
          'error': 'File type text/x-custom is not allowed',
        }, status: 500);
      }
      return _json({
        'success': true,
        'data': {'id': 11},
      }, status: 201);
    }
    if (employeeDocsId != null && options.method == 'GET') {
      return _json({
        'success': true,
        'data': [
          {
            'id': 9,
            'employee_id': int.parse(employeeDocsId.group(1)!),
            'document_name': 'CNIC Copy',
            'document_type': 'ID',
            'document_number': '42101-1234567-1',
          },
        ],
      });
    }
    // ── User management (PORTING.md §5) ─────────────────────────
    if (options.path == '/users' && options.method == 'GET') {
      lastUsersQuery = options.queryParameters;
      const allUsers = [
        {
          'id': 1,
          'username': 'admin',
          'email': 'admin@minierp.com',
          'full_name': 'Fawad',
          'role': 'admin',
          'role_id': 1,
          'is_active': 1,
        },
        {
          'id': 2,
          'username': 'sales1',
          'email': 'sales@minierp.com',
          'full_name': 'Sales User',
          'role': 'user',
          'role_id': 2,
          'is_active': 1,
        },
        {
          'id': 3,
          'username': 'bob',
          'email': 'bob@minierp.com',
          'full_name': 'Bob',
          'role': 'user',
          'role_id': 2,
          'is_active': 0,
        },
      ];
      final q = options.queryParameters;
      final search = (q['search'] as String?) ?? '';
      final role = q['role'] as String?;
      final active = q['is_active'];
      final rows = allUsers
          .where((u) {
        if (role == null) return true;
        return u['role'] == role;
      }).where((u) {
        if (active == null) return true;
        return u['is_active'] == (active == 1 || active == '1');
      }).where(
        (u) =>
            search.isEmpty ||
            (u['username'] as String)
                .toLowerCase()
                .contains(search.toLowerCase()) ||
            (u['full_name'] as String)
                .toLowerCase()
                .contains(search.toLowerCase()),
      ).toList();
      return _json({'success': true, 'data': rows});
    }
    if (options.path == '/users' && options.method == 'POST') {
      final body = options.data as Map<String, dynamic>;
      lastUserPostBody = body;
      if (rejectUserCreate) {
        return _json({'error': 'Username already exists'}, status: 409);
      }
      return _json({
        'success': true,
        'data': {
          'id': 99,
          'username': body['username'],
          'email': body['email'],
          'full_name': body['full_name'],
          'role': 'user',
          'role_id': body['role_id'],
          'is_active': body['is_active'] ?? true,
        },
      }, status: 201);
    }
    final userId = RegExp(r'^/users/(\d+)$').firstMatch(options.path);
    if (userId != null && options.method == 'PUT') {
      lastUserPutBody = options.data as Map<String, dynamic>;
      return _json({
        'success': true,
        'data': {
          'id': int.parse(userId.group(1)!),
          'username': 'admin',
          'email': 'admin@minierp.com',
          'full_name': lastUserPutBody?['full_name'] ?? 'Fawad',
          'role': 'admin',
          'role_id': lastUserPutBody?['role_id'] ?? 1,
          'is_active': lastUserPutBody?['is_active'] ?? true,
        },
      });
    }
    final toggleStatusId = RegExp(
      r'^/users/(\d+)/toggle-status$',
    ).firstMatch(options.path);
    if (toggleStatusId != null && options.method == 'PUT') {
      lastToggleBody = options.data as Map<String, dynamic>;
      userToggleCount++;
      return _json({'success': true, 'message': 'User status updated'});
    }
    final resetPasswordId = RegExp(
      r'^/users/(\d+)/reset-password$',
    ).firstMatch(options.path);
    if (resetPasswordId != null && options.method == 'PUT') {
      final body = options.data as Map<String, dynamic>;
      lastResetPasswordBody = body['newPassword'] as String?;
      return _json({'success': true, 'message': 'Password reset successfully'});
    }
    if (userId != null && options.method == 'DELETE') {
      userDeleteCount++;
      return _json({'success': true, 'message': 'User deleted successfully'});
    }
    if (options.path == '/roles' && options.method == 'GET') {
      return _json({
        'success': true,
        'data': [
          {
            'id': 1,
            'role_name': 'Admin',
            'description': 'Full system access',
            'is_system_role': 1,
            'is_active': 1,
            'permission_count': 30,
          },
          {
            'id': 2,
            'role_name': 'User',
            'description': 'Standard access',
            'is_system_role': 1,
            'is_active': 1,
            'permission_count': 12,
          },
          {
            'id': 3,
            'role_name': 'Manager',
            'description': 'Team management',
            'is_system_role': 0,
            'is_active': 1,
            'permission_count': 8,
          },
        ],
      });
    }
    final roleId = RegExp(r'^/roles/(\d+)$').firstMatch(options.path);
    if (roleId != null && options.method == 'DELETE') {
      roleDeleteCount++;
      return _json({'success': true, 'message': 'Role deleted successfully'});
    }
    final rolePermissionsId = RegExp(
      r'^/roles/(\d+)/permissions$',
    ).firstMatch(options.path);
    if (rolePermissionsId != null) {
      if (options.method == 'GET') {
        rolePermissionsFetchCount++;
        return _json({
          'success': true,
          'data': [
            {'id': 1, 'permission_name': 'View Users', 'module': 'users', 'action': 'read', 'assigned': 1},
            {'id': 2, 'permission_name': 'Create Users', 'module': 'users', 'action': 'create', 'assigned': 0},
            {'id': 3, 'permission_name': 'View Invoices', 'module': 'invoices', 'action': 'read', 'assigned': 1},
            {'id': 4, 'permission_name': 'Create Invoices', 'module': 'invoices', 'action': 'create', 'assigned': 0},
          ],
        });
      }
      if (options.method == 'PUT') {
        final body = options.data as Map<String, dynamic>;
        lastRolePermissionsIds =
            (body['permissions'] as List).cast<num>().map((n) => n.toInt()).toList();
        if (rejectRolePermissionsSave) {
          return _json({'error': 'Role not found'}, status: 404);
        }
        return _json({'success': true, 'message': 'Permissions updated successfully'});
      }
    }
    if (options.path == '/roles' && options.method == 'POST') {
      final body = options.data as Map<String, dynamic>;
      lastRolePostBody = body;
      return _json({
        'success': true,
        'data': {
          'id': 9,
          'role_name': body['role_name'],
          'description': body['description'],
          'is_system_role': 0,
          'is_active': 1,
          'permission_count': (body['permissions'] as List?)?.length ?? 0,
        },
      }, status: 201);
    }
    if (roleId != null && options.method == 'PUT') {
      lastRolePutBody = options.data as Map<String, dynamic>;
      return _json({
        'success': true,
        'data': {
          'id': int.parse(roleId.group(1)!),
          'role_name': 'Manager',
          'description': lastRolePutBody?['description'],
          'is_system_role': 0,
          'is_active': lastRolePutBody?['is_active'] ?? true,
          'permission_count': 8,
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

/// Stubs the `printing` plugin's method channel so the invoice print
/// preview can render and the print job can complete under `flutter
/// test` (PORTING.md §12 — no real platform backend exists there).
/// `printingInfo` reports rastering available; `rasterPdf` emits one
/// 1×1 page; `printPdf` completes the job as printed.
void _mockPrintingChannel() {
  const channel = MethodChannel('net.nfet.printing');
  final messenger = TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async {
    switch (call.method) {
      case 'printingInfo':
        return {'canRaster': true, 'canPrint': true};
      case 'rasterPdf':
        final job = (call.arguments as Map)['job'];
        await messenger.handlePlatformMessage(
          'net.nfet.printing',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('onPageRasterized', {
              'job': job,
              'width': 1,
              'height': 1,
              'image': Uint8List.fromList([255, 0, 0, 255]),
            }),
          ),
          (_) {},
        );
        await messenger.handlePlatformMessage(
          'net.nfet.printing',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('onPageRasterEnd', {'job': job, 'error': null}),
          ),
          (_) {},
        );
        return null;
      case 'printPdf':
        final job = (call.arguments as Map)['job'];
        await messenger.handlePlatformMessage(
          'net.nfet.printing',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('onCompleted', {'job': job, 'completed': true, 'error': null}),
          ),
          (_) {},
        );
        return 1;
      default:
        return null;
    }
  });
}

void main() {
  // The locale provider persists to SharedPreferences; tests use the
  // in-memory mock so the platform plugin isn't hit.
  SharedPreferences.setMockInitialValues({});

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
    // A wide surface so all KPI cards fit the horizontal strip.
    tester.view.physicalSize = const Size(2000, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
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

    // The two summary fields rendered on top of the base KPI strip:
    // the recentProductions KPI card (last in the strip) + the
    // stock-by-category donut legend.
    expect(find.text('Recent Productions'), findsOneWidget);
    expect(find.text('12'), findsOneWidget); // recentProductions value
    expect(find.text('Stock by Category'), findsOneWidget);
    expect(find.text('Parts'), findsOneWidget); // legend category
    expect(find.text('500 (100%)'), findsOneWidget); // total + share

    // The two block panels (GET /dashboard/ar-summary + top-customers)
    // render their data next to the summary-driven panels.
    expect(find.text('AR Summary'), findsOneWidget);
    expect(find.text('420,000.00'), findsOneWidget); // total AR
    expect(find.text('25 customers'), findsOneWidget);
    expect(find.text('Top Customers'), findsOneWidget);
    expect(find.text('Acme Corp'), findsOneWidget); // top customer row
    expect(find.text('12 invoices'), findsOneWidget); // invoice count meta
    expect(find.text('Current'), findsOneWidget); // first aging bucket
    expect(find.text('1-30 Days'), findsOneWidget); // second aging bucket
  });

  testWidgets('cash position card opens the balance breakdown dialog', (
    tester,
  ) async {
    // Wide surface so every KPI card and the cash strip are built.
    tester.view.physicalSize = const Size(2000, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
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

    // The Cash card shows the compact in/out breakdown from the fake
    // /dashboard/cash-position payload (12,000 in / 4,000 out).
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('12,000'), findsOneWidget);
    expect(find.text('4,000'), findsOneWidget);

    // Tapping the card opens the drill-down: the balance build-up
    // (opening + inflow − outflow) and every transaction behind it.
    await tester.tap(find.text('Cash'));
    await tester.pumpAndSettle();

    expect(find.text('Transactions'), findsOneWidget);
    expect(find.text('20,000.00'), findsOneWidget); // opening
    // +/− amounts appear twice each: the summary row and its matching
    // transaction row.
    expect(find.text('+12,000.00'), findsNWidgets(2)); // inflow
    expect(find.text('−4,000.00'), findsNWidgets(2)); // outflow
    expect(find.text('Payment received'), findsOneWidget);
    expect(find.textContaining('PAY002'), findsOneWidget);
    expect(find.text('Supplier payment'), findsOneWidget);
    expect(find.textContaining('PAY001'), findsOneWidget);
    // Returns show up as labelled refunds, so a payment reversal is
    // never mistaken for a payment out.
    expect(find.text('Refund'), findsOneWidget);
    expect(find.textContaining('PAY004'), findsOneWidget);
    expect(find.textContaining('Refund for return on INV-2026-152278'),
        findsOneWidget);
  });

  testWidgets('opening balance editor saves the starting cash', (
    tester,
  ) async {
    // Wide surface so every KPI card and the cash strip are built.
    tester.view.physicalSize = const Size(2000, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final adapter = _AuthFakeAdapter();
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

    // The cash strip header has an "Opening balance" editor button.
    await tester.tap(find.text('Opening balance'));
    await tester.pumpAndSettle();

    // The dialog lists every cash account with its current seed value
    // (Cash starts at 20,000 from the fake GET).
    expect(find.text('Opening balance'), findsWidgets); // title + button
    expect(find.widgetWithText(TextField, 'Cash'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Bank'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Easypaisa'), findsOneWidget);

    // Raise the starting cash to 25,000 and save.
    await tester.enterText(find.widgetWithText(TextField, 'Cash'), '25000');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // The PUT carried the edited seed balance, the dialog closed, and
    // the confirmation snackbar appeared.
    final body = adapter.lastOpeningBalancesPutBody;
    expect(body, isNotNull);
    final cashEntry = (body!['accounts'] as List).cast<Map<String, dynamic>>()
        .firstWhere((a) => a['key'] == 'cash');
    expect(cashEntry['amount'], 25000);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Opening balances saved'), findsOneWidget);
  });

  testWidgets('dashboard shows the global date range picker and hint', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
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

    // The toolbar's From/To pickers (the app-wide range) + the hint
    // that it applies to every report screen.
    expect(find.byType(DateFilterButton), findsNWidgets(2));
    expect(
      find.text('Date range applies to all report screens'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });

  testWidgets('dashboard date range propagates to every report page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final adapter = _AuthFakeAdapter();
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

    // Change the global From date on the dashboard (July 13 → July 20).
    await tester.tap(find.byType(DateFilterButton).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('20'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    final expectedFrom = isoDate(DateTime(now.year, now.month - 1, 20));

    // The dashboard's own summary refetched with the new range too — the
    // KPI figures and the sales/purchases chart respect the picker.
    expect(adapter.lastDashboardSummaryQuery?['fromDate'], expectedFrom);
    expect(adapter.lastDashboardSummaryQuery?['toDate'], isoDate(now));

    // And every report page picks the new range up.
    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sales Summary Report'));
    await tester.pumpAndSettle();
    expect(adapter.lastSalesSummaryQuery?['fromDate'], expectedFrom);
    expect(adapter.lastSalesSummaryQuery?['toDate'], isoDate(now));
  });

  testWidgets('dashboard refresh button reloads every block', (tester) async {
    tester.view.physicalSize = const Size(2000, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final adapter = _AuthFakeAdapter();
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
    expect(adapter.dashboardSummaryCalls, 1);

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    expect(adapter.dashboardSummaryCalls, greaterThanOrEqualTo(2));
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

  Future<void> bootToItems(
    WidgetTester tester, {
    String role = 'admin',
    _AuthFakeAdapter? adapter,
  }) async {
    final storage = _FakeTokenStorage()..token = 'test-token';
    final dio = Dio(BaseOptions(baseUrl: ApiClient.baseUrl));
    dio.httpClientAdapter = adapter ?? _AuthFakeAdapter(role: role);
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
    expect(find.text('Active'), findsNWidgets(4));
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
    // Scoped to the dialog — the inventory shell's tab bar also renders a
    // 'Stock by Warehouse' destination behind the dialog.
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Stock by Warehouse'),
      ),
      findsOneWidget,
    );
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

  testWidgets('stock ledger opens from the item detail with in/out rows', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToItems(tester);

    // Open the item detail (double-tap Widget A), then the stock ledger.
    await tester.tap(find.text('Widget A'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Widget A'));
    await tester.pumpAndSettle();
    expect(find.text('Item Details'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Stock Ledger'));
    await tester.pumpAndSettle();

    // Header shows the item label; rows come from the bare ledger array
    // (SALE -5 then PURCHASE +10, newest-first).
    expect(find.text('Stock Ledger'), findsWidgets);
    expect(find.text('FG001 · Widget A'), findsOneWidget);
    // Type labels from the movement-type l10n keys.
    expect(find.text('Sale'), findsOneWidget);
    expect(find.text('Purchase'), findsOneWidget);
    // References from the rows.
    expect(find.text('INV-2026-001'), findsOneWidget);
    expect(find.text('PUR-2026-001'), findsOneWidget);
    // Running balance walks oldest-first: PURCHASE +10 → 10; SALE -3 → 7.
    // Scoped to the top dialog — '3'/'7'/'10' also render in the grid and
    // the item detail dialog underneath. '10' appears twice (the In cell
    // and the balance cell of the purchase row).
    final ledgerDialog = find.byType(Dialog).last;
    expect(
      find.descendant(of: ledgerDialog, matching: find.text('10')),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: ledgerDialog, matching: find.text('3')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: ledgerDialog, matching: find.text('7')),
      findsOneWidget,
    );

    // Close returns to the item detail underneath (its own 'Stock Ledger'
    // button remains, so assert on ledger-only content instead).
    await tester.tap(find.widgetWithText(TextButton, 'Close').last);
    await tester.pumpAndSettle();
    expect(find.text('FG001 · Widget A'), findsNothing);
    expect(find.text('Item Details'), findsOneWidget);
  });

  testWidgets('stock ledger shows the empty state when no movements exist', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter()..emptyStockLedger = true;
    await bootToItems(tester, adapter: adapter);

    await tester.tap(find.text('Widget A'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Widget A'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Stock Ledger'));
    await tester.pumpAndSettle();

    expect(find.text('No stock movements found'), findsOneWidget);
  });

  testWidgets('stock ledger filters by warehouse via warehouse_id', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToItems(tester, adapter: adapter);

    await tester.tap(find.text('Widget A'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Widget A'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Stock Ledger'));
    await tester.pumpAndSettle();

    // Unfiltered: all three rows (TRANSFER +2, SALE -3, PURCHASE +10).
    final ledgerDialog = find.byType(Dialog).last;
    expect(adapter.lastLedgerQuery, isEmpty);
    expect(
      find.descendant(of: ledgerDialog, matching: find.text('Transfer')),
      findsOneWidget,
    );

    // Pick the Raw Materials warehouse (WH-RAW, id 2) from the filter
    // dropdown; only the TRANSFER row remains.
    await tester.tap(find.byType(SearchableSelect<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WH-RAW · Raw Materials').last);
    await tester.pumpAndSettle();

    expect(adapter.lastLedgerQuery, {'warehouse_id': 2});
    expect(
      find.descendant(
        of: find.byType(Dialog).last,
        matching: find.text('Transfer'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(Dialog).last,
        matching: find.text('Sale'),
      ),
      findsNothing,
    );
    // Running balance after the single filtered movement: +2 → 2.
    expect(
      find.descendant(of: find.byType(Dialog).last, matching: find.text('2')),
      findsNWidgets(2), // In cell + balance cell.
    );

    // Back to All Warehouses restores the full ledger.
    await tester.tap(find.byType(SearchableSelect<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All Warehouses').last);
    await tester.pumpAndSettle();
    expect(adapter.lastLedgerQuery, isEmpty);
    expect(
      find.descendant(
        of: find.byType(Dialog).last,
        matching: find.text('Sale'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('stock ledger exports the visible rows to CSV', (tester) async {
    useWideSurface(tester);
    await bootToItems(tester);

    // Open the item detail, then the stock ledger.
    await tester.tap(find.text('Widget A'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Widget A'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Stock Ledger'));
    await tester.pumpAndSettle();

    // Stub the file_picker save channel to return a real temp path; the
    // export helper then writes the CSV there.
    final target = '${Directory.systemTemp.path}/minierp-ledger-test.csv';
    final targetFile = File(target);
    if (targetFile.existsSync()) targetFile.deleteSync();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
          (call) async {
            if (call.method == 'save') return target;
            return null;
          },
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
            null,
          ),
    );

    // The save helper does real async file I/O (File.writeAsBytes) that
    // never completes under the test's fake-async zone — drive it inside
    // runAsync so the write finishes and the toast can appear.
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(TextButton, 'Export to CSV'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    // Success toast + the CSV file exists with the ledger rows.
    expect(find.text('Stock ledger exported'), findsOneWidget);
    final file = File(target);
    expect(file.existsSync(), isTrue);
    final content = file.readAsStringSync();
    expect(content, contains('Date'));
    expect(content, contains('Balance'));
    // All three fixture rows survive the export (newest-first).
    expect(content, contains('Transfer'));
    expect(content, contains('WH-RAW'));
    expect(content, contains('Sale'));
    expect(content, contains('INV-2026-001'));
    expect(content, contains('Purchase'));
    expect(content, contains('PUR-2026-001'));
    if (file.existsSync()) file.deleteSync();
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
    await tester.tap(find.byType(SearchableSelect<String>).at(1));
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

  testWidgets('Ctrl+N opens the new-record form from a list screen', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToItems(tester);

    // No toolbar tap — the shell's ScreenShortcutScope must resolve the
    // shortcut from arbitrary focus (post-boot focus sits in the scope's
    // own focus or the nav rail, both inside the scope). This is the
    // regression guard for the keypress-walk resolution: it must fire
    // without the search field being touched.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    // The item form dialog opened (the Save button only exists in the
    // dialog — the toolbar's own "New Item" button is always present).
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
  });

  testWidgets('Ctrl+F focuses the search field from a grid cell', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToItems(tester);

    // Give the grid keyboard focus — the exact state a user reaches by
    // clicking a cell (PlutoGrid's tap handler requests the grid's own
    // focus node), using the same helper the F2/Enter tests use.
    final sm = tester
        .state<PlutoGridState>(find.byType(PlutoGrid))
        .stateManager;
    sm.setCurrentCell(sm.firstCell, 0);
    sm.gridFocusNode.requestFocus();
    await tester.pump();

    // Sanity: focus is on the grid, not the toolbar search field.
    final searchField = tester.widget<TextField>(
      find.byType(TextField).first,
    );
    expect(FocusManager.instance.primaryFocus, isNot(searchField.focusNode));

    // Ctrl+F from a grid cell must focus the visible screen's search —
    // the regression guard for the keypress-walk resolution (the grid is
    // a sibling of the toolbar, not a descendant, so an ancestor lookup
    // from the focused cell would find nothing). PlutoGrid swallows every
    // focus-system key, so this also guards the HardwareKeyboard
    // interception that makes the shortcut fire from the grid at all.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(FocusManager.instance.primaryFocus, searchField.focusNode);
  });

  testWidgets('Ctrl+R refetches the items list from a grid cell', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToItems(tester, adapter: adapter);

    // Give the grid keyboard focus — the same state the Ctrl+F test uses
    // (PlutoGrid swallows every focus-system key, so the refresh must
    // travel the HardwareKeyboard path too).
    final sm = tester
        .state<PlutoGridState>(find.byType(PlutoGrid))
        .stateManager;
    sm.setCurrentCell(sm.firstCell, 0);
    sm.gridFocusNode.requestFocus();
    await tester.pump();

    final fetchesBefore = adapter.itemsFetchCount;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    // Ctrl+R invalidated the items provider → exactly one refetch, and
    // the grid still shows the reloaded rows.
    expect(adapter.itemsFetchCount, fetchesBefore + 1);
    expect(find.text('Widget A'), findsOneWidget);
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

  testWidgets('expenses grid exports the rows to CSV', (tester) async {
    useWideSurface(tester);
    await bootToExpenses(tester);

    // Stub the file_picker save channel to return a real temp path; the
    // shared save helper then writes the CSV there (same pattern as the
    // sales-orders and returns export tests).
    final target = '${Directory.systemTemp.path}/minierp-expenses-test.csv';
    final targetFile = File(target);
    if (targetFile.existsSync()) targetFile.deleteSync();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
          (call) async {
            if (call.method == 'save') return target;
            return null;
          },
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
            null,
          ),
    );

    // The save helper does real async file I/O (File.writeAsBytes) that
    // never completes under the test's fake-async zone — drive it inside
    // runAsync so the write finishes and the toast can appear.
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(TextButton, 'Export to CSV'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    // Success toast + the CSV file exists with the expense rows (header
    // columns, both fixture rows with their formatted amounts and the
    // localized status labels).
    expect(find.text('Expenses exported'), findsOneWidget);
    final file = File(target);
    expect(file.existsSync(), isTrue);
    final content = file.readAsStringSync();
    expect(content, contains('Expense No'));
    expect(content, contains('EXP-2605-0001'));
    expect(content, contains('Generator diesel'));
    expect(content, contains('Approved'));
    expect(content, contains('1,000.00'));
  });

  // Activity log (PORTING.md §5) — offset-paginated grid over
  // GET /activity-logs with the stats strip and filter dropdowns.
  Future<void> bootToActivityLog(
    WidgetTester tester, {
    _AuthFakeAdapter? adapter,
  }) async {
    final storage = _FakeTokenStorage()..token = 'test-token';
    final dio = Dio(BaseOptions(baseUrl: ApiClient.baseUrl));
    dio.httpClientAdapter = adapter ?? _AuthFakeAdapter();
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
    await tester.tap(find.text('Activity Log'));
    await tester.pumpAndSettle();
  }

  Future<void> bootToSettings(
    WidgetTester tester, {
    _AuthFakeAdapter? adapter,
  }) async {
    final storage = _FakeTokenStorage()..token = 'test-token';
    final dio = Dio(BaseOptions(baseUrl: ApiClient.baseUrl));
    dio.httpClientAdapter = adapter ?? _AuthFakeAdapter();
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
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
  }

  Future<void> bootToForecasts(
    WidgetTester tester, {
    _AuthFakeAdapter? adapter,
    int tab = 0,
  }) async {
    final storage = _FakeTokenStorage()..token = 'test-token';
    final dio = Dio(BaseOptions(baseUrl: ApiClient.baseUrl));
    dio.httpClientAdapter = adapter ?? _AuthFakeAdapter();
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
    await tester.tap(find.text('Forecasts'));
    await tester.pumpAndSettle();
    if (tab > 0) {
      final label = switch (tab) {
        1 => 'Demand Forecast',
        2 => 'Trends',
        _ => 'Accuracy',
      };
      // The forecast shell's NavigationBar tab — scoped so the
      // dashboard's headline (also "Demand Forecast", kept alive by the
      // shell's IndexedStack) doesn't collide with the finder.
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();
    }
  }

  Future<void> bootToIntegrations(
    WidgetTester tester, {
    _AuthFakeAdapter? adapter,
  }) async {
    final storage = _FakeTokenStorage()..token = 'test-token';
    final dio = Dio(BaseOptions(baseUrl: ApiClient.baseUrl));
    dio.httpClientAdapter = adapter ?? _AuthFakeAdapter();
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
    await tester.tap(find.text('Integrations'));
    await tester.pumpAndSettle();
  }

  Future<void> bootToEmployees(
    WidgetTester tester, {
    _AuthFakeAdapter? adapter,
  }) async {
    final storage = _FakeTokenStorage()..token = 'test-token';
    final dio = Dio(BaseOptions(baseUrl: ApiClient.baseUrl));
    dio.httpClientAdapter = adapter ?? _AuthFakeAdapter();
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
    await tester.tap(find.text('Employees'));
    await tester.pumpAndSettle();
  }

  Future<void> bootToAdmin(
    WidgetTester tester, {
    _AuthFakeAdapter? adapter,
    int tab = 0,
  }) async {
    final storage = _FakeTokenStorage()..token = 'test-token';
    final dio = Dio(BaseOptions(baseUrl: ApiClient.baseUrl));
    dio.httpClientAdapter = adapter ?? _AuthFakeAdapter();
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
    await tester.tap(find.text('Users'));
    await tester.pumpAndSettle();
    if (tab > 0) {
      final label = switch (tab) {
        1 => 'Roles',
        _ => 'Users',
      };
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();
    }
  }

  testWidgets('activity log screen renders the grid with server data', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToActivityLog(tester);

    // Rows + column headers from the fake /activity-logs payload.
    expect(find.text('Created invoice INV-2608-0012'), findsOneWidget);
    expect(find.text('Failed login attempt from unknown host'), findsOneWidget);
    expect(find.text('Invoice #12'), findsOneWidget);
    expect(find.text('Timestamp'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    // Log-level badges render for both rows (scoped to the badges: the
    // actions dropdown's unselected item widgets also hold these strings).
    expect(
      find.descendant(
        of: find.byType(StatusBadge),
        matching: find.text('INFO'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(StatusBadge),
        matching: find.text('ERROR'),
      ),
      findsOneWidget,
    );
    // Stats strip totals from the fake /activity-logs/stats payload.
    expect(find.text('Total logs'), findsOneWidget);
    expect(find.text('125'), findsOneWidget);
    // Offset envelope → pagination bar (2 rows at limit 50 = 1 page).
    expect(find.text('Page 1 of 1'), findsOneWidget);
    expect(find.text('· 2 logs'), findsOneWidget);
    // Keyboard hint status bar (shared GridStatusBar, like the other
    // read-only grid screens).
    expect(find.text('↑ ↓ ← →'), findsOneWidget);
    expect(find.text('Enter / F2'), findsOneWidget);
  });

  testWidgets('activity log search filters the grid server-side', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToActivityLog(tester);

    await tester.enterText(find.byType(TextField), 'failed');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Failed login attempt from unknown host'), findsOneWidget);
    expect(find.text('Created invoice INV-2608-0012'), findsNothing);
  });

  testWidgets('activity log F2 opens the detail dialog', (tester) async {
    useWideSurface(tester);
    await bootToActivityLog(tester);

    // Same current-cell + focus setup as the suppliers F2 test — fired
    // through the REAL key pipeline (FocusScope → keyManager →
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

    // Detail dialog renders the focused row's fields (scoped to the
    // dialog: the description and username also exist in the grid behind
    // the modal).
    Finder inDialog(String text) =>
        find.descendant(of: find.byType(Dialog), matching: find.text(text));
    expect(inDialog('Activity Detail'), findsOneWidget);
    expect(inDialog('Created invoice INV-2608-0012'), findsOneWidget);
    expect(inDialog('admin'), findsOneWidget);
    expect(inDialog('127.0.0.1'), findsOneWidget);

    // Close returns to the grid.
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    expect(find.text('Activity Detail'), findsNothing);
  });

  testWidgets(
    'activity log cleanup (admin) confirms retention days and posts',
    (tester) async {
      useWideSurface(tester);
      final adapter = _AuthFakeAdapter();
      await bootToActivityLog(tester, adapter: adapter);

      await tester.tap(find.text('Cleanup'));
      await tester.pumpAndSettle();
      expect(find.text('Clean up old logs'), findsOneWidget);

      // Default retention is 90 days — just confirm.
      await tester.tap(find.widgetWithText(FilledButton, 'Cleanup'));
      await tester.pumpAndSettle();

      expect(adapter.lastCleanupBody?['days'], 90);
      // Success toast carries the server's deleted count.
      expect(find.text('Cleaned up 3 log entries'), findsOneWidget);
    },
  );

  testWidgets('activity log hides the cleanup action for non-admin users', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToActivityLog(tester, adapter: _AuthFakeAdapter(role: 'user'));

    expect(find.text('Cleanup'), findsNothing);
    // The rest of the toolbar is still available.
    expect(find.text('Export CSV'), findsOneWidget);
  });

  testWidgets('activity log cleanup failure keeps the dialog open', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter()..rejectCleanup = true;
    await bootToActivityLog(tester, adapter: adapter);

    await tester.tap(find.text('Cleanup'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Cleanup'));
    await tester.pumpAndSettle();

    // Error toast with the server's message; the dialog stays open so the
    // user can adjust the retention period and retry.
    expect(find.text('Cleanup not permitted'), findsOneWidget);
    expect(find.text('Clean up old logs'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Clean up old logs'), findsNothing);
  });

  testWidgets('settings screen renders the grouped editor with server values', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToSettings(tester);

    // Section cards split the key store by domain.
    expect(find.text('Company'), findsOneWidget);
    expect(find.text('Currency & Formatting'), findsOneWidget);
    expect(find.text('Tax'), findsOneWidget);
    expect(find.text('Document Numbering'), findsOneWidget);
    // Integration keys are hidden (they belong to the Integrations module).
    expect(find.text('Enable SendGrid email service'), findsNothing);

    // Fields prefill from the fake /settings payload.
    expect(find.widgetWithText(TextFormField, 'Mini ERP'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'PKR'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '0'), findsOneWidget); // tax_rate
    expect(find.widgetWithText(TextFormField, '114'), findsOneWidget); // STK counter
  });

  testWidgets('settings screen posts bulk save for changed fields only', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToSettings(tester, adapter: adapter);

    // Edit the company name field.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Mini ERP'),
      'Acme Industries',
    );
    await tester.pumpAndSettle();

    // The Company card marks itself unsaved; Save posts only that change.
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Save').first);
    await tester.pumpAndSettle();

    expect(adapter.lastSettingsBulkBody, {'company_name': 'Acme Industries'});
    expect(find.text('Settings saved'), findsOneWidget);
    expect(find.text('Unsaved changes'), findsNothing);

    // The refetched/returned store now carries the new value.
    expect(adapter.settingsStore['company_name'], isA<Map<String, dynamic>>());
  });

  testWidgets('settings screen surfaces a failed bulk save', (tester) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter()..rejectSettingsSave = true;
    await bootToSettings(tester, adapter: adapter);

    // Save a field change against a rejecting server.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Mini ERP'),
      'Renamed',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save').first);
    await tester.pumpAndSettle();

    // Error toast with the server's message; the chip stays (still dirty).
    expect(find.text('Settings update rejected'), findsOneWidget);
    expect(find.text('Unsaved changes'), findsOneWidget);
  });

  testWidgets('activity log date-range filter sends start_date/end_date', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToActivityLog(tester, adapter: adapter);

    // From/To buttons from the shared DateRangeFilter render in the
    // toolbar.
    expect(find.text('From'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);

    // Set the range through the providers (the filter's own date-picker
    // interaction is covered by date_picker_helpers_test.dart).
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ActivityLogScreen)),
    );
    container.read(activityLogFromDateProvider.notifier).state = DateTime(
      2026,
      8,
      1,
    );
    await tester.pumpAndSettle();
    container.read(activityLogToDateProvider.notifier).state = DateTime(
      2026,
      8,
      9,
    );
    await tester.pumpAndSettle();

    expect(adapter.lastActivityLogsQuery?['start_date'], '2026-08-01');
    expect(adapter.lastActivityLogsQuery?['end_date'], '2026-08-09');

    // The clear button resets the range and refetches without dates.
    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();
    expect(adapter.lastActivityLogsQuery?['start_date'], isNull);
    expect(adapter.lastActivityLogsQuery?['end_date'], isNull);
  });

  // Reports module — hub + the first report screens (PORTING.md §11).
  Future<void> bootToReports(
    WidgetTester tester, {
    _AuthFakeAdapter? adapter,
  }) async {
    final storage = _FakeTokenStorage()..token = 'test-token';
    final dio = Dio(BaseOptions(baseUrl: ApiClient.baseUrl));
    dio.httpClientAdapter = adapter ?? _AuthFakeAdapter();
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
    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();
  }

  testWidgets('reports hub lists the report categories and cards', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToReports(tester);

    // Hub headline + the first (Sales) category — the hub ListView only
    // builds the cards that fit the window.
    expect(find.text('Reports Dashboard'), findsOneWidget);
    expect(find.text('Sales Reports'), findsOneWidget);
    expect(find.text('Sales Summary Report'), findsOneWidget);
    expect(find.text('Sales by Customer Report'), findsOneWidget);
    expect(find.text('Sales by Item Report'), findsOneWidget);
  });

  testWidgets('reports hub navigates to the AR aging grid', (tester) async {
    useWideSurface(tester);
    await bootToReports(tester);

    // Scroll the hub to the Accounts Receivable category and open it.
    await tester.dragUntilVisible(
      find.text('AR Aging'),
      find.byType(ReportsDashboardScreen),
      const Offset(0, -250),
    );
    await tester.tap(find.text('AR Aging'));
    await tester.pumpAndSettle();

    // Summary strip totals + per-customer buckets from the fake payload.
    // "1-30 Days" appears twice (strip label + grid column header) and
    // "70.50" twice (strip total + Acme's grid cell) now that the rows
    // render.
    expect(find.text('Acme Corp'), findsOneWidget);
    expect(find.text('Beta Ltd'), findsOneWidget);
    expect(find.text('1-30 Days'), findsNWidgets(2));
    expect(find.text('420.50'), findsOneWidget); // total receivables
    expect(find.text('70.50'), findsNWidgets(2)); // strip + Acme cell
  });

  testWidgets('sales summary report renders stats and detail rows', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToReports(tester);

    await tester.tap(find.text('Sales Summary Report'));
    await tester.pumpAndSettle();

    // Stat cards from the summary block. The grid's two rows render
    // serial `#1`/`#2`, so the total-invoices stat matches the serial
    // cell too.
    expect(find.text('2'), findsNWidgets(2)); // total invoices + #2
    expect(find.text('1,500.00'), findsOneWidget); // total sales
    expect(find.text('110'), findsOneWidget); // items sold
    expect(find.text('750.00'), findsOneWidget); // avg invoice value
    // Detail grid rows.
    expect(find.text('INV-2026-001'), findsOneWidget);
    expect(find.text('INV-2026-002'), findsOneWidget);
    expect(find.text('Partially Paid'), findsOneWidget);
    expect(find.text('Unpaid'), findsOneWidget);
  });

  testWidgets('low stock report renders rows and opens the detail dialog', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToReports(tester);

    await tester.tap(find.text('Low Stock Alert Report'));
    await tester.pumpAndSettle();

    // Summary strip (2 items, shortage 5 + 50) + rows from the payload.
    expect(find.text('2 low stock items'), findsOneWidget);
    expect(find.text('Shortage total: 55'), findsOneWidget);
    expect(find.text('Widget A'), findsOneWidget);
    expect(find.text('Bolt'), findsOneWidget);

    // Double-tap the Widget A row (within the double-tap window) → the
    // detail dialog with the full field set (incl. stock status + price).
    await tester.tap(find.text('Widget A'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Widget A'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('10 pcs'), findsOneWidget); // minimum stock value
    expect(find.text('8 pcs'), findsOneWidget); // reorder level
    expect(find.text('45.00'), findsOneWidget); // selling price
    expect(find.text('Low Stock'), findsOneWidget); // stock status row
  });

  testWidgets('stock level report renders the summary strip and rows', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToReports(tester);

    await tester.tap(find.text('Stock Level Report'));
    await tester.pumpAndSettle();

    // Summary strip: 2 items / 1 in stock / 1 out of stock. The grid's
    // two rows render serial `#1`/`#2`, so those stats match the serial
    // cells too (the "1" appears as #1 + both counts).
    expect(find.text('2'), findsNWidgets(2)); // total items + #2
    expect(find.text('1'), findsNWidgets(3)); // #1 + in stock + out

    // Grid rows from the payload.
    expect(find.text('Widget A'), findsOneWidget);
    expect(find.text('Bolt'), findsOneWidget);

    // Double-tap the Widget A row → the detail dialog.
    await tester.tap(find.text('Widget A'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Widget A'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('25 pcs'), findsOneWidget); // current stock
    // "In Stock" ×3 — summary-strip label + grid badge + dialog row.
    expect(find.text('In Stock'), findsNWidgets(3));
  });

  testWidgets('stock valuation report renders value rows and summary', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToReports(tester);

    await tester.tap(find.text('Stock Valuation Report'));
    await tester.pumpAndSettle();

    // Summary strip: total value 830.00 + item counts.
    expect(find.text('830.00'), findsOneWidget);
    expect(find.text('Widget A'), findsOneWidget);
    expect(find.text('750.00'), findsOneWidget); // Widget A total value
    expect(find.text('Bolt'), findsOneWidget);

    // Double-tap the Widget A row → the detail dialog with unit cost.
    await tester.tap(find.text('Widget A'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Widget A'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    // "30.00" ×2 and "batch" ×2 — grid cell + dialog row each.
    expect(find.text('30.00'), findsNWidgets(2)); // unit cost
    expect(find.text('batch'), findsNWidgets(2)); // valuation method
  });

  testWidgets('sales by customer report renders rows over the date range', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToReports(tester);

    await tester.tap(find.text('Sales by Customer Report'));
    await tester.pumpAndSettle();

    expect(find.text('Acme Corp'), findsOneWidget);
    expect(find.text('2,400.00'), findsOneWidget); // total sales
    expect(find.text('Beta Ltd'), findsOneWidget);

    // Double-tap the Acme Corp row → the detail dialog.
    await tester.tap(find.text('Acme Corp'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Acme Corp'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    // "billing@acme.test" ×2 and "800.00" ×2 — grid cell + dialog row
    // each.
    expect(find.text('billing@acme.test'), findsNWidgets(2)); // email
    expect(find.text('800.00'), findsNWidgets(2)); // avg order value
  });

  testWidgets('stock level grid exports the rows to CSV', (tester) async {
    useWideSurface(tester);
    await bootToReports(tester);

    await tester.tap(find.text('Stock Level Report'));
    await tester.pumpAndSettle();

    final target = '${Directory.systemTemp.path}/minierp-stock-level-test.csv';
    final targetFile = File(target);
    if (targetFile.existsSync()) targetFile.deleteSync();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
          (call) async {
            if (call.method == 'save') return target;
            return null;
          },
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
            null,
          ),
    );

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(TextButton, 'Export to CSV'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(find.text('Report exported'), findsOneWidget);
    final file = File(target);
    expect(file.existsSync(), isTrue);
    final content = file.readAsStringSync();
    expect(content, contains('Item Name'));
    expect(content, contains('Widget A'));
    expect(content, contains('Bolt'));
    expect(content, contains('In Stock')); // localized status
    expect(content, contains('Out of Stock'));
    expect(content, contains('45.00')); // selling price
  });

  testWidgets('stock valuation grid exports the rows to CSV', (tester) async {
    useWideSurface(tester);
    await bootToReports(tester);

    await tester.tap(find.text('Stock Valuation Report'));
    await tester.pumpAndSettle();

    final target =
        '${Directory.systemTemp.path}/minierp-stock-valuation-test.csv';
    final targetFile = File(target);
    if (targetFile.existsSync()) targetFile.deleteSync();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
          (call) async {
            if (call.method == 'save') return target;
            return null;
          },
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
            null,
          ),
    );

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(TextButton, 'Export to CSV'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(find.text('Report exported'), findsOneWidget);
    final file = File(target);
    expect(file.existsSync(), isTrue);
    final content = file.readAsStringSync();
    expect(content, contains('Total Value'));
    expect(content, contains('Widget A'));
    expect(content, contains('750.00')); // Widget A total value
    expect(content, contains('batch')); // valuation method
  });

  testWidgets('sales by customer grid exports the rows to CSV', (tester) async {
    useWideSurface(tester);
    await bootToReports(tester);

    await tester.tap(find.text('Sales by Customer Report'));
    await tester.pumpAndSettle();

    final target =
        '${Directory.systemTemp.path}/minierp-sales-by-customer-test.csv';
    final targetFile = File(target);
    if (targetFile.existsSync()) targetFile.deleteSync();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
          (call) async {
            if (call.method == 'save') return target;
            return null;
          },
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
            null,
          ),
    );

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(TextButton, 'Export to CSV'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(find.text('Report exported'), findsOneWidget);
    final file = File(target);
    expect(file.existsSync(), isTrue);
    final content = file.readAsStringSync();
    expect(content, contains('Avg. Order Value'));
    expect(content, contains('Acme Corp'));
    expect(content, contains('billing@acme.test'));
    expect(content, contains('2,400.00')); // total sales
    expect(content, contains('800.00')); // avg order value
  });

  testWidgets('sales by item report renders rows over the date range', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToReports(tester, adapter: adapter);

    await tester.tap(find.text('Sales by Item Report'));
    await tester.pumpAndSettle();

    expect(find.text('Widget A'), findsOneWidget);
    expect(find.text('Gadget'), findsOneWidget);
    expect(find.text('24,000.00'), findsOneWidget); // total sales
    expect(find.text('200.00'), findsOneWidget); // avg selling price
    expect(find.text('120'), findsOneWidget); // quantity sold
    // The endpoint requires both dates — the port always sends them.
    expect(adapter.lastSalesByItemQuery?['fromDate'], isNotNull);
    expect(adapter.lastSalesByItemQuery?['toDate'], isNotNull);

    // Double-tap the Widget A row → the detail dialog.
    await tester.tap(find.text('Widget A'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Widget A'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Quantity Sold'), findsOneWidget); // dialog row
    expect(find.text('FG001'), findsNWidgets(2)); // code: grid + dialog
  });

  testWidgets('sales by item report surfaces a failed fetch', (tester) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter()..failSalesByItem = true;
    await bootToReports(tester, adapter: adapter);

    await tester.tap(find.text('Sales by Item Report'));
    await tester.pumpAndSettle();

    expect(find.text('Failed to fetch sales by item'), findsOneWidget);
  });

  testWidgets('supplier analysis report renders the delivery-rate cells', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToReports(tester, adapter: adapter);

    await tester.tap(find.text('Supplier Analysis Report'));
    await tester.pumpAndSettle();

    expect(find.text('Al-Fatah Traders'), findsOneWidget);
    expect(find.text('Karachi Steel'), findsOneWidget);
    expect(find.text('180,000.00'), findsOneWidget); // total purchase value
    expect(find.text('100%'), findsNWidgets(2)); // both rows at 100
    expect(adapter.lastSupplierAnalysisQuery?['fromDate'], isNotNull);
    expect(adapter.lastSupplierAnalysisQuery?['toDate'], isNotNull);

    // Double-tap the Al-Fatah row → the detail dialog.
    await tester.tap(find.text('Al-Fatah Traders'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Al-Fatah Traders'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    // "18" (total items) appears only in the dialog — the grid has no
    // total-items column.
    expect(find.text('18'), findsOneWidget);
    expect(find.text('4'), findsNWidgets(2)); // orders: grid cell + dialog
  });

  testWidgets('production summary report renders strip and rows', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToReports(tester, adapter: adapter);

    await tester.tap(find.text('Production Summary Report'));
    await tester.pumpAndSettle();

    expect(find.text('Total Production Orders'), findsOneWidget);
    // "Completed Quantity" appears twice — summary-strip label + grid
    // column header.
    expect(find.text('Completed Quantity'), findsNWidgets(2));
    expect(find.text('WO-001'), findsOneWidget);
    expect(find.text('WO-002'), findsOneWidget);
    expect(find.text('Completed'), findsNWidgets(2)); // status column
    expect(adapter.lastProductionSummaryQuery?['fromDate'], isNotNull);
    expect(adapter.lastProductionSummaryQuery?['toDate'], isNotNull);

    // Double-tap the WO-001 row → the detail dialog.
    await tester.tap(find.text('WO-001'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('WO-001'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Planned Quantity'), findsOneWidget); // dialog row
    // Dialog title + grid cell both show WO-001.
    expect(find.text('WO-001'), findsNWidgets(2));
  });

  testWidgets('bom usage report renders rows with the item picker', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToReports(tester, adapter: adapter);

    await tester.tap(find.text('BOM Usage'));
    await tester.pumpAndSettle();

    expect(find.text('Widget A BOM'), findsOneWidget);
    expect(find.text('Gadget BOM'), findsOneWidget);
    expect(find.text('3'), findsOneWidget); // usage count
    expect(find.text('4'), findsOneWidget); // total components
    expect(find.text('All Items'), findsOneWidget); // picker hint
    expect(adapter.lastBomUsageQuery?['fromDate'], isNotNull);
    expect(adapter.lastBomUsageQuery?['toDate'], isNotNull);

    // Double-tap the Widget A BOM row → the detail dialog.
    await tester.tap(find.text('Widget A BOM'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Widget A BOM'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    // Usage count '3' and components '4' now appear in grid + dialog.
    expect(find.text('3'), findsNWidgets(2));
    expect(find.text('4'), findsNWidgets(2));
    expect(find.text('Active'), findsNWidgets(3)); // 2 grid rows + dialog
  });

  testWidgets('DSO report renders the metric cards and exports', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToReports(tester);

    await tester.tap(find.text('Days Sales Outstanding (DSO) Report'));
    await tester.pumpAndSettle();

    // Headline DSO card + the three metric cards.
    expect(find.text('18.65 days'), findsOneWidget);
    expect(find.text('Total AR'), findsOneWidget);
    expect(find.text('50,000.00'), findsOneWidget); // total AR value

    final target = '${Directory.systemTemp.path}/minierp-dso-test.csv';
    final targetFile = File(target);
    if (targetFile.existsSync()) targetFile.deleteSync();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
          (call) async {
            if (call.method == 'save') return target;
            return null;
          },
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
            null,
          ),
    );

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(TextButton, 'Export to CSV'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(find.text('Report exported'), findsOneWidget);
    final file = File(target);
    expect(file.existsSync(), isTrue);
    final content = file.readAsStringSync();
    expect(content, contains('Days Sales Outstanding'));
    expect(content, contains('101,895.00')); // total sales
    expect(content, contains('50,000.00')); // total AR
  });

  testWidgets('cash flow report renders the metrics and analysis', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToReports(tester);

    await tester.tap(find.text('Cash Flow Report'));
    await tester.pumpAndSettle();

    expect(find.text('Total Cash Inflow'), findsOneWidget);
    expect(find.text('52,895.00'), findsOneWidget); // inflow value
    expect(find.text('1,000.00'), findsOneWidget); // outflow value
    expect(find.text('51,895.00'), findsOneWidget); // net cash flow
    // Positive-flow analysis note.
    expect(find.textContaining('positive cash flow'), findsOneWidget);
  });

  testWidgets('profit & loss report renders metrics and expense breakdown', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToReports(tester);

    await tester.tap(find.text('Profit & Loss Report'));
    await tester.pumpAndSettle();

    expect(find.text('Total Revenue'), findsOneWidget);
    expect(find.text('101,895.00'), findsOneWidget); // revenue value
    expect(find.text('Cost of Goods Sold (COGS)'), findsOneWidget);
    expect(find.text('Net Profit'), findsOneWidget);
    expect(find.text('-171,420.50'), findsOneWidget); // net profit
    // Margins combo card renders both percentages.
    expect(find.textContaining('-166.27%'), findsOneWidget);
    expect(find.textContaining('-168.23%'), findsOneWidget);
    // Expenses-by-category breakdown from the payload — 2,000.00
    // appears twice (Total Expenses card + Marketing breakdown row).
    expect(find.text('Expenses by Category'), findsOneWidget);
    expect(find.text('Marketing'), findsOneWidget);
    expect(find.text('2,000.00'), findsNWidgets(2)); // expenses card + row
  });

  testWidgets('inventory movement report renders grid and summary', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToReports(tester);

    await tester.tap(find.text('Inventory Movement Report'));
    await tester.pumpAndSettle();

    // Summary strip.
    expect(find.text('Total Inbound'), findsOneWidget);
    expect(find.text('Total Outbound'), findsOneWidget);
    expect(find.text('Net Movement'), findsOneWidget);
    // Row data from the fake payload.
    expect(find.text('Cardboard Box (Small)'), findsOneWidget);
    expect(find.text('Main Warehouse'), findsOneWidget);
    expect(find.text('Sale'), findsOneWidget); // localized movement type
  });

  testWidgets('purchase summary report renders grid and summary', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToReports(tester);

    await tester.tap(find.text('Purchase Summary Report'));
    await tester.pumpAndSettle();

    // Summary strip — 'Total Cost' also appears as a grid column header.
    expect(find.text('Total Orders'), findsOneWidget);
    expect(find.text('Total Cost'), findsWidgets);
    // Row data from the fake payload.
    expect(find.text('PO-2026-0004'), findsOneWidget);
    expect(find.text('Haier Distributors'), findsOneWidget);
    expect(find.text('Completed'), findsWidgets);
  });

  testWidgets('expenses report renders grid, KPI strip and breakdown', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToReports(tester);

    await tester.tap(find.text('Expenses Report'));
    await tester.pumpAndSettle();

    // KPI strip from the fake summary (server values verbatim).
    expect(find.text('Total Expenses'), findsWidgets);
    expect(find.text('Total Records'), findsOneWidget);
    expect(find.text('27,500.00'), findsWidgets);
    expect(find.text('Average Expense'), findsOneWidget);
    expect(find.text('13,750.00'), findsOneWidget);
    // Category breakdown label + chips.
    expect(find.text('Expenses by Category'), findsOneWidget);
    expect(find.textContaining('Utilities'), findsWidgets);
    // Grid rows from the fake payload.
    expect(find.text('EXP-2026-0003'), findsOneWidget);
    expect(find.text('EXP-2026-0004'), findsOneWidget);
    expect(find.text('LESCO'), findsOneWidget);
    // Category dropdown rendered with the shared "All Categories" label.
    expect(find.text('All Categories'), findsOneWidget);
  });
  testWidgets('top debtors report renders debtor rows', (tester) async {
    useWideSurface(tester);
    await bootToReports(tester);

    await tester.tap(find.text('Top Debtors Report'));
    await tester.pumpAndSettle();

    expect(find.text('Awees Super Store'), findsOneWidget);
    expect(find.text('Gulhaji Plaza'), findsOneWidget);
    expect(find.text('CUST-006'), findsOneWidget);
    expect(find.text('Total Outstanding'), findsWidgets); // column + header
  });

  testWidgets('AR aging grid exports the rows to CSV', (tester) async {
    useWideSurface(tester);
    await bootToReports(tester);

    await tester.tap(find.text('AR Aging'));
    await tester.pumpAndSettle();

    // Stub the file_picker save channel to return a real temp path; the
    // shared save helper then writes the CSV there (same pattern as the
    // expenses export test).
    final target = '${Directory.systemTemp.path}/minierp-ar-aging-test.csv';
    final targetFile = File(target);
    if (targetFile.existsSync()) targetFile.deleteSync();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
          (call) async {
            if (call.method == 'save') return target;
            return null;
          },
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
            null,
          ),
    );

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(TextButton, 'Export to CSV'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(find.text('Report exported'), findsOneWidget);
    final file = File(target);
    expect(file.existsSync(), isTrue);
    final content = file.readAsStringSync();
    expect(content, contains('Total Outstanding'));
    expect(content, contains('Acme Corp'));
    expect(content, contains('Beta Ltd'));
    // Per-bucket row values (the summary strip total 420.50 is not part
    // of the grid export).
    expect(content, contains('120.50')); // Acme total outstanding
    expect(content, contains('200.00')); // Beta 90+ bucket
  });

  testWidgets('expenses report exports the rows to CSV', (tester) async {
    useWideSurface(tester);
    await bootToReports(tester);

    await tester.tap(find.text('Expenses Report'));
    await tester.pumpAndSettle();

    // Stub the file_picker save channel to return a real temp path; the
    // shared save helper then writes the CSV there.
    final target =
        '${Directory.systemTemp.path}/minierp-expenses-report-test.csv';
    final targetFile = File(target);
    if (targetFile.existsSync()) targetFile.deleteSync();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
          (call) async {
            if (call.method == 'save') return target;
            return null;
          },
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
            null,
          ),
    );

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(TextButton, 'Export to CSV'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(find.text('Report exported'), findsOneWidget);
    final file = File(target);
    expect(file.existsSync(), isTrue);
    final content = file.readAsStringSync();
    expect(content, contains('EXP-2026-0003'));
    expect(content, contains('EXP-2026-0004'));
    expect(content, contains('Utilities'));
    expect(content, contains('25,000.00'));
    expect(content, contains('Approved')); // localized status label
  });
  testWidgets('low stock grid exports the rows to CSV', (tester) async {
    useWideSurface(tester);
    await bootToReports(tester);

    await tester.tap(find.text('Low Stock Alert Report'));
    await tester.pumpAndSettle();

    final target = '${Directory.systemTemp.path}/minierp-low-stock-test.csv';
    final targetFile = File(target);
    if (targetFile.existsSync()) targetFile.deleteSync();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
          (call) async {
            if (call.method == 'save') return target;
            return null;
          },
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
            null,
          ),
    );

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(TextButton, 'Export to CSV'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(find.text('Report exported'), findsOneWidget);
    final file = File(target);
    expect(file.existsSync(), isTrue);
    final content = file.readAsStringSync();
    expect(content, contains('Minimum Stock'));
    expect(content, contains('Widget A'));
    expect(content, contains('Bolt'));
    expect(content, contains('Shortage'));
  });

  testWidgets('sales summary grid exports the rows to CSV', (tester) async {
    useWideSurface(tester);
    await bootToReports(tester);

    await tester.tap(find.text('Sales Summary Report'));
    await tester.pumpAndSettle();

    final target =
        '${Directory.systemTemp.path}/minierp-sales-summary-test.csv';
    final targetFile = File(target);
    if (targetFile.existsSync()) targetFile.deleteSync();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
          (call) async {
            if (call.method == 'save') return target;
            return null;
          },
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
            null,
          ),
    );

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(TextButton, 'Export to CSV'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(find.text('Report exported'), findsOneWidget);
    final file = File(target);
    expect(file.existsSync(), isTrue);
    final content = file.readAsStringSync();
    expect(content, contains('Invoice No'));
    expect(content, contains('INV-2026-001'));
    expect(content, contains('INV-2026-002'));
    expect(content, contains('Partially Paid'));
    expect(content, contains('Unpaid'));
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
    await tester.tap(find.byType(SearchableSelect<String>).at(0));
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

  /// Settles the invoice print preview page with bounded pumps. The
  /// page's PdfPreview raster never completes under `flutter test`
  /// (dart:ui image decoding is unavailable), so its loading spinner
  /// animates while the preview is the top route — pumpAndSettle would
  /// time out on it. Use this after navigating to/back from the preview;
  /// pumpAndSettle is fine once an opaque route covers it (overlay
  /// tickers are muted) or after it is popped.
  Future<void> pumpPreviewPage(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
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

  testWidgets('sales grid exports the rows to CSV', (tester) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToSales(tester, adapter);

    // Stub the file_picker save channel to return a real temp path; the
    // shared save helper then writes the CSV there (same pattern as the
    // orders and returns export tests).
    final target = '${Directory.systemTemp.path}/minierp-invoices-test.csv';
    final targetFile = File(target);
    if (targetFile.existsSync()) targetFile.deleteSync();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
          (call) async {
            if (call.method == 'save') return target;
            return null;
          },
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
            null,
          ),
    );

    // Real async file I/O — drive it inside runAsync so the write
    // finishes and the toast can appear.
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(TextButton, 'Export to CSV'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    // Success toast + the CSV file exists with the invoices rows
    // (header columns, all three fixture rows with their formatted
    // totals and the localized status labels).
    expect(find.text('Invoices exported'), findsOneWidget);
    final file = File(target);
    expect(file.existsSync(), isTrue);
    final content = file.readAsStringSync();
    expect(content, contains('Invoice No'));
    expect(content, contains('INV-2026-440955'));
    expect(content, contains('Acme Corp'));
    expect(content, contains('Unpaid'));
    expect(content, contains('1,500.00'));
    expect(content, contains('INV-2026-440956'));
    expect(content, contains('800.00'));
    expect(content, contains('INV-2026-440957'));
    expect(content, contains('Overdue'));
    expect(content, contains('300.00'));
    if (file.existsSync()) file.deleteSync();
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

    await tester.tap(find.byType(SearchableSelect<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paid').last);
    await tester.pumpAndSettle();

    expect(adapter.lastInvoicesQuery?['status'], 'Paid');
    expect(find.text('INV-2026-440956'), findsOneWidget);
    expect(find.text('INV-2026-440955'), findsNothing);
    expect(find.text('INV-2026-440957'), findsNothing);
  });

  testWidgets('invoice form: create page opens and validates', (tester) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToSales(tester, adapter);

    // New Invoice pushes the routed form page (the sales refactor
    // replaced the modal dialog with a full page at /sales/form).
    await tester.tap(find.widgetWithText(FilledButton, 'New Invoice'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('New Invoice'),
      ),
      findsOneWidget,
    );
    expect(find.byType(PlutoGrid), findsOneWidget);

    // The customer popup auto-opens on load (spec §2.1) — dismiss it so
    // the Save button below is not covered by the popup barrier.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // Saving without a customer: the customer rule fires first.
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Customer is required'), findsOneWidget);
    expect(adapter.lastInvoicePostBody, isNull);

    // Pick a customer; without a line item the submit still blocks.
    // (Scroll-safe: the Save tap above scrolled the page down, and the
    // always-visible payment panel makes the form tall.)
    await tester.ensureVisible(find.byType(SearchableSelect<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SearchableSelect<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acme Corp').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('At least one item is required'), findsOneWidget);
    expect(adapter.lastInvoicePostBody, isNull);
  });

  testWidgets('invoice form: edit prefills items and PUTs updates', (
    tester,
  ) async {
    _mockPrintingChannel();
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToSales(tester, adapter);

    // Double-tap the row opens the A4 print preview (not the edit
    // form); Edit on the preview page pushes the routed edit form with
    // the invoice, and the form prefills from the bare detail fetch.
    await tester.tap(find.text('INV-2026-440955'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('INV-2026-440955'));
    await pumpPreviewPage(tester);
    expect(find.byType(PdfPreview), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Edit Invoice'),
      ),
      findsOneWidget,
    );

    // The line prefills from the bare detail: item label + qty cell in
    // the line-items grid (the description cell shows the item name).
    expect(
      find.descendant(
        of: find.byType(PlutoGrid),
        matching: find.text('Widget A'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(PlutoGrid), matching: find.text('10')),
      findsOneWidget,
    );

    // Save posts the prefilled body unchanged (qty 10 × rate 100).
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    // The form pops back to the preview (its spinner animates), so the
    // pop is settled with bounded pumps too.
    await pumpPreviewPage(tester);

    // Form popped, PUT body matches the updateInvoice DTO shape.
    expect(find.text('Edit Invoice'), findsNothing);
    final body = adapter.lastInvoicePutBody!;
    expect(body.containsKey('invoice_no'), isFalse); // edit keeps the no.
    expect(body['customer_id'], 1);
    expect(body['status'], 'Unpaid');
    expect(body['discount_scope'], 'invoice');
    expect(body['discount_type'], 'flat');
    expect(body['discount_value'], 0);
    expect(body['total_amount'], 1000);
    final items = body['items'] as List;
    expect(items.single['item_id'], 1);
    expect(items.single['quantity'], 10);
    expect(items.single['unit_price'], 100);
  });

  testWidgets('sales screen: double-tap opens the invoice print preview', (
    tester,
  ) async {
    _mockPrintingChannel();
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToSales(tester, adapter);

    // Double-tap the row → A4 print preview page (not the edit form),
    // with a rendered PdfPreview and explicit Print + Cancel actions.
    await tester.tap(find.text('INV-2026-440955'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('INV-2026-440955'));
    await pumpPreviewPage(tester);

    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.textContaining('INV-2026-440955'),
      ),
      findsOneWidget,
    );
    expect(find.byType(PdfPreview), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Print A4'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Edit'), findsOneWidget);

    // Cancel: the back arrow pops back to the sales grid (the preview
    // is disposed, so the grid below settles normally).
    await tester.tap(find.byType(BackButton));
    await pumpPreviewPage(tester);
    expect(find.byType(PdfPreview), findsNothing);
    expect(find.text('INV-2026-440955'), findsWidgets);
  });

  // Invoice returns (PORTING.md §5/§6) — bare-array endpoint (no search
  // or page params), read-only grid tab of the sales shell; the
  // process-return dialog lives on the invoice edit form's bottom bar.
  Future<void> bootToInvoiceReturns(
    WidgetTester tester,
    _AuthFakeAdapter adapter,
  ) async {
    await bootToSales(tester, adapter);
    // Switch the sales shell to the returns tab (invoices is default).
    await tester.tap(find.text('Invoice Returns'));
    await tester.pumpAndSettle();
  }

  testWidgets('invoice returns screen renders the returns grid', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToSales(tester, adapter);

    // Offstage returns tab is skipped by the default finders.
    expect(find.text('SM-2026-0031'), findsNothing);
    await tester.tap(find.text('Invoice Returns'));
    await tester.pumpAndSettle();

    // Rows from the bare-array fake: return no, item, qty magnitudes and
    // the currency-formatted values.
    expect(find.text('SM-2026-0031'), findsOneWidget);
    expect(find.text('SM-2026-0034'), findsOneWidget);
    expect(find.text('Widget A'), findsOneWidget);
    expect(find.text('Widget B'), findsOneWidget);
    expect(find.text('4'), findsOneWidget); // qty, row 1
    // Row 2's serial `#` is also rendered as '2', so the qty assert
    // matches the serial cell too.
    expect(find.text('2'), findsNWidgets(2)); // qty, row 2 + serial #2
    expect(find.text('100.00'), findsOneWidget); // unit cost, row 1
    expect(find.text('400.00'), findsOneWidget); // 4 × 100 return value
    expect(find.text('45.00'), findsOneWidget); // unit cost, row 2
    expect(find.text('90.00'), findsOneWidget); // 2 × 45 return value
    // Grid column headers.
    expect(find.text('Return No'), findsOneWidget);
    expect(find.text('Return Date'), findsOneWidget);
    expect(find.text('Return Qty'), findsOneWidget);
  });

  testWidgets('invoice returns screen shows the keyboard hint status bar', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToInvoiceReturns(tester, adapter);

    // The same AG-Grid-style status bar the other grids render (the
    // offstage grids' bars are skipped by the default finders).
    expect(find.text('↑ ↓ ← →'), findsOneWidget);
    expect(find.text('Enter / F2'), findsOneWidget);
    expect(find.text('Navigate'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('invoice returns screen F2 opens the return detail dialog', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToInvoiceReturns(tester, adapter);

    // Same current-cell + focus setup as the other grids' F2 tests —
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

    // The read-only detail dialog renders from the in-memory row (no
    // per-row fetch): header, RETURN badge, info rows + value tile.
    final dialog = find.byType(Dialog);
    expect(find.text('Invoice Return'), findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.text('SM-2026-0031')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('Return')),
      findsOneWidget, // type badge
    );
    expect(
      find.descendant(of: dialog, matching: find.text('Acme Corp')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('Widget A')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('400.00')),
      findsOneWidget,
    );

    // Close returns to the grid.
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    expect(find.text('Invoice Return'), findsNothing);
  });

  testWidgets('invoice returns grid exports the rows to CSV', (tester) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToInvoiceReturns(tester, adapter);

    // Stub the file_picker save channel to return a real temp path; the
    // shared save helper then writes the CSV there (same pattern as the
    // stock ledger export test).
    final target = '${Directory.systemTemp.path}/minierp-returns-test.csv';
    final targetFile = File(target);
    if (targetFile.existsSync()) targetFile.deleteSync();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
          (call) async {
            if (call.method == 'save') return target;
            return null;
          },
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
            null,
          ),
    );

    // The save helper does real async file I/O (File.writeAsBytes) that
    // never completes under the test's fake-async zone — drive it inside
    // runAsync so the write finishes and the toast can appear.
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(TextButton, 'Export to CSV'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    // Success toast + the CSV file exists with the returns rows (header
    // columns, both fixture rows with their formatted values).
    expect(find.text('Invoice returns exported'), findsOneWidget);
    final file = File(target);
    expect(file.existsSync(), isTrue);
    final content = file.readAsStringSync();
    expect(content, contains('Return No'));
    expect(content, contains('SM-2026-0031'));
    expect(content, contains('Widget A'));
    expect(content, contains('Acme Corp'));
    expect(content, contains('400.00')); // 4 × 100 return value
    expect(content, contains('SM-2026-0034'));
    expect(content, contains('90.00')); // 2 × 45 return value
    if (file.existsSync()) file.deleteSync();
  });

  testWidgets('invoice form: process return posts qty + reason and refetches', (
    tester,
  ) async {
    _mockPrintingChannel();
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToSales(tester, adapter);

    // Double-tap opens the A4 print preview (whose raster never settles
    // under flutter test) — bounded pumps, then Edit pushes the routed
    // form whose bottom bar has the Process Return action.
    await tester.tap(find.text('INV-2026-440955'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('INV-2026-440955'));
    await pumpPreviewPage(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Invoice'), findsOneWidget);

    await tester.ensureVisible(find.text('Process Return'));
    await tester.tap(find.text('Process Return'));
    await tester.pumpAndSettle();

    // The dialog fetches fresh detail (qty 10, returned 0 → 10 available)
    // and defaults the disposition to credit (balance still owed).
    expect(find.text('Invoice Return'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('Widget A')),
      findsOneWidget,
    );

    final dialogFields = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(dialogFields.first, '4');
    await tester.enterText(dialogFields.at(1), 'Damaged');
    await tester.tap(find.widgetWithText(FilledButton, 'Return'));
    await tester.pumpAndSettle();

    final body = adapter.lastInvoiceReturnBody!;
    final items = body['items'] as List;
    expect((items.single as Map)['invoice_item_id'], 10);
    expect((items.single as Map)['return_quantity'], 4);
    expect(body['reason'], 'Damaged');
    expect(body['disposition'], 'credit');
    // Toast with the net return from the enveloped data payload; the
    // dialog popped itself.
    expect(
      find.textContaining('Return processed successfully'),
      findsOneWidget,
    );
    expect(find.text('Invoice Return'), findsNothing);
  });

  testWidgets('invoice form: process return validates qty against available', (
    tester,
  ) async {
    _mockPrintingChannel();
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToSales(tester, adapter);

    await tester.tap(find.text('INV-2026-440955'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('INV-2026-440955'));
    await pumpPreviewPage(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Process Return'));
    await tester.tap(find.text('Process Return'));
    await tester.pumpAndSettle();

    // 500 exceeds the 10 available — the validator blocks the POST.
    final dialogFields = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(dialogFields.first, '500');
    await tester.tap(find.widgetWithText(FilledButton, 'Return'));
    await tester.pumpAndSettle();

    expect(
      find.text('Return quantity exceeds the available quantity'),
      findsOneWidget,
    );
    expect(adapter.lastInvoiceReturnBody, isNull);
  });

  testWidgets('invoice form: process return surfaces a server rejection', (
    tester,
  ) async {
    _mockPrintingChannel();
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter()..rejectInvoiceReturn = true;
    await bootToSales(tester, adapter);

    await tester.tap(find.text('INV-2026-440955'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('INV-2026-440955'));
    await pumpPreviewPage(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Process Return'));
    await tester.tap(find.text('Process Return'));
    await tester.pumpAndSettle();

    final dialogFields = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(dialogFields.first, '4');
    await tester.tap(find.widgetWithText(FilledButton, 'Return'));
    await tester.pumpAndSettle();

    // The enveloped 400 error surfaces in the dialog's error banner and
    // the dialog stays open.
    expect(find.text('Cannot return a cancelled invoice'), findsOneWidget);
    expect(find.text('Invoice Return'), findsOneWidget);
  });

  // Payments module (PORTING.md §5/§6) — the second server-paginated
  // endpoint after customers: `GET /payments` returns one page plus a
  // `pagination` block. The Record Payment dialog is the invoice-payment
  // flow (`POST /payments` with `invoice_allocations` — there is no
  // `POST /invoices/:id/pay`; the server validates each allocation
  // against the invoice's balance and the total against the amount).
  Future<void> bootToPayments(
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
    // Tap the rail item by its unique icon (the Payments label also
    // names the dashboard KPI card).
    await tester.tap(find.byIcon(Icons.account_balance_wallet_outlined));
    await tester.pumpAndSettle();
  }

  testWidgets('payments screen renders the paged grid with server data', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToPayments(tester, adapter);

    // Default server-pagination query (page 1, limit 10) + the server's
    // default payment_date DESC ordering.
    expect(adapter.lastPaymentsQuery?['page'], 1);
    expect(adapter.lastPaymentsQuery?['limit'], 10);
    expect(adapter.lastPaymentsQuery?['sortOrder'], 'DESC');

    // Rows + column headers from the fake /payments payload.
    expect(find.text('PAY-2026-0001'), findsOneWidget);
    expect(find.text('PAY-2026-0002'), findsOneWidget);
    expect(find.text('Acme Corp'), findsOneWidget);
    expect(find.text('Beta Ltd'), findsOneWidget);
    expect(find.text('500.00'), findsOneWidget); // amount, row 1
    expect(find.text('800.00'), findsOneWidget); // amount, row 2
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('Bank Transfer'), findsOneWidget);
    expect(find.text('Payment No'), findsOneWidget); // column header
    // Server pagination block → bar (2 payments at limit 10 = 1 page).
    expect(find.text('Page 1 of 1'), findsOneWidget);
    expect(find.text('· 2 Payments'), findsOneWidget);
  });

  testWidgets('payments screen F2 opens the payment detail dialog', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToPayments(tester, adapter);

    // Same current-cell + focus setup as the other grids' F2 tests.
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

    // Detail dialog renders the enveloped GET /payments/1 payload.
    final dialog = find.byType(Dialog);
    expect(find.text('Payment Details'), findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.text('PAY-2026-0001')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('Acme Corp')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('500.00')),
      findsOneWidget, // amount tile
    );

    // Close returns to the grid.
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    expect(find.text('Payment Details'), findsNothing);
  });

  testWidgets('record payment allocates to open invoices and posts', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToPayments(tester, adapter);

    await tester.tap(find.widgetWithText(FilledButton, 'Record Payment'));
    await tester.pumpAndSettle();

    // Pick Acme Corp from the customer picker (dropdown over all
    // customers — CUST001 — Acme Corp).
    await tester.tap(find.byType(SearchableSelect<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CUST001 — Acme Corp').last);
    await tester.pumpAndSettle();

    // Open invoices load from /invoices (balance > 0 filtered client-
    // side): INV-2026-440955 (1,500.00) + INV-2026-440957 (200.00).
    expect(find.text('INV-2026-440955'), findsOneWidget);
    expect(find.text('INV-2026-440957'), findsOneWidget);
    expect(find.textContaining('1,500.00'), findsOneWidget); // balance

    // Allocate 1000 to the first line, 200 to the second — the amount
    // fields are the first two TextFormFields in the dialog.
    final fields = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(fields.at(0), '1000');
    await tester.enterText(fields.at(1), '200');
    await tester.pump();
    expect(find.text('Total Allocated: 1,200.00'), findsOneWidget);

    // The submit button sits at the bottom of the dialog's scrollable
    // body — bring it into view before tapping.
    final submitBtn = find.descendant(
      of: find.byType(Dialog),
      matching: find.widgetWithText(FilledButton, 'Record Payment'),
    );
    await tester.ensureVisible(submitBtn);
    await tester.tap(submitBtn);
    await tester.pumpAndSettle();

    // POST /payments body — amount == sum of allocations, each line
    // carrying the invoice_id + amount.
    final body = adapter.lastPaymentPostBody!;
    expect(body['customer_id'], 1);
    expect(body['amount'], 1200);
    expect(body['payment_method'], 'Cash');
    expect((body['payment_date'] as String).length, 10); // yyyy-MM-dd
    final allocs = body['invoice_allocations'] as List;
    expect((allocs[0] as Map)['invoice_id'], 1);
    expect((allocs[0] as Map)['amount'], 1000);
    expect((allocs[1] as Map)['invoice_id'], 3);
    expect((allocs[1] as Map)['amount'], 200);
    // Toast with the recorded total; the dialog popped itself.
    expect(
      find.textContaining('Payment recorded successfully'),
      findsOneWidget,
    );
    expect(find.text('Select Customer'), findsNothing);
  });

  testWidgets('record payment caps an allocation at the invoice balance', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToPayments(tester, adapter);

    await tester.tap(find.widgetWithText(FilledButton, 'Record Payment'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SearchableSelect<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CUST001 — Acme Corp').last);
    await tester.pumpAndSettle();

    // 2000 exceeds the 1,500.00 balance of the first invoice — the
    // validator blocks the POST.
    final fields = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(fields.at(0), '2000');
    await tester.pump(); // rebuild enables the submit button
    final submitBtn = find.descendant(
      of: find.byType(Dialog),
      matching: find.widgetWithText(FilledButton, 'Record Payment'),
    );
    await tester.ensureVisible(submitBtn);
    await tester.tap(submitBtn);
    await tester.pumpAndSettle();

    expect(
      find.text('Payment exceeds the remaining balance of 1,500.00'),
      findsOneWidget,
    );
    expect(adapter.lastPaymentPostBody, isNull);
  });

  testWidgets('payment detail deletes the payment with confirm', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToPayments(tester, adapter);

    // Double-tap the row opens the detail dialog.
    await tester.tap(find.text('PAY-2026-0001'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('PAY-2026-0001'));
    await tester.pumpAndSettle();
    expect(find.text('Payment Details'), findsOneWidget);

    // Detail Delete → confirm (the confirm FilledButton is the only one
    // labelled Delete).
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(adapter.paymentDeleteCount, 1);
    expect(find.text('Payment deleted successfully!'), findsOneWidget);
    expect(find.text('Payment Details'), findsNothing);
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

  // Sales Orders — the `/sales` branch's second tab (the shell hosts the
  // invoices grid as tab 0 and the SO grid as tab 1; the web app routes
  // /sales-orders inside the sales module).
  Future<void> bootToSalesOrders(
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
    await tester.tap(find.byIcon(Icons.point_of_sale_outlined));
    await tester.pumpAndSettle();
    // Switch the sales shell to the Sales Orders tab (invoices is the
    // default). "Sales Orders" also names the rail tooltip/dashboard
    // card — scope the tap to the shell's NavigationBar.
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Sales Orders'),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> bootToProduction(
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
    // The Production rail icon is unique to the production destination.
    await tester.tap(find.byIcon(Icons.factory_outlined));
    await tester.pumpAndSettle();
  }

  testWidgets('sales orders screen renders the PlutoGrid with server data', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToSalesOrders(tester, adapter);

    // Rows + column headers from the fake /sales-orders payload.
    expect(find.text('SO-2026-001'), findsOneWidget);
    expect(find.text('SO-2026-002'), findsOneWidget);
    expect(find.text('SO-2026-003'), findsOneWidget);
    expect(find.text('Acme Corp'), findsOneWidget);
    expect(find.text('Beta Ltd'), findsOneWidget);
    expect(find.text('SO #'), findsOneWidget);
    // Status badges map to the salesorders* localized labels.
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Invoiced'), findsOneWidget);
    // Totals via the shared currency formatter.
    expect(find.text('1,500.00'), findsOneWidget);
    expect(find.text('2,500.00'), findsOneWidget);
    expect(find.text('800.00'), findsOneWidget);
  });

  testWidgets('sales orders grid exports the rows to CSV', (tester) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToSalesOrders(tester, adapter);

    // Stub the file_picker save channel to return a real temp path; the
    // shared save helper then writes the CSV there (same pattern as the
    // returns and stock ledger export tests).
    final target = '${Directory.systemTemp.path}/minierp-salesorders-test.csv';
    final targetFile = File(target);
    if (targetFile.existsSync()) targetFile.deleteSync();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
          (call) async {
            if (call.method == 'save') return target;
            return null;
          },
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
            null,
          ),
    );

    // The save helper does real async file I/O (File.writeAsBytes) that
    // never completes under the test's fake-async zone — drive it inside
    // runAsync so the write finishes and the toast can appear.
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(TextButton, 'Export to CSV'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    // Success toast + the CSV file exists with the orders rows (header
    // columns, both fixture rows with their formatted totals and the
    // localized status labels).
    expect(find.text('Sales orders exported'), findsOneWidget);
    final file = File(target);
    expect(file.existsSync(), isTrue);
    final content = file.readAsStringSync();
    expect(content, contains('SO #'));
    expect(content, contains('SO-2026-001'));
    expect(content, contains('Acme Corp'));
    expect(content, contains('Confirmed')); // so1Status default
    expect(content, contains('1,500.00'));
    expect(content, contains('SO-2026-002'));
    expect(content, contains('2,500.00'));
    expect(content, contains('SO-2026-003'));
    expect(content, contains('800.00'));
    if (file.existsSync()) file.deleteSync();
  });

  testWidgets('sales orders screen F2 opens the SO detail dialog', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToSalesOrders(tester, adapter);

    // Same current-cell + focus setup as the items/PO F2 tests — fired
    // through the REAL key pipeline (FocusScope → keyManager →
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

    // Detail dialog renders the fetched SO (header label + an item row
    // from the fake /sales-orders/1 payload).
    expect(find.text('Sales Order Details'), findsOneWidget);
    expect(find.text('Widget A'), findsOneWidget);
    expect(find.text('FG001'), findsOneWidget);
    expect(find.text('1,500.00'), findsWidgets); // total tile + amounts

    // Close returns to the grid.
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    expect(find.text('Sales Order Details'), findsNothing);
  });

  testWidgets('sales orders screen New SO button opens the create form', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToSalesOrders(tester, adapter);

    await tester.tap(find.widgetWithText(FilledButton, 'New Sales Order'));
    await tester.pumpAndSettle();
    expect(find.text('New Sales Order'), findsWidgets); // title

    // Validation: saving empty shows the server DTO-message equivalents.
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Select a customer'), findsOneWidget);
    expect(adapter.lastSalesOrderPostBody, isNull);

    // Pick a customer (first int dropdown; the line's item select comes
    // after). Menu label is '<code> — <name>' like the PO form.
    await tester.tap(find.byType(SearchableSelect<int>).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('CUST001').last);
    await tester.pumpAndSettle();

    // Fill the first line: item select (int dropdown #2 — #0 is the
    // customer, #1 the warehouse, #2 the line's item), quantity, unit
    // price.
    await tester.tap(find.byType(SearchableSelect<int>).at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('FG001').last);
    await tester.pumpAndSettle();
    // Notes is the first TextFormField; the line's quantity and unit
    // price are the next two.
    await tester.enterText(find.byType(TextFormField).at(1), '10');
    await tester.enterText(find.byType(TextFormField).at(2), '100');

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // Dialog closed; POST body matches the createSalesOrder DTO shape.
    expect(find.widgetWithText(Dialog, 'New Sales Order'), findsNothing);
    expect(adapter.lastSalesOrderPostBody?['customer_id'], 1);
    expect(adapter.lastSalesOrderPostBody?['so_date'], isNotEmpty);
    expect(adapter.lastSalesOrderPostBody?['status'], 'Draft');
    final items = adapter.lastSalesOrderPostBody?['items'] as List;
    expect(items, hasLength(1));
    expect((items.first as Map)['item_id'], 1);
    expect((items.first as Map)['quantity'], 10);
    expect((items.first as Map)['unit_price'], 100);
  });

  testWidgets('sales orders form: edit prefills and PUTs the full body', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToSalesOrders(tester, adapter);

    // Double-tap the row opens the detail dialog.
    await tester.tap(find.text('SO-2026-001'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('SO-2026-001'));
    await tester.pumpAndSettle();
    expect(find.text('Sales Order Details'), findsOneWidget);

    // Draft SO #1 (so1Status starts 'Confirmed' → flip to Draft so the
    // Edit button shows; simpler: reuse the detail's Edit button which
    // renders for Draft only, so drive via the second row? No — set
    // status first via the stateful fake).
    adapter.so1Status = 'Draft';
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();

    // Re-open after flipping to Draft: Edit appears.
    await tester.tap(find.text('SO-2026-001'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('SO-2026-001'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Sales Order'), findsOneWidget);

    // Change the first line's quantity; PUT carries the full replacement
    // items array (server-side delete + reinsert). The notes field is
    // TextFormField #0; the first line's qty/price are #1/#2.
    await tester.enterText(find.byType(TextFormField).at(1), '20');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Sales Order'), findsNothing);
    expect(adapter.lastSalesOrderPutBody?['customer_id'], 1);
    expect(adapter.lastSalesOrderPutBody?['so_date'], '2026-01-20');
    final items = adapter.lastSalesOrderPutBody?['items'] as List;
    expect(items, hasLength(2)); // prefilled from the detail fetch
    expect((items.first as Map)['item_id'], 1);
    expect((items.first as Map)['quantity'], 20);
    expect((items.first as Map)['unit_price'], 100);
  });

  testWidgets('sales order form: Print A4 shows only in edit mode', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToSalesOrders(tester, adapter);

    // Create mode: nothing saved yet, so no Print A4 action.
    await tester.tap(find.widgetWithText(FilledButton, 'New Sales Order'));
    await tester.pumpAndSettle();
    expect(find.text('New Sales Order'), findsWidgets); // title
    expect(find.text('Print A4'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    // Edit mode (Draft → Edit visible): the Print A4 action appears.
    adapter.so1Status = 'Draft';
    await tester.tap(find.text('SO-2026-001'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('SO-2026-001'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Sales Order'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(Dialog).last,
        matching: find.widgetWithText(TextButton, 'Print A4'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('sales order detail: Print A4 is available for any status', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToSalesOrders(tester, adapter);

    // Open the detail dialog (SO-2026-001 defaults to Confirmed).
    await tester.tap(find.text('SO-2026-001'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('SO-2026-001'));
    await tester.pumpAndSettle();
    expect(find.text('Sales Order Details'), findsOneWidget);
    // Print A4 sits in the footer regardless of status.
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Print A4'),
      ),
      findsOneWidget,
    );

    // Draft keeps the action next to Edit + Delete.
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    adapter.so1Status = 'Draft';
    await tester.tap(find.text('SO-2026-001'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('SO-2026-001'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Print A4'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Edit'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('sales orders detail: Cancel confirms and flips the badge', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToSalesOrders(tester, adapter);

    // Open the detail of Confirmed SO #1.
    await tester.tap(find.text('SO-2026-001'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('SO-2026-001'));
    await tester.pumpAndSettle();
    expect(find.text('Sales Order Details'), findsOneWidget);
    expect(adapter.salesOrderCancelCount, 0);

    // Cancel (visible for non-Cancelled orders) → confirm dialog.
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cancel this sales order'), findsOneWidget);
    // The confirm dialog's actions: confirm is a FilledButton labelled
    // Cancel, dismiss is a TextButton labelled Close.
    await tester.tap(
      find.descendant(
        of: find.byType(Dialog).last,
        matching: find.widgetWithText(FilledButton, 'Cancel'),
      ),
    );
    await tester.pumpAndSettle();

    // The cancel POST fired; both the detail and list providers were
    // invalidated and refetched with the Cancelled status (the detail
    // badge and the grid row behind it both flip; the detail's Cancel
    // button disappears).
    expect(adapter.salesOrderCancelCount, 1);
    expect(find.text('Cancelled'), findsWidgets);
    // The detail dialog's Cancel button is gone (status is now Cancelled).
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.widgetWithText(TextButton, 'Cancel'),
      ),
      findsNothing,
    );
  });

  // Quotations — the `/sales` branch's third tab (the shell hosts the
  // invoices grid as tab 0, sales orders as tab 1, quotations as tab 2;
  // the web app routes /quotations inside the sales module).
  Future<void> bootToQuotations(
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
    await tester.tap(find.byIcon(Icons.point_of_sale_outlined));
    await tester.pumpAndSettle();
    // "Quotations" may also name a dashboard card — scope the tap to the
    // shell's NavigationBar.
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Quotations'),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('quotations screen renders the PlutoGrid with server data', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToQuotations(tester, adapter);

    // Rows + column headers from the fake /quotations payload.
    expect(find.text('QT-2026-001'), findsOneWidget);
    expect(find.text('QT-2026-002'), findsOneWidget);
    expect(find.text('QT-2026-003'), findsOneWidget);
    expect(find.text('Acme Corp'), findsOneWidget);
    expect(find.text('Beta Ltd'), findsOneWidget);
    expect(find.text('Quotation #'), findsOneWidget);
    // Status badges map to the quotations* localized labels.
    expect(find.text('Sent'), findsOneWidget);
    expect(find.text('Draft'), findsOneWidget);
    expect(find.text('Accepted'), findsOneWidget);
    // Totals via the shared currency formatter.
    expect(find.text('1,200.00'), findsOneWidget);
    expect(find.text('900.00'), findsOneWidget);
    expect(find.text('700.00'), findsOneWidget);
  });

  testWidgets('quotations grid exports the rows to CSV', (tester) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToQuotations(tester, adapter);

    // Stub the file_picker save channel to return a real temp path; the
    // shared save helper then writes the CSV there (same pattern as the
    // orders and returns export tests).
    final target = '${Directory.systemTemp.path}/minierp-quotations-test.csv';
    final targetFile = File(target);
    if (targetFile.existsSync()) targetFile.deleteSync();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
          (call) async {
            if (call.method == 'save') return target;
            return null;
          },
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
            null,
          ),
    );

    // Real async file I/O — drive it inside runAsync so the write
    // finishes and the toast can appear.
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(TextButton, 'Export to CSV'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    // Success toast + the CSV file exists with the quotations rows
    // (header columns, all three fixture rows with their formatted
    // totals and the localized status labels).
    expect(find.text('Quotations exported'), findsOneWidget);
    final file = File(target);
    expect(file.existsSync(), isTrue);
    final content = file.readAsStringSync();
    expect(content, contains('Quotation #'));
    expect(content, contains('QT-2026-001'));
    expect(content, contains('Acme Corp'));
    expect(content, contains('Sent')); // quotation1Status default
    expect(content, contains('1,200.00'));
    expect(content, contains('QT-2026-002'));
    expect(content, contains('900.00'));
    expect(content, contains('QT-2026-003'));
    expect(content, contains('700.00'));
    if (file.existsSync()) file.deleteSync();
  });

  testWidgets('quotations screen F2 opens the quotation detail dialog', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToQuotations(tester, adapter);

    // Same current-cell + focus setup as the SO/PO F2 tests — fired
    // through the REAL key pipeline (FocusScope → keyManager →
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

    // Detail dialog renders the fetched quotation (header label + an
    // item row from the fake /quotations/1 payload).
    expect(find.text('Quotation Details'), findsOneWidget);
    expect(find.text('Widget A'), findsOneWidget);
    expect(find.text('FG001'), findsOneWidget);
    expect(find.text('1,200.00'), findsWidgets); // total tile + amounts

    // Close returns to the grid.
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    expect(find.text('Quotation Details'), findsNothing);
  });

  testWidgets('quotations screen New Quotation button opens the create form', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToQuotations(tester, adapter);

    await tester.tap(find.widgetWithText(FilledButton, 'New Quotation'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Dialog, 'New Quotation'), findsOneWidget);

    // Validation: saving empty shows the server DTO-message equivalents.
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Select a customer'), findsOneWidget);
    expect(adapter.lastQuotationPostBody, isNull);

    // Pick a customer (dropdown #0; the line's item select is #2).
    await tester.tap(find.byType(SearchableSelect<int>).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('CUST001').last);
    await tester.pumpAndSettle();

    // Fill the first line: item select, quantity, unit price. Notes is
    // TextFormField #0 and terms #1; the line's qty/price are #2/#3.
    await tester.tap(find.byType(SearchableSelect<int>).at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('FG001').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(2), '10');
    await tester.enterText(find.byType(TextFormField).at(3), '100');

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // Dialog closed; POST body matches the createQuotation DTO shape.
    expect(find.widgetWithText(Dialog, 'New Quotation'), findsNothing);
    expect(adapter.lastQuotationPostBody?['customer_id'], 1);
    expect(adapter.lastQuotationPostBody?['quotation_date'], isNotEmpty);
    expect(adapter.lastQuotationPostBody?['status'], 'Draft');
    final items = adapter.lastQuotationPostBody?['items'] as List;
    expect(items, hasLength(1));
    expect((items.first as Map)['item_id'], 1);
    expect((items.first as Map)['quantity'], 10);
    expect((items.first as Map)['unit_price'], 100);
  });

  testWidgets('quotation form: edit prefills and PUTs the full body', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToQuotations(tester, adapter);

    // Double-tap the row opens the detail dialog.
    await tester.tap(find.text('QT-2026-001'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('QT-2026-001'));
    await tester.pumpAndSettle();
    expect(find.text('Quotation Details'), findsOneWidget);

    // QT-2026-001 is Sent — no Edit. Flip to Draft and re-open so the
    // Edit button appears.
    adapter.quotation1Status = 'Draft';
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('QT-2026-001'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('QT-2026-001'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Quotation'), findsOneWidget);

    // Change the first line's quantity; PUT carries the full replacement
    // items array (server-side delete + reinsert). Notes=0, terms=1,
    // first line's qty=2.
    await tester.enterText(find.byType(TextFormField).at(2), '20');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(Dialog, 'Edit Quotation'), findsNothing);
    expect(adapter.lastQuotationPutBody?['customer_id'], 1);
    expect(adapter.lastQuotationPutBody?['quotation_date'], '2026-01-18');
    final items = adapter.lastQuotationPutBody?['items'] as List;
    expect(items, hasLength(2)); // prefilled from the detail fetch
    expect((items.first as Map)['item_id'], 1);
    expect((items.first as Map)['quantity'], 20);
    expect((items.first as Map)['unit_price'], 100);
  });

  testWidgets('quotation form: Print A4 shows only in edit mode', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToQuotations(tester, adapter);

    // Create mode: nothing saved yet, so no Print A4 action.
    await tester.tap(find.widgetWithText(FilledButton, 'New Quotation'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Dialog, 'New Quotation'), findsOneWidget);
    expect(find.text('Print A4'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    // Edit mode (Draft → Edit visible): the Print A4 action appears.
    adapter.quotation1Status = 'Draft';
    await tester.tap(find.text('QT-2026-001'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('QT-2026-001'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Quotation'), findsOneWidget);
    // The detail dialog behind the form also has Print A4 now, so scope
    // to the topmost (form) dialog.
    expect(
      find.descendant(
        of: find.byType(Dialog).last,
        matching: find.widgetWithText(TextButton, 'Print A4'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('quotation detail: Print A4 is available for any status', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToQuotations(tester, adapter);

    // Open the detail dialog (QT-2026-001 defaults to Sent).
    await tester.tap(find.text('QT-2026-001'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('QT-2026-001'));
    await tester.pumpAndSettle();
    expect(find.text('Quotation Details'), findsOneWidget);
    // Print A4 sits in the footer regardless of status.
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Print A4'),
      ),
      findsOneWidget,
    );

    // Draft keeps the action next to Edit + Delete.
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    adapter.quotation1Status = 'Draft';
    await tester.tap(find.text('QT-2026-001'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('QT-2026-001'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Print A4'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Edit'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'quotations detail: Convert to SO confirms and creates a sales order',
    (tester) async {
      useWideSurface(tester);
      final adapter = _AuthFakeAdapter();
      adapter.quotation1Status = 'Accepted';
      await bootToQuotations(tester, adapter);

      // Open the detail of the Accepted quotation.
      await tester.tap(find.text('QT-2026-001'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('QT-2026-001'));
      await tester.pumpAndSettle();
      expect(find.text('Quotation Details'), findsOneWidget);
      expect(adapter.quotationConvertCount, 0);

      // Accepted → the Convert to SO action is visible; tapping opens the
      // confirm dialog.
      await tester.tap(find.widgetWithText(TextButton, 'Convert to SO'));
      await tester.pumpAndSettle();
      expect(find.textContaining('create a sales order'), findsOneWidget);
      // Confirm via the dialog's FilledButton (dismiss is a TextButton
      // labelled Cancel).
      await tester.tap(
        find.descendant(
          of: find.byType(Dialog).last,
          matching: find.widgetWithText(FilledButton, 'Convert to SO'),
        ),
      );
      await tester.pumpAndSettle();

      // The convert POST fired; both the detail and list providers were
      // invalidated and refetched with the Converted status (the dialog
      // badge and the grid row behind it both flip). The success toast
      // names the created sales order.
      expect(adapter.quotationConvertCount, 1);
      expect(find.text('Converted'), findsWidgets);
      expect(find.textContaining('SO-2026-007'), findsOneWidget);
      // The detail dialog's Convert button is gone (status is Converted).
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.widgetWithText(TextButton, 'Convert to SO'),
        ),
        findsNothing,
      );
    },
  );

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

  Future<void> bootToPurchaseReturns(
    WidgetTester tester,
    _AuthFakeAdapter adapter,
  ) async {
    await bootToPurchaseOrders(tester, adapter);
    // Switch the purchasing shell to the returns tab (PO is the default).
    await tester.tap(find.text('Purchase Returns'));
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
    // Gamma Goods' badge + the toolbar's Inactive status-filter segment.
    expect(find.text('Inactive'), findsNWidgets(2));
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
    // Gamma Inc's badge + the toolbar's Inactive status-filter segment.
    expect(find.text('Inactive'), findsNWidgets(2));
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

  testWidgets('customers screen status filter sends the server status param', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToCustomers(tester, adapter);

    // Default (All) omits the status param.
    expect(adapter.lastCustomersQuery?['status'], isNull);

    // Tap the toolbar's Active segment — the grid re-fetches with
    // ?status=active. The 'Active' label also appears on status badges in
    // the grid, so scope the tap to inside the SegmentedButton.
    final segments = find.bySubtype<SegmentedButton<dynamic>>();
    await tester.tap(
      find.descendant(of: segments, matching: find.text('Active')),
    );
    await tester.pumpAndSettle();
    expect(adapter.lastCustomersQuery?['status'], 'active');

    // Inactive segment → ?status=inactive (resets to page 1).
    await tester.tap(
      find.descendant(of: segments, matching: find.text('Inactive')),
    );
    await tester.pumpAndSettle();
    expect(adapter.lastCustomersQuery?['status'], 'inactive');
    expect(adapter.lastCustomersQuery?['page'], 1);
  });

  testWidgets('customers screen row menu delete confirms and calls DELETE', (
    tester,
  ) async {
    // Wider than [useWideSurface]: the full web-parity column set (~1590px
    // incl. the hidden cells) plus the 180px nav rail pushes the trailing
    // actions column past the 1600px surface, so the ⋮ tap would miss.
    tester.view.physicalSize = const Size(2200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final adapter = _AuthFakeAdapter();
    await bootToCustomers(tester, adapter);

    // Open the first row's ⋮ menu (the actions cell's Listener + the
    // grid's more_vert icon — scoped to the grid so other more_vert
    // icons, e.g. the AppBar's language menu, are excluded).
    final gridMenuButton = find
        .descendant(
          of: find.byType(PlutoGrid),
          matching: find.byIcon(Icons.more_vert),
        )
        .first;
    await tester.tap(gridMenuButton);
    await tester.pumpAndSettle();
    expect(find.text('View'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);

    // Choose Delete → the confirm dialog appears → confirm it.
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    // The soft-delete fired for the first row (Acme Corp, id 1).
    expect(adapter.lastCustomerDeleteId, 1);
  });

  testWidgets('customers screen row menu View opens the detail page with '
      'Record Payment modal', (tester) async {
    // Wider than [useWideSurface]: the trailing actions column needs the
    // extra width to be on-screen.
    tester.view.physicalSize = const Size(2200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final adapter = _AuthFakeAdapter();
    await bootToCustomers(tester, adapter);

    // ⋮ → View pushes the detail page.
    await tester.tap(
      find
          .descendant(
            of: find.byType(PlutoGrid),
            matching: find.byIcon(Icons.more_vert),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();

    expect(find.text('Record Payment'), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);

    // Record Payment opens the web-style modal with the customer pre-bound
    // and its open invoices listed for allocation.
    await tester.tap(find.text('Record Payment'));
    await tester.pumpAndSettle();
    expect(find.text('CUST001 — Acme Corp'), findsOneWidget);
    expect(find.text('Available Invoices'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('customers screen Fix Balances confirms and calls recalculate', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToCustomers(tester, adapter);

    // The toolbar's Fix Balances button → confirm dialog.
    await tester.tap(find.text('Fix Balances'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    // Confirm via the dialog's FilledButton (rendered last, above the
    // toolbar's same-labelled button).
    await tester.tap(find.widgetWithText(FilledButton, 'Fix Balances').last);
    await tester.pumpAndSettle();

    expect(adapter.recalculateBalancesCalled, isTrue);
  });

  testWidgets('customers screen F2 opens the customer detail page', (
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

    // The full-screen detail page renders: header (name + contact),
    // quick stats (credit limit stat), Record Payment + the 5 tabs.
    expect(find.text('Acme Corp'), findsOneWidget);
    expect(find.text('(Jane Doe)'), findsOneWidget);
    expect(find.text('5,000.00'), findsOneWidget); // credit-limit stat
    expect(find.text('Record Payment'), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Invoices'), findsOneWidget);

    // Back returns to the grid.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Overview'), findsNothing);
  });

  testWidgets('customers screen Enter opens the customer detail page', (
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

    expect(find.text('Acme Corp'), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Overview'), findsNothing);
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

    expect(find.text('Overview'), findsNothing);
    expect(find.text('Record Payment'), findsNothing);
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

  testWidgets('customer form: edit from the row menu PUTs and updates', (
    tester,
  ) async {
    // Wider surface: the trailing ⋮ actions column must be on-screen.
    tester.view.physicalSize = const Size(2200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final adapter = _AuthFakeAdapter();
    await bootToCustomers(tester, adapter);

    // Open the first row's ⋮ menu and choose Edit — opens the form dialog
    // pre-filled from the grid row's Customer.
    await tester.tap(
      find
          .descendant(
            of: find.byType(PlutoGrid),
            matching: find.byIcon(Icons.more_vert),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Customer'), findsOneWidget);

    // Change the name (first TextFormField) and save.
    await tester.enterText(find.byType(TextFormField).at(0), 'Acme Corp Ltd');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Customer'), findsNothing);
    // The PUT body carries the row-provided prefill values plus the
    // edited name (customer_code is never sent).
    expect(adapter.lastCustomerPutBody?['customer_name'], 'Acme Corp Ltd');
    expect(adapter.lastCustomerPutBody?['phone'], '555-0101');
    expect(adapter.lastCustomerPutBody?['email'], 'a@acme.com');
    expect(adapter.lastCustomerPutBody?.containsKey('customer_code'), false);
  });

  testWidgets('customer detail Ledger tab shows grouped entries and totals', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToCustomers(tester, adapter);

    // F2 opens the detail page, then switch to the Ledger tab.
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

    await tester.tap(find.text('Ledger').first);
    await tester.pumpAndSettle();

    // The fake ledger's INVOICE becomes a group header carrying its own
    // date/type/reference plus the invoice debit, summed credit (total
    // paid) and remaining balance (web parity). The PAYMENT carries
    // linked_invoice_no, so it groups under the invoice header.
    expect(find.text('INVOICE'), findsOneWidget); // header type cell
    expect(find.text('INV-2026-001'), findsOneWidget); // reference col
    // Header summary (collapsed): 1 payment · Balance: 300.00; the
    // child payment is hidden until expanded.
    expect(find.textContaining('1 payments · Balance: 300.00'), findsOneWidget);
    expect(find.text('500.00'), findsWidgets); // header debit
    expect(find.text('Payment received'), findsNothing); // child hidden
    // Totals footer: balance = debit 500 − credit 200 = 300 (also shown
    // in the page's quick-stat Balance, so multiple matches).
    expect(find.text('300.00'), findsWidgets);

    // Expanding the group reveals the payment row, indented with the
    // web's "—" child marker.
    await tester.tap(find.textContaining('1 payments · Balance: 300.00'));
    await tester.pumpAndSettle();
    expect(find.text('Payment received'), findsOneWidget);
    expect(find.text('—'), findsOneWidget); // child indent marker
  });

  testWidgets('suppliers screen F2 opens the supplier detail page', (
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

    // The full-screen detail page renders: header (name + contact),
    // quick stats, Record Payment + the 5 tabs.
    expect(find.text('Alpha Traders'), findsOneWidget);
    expect(find.text('(Ali Raza)'), findsOneWidget);
    expect(find.text('250.00'), findsWidgets); // balance quick-stat
    expect(find.text('Record Payment'), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('POs'), findsOneWidget);

    // Back returns to the grid.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Overview'), findsNothing);
  });

  testWidgets('suppliers screen Enter opens the supplier detail page', (
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

    expect(find.text('Alpha Traders'), findsOneWidget);
    expect(find.text('(Ali Raza)'), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Overview'), findsNothing);
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

    expect(find.text('Overview'), findsNothing);
    expect(find.text('Record Payment'), findsNothing);
  });

  testWidgets('suppliers screen row menu delete confirms and calls DELETE', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final adapter = _AuthFakeAdapter();
    await bootToSuppliers(tester, adapter);

    final gridMenuButton = find
        .descendant(
          of: find.byType(PlutoGrid),
          matching: find.byIcon(Icons.more_vert),
        )
        .first;
    await tester.tap(gridMenuButton);
    await tester.pumpAndSettle();
    expect(find.text('View'), findsOneWidget);

    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    // Confirm dialog message (scoped — the grid's supplier-name cell
    // also contains 'Alpha Traders').
    expect(
      find.textContaining('Are you sure you want to delete'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Delete').last);
    await tester.pumpAndSettle();
    expect(adapter.supplierDeleteCount, 1);
    // The list refetches after a successful delete.
    expect(adapter.lastSuppliersQuery?['page'], 1);
  });

  testWidgets('supplier detail Record Payment modal posts PO allocations', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToSuppliers(tester, adapter);

    // F2 opens the detail page, then Record Payment.
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

    await tester.tap(find.widgetWithText(FilledButton, 'Record Payment'));
    await tester.pumpAndSettle();

    // Modal opens with the supplier pre-bound and the open PO listed.
    expect(find.text('SUP001 — Alpha Traders'), findsOneWidget);
    expect(find.text('PO-2026-001'), findsOneWidget);

    // Amount + add the PO allocation.
    await tester.enterText(find.byType(TextFormField).at(1), '1000');
    await tester.pump();
    await tester.tap(find.text('+ Add'));
    await tester.pump();

    // Submit posts the supplier-shaped body with po_allocations.
    await tester.tap(find.widgetWithText(FilledButton, 'Record Payment').last);
    await tester.pumpAndSettle();

    final body = adapter.lastPaymentPostBody!;
    expect(body['supplier_id'], 1);
    expect(body['amount'], 1000);
    expect((body['po_allocations'] as List).length, 1);
    expect((body['po_allocations'] as List).first['po_id'], 1);
    expect((body['po_allocations'] as List).first['amount'], 1000);
  });

  testWidgets('supplier detail Ledger tab shows entries and totals', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToSuppliers(tester, adapter);

    // F2 opens the detail page, then switch to the Ledger tab.
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

    await tester.tap(find.text('Ledger').first);
    await tester.pumpAndSettle();

    // Entries from the fake /suppliers/1/ledger payload (description +
    // reference subtext).
    expect(find.text('Purchase goods'), findsOneWidget);
    expect(find.text('PO-2026-001'), findsOneWidget);
    expect(find.text('Payment made'), findsOneWidget);
    // Web-parity amount treatment: debit/credit cells are currency-
    // formatted and zero cells are blank — raw numbers (500.0 / 200.0)
    // and "0.00" placeholders must not appear. The formatted amounts
    // show in both the grid cells and the totals footer.
    expect(find.text('500.00'), findsWidgets);
    expect(find.text('200.00'), findsWidgets);
    expect(find.text('120.50'), findsWidgets);
    expect(find.text('500.0'), findsNothing);
    expect(find.text('200.0'), findsNothing);
    expect(find.text('0.00'), findsNothing);
  });

  testWidgets('supplier detail Statement tab shows the running balance', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToSuppliers(tester, adapter);

    // F2 opens the detail page, then switch to the Statement tab.
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

    await tester.tap(find.text('Statement').first);
    await tester.pumpAndSettle();

    // Summary tiles + the opening row + transaction rows.
    expect(find.text('Statement Summary'), findsOneWidget);
    expect(find.text('Opening Balance'), findsNWidgets(2)); // tile + row
    expect(find.text('Closing Balance'), findsNWidgets(2)); // tile + row
    expect(find.text('Purchase goods'), findsOneWidget);
    expect(find.text('Payment made'), findsOneWidget);
    // opening: tile + row; total debit 500 = entry + totals; total credit
    // 200 = entry + totals; closing 400 = tile + entry-2 balance + totals.
    expect(find.text('100.00'), findsNWidgets(2));
    expect(find.text('500.00'), findsNWidgets(2));
    expect(find.text('200.00'), findsNWidgets(2));
    expect(find.text('400.00'), findsNWidgets(3));
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

  testWidgets('suppliers screen row menu edit PUTs and updates', (
    tester,
  ) async {
    // Wider than [useWideSurface]: the full web-parity column set plus
    // the nav rail pushes the trailing actions column off a 1600px
    // surface, so the ⋮ tap would miss.
    tester.view.physicalSize = const Size(2200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final adapter = _AuthFakeAdapter();
    await bootToSuppliers(tester, adapter);

    // Open the first row's ⋮ menu and choose Edit — opens the form dialog
    // pre-filled from the grid row's Supplier.
    await tester.tap(
      find
          .descendant(
            of: find.byType(PlutoGrid),
            matching: find.byIcon(Icons.more_vert),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
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
    // The PUT body carries the row-provided prefill values plus the
    // edited name (supplier_code is not updatable server-side).
    expect(adapter.lastSupplierPutBody?['supplier_name'], 'Alpha Traders Ltd');
    expect(adapter.lastSupplierPutBody?['phone'], '555-0201');
    expect(adapter.lastSupplierPutBody?['email'], 'a@alpha.com');
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

  testWidgets('purchase orders grid exports the rows to CSV', (tester) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToPurchaseOrders(tester, adapter);

    // Stub the file_picker save channel to return a real temp path; the
    // shared save helper then writes the CSV there (same pattern as the
    // sales-orders and returns export tests).
    final target =
        '${Directory.systemTemp.path}/minierp-purchaseorders-test.csv';
    final targetFile = File(target);
    if (targetFile.existsSync()) targetFile.deleteSync();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
          (call) async {
            if (call.method == 'save') return target;
            return null;
          },
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
            null,
          ),
    );

    // The save helper does real async file I/O (File.writeAsBytes) that
    // never completes under the test's fake-async zone — drive it inside
    // runAsync so the write finishes and the toast can appear.
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(TextButton, 'Export to CSV'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    // Success toast + the CSV file exists with the orders rows (header
    // columns, both fixture rows with their formatted totals and the
    // localized status labels).
    expect(find.text('Purchase orders exported'), findsOneWidget);
    final file = File(target);
    expect(file.existsSync(), isTrue);
    final content = file.readAsStringSync();
    expect(content, contains('PO No'));
    expect(content, contains('PO-2026-001'));
    expect(content, contains('Alpha Traders'));
    expect(content, contains('Draft'));
    expect(content, contains('1,500.00'));
    expect(content, contains('PO-2026-002'));
    expect(content, contains('Beta Suppliers'));
    expect(content, contains('2,500.00'));
    if (file.existsSync()) file.deleteSync();
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

  testWidgets('purchase returns screen renders the returns grid', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToPurchaseReturns(tester, adapter);

    // Rows from the bare-array fake (return no + item), the localized
    // type badges, the qty magnitudes and the currency-formatted values.
    expect(find.text('SM-2026-0018'), findsOneWidget);
    expect(find.text('SM-2026-0021'), findsOneWidget);
    expect(find.text('Raw Material A'), findsOneWidget);
    expect(find.text('Finished Good B'), findsOneWidget);
    expect(find.text('Purchase Return'), findsOneWidget); // type badge
    expect(find.text('PO Return'), findsOneWidget);
    expect(find.text('5'), findsOneWidget); // |quantity| of row 1
    expect(find.text('10.00'), findsOneWidget); // unit cost, row 1
    expect(find.text('50.00'), findsOneWidget); // 5 × 10 return value
    expect(find.text('40.00'), findsOneWidget); // unit cost, row 2
    expect(find.text('80.00'), findsOneWidget); // 2 × 40 return value
    // Grid column headers.
    expect(find.text('Return No'), findsOneWidget);
    expect(find.text('Return Date'), findsOneWidget);
    expect(find.text('Type'), findsOneWidget);
  });

  testWidgets('purchase returns grid exports the rows to CSV', (tester) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToPurchaseReturns(tester, adapter);

    // Stub the file_picker save channel to return a real temp path; the
    // shared save helper then writes the CSV there (same pattern as the
    // invoice-returns and stock ledger export tests).
    final target =
        '${Directory.systemTemp.path}/minierp-purchasereturns-test.csv';
    final targetFile = File(target);
    if (targetFile.existsSync()) targetFile.deleteSync();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
          (call) async {
            if (call.method == 'save') return target;
            return null;
          },
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
            null,
          ),
    );

    // The save helper does real async file I/O (File.writeAsBytes) that
    // never completes under the test's fake-async zone — drive it inside
    // runAsync so the write finishes and the toast can appear.
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(TextButton, 'Export to CSV'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    // Success toast + the CSV file exists with the returns rows (header
    // columns, both fixture rows with their formatted values and the
    // localized type badges).
    expect(find.text('Purchase returns exported'), findsOneWidget);
    final file = File(target);
    expect(file.existsSync(), isTrue);
    final content = file.readAsStringSync();
    expect(content, contains('Return No'));
    expect(content, contains('SM-2026-0018'));
    expect(content, contains('Raw Material A'));
    expect(content, contains('Purchase Return'));
    expect(content, contains('50.00')); // 5 × 10 return value
    expect(content, contains('SM-2026-0021'));
    expect(content, contains('80.00')); // 2 × 40 return value
    if (file.existsSync()) file.deleteSync();
  });

  testWidgets('purchase returns screen shows the keyboard hint status bar', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToPurchaseReturns(tester, adapter);

    // The same AG-Grid-style status bar the other grids render (the
    // offstage PO grid's bar is skipped by the default finders).
    expect(find.text('↑ ↓ ← →'), findsOneWidget);
    expect(find.text('Enter / F2'), findsOneWidget);
    expect(find.text('Navigate'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('purchasing shell defaults to PO and switches to returns', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToPurchaseOrders(tester, adapter);

    // Default tab = the purchase orders grid; the returns rows are
    // offstage (IndexedStack) and skipped by the default finders.
    expect(find.text('PO-2026-001'), findsOneWidget);
    expect(find.text('SM-2026-0018'), findsNothing);

    await tester.tap(find.text('Purchase Returns'));
    await tester.pumpAndSettle();

    expect(find.text('SM-2026-0018'), findsOneWidget);
    expect(find.text('PO-2026-001'), findsNothing);
  });

  testWidgets('purchase orders screen New PO button opens the create form', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToPurchaseOrders(tester, adapter);

    await tester.tap(find.text('New Purchase Order'));
    await tester.pumpAndSettle();

    // The toolbar button keeps its label — scope the title to the dialog.
    expect(find.widgetWithText(Dialog, 'New Purchase Order'), findsOneWidget);
    expect(find.text('Add Item'), findsOneWidget);
  });

  testWidgets('purchase order form: create posts the schema-shaped body', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToPurchaseOrders(tester, adapter);

    await tester.tap(find.text('New Purchase Order'));
    await tester.pumpAndSettle();

    // Supplier (first int dropdown; the item/warehouse selects come
    // after). Menu label is '<code> — <name>'.
    await tester.tap(find.byType(SearchableSelect<int>).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SUP001 — Alpha Traders').last);
    await tester.pumpAndSettle();

    // Pick the line's item (third int dropdown: supplier, warehouse,
    // then the line).
    await tester.tap(find.byType(SearchableSelect<int>).at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FG001 — Widget A').last);
    await tester.pumpAndSettle();

    // Notes field first, then the line's qty + unit price.
    await tester.enterText(find.byType(TextFormField).at(1), '10');
    await tester.enterText(find.byType(TextFormField).at(2), '15.5');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // Dialog closed; POST body matches the purchaseOrderSchema shape.
    expect(find.widgetWithText(Dialog, 'New Purchase Order'), findsNothing);
    expect(adapter.lastPoPostBody?['supplier_id'], 1);
    expect(adapter.lastPoPostBody?['status'], 'Draft'); // schema default
    expect(adapter.lastPoPostBody?['items'], [
      {'item_id': 1, 'quantity': 10, 'unit_price': 15.5},
    ]);
    final now = DateTime.now();
    final today =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    expect(adapter.lastPoPostBody?['po_date'], today);
  });

  testWidgets('purchase order form: edit prefills and reconciles items', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToPurchaseOrders(tester, adapter);

    // Open PO-2026-001's detail, then Edit.
    await tester.tap(find.text('PO-2026-001'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('PO-2026-001'));
    await tester.pumpAndSettle();
    expect(find.text('Purchase Order Details'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();

    // Prefilled from the fake detail: supplier, item line (code — name),
    // qty 100, unit price 10.
    expect(find.text('Edit Purchase Order'), findsOneWidget);
    expect(find.text('SUP001 — Alpha Traders'), findsOneWidget);
    expect(find.text('RM001 — Raw Material A'), findsOneWidget);

    // Notes first, then the line's qty + unit price — change the qty.
    await tester.enterText(find.byType(TextFormField).at(1), '120');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // Header PUT (no items/status — the update DTO is header-only).
    expect(adapter.lastPoPutBody?['supplier_id'], 1);
    expect(adapter.lastPoPutBody?['po_date'], '2026-01-20');
    expect(adapter.lastPoPutBody?['expected_delivery_date'], '2026-02-01');
    expect(adapter.lastPoPutBody!.containsKey('items'), isFalse);
    expect(adapter.lastPoPutBody!.containsKey('status'), isFalse);
    // The changed line goes through PUT items/:id (quantity only — price
    // is unchanged); no adds, no deletes.
    expect(adapter.lastPoItemPutBody?['quantity'], 120);
    expect(adapter.lastPoItemPutBody?['unit_price'], 10);
    expect(adapter.lastPoItemPostBody, isNull);
    expect(adapter.poItemDeleteCount, 0);
    expect(find.text('Edit Purchase Order'), findsNothing);
  });

  testWidgets('purchase order form: Print A4 shows only in edit mode', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToPurchaseOrders(tester, adapter);

    // Create mode: nothing saved yet, so no Print A4 action.
    await tester.tap(find.text('New Purchase Order'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Dialog, 'New Purchase Order'), findsOneWidget);
    expect(find.text('Print A4'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    // Edit mode (Draft → Edit visible): the Print A4 action appears. The
    // detail dialog behind the form also has it now, so scope to the top.
    await tester.tap(find.text('PO-2026-001'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('PO-2026-001'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Purchase Order'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(Dialog).last,
        matching: find.widgetWithText(TextButton, 'Print A4'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('purchase order detail: Print A4 is available for any status', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToPurchaseOrders(tester, adapter);

    // Open the detail dialog (PO-2026-001 defaults to Draft).
    await tester.tap(find.text('PO-2026-001'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('PO-2026-001'));
    await tester.pumpAndSettle();
    expect(find.text('Purchase Order Details'), findsOneWidget);
    // Print A4 sits in the footer regardless of status.
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Print A4'),
      ),
      findsOneWidget,
    );

    // Submitted keeps the action next to Receive Goods.
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    adapter.po1Status = 'Submitted';
    await tester.tap(find.text('PO-2026-001'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('PO-2026-001'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Print A4'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Receive Goods'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('purchase order form: item change removes and re-adds the line', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToPurchaseOrders(tester, adapter);

    await tester.tap(find.text('PO-2026-001'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('PO-2026-001'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();

    // Switch the first line's item (supplier, warehouse, then the line).
    await tester.tap(find.byType(SearchableSelect<int>).at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FG002 — Finished Good B').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // PUT can't re-target a line — the old line is deleted and the new
    // item re-added via POST carrying item_id (the bug the review caught:
    // _lineBody would have omitted it for a line with a server id).
    expect(adapter.poItemDeleteCount, 1);
    expect(adapter.lastPoItemPostBody?['item_id'], 5);
    expect(adapter.lastPoItemPostBody?['quantity'], 100);
    expect(adapter.lastPoItemPostBody?['unit_price'], 10);
    expect(adapter.lastPoItemPutBody, isNull);
  });

  testWidgets('purchase order: submit moves a Draft PO to Submitted', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToPurchaseOrders(tester, adapter);

    // Open the detail dialog for PO-2026-001.
    await tester.tap(find.text('PO-2026-001'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('PO-2026-001'));
    await tester.pumpAndSettle();

    // Draft-only actions: Submit + Edit in the footer.
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('Submit')),
      findsOneWidget,
    );

    // Submit → confirm dialog.
    await tester.tap(
      find.descendant(of: find.byType(Dialog), matching: find.text('Submit')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.text(
        'Submit this purchase order? It will be locked and posted to the supplier ledger.',
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Submit'),
      ),
    );
    await tester.pumpAndSettle();

    expect(adapter.lastPoStatusBody, {'status': 'Submitted'});
    // The detail refetched: badge flipped, Submit/Edit actions gone.
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Submitted'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('Submit')),
      findsNothing,
    );
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('Edit')),
      findsNothing,
    );
  });

  testWidgets('purchase order: submit rejection keeps the PO in Draft', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter()..rejectPoStatus = true;
    await bootToPurchaseOrders(tester, adapter);

    // Open the detail dialog for PO-2026-001 and submit.
    await tester.tap(find.text('PO-2026-001'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('PO-2026-001'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(Dialog), matching: find.text('Submit')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Submit'),
      ),
    );
    await tester.pumpAndSettle();

    expect(adapter.lastPoStatusBody, {'status': 'Submitted'});
    // The server's message surfaces verbatim; badge stays Draft and the
    // Submit action remains available.
    expect(
      find.text('Cannot transition from Draft to Submitted'),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('Draft')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('Submit')),
      findsOneWidget,
    );
  });

  testWidgets('purchase order: receive goods posts the receipt and shows history', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToPurchaseOrders(tester, adapter);

    // Open the detail dialog for PO-2026-001 and submit it first (the
    // Receive Goods action only exists on non-Draft POs).
    await tester.tap(find.text('PO-2026-001'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('PO-2026-001'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(Dialog), matching: find.text('Submit')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Submit'),
      ),
    );
    await tester.pumpAndSettle();

    // Submitted → the footer gains Receive Goods (Submit/Edit gone).
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Receive Goods'),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Receive Goods'),
      ),
    );
    await tester.pumpAndSettle();

    // The form: warehouse pre-filled from the PO, the receivable line
    // (item 2 is fully received → no line), qty pre-filled to pending.
    // Scope to the top dialog — the detail beneath also shows the item.
    final dialog = find.byType(Dialog).last;
    expect(find.text('Receive Goods'), findsWidgets); // title + button
    expect(
      find.descendant(
        of: dialog,
        matching: find.text('WH-MAIN — Main Warehouse'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('Raw Material A')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('Ordered: 100')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('Pending: 100')),
      findsOneWidget,
    );

    // The dialog autofocuses its primary input — the first received-qty
    // cell — so the user can adjust quantities (or Enter to receive all)
    // without clicking. Verify via the focus manager that the focus
    // actually landed there: the closed dialog's only EditableTexts are
    // the notes field and the qty cell, so `.last` is the qty field.
    final qtyEditable = tester.widget<EditableText>(
      find
          .descendant(of: dialog, matching: find.byType(EditableText))
          .last,
    );
    expect(FocusManager.instance.primaryFocus, qtyEditable.focusNode);

    // Receive 60 of the 100 pending — exercises the editable qty (and
    // leaves 40 pending, so the PO stays Partially Received). Notes is
    // the first TextFormField in the dialog; the qty field is the second.
    await tester.enterText(find.byType(TextFormField).last, '60');
    await tester.pump();

    // Record the receipt. Scope to the top dialog: the detail dialog's
    // tonal Receive Goods footer button is still mounted beneath it.
    await tester.tap(
      find.descendant(
        of: dialog,
        matching: find.widgetWithText(FilledButton, 'Receive Goods'),
      ),
    );
    await tester.pumpAndSettle();

    // Receive dialog closed (only the detail dialog remains) + POST body
    // matches the createGoodsReceipt schema.
    expect(find.byType(Dialog), findsOneWidget);
    expect(adapter.lastPoReceiptBody?['warehouse_id'], 1);
    expect(adapter.lastPoReceiptBody?['items'], [
      {'po_item_id': 1, 'received_quantity': 60},
    ]);

    // The detail beneath refetched and now shows the receipt in history
    // (60 received of 100 — the only '60' in the dialog is the receipt
    // row's qty; the items table still lists the ordered 100).
    final detailDialog = find.byType(Dialog);
    expect(
      find.descendant(of: detailDialog, matching: find.text('Receipts')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: detailDialog, matching: find.text('GR-2026-001')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: detailDialog, matching: find.text('60')),
      findsOneWidget,
    );
  });

  testWidgets('purchase order form: delete confirms and pops both dialogs', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToPurchaseOrders(tester, adapter);

    // Detail dialog → Edit → the form shows the destructive Delete.
    await tester.tap(find.text('PO-2026-001'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('PO-2026-001'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, 'Delete'), findsOneWidget);

    // Confirm dialog → Delete.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.text(
        'Are you sure you want to delete this purchase order? This cannot be undone.',
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Delete'),
      ),
    );
    await tester.pumpAndSettle();

    expect(adapter.poDeleteCount, 1);
    // Both dialogs popped — back on the grid, toast visible.
    expect(find.text('Edit Purchase Order'), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Purchase order deleted'), findsOneWidget);
    expect(find.text('PO-2026-001'), findsOneWidget);
  });

  testWidgets('purchases screen renders the purchases grid', (tester) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToPurchaseOrders(tester, adapter);

    // The rail + shell tab both read 'Purchases' — scope to the bar.
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Purchases'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PUR-2026-001'), findsOneWidget);
    expect(find.text('PUR-2026-002'), findsOneWidget);
    expect(find.text('Raw Material A'), findsOneWidget);
    expect(find.text('Alpha Traders'), findsOneWidget);
    expect(find.text('INV-101'), findsOneWidget);
  });

  testWidgets('process return posts quantity + reason and refetches', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToPurchaseOrders(tester, adapter);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Purchases'),
      ),
    );
    await tester.pumpAndSettle();

    // Open the detail dialog for PUR-2026-001 (double-tap the row).
    await tester.tap(find.text('PUR-2026-001'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('PUR-2026-001'));
    await tester.pumpAndSettle();

    // Detail shows the Process Return action, then opens the return form.
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Process Return'),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Process Return'),
      ),
    );
    await tester.pumpAndSettle();

    // Fill qty + reason and submit.
    await tester.enterText(find.byType(TextFormField).first, '50');
    await tester.enterText(find.byType(TextFormField).at(1), 'Damaged');
    await tester.tap(find.widgetWithText(FilledButton, 'Return to Supplier'));
    await tester.pumpAndSettle();

    expect(adapter.lastPurchaseReturnBody?['quantity'], 50);
    expect(adapter.lastPurchaseReturnBody?['reason'], 'Damaged');
    expect(adapter.purchase1ReturnedQty, 50);
    // Toast (with the returned value from the enveloped data payload) +
    // the detail refetched: the Returned Qty tile reads 50 (the stateful
    // GET was re-read) and 50 remain returnable.
    expect(
      find.textContaining('Return processed successfully'),
      findsOneWidget,
    );
    expect(find.text('50'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Process Return'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('process return validates qty against the available amount', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToPurchaseOrders(tester, adapter);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Purchases'),
      ),
    );
    await tester.pumpAndSettle();

    // Open the detail dialog for PUR-2026-001 and the return form.
    await tester.tap(find.text('PUR-2026-001'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('PUR-2026-001'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Process Return'),
      ),
    );
    await tester.pumpAndSettle();

    // 500 exceeds the 100 available — the validator blocks the POST.
    await tester.enterText(find.byType(TextFormField).first, '500');
    await tester.tap(find.widgetWithText(FilledButton, 'Return to Supplier'));
    await tester.pumpAndSettle();

    expect(
      find.text('Return quantity exceeds the available quantity'),
      findsOneWidget,
    );
    expect(adapter.lastPurchaseReturnBody, isNull);
  });

  testWidgets('process return surfaces a server rejection', (tester) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter()..rejectPurchaseReturn = true;
    await bootToPurchaseOrders(tester, adapter);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Purchases'),
      ),
    );
    await tester.pumpAndSettle();

    // Open the detail dialog for PUR-2026-001 and the return form.
    await tester.tap(find.text('PUR-2026-001'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('PUR-2026-001'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Process Return'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '50');
    await tester.tap(find.widgetWithText(FilledButton, 'Return to Supplier'));
    await tester.pumpAndSettle();

    // The server's message surfaces in the ErrorBanner; the dialog stays
    // open with the submit action available and no quantity recorded.
    expect(find.text('Insufficient stock remaining to return'), findsOneWidget);
    expect(find.text('Return to Supplier'), findsOneWidget);
    expect(adapter.purchase1ReturnedQty, 0);
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

  testWidgets('warehouses tab renders the warehouses grid', (tester) async {
    useWideSurface(tester);
    await bootToItems(tester);

    // The sibling tabs stay mounted in the IndexedStack but offstage, so
    // their grids are skipped by the default finders.
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Warehouses'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('WH-MAIN'), findsOneWidget);
    expect(find.text('Main Warehouse'), findsOneWidget);
    expect(find.text('WH-RAW'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Inactive'), findsOneWidget);
  });

  testWidgets('stock movements tab renders and opens the movement detail', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToItems(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Stock Movements'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SM-2026-0100'), findsOneWidget);
    expect(find.text('SM-2026-0101'), findsOneWidget);
    expect(find.text('PURCHASE'), findsOneWidget);
    expect(find.text('SALE'), findsOneWidget);

    // Double-tap opens the in-memory movement detail dialog.
    await tester.tap(find.text('SM-2026-0100'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('SM-2026-0100'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Stock Movement'),
      ),
      findsOneWidget,
    );
    // The movement no appears twice inside the dialog: the title and the
    // Movement No info row.
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('SM-2026-0100'),
      ),
      findsNWidgets(2),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Close'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('stock by warehouse tab renders item×warehouse balances', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToItems(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Stock by Warehouse'),
      ),
    );
    await tester.pumpAndSettle();

    // The item/warehouse code columns are hidden; names render per row.
    expect(find.text('Widget A'), findsOneWidget);
    expect(find.text('Raw Material A'), findsOneWidget);
    expect(find.text('Raw Materials'), findsOneWidget);
  });

  testWidgets('stock by warehouse double-tap drills into the item detail', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToItems(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Stock by Warehouse'),
      ),
    );
    await tester.pumpAndSettle();

    // Double-tap the Widget A balance row (hidden id cell = item id 1) —
    // opens the fetched item detail dialog with its per-warehouse
    // breakdown (GET /inventory/items/1).
    await tester.tap(find.text('Widget A'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Widget A'));
    await tester.pumpAndSettle();

    expect(find.text('Item Details'), findsOneWidget);
    // Scoped: the balances grid behind also renders 'Main Warehouse', and
    // the 'Stock by Warehouse' tab label sits behind the dialog.
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Main Warehouse'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Stock by Warehouse'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('Widget A')),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('physical counts tab renders and opens the count detail', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToItems(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Physical Counts'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PC-2026-001'), findsOneWidget);
    expect(find.text('PC-2026-002'), findsOneWidget);
    expect(find.text('Draft'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);

    // Double-tap opens the count detail (header + counted item lines).
    await tester.tap(find.text('PC-2026-001'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('PC-2026-001'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Physical Count'),
      ),
      findsOneWidget,
    );
    expect(find.text('Counted Items'), findsOneWidget);
    expect(find.text('RM001 — Raw Material A'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('warehouse form: create posts the schema-shaped body', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToItems(tester, adapter: adapter);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Warehouses'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Warehouse'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('New Warehouse'),
      ),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextFormField).at(0), 'WH-NEW');
    await tester.enterText(find.byType(TextFormField).at(1), 'New Warehouse B');
    await tester.enterText(find.byType(TextFormField).at(2), 'Sector 21');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(adapter.lastWarehousePostBody, {
      'warehouse_code': 'WH-NEW',
      'warehouse_name': 'New Warehouse B',
      'location': 'Sector 21',
    });
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('warehouse form: edit prefills and PUTs updates', (tester) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToItems(tester, adapter: adapter);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Warehouses'),
      ),
    );
    await tester.pumpAndSettle();

    // Double-tap the WH-MAIN row opens the edit form, prefilled.
    await tester.tap(find.text('WH-MAIN'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('WH-MAIN'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Warehouse'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'WH-MAIN'), findsOneWidget);
    expect(
      find.widgetWithText(TextFormField, 'Main Warehouse'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextFormField, 'Sector 14'), findsOneWidget);

    // Code is immutable on edit; change the name only.
    await tester.enterText(find.byType(TextFormField).at(1), 'Main WH Updated');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(adapter.lastWarehousePutBody?['warehouse_code'], 'WH-MAIN');
    expect(adapter.lastWarehousePutBody?['warehouse_name'], 'Main WH Updated');
    expect(adapter.lastWarehousePutBody?['location'], 'Sector 14');
    expect(adapter.lastWarehousePostBody, isNull);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('warehouse form: validates required fields before posting', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToItems(tester, adapter: adapter);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Warehouses'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Warehouse'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // Code + name are required — both validators surface the message.
    expect(find.text('Required'), findsNWidgets(2));
    expect(adapter.lastWarehousePostBody, isNull);
    expect(find.byType(Dialog), findsOneWidget);
  });

  testWidgets('warehouse form: surfaces a server rejection on create', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter()..rejectWarehouseCreate = true;
    await bootToItems(tester, adapter: adapter);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Warehouses'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Warehouse'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'WH-MAIN');
    await tester.enterText(find.byType(TextFormField).at(1), 'Duplicate');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // The server's message surfaces in the error panel; the dialog stays
    // open with the submit action re-enabled.
    expect(find.text('Warehouse code already exists'), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
  });

  testWidgets('warehouses tab search filters rows after the debounce', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToItems(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Warehouses'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('WH-MAIN'), findsOneWidget);
    expect(find.text('WH-RAW'), findsOneWidget);

    // Type before the 300ms debounce fires — the rows are untouched.
    await tester.enterText(find.byType(TextField), 'raw');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('WH-MAIN'), findsOneWidget);
    expect(find.text('WH-RAW'), findsOneWidget);

    // After the debounce, only WH-RAW (code 'raw') matches.
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.text('WH-MAIN'), findsNothing);
    expect(find.text('Main Warehouse'), findsNothing);
    expect(find.text('WH-RAW'), findsOneWidget);
    expect(find.text('Raw Materials'), findsOneWidget);
  });

  testWidgets('physical count: complete transitions Draft to Completed', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToItems(tester, adapter: adapter);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Physical Counts'),
      ),
    );
    await tester.pumpAndSettle();

    // Open the count detail (double-tap the PC-2026-001 row).
    await tester.tap(find.text('PC-2026-001'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('PC-2026-001'));
    await tester.pumpAndSettle();

    // Draft-only actions: Complete + Cancel in the footer.
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Complete Count'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Cancel Count'),
      ),
      findsOneWidget,
    );

    // Complete → confirm dialog.
    await tester.tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Complete Count'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.text(
        'Complete this count? Adjustments will be posted for any items with variances.',
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Complete Count'),
      ),
    );
    await tester.pumpAndSettle();

    // The detail refetched: badge flipped, actions gone, toast shown.
    expect(find.text('Count completed'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Completed'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Complete Count'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Cancel Count'),
      ),
      findsNothing,
    );
  });

  testWidgets('physical count: cancel transitions Draft to Cancelled', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToItems(tester, adapter: adapter);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Physical Counts'),
      ),
    );
    await tester.pumpAndSettle();

    // Open the count detail.
    await tester.tap(find.text('PC-2026-001'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('PC-2026-001'));
    await tester.pumpAndSettle();

    // Cancel → confirm dialog (destructive).
    await tester.tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Cancel Count'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.text('Cancel this count? It cannot be completed afterward.'),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Cancel Count'),
      ),
    );
    await tester.pumpAndSettle();

    // The detail refetched: badge flipped, actions gone, toast shown.
    expect(find.text('Count cancelled'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Cancelled'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Complete Count'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Cancel Count'),
      ),
      findsNothing,
    );
  });

  testWidgets('physical count: complete rejection keeps the count in Draft', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter()..rejectPcComplete = true;
    await bootToItems(tester, adapter: adapter);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Physical Counts'),
      ),
    );
    await tester.pumpAndSettle();

    // Open the count detail and attempt to complete.
    await tester.tap(find.text('PC-2026-001'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('PC-2026-001'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Complete Count'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Complete Count'),
      ),
    );
    await tester.pumpAndSettle();

    // The server message surfaces verbatim; badge stays Draft and the
    // actions remain available.
    expect(find.text('Cannot complete Completed session'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('Draft')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Complete Count'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Cancel Count'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('physical count: record items posts quantities and refetches', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToItems(tester, adapter: adapter);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Physical Counts'),
      ),
    );
    await tester.pumpAndSettle();

    // Open the count detail.
    await tester.tap(find.text('PC-2026-001'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('PC-2026-001'));
    await tester.pumpAndSettle();

    // Record Items opens the editable item table (RM001 prefilled 95,
    // RM002 uncounted).
    await tester.tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Record Items'),
      ),
    );
    await tester.pumpAndSettle();
    // Scope to the record dialog — the detail dialog behind also renders
    // the same item labels in its table.
    final recordDialog = find.ancestor(
      of: find.widgetWithText(FilledButton, 'Save Counts'),
      matching: find.byType(Dialog),
    );
    expect(
      find.descendant(
        of: recordDialog,
        matching: find.text('RM001 — Raw Material A'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: recordDialog,
        matching: find.text('RM002 — Raw Material B'),
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextFormField, '95'), findsOneWidget);

    // Record RM001 → 88 and leave RM002 blank (unchanged).
    await tester.enterText(find.byType(TextFormField).first, '88');
    await tester.tap(find.widgetWithText(FilledButton, 'Save Counts'));
    await tester.pumpAndSettle();

    expect(adapter.lastPcRecordBody, {'item_id': 4, 'counted_quantity': 88});
    // The record dialog popped, the detail refetched and the table shows
    // the recorded 88 next to RM001 while RM002 stays uncounted (—).
    expect(find.text('Counts recorded'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('88')),
      findsOneWidget,
    );
    // RM002 stays uncounted: the em dash renders in both its Counted and
    // Variance cells.
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('—')),
      findsNWidgets(2),
    );
  });

  testWidgets('physical count: record items validates before posting', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToItems(tester, adapter: adapter);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Physical Counts'),
      ),
    );
    await tester.pumpAndSettle();

    // Open the count detail and the record dialog.
    await tester.tap(find.text('PC-2026-001'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('PC-2026-001'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Record Items'),
      ),
    );
    await tester.pumpAndSettle();

    // Both fields empty → nothing to record.
    await tester.enterText(find.byType(TextFormField).first, '');
    await tester.tap(find.widgetWithText(FilledButton, 'Save Counts'));
    await tester.pumpAndSettle();
    expect(find.text('Enter at least one counted quantity'), findsOneWidget);
    expect(adapter.lastPcRecordBody, isNull);

    // Negative qty → per-field validation error, still no POST.
    await tester.enterText(find.byType(TextFormField).first, '-5');
    await tester.tap(find.widgetWithText(FilledButton, 'Save Counts'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid quantity'), findsOneWidget);
    expect(adapter.lastPcRecordBody, isNull);
  });

  testWidgets('physical count: record items rejection keeps the dialog open', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter()..rejectPcRecord = true;
    await bootToItems(tester, adapter: adapter);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Physical Counts'),
      ),
    );
    await tester.pumpAndSettle();

    // Open the count detail and the record dialog.
    await tester.tap(find.text('PC-2026-001'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('PC-2026-001'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Record Items'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '88');
    await tester.tap(find.widgetWithText(FilledButton, 'Save Counts'));
    await tester.pumpAndSettle();

    // The server message surfaces verbatim; the dialog stays open so the
    // user can retry (Save re-enabled).
    expect(
      find.text('Cannot record count for Completed session'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Save Counts'), findsOneWidget);
    expect(adapter.lastPcRecordBody, {'item_id': 4, 'counted_quantity': 88});
  });

  testWidgets('warehouse form: delete confirms and removes the warehouse', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToItems(tester, adapter: adapter);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Warehouses'),
      ),
    );
    await tester.pumpAndSettle();

    // Double-tap WH-MAIN opens the edit form with the destructive Delete.
    await tester.tap(find.text('WH-MAIN'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('WH-MAIN'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Warehouse'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Delete'), findsOneWidget);

    // Confirm dialog → Delete.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.text('Delete this warehouse? It cannot be undone.'),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Delete'),
      ),
    );
    await tester.pumpAndSettle();

    expect(adapter.warehouseDeleteCount, 1);
    // Form popped, the grid refetched without WH-MAIN, toast visible.
    expect(find.text('Edit Warehouse'), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Warehouse deleted'), findsOneWidget);
    expect(find.text('WH-MAIN'), findsNothing);
    expect(find.text('WH-RAW'), findsOneWidget);
  });

  testWidgets('warehouse form: delete rejection keeps the form open', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter()..rejectWarehouseDelete = true;
    await bootToItems(tester, adapter: adapter);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Warehouses'),
      ),
    );
    await tester.pumpAndSettle();

    // Open the edit form and attempt to delete.
    await tester.tap(find.text('WH-MAIN'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('WH-MAIN'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Delete'),
      ),
    );
    await tester.pumpAndSettle();

    // The 404 message surfaces; the form stays open with Delete enabled.
    expect(find.text('Warehouse not found'), findsOneWidget);
    expect(find.text('Edit Warehouse'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Delete'), findsOneWidget);
    expect(adapter.warehouseDeleteCount, 1);
  });

  testWidgets('stock adjustment records a signed movement with reason', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToItems(tester, adapter: adapter);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Stock Movements'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'New Adjustment'));
    await tester.pumpAndSettle();

    // Item (first int dropdown; menu label is '<code> — <name>').
    await tester.tap(find.byType(SearchableSelect<int>).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FG001 — Widget A').last);
    await tester.pumpAndSettle();

    // Warehouse (second int dropdown).
    await tester.tap(find.byType(SearchableSelect<int>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Main Warehouse').last);
    await tester.pumpAndSettle();

    // Quantity, then reason (the screen's search is a TextField, so the
    // dialog owns the only TextFormFields).
    await tester.enterText(find.byType(TextFormField).at(0), '-10');
    await tester.enterText(find.byType(TextFormField).at(1), 'Broken stock');
    await tester.tap(find.widgetWithText(FilledButton, 'Record Adjustment'));
    await tester.pumpAndSettle();

    expect(adapter.movementPostCount, 1);
    expect(adapter.lastMovementPostBody, {
      'item_id': 1,
      'warehouse_id': 1,
      'quantity': -10,
      'movement_type': 'ADJUSTMENT',
      'remarks': 'Broken stock',
    });
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Stock adjustment recorded'), findsOneWidget);
  });

  testWidgets('stock adjustment validates before posting', (tester) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToItems(tester, adapter: adapter);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Stock Movements'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'New Adjustment'));
    await tester.pumpAndSettle();

    // Empty save: item, warehouse, and quantity all required.
    await tester.tap(find.widgetWithText(FilledButton, 'Record Adjustment'));
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsNWidgets(3));
    expect(adapter.movementPostCount, 0);

    // Non-numeric and zero quantities are rejected locally.
    await tester.enterText(find.byType(TextFormField).at(0), 'abc');
    await tester.tap(find.widgetWithText(FilledButton, 'Record Adjustment'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid quantity'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), '0');
    await tester.tap(find.widgetWithText(FilledButton, 'Record Adjustment'));
    await tester.pumpAndSettle();
    expect(find.text('Quantity cannot be zero'), findsOneWidget);
    expect(adapter.movementPostCount, 0);
  });

  testWidgets('stock adjustment surfaces the server rejection', (tester) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter()..rejectMovementCreate = true;
    await bootToItems(tester, adapter: adapter);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Stock Movements'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'New Adjustment'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SearchableSelect<int>).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FG001 — Widget A').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SearchableSelect<int>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Main Warehouse').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '-10');
    await tester.tap(find.widgetWithText(FilledButton, 'Record Adjustment'));
    await tester.pumpAndSettle();

    // The 400 message surfaces in the error banner; the dialog stays
    // open for retry.
    expect(adapter.movementPostCount, 1);
    expect(find.text('Insufficient stock for adjustment'), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Record Adjustment'),
      findsOneWidget,
    );
  });

  testWidgets('stock transfer posts outgoing and incoming movements', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToItems(tester, adapter: adapter);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Stock Movements'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'New Transfer'));
    await tester.pumpAndSettle();

    // Item, source, destination (the three int dropdowns in order).
    await tester.tap(find.byType(SearchableSelect<int>).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FG001 — Widget A').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SearchableSelect<int>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Main Warehouse').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SearchableSelect<int>).at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Raw Materials').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), '5');
    await tester.enterText(find.byType(TextFormField).at(1), 'Move to raw');
    await tester.tap(find.widgetWithText(FilledButton, 'Transfer Stock'));
    await tester.pumpAndSettle();

    expect(adapter.movementPostBodies.length, 2);
    // Outgoing leg: negative quantity, source warehouse, no reference.
    expect(adapter.movementPostBodies[0], {
      'item_id': 1,
      'warehouse_id': 1,
      'quantity': -5,
      'movement_type': 'TRANSFER',
      'reference_doctype': 'TRANSFER',
      'remarks': 'Move to raw',
    });
    // Incoming leg: positive quantity, destination warehouse, linked to
    // the outgoing movement's server-generated number.
    expect(adapter.movementPostBodies[1], {
      'item_id': 1,
      'warehouse_id': 2,
      'quantity': 5,
      'movement_type': 'TRANSFER',
      'reference_doctype': 'TRANSFER',
      'reference_docno': 'SM-2026-0102',
      'remarks': 'Move to raw',
    });
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Stock transferred'), findsOneWidget);
  });

  testWidgets('stock transfer validates source, destination, and quantity', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToItems(tester, adapter: adapter);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Stock Movements'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'New Transfer'));
    await tester.pumpAndSettle();

    // Empty save: item, source, destination, and quantity all required.
    await tester.tap(find.widgetWithText(FilledButton, 'Transfer Stock'));
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsNWidgets(4));
    expect(adapter.movementPostCount, 0);

    // Same source and destination is rejected up front.
    await tester.tap(find.byType(SearchableSelect<int>).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FG001 — Widget A').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SearchableSelect<int>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Main Warehouse').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SearchableSelect<int>).at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Main Warehouse').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '5');
    await tester.tap(find.widgetWithText(FilledButton, 'Transfer Stock'));
    await tester.pumpAndSettle();
    expect(
      find.text('Source and destination must be different'),
      findsOneWidget,
    );
    expect(adapter.movementPostCount, 0);

    // A non-positive quantity is rejected.
    await tester.tap(find.byType(SearchableSelect<int>).at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Raw Materials').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '0');
    await tester.tap(find.widgetWithText(FilledButton, 'Transfer Stock'));
    await tester.pumpAndSettle();
    expect(find.text('Quantity must be positive'), findsOneWidget);
    expect(adapter.movementPostCount, 0);
  });

  testWidgets('stock transfer surfaces outgoing-leg rejection', (tester) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter()..rejectMovementCreate = true;
    await bootToItems(tester, adapter: adapter);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Stock Movements'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'New Transfer'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SearchableSelect<int>).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FG001 — Widget A').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SearchableSelect<int>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Main Warehouse').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SearchableSelect<int>).at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Raw Materials').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '5');
    await tester.tap(find.widgetWithText(FilledButton, 'Transfer Stock'));
    await tester.pumpAndSettle();

    // The outgoing leg 400s before any INSERT — nothing recorded.
    expect(adapter.movementPostCount, 1);
    expect(find.text('Insufficient stock for adjustment'), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Transfer Stock'), findsOneWidget);
  });

  testWidgets('stock transfer flags a failed incoming leg', (tester) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter()..rejectSecondMovement = true;
    await bootToItems(tester, adapter: adapter);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Stock Movements'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'New Transfer'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SearchableSelect<int>).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FG001 — Widget A').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SearchableSelect<int>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Main Warehouse').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SearchableSelect<int>).at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Raw Materials').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '5');
    await tester.tap(find.widgetWithText(FilledButton, 'Transfer Stock'));
    await tester.pumpAndSettle();

    // The outgoing leg recorded; the incoming leg's 400 surfaces with
    // the partial-failure prefix so a retry doesn't re-post the OUT.
    expect(adapter.movementPostCount, 2);
    expect(find.textContaining('Transfer incomplete:'), findsOneWidget);
    expect(
      find.textContaining('Destination warehouse not found'),
      findsOneWidget,
    );
    expect(find.byType(Dialog), findsOneWidget);
  });

  testWidgets('stock transfer retry re-posts only the incoming leg', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter()..rejectSecondMovement = true;
    await bootToItems(tester, adapter: adapter);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Stock Movements'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'New Transfer'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SearchableSelect<int>).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FG001 — Widget A').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SearchableSelect<int>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Main Warehouse').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SearchableSelect<int>).at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Raw Materials').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '5');
    await tester.enterText(find.byType(TextFormField).at(1), 'Move to raw');
    await tester.tap(find.widgetWithText(FilledButton, 'Transfer Stock'));
    await tester.pumpAndSettle();
    expect(adapter.movementPostCount, 2);

    // Retry: the OUT leg is already on the server, so only the IN leg
    // re-posts — reusing the same linking reference.
    await tester.tap(find.widgetWithText(FilledButton, 'Transfer Stock'));
    await tester.pumpAndSettle();
    expect(adapter.movementPostBodies.length, 3);
    expect(adapter.movementPostBodies[2], {
      'item_id': 1,
      'warehouse_id': 2,
      'quantity': 5,
      'movement_type': 'TRANSFER',
      'reference_doctype': 'TRANSFER',
      'reference_docno': 'SM-2026-0102',
      'remarks': 'Move to raw',
    });
    expect(find.textContaining('Transfer incomplete:'), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
  });

  testWidgets('movement detail fetches and reverses an adjustment', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToItems(tester, adapter: adapter);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Stock Movements'),
      ),
    );
    await tester.pumpAndSettle();

    // Double-tap the ADJUSTMENT row: the dialog fetches
    // GET /inventory/stock-movements/3 for fresh data.
    await tester.tap(find.text('SM-2026-0102'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('SM-2026-0102'));
    await tester.pumpAndSettle();

    expect(adapter.movementDetailFetchCount, 1);
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.widgetWithText(OutlinedButton, 'Reverse Adjustment'),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.widgetWithText(OutlinedButton, 'Reverse Adjustment'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Reverse Adjustment'),
      ),
    );
    await tester.pumpAndSettle();

    // The compensating movement: inverse quantity, linked to the original
    // via reference_docno.
    expect(adapter.movementPostCount, 1);
    expect(adapter.lastMovementPostBody, {
      'item_id': 4,
      'warehouse_id': 1,
      'quantity': 10.0,
      'movement_type': 'ADJUSTMENT',
      'remarks': 'Reverse of SM-2026-0102',
      'reference_doctype': 'ADJUSTMENT',
      'reference_docno': 'SM-2026-0102',
    });
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Adjustment reversed'), findsOneWidget);
  });

  testWidgets('movement detail hides reverse for non-adjustments', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToItems(tester, adapter: adapter);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Stock Movements'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('SM-2026-0100'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('SM-2026-0100'));
    await tester.pumpAndSettle();

    expect(adapter.movementDetailFetchCount, 1);
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.widgetWithText(OutlinedButton, 'Reverse Adjustment'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.widgetWithText(FilledButton, 'Close'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('movement reversal surfaces the server rejection', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter()..rejectMovementCreate = true;
    await bootToItems(tester, adapter: adapter);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Stock Movements'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('SM-2026-0102'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('SM-2026-0102'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.widgetWithText(OutlinedButton, 'Reverse Adjustment'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Reverse Adjustment'),
      ),
    );
    await tester.pumpAndSettle();

    // The 400 surfaces as an error toast; the dialog stays open.
    expect(adapter.movementPostCount, 1);
    expect(find.text('Insufficient stock for adjustment'), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
  });

  testWidgets('movement filter refetches by movement type', (tester) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToItems(tester, adapter: adapter);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Stock Movements'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('SM-2026-0100'), findsOneWidget);

    await tester.tap(find.byType(SearchableSelect<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adjustment').last);
    await tester.pumpAndSettle();

    // The list refetched with the movement_type query param and now shows
    // only the adjustment row.
    expect(adapter.lastMovementQuery, {'movement_type': 'ADJUSTMENT'});
    expect(find.text('SM-2026-0102'), findsOneWidget);
    expect(find.text('SM-2026-0100'), findsNothing);
    expect(find.text('SM-2026-0101'), findsNothing);
  });

  testWidgets('movement filter resets to all movements', (tester) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToItems(tester, adapter: adapter);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Stock Movements'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SearchableSelect<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adjustment').last);
    await tester.pumpAndSettle();
    expect(adapter.lastMovementQuery, {'movement_type': 'ADJUSTMENT'});

    // Back to All — the refetch drops the query param.
    await tester.tap(find.byType(SearchableSelect<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All Movements').last);
    await tester.pumpAndSettle();

    expect(adapter.lastMovementQuery, isNot(contains('movement_type')));
    expect(find.text('SM-2026-0100'), findsOneWidget);
    expect(find.text('SM-2026-0101'), findsOneWidget);
    expect(find.text('SM-2026-0102'), findsOneWidget);
  });

  testWidgets('transfer IN detail links to the OUT leg and opens it', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToItems(tester, adapter: adapter);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Stock Movements'),
      ),
    );
    await tester.pumpAndSettle();

    // The IN leg's reference_docno names the OUT leg's movement number.
    await tester.tap(find.text('SM-2026-0104'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('SM-2026-0104'));
    await tester.pumpAndSettle();
    expect(adapter.movementDetailFetchCount, 1);
    expect(find.text('Linked Movement: SM-2026-0103'), findsOneWidget);

    // Tapping the link opens the counterpart's detail.
    await tester.tap(find.text('Linked Movement: SM-2026-0103'));
    await tester.pumpAndSettle();
    expect(adapter.movementDetailFetchCount, 2);
    expect(
      find.descendant(
        of: find.byType(Dialog).last,
        matching: find.text('SM-2026-0103'),
      ),
      findsWidgets,
    );
  });

  testWidgets('transfer OUT detail links back to the IN leg', (tester) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToItems(tester, adapter: adapter);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Stock Movements'),
      ),
    );
    await tester.pumpAndSettle();

    // The OUT leg has no reference; the IN leg names its number, so the
    // reverse match surfaces the link. 'SM-2026-0103' also appears in the
    // IN row's Reference cell — the No-column cell is the first match.
    await tester.tap(find.text('SM-2026-0103').first);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('SM-2026-0103').first);
    await tester.pumpAndSettle();

    expect(find.text('Linked Movement: SM-2026-0104'), findsOneWidget);
  });

  testWidgets('non-transfer movement detail shows no linked movement', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToItems(tester, adapter: adapter);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Stock Movements'),
      ),
    );
    await tester.pumpAndSettle();

    // The purchase reference (PUR-2026-001) is a document number, never a
    // movement number — nothing to link.
    await tester.tap(find.text('SM-2026-0100'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('SM-2026-0100'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Linked Movement'), findsNothing);
  });

  // Production module (PORTING.md §13) — runs grid + detail + record
  // form; BOM list + detail + create form.
  testWidgets('production runs grid renders the bare-endpoint rows', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToProduction(tester, adapter);

    expect(find.text('PROD-2026-0044'), findsOneWidget);
    expect(find.text('1.5 Ton Split AC Carton Box'), findsOneWidget);
    expect(find.text('BATCH-26-PRD-0044'), findsOneWidget);
    expect(find.text('New Production'), findsOneWidget);
    // Sidebar link is branded "Manufacturing"; the app bar and module
    // tab keep the feature name "Production" (only the menu link
    // changed).
    expect(find.text('Manufacturing'), findsOneWidget);
    expect(find.text('Production'), findsNWidgets(2));
  });

  testWidgets('production form has no editable input lines (BOM only)', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToProduction(tester, adapter);

    await tester.tap(find.widgetWithText(FilledButton, 'New Production'));
    await tester.pumpAndSettle();

    // Exactly the four fixed pickers — no per-material line rows.
    expect(find.byType(SearchableSelect<int>), findsNWidgets(4));
    expect(find.text('Add Input'), findsNothing);
    // The availability table appears only after a BOM is picked.
    expect(find.byType(DataTable), findsNothing);
    expect(find.text('Available'), findsNothing);
    // Hint while no BOM is selected.
    expect(
      find.text('Select a BOM \u2014 its material lines appear here.'),
      findsOneWidget,
    );
  });

  testWidgets('production detail double-tap fetches and shows inputs', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToProduction(tester, adapter);

    await tester.tap(find.text('PROD-2026-0044'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('PROD-2026-0044'));
    await tester.pumpAndSettle();

    expect(adapter.productionDetailFetchCount, 1);
    expect(find.text('Production Details'), findsOneWidget);
    // The raw-material input line from the fake detail.
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('RM002 — Bolt'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Karkhano Warehouse'),
      ),
      findsWidgets,
    );
  });

  testWidgets('record production: BOM auto-scales lines and posts', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToProduction(tester, adapter);

    await tester.tap(find.widgetWithText(FilledButton, 'New Production'));
    await tester.pumpAndSettle();

    // Output item = FG001 (Widget A) — the BOM's finished item.
    await tester.tap(find.byType(SearchableSelect<int>).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FG001 — Widget A').last);
    await tester.pumpAndSettle();

    // Output quantity 2, finished-goods warehouse Main Warehouse.
    await tester.enterText(find.byType(TextFormField).at(0), '2');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SearchableSelect<int>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Main Warehouse').last);
    await tester.pumpAndSettle();

    // Pick BOM-2026-0001 → detail fetched (GET /boms/1) → lines
    // auto-scaled to 2 × per-batch quantities (6 × Bolt, 4 × RM A).
    expect(adapter.bomDetailFetchCount, 0);
    await tester.tap(find.byType(SearchableSelect<int>).at(3));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BOM-2026-0001 — Widget A').last);
    await tester.pumpAndSettle();
    expect(adapter.bomDetailFetchCount, 1);
    expect(find.text('RM002 — Bolt'), findsOneWidget);
    expect(find.text('RM001 — Raw Material A'), findsOneWidget);

    // The inputs render as a read-only availability table (no editable
    // lines, no "Add Input"): scaled 2× (6 × Bolt, 4 × RM A) with the
    // stock available from the BOM detail join.
    expect(find.text('Add Input'), findsNothing);
    final table = find.byType(DataTable);
    expect(table, findsOneWidget);
    expect(find.text('Available'), findsOneWidget);
    expect(
      find.descendant(of: table, matching: find.text('6')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: table, matching: find.text('4')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: table, matching: find.text('120')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: table, matching: find.text('30')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: table, matching: find.text('box')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: table, matching: find.text('kg')),
      findsOneWidget,
    );

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final body = adapter.lastProductionPostBody!;
    expect(body['output_item_id'], 1);
    expect(body['output_quantity'], 2);
    expect(body['warehouse_id'], 1);
    expect((body['production_date'] as String).length, 10);
    expect((body['bom_id'] as int), 1);
    expect(body['overhead_cost'], 0);
    final items = body['input_items'] as List;
    expect(items, hasLength(2));
    expect((items[0] as Map)['item_id'], 2);
    expect((items[0] as Map)['quantity'], 6);
    expect((items[1] as Map)['item_id'], 4);
    expect((items[1] as Map)['quantity'], 4);
    expect(find.text('Production recorded'), findsOneWidget);
    expect(find.text('New Production'), findsOneWidget);
  });

  testWidgets('record production validates before posting', (tester) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToProduction(tester, adapter);

    await tester.tap(find.widgetWithText(FilledButton, 'New Production'));
    await tester.pumpAndSettle();
    // Output quantity missing → the required validator blocks save.
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(adapter.lastProductionPostBody, isNull);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Required'), findsWidgets);
    // A BOM is now mandatory — the inputs can't be typed by hand.
    expect(
      find.text('Select a BOM to load its material inputs.'),
      findsWidgets,
    );
  });

  testWidgets('production detail delete confirms and refetches the list', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToProduction(tester, adapter);

    await tester.tap(find.text('PROD-2026-0044'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('PROD-2026-0044'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(adapter.productionDeleteCount, 1);
    expect(find.text('Production deleted'), findsOneWidget);
    // List refetch after the delete returns an empty array.
    expect(find.text('PROD-2026-0044'), findsNothing);
  });

  testWidgets('BOM tab lists the BOMs and opens the detail', (tester) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToProduction(tester, adapter);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('BOM'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('BOM-2026-0001'), findsOneWidget);
    expect(find.text('Box BOM'), findsOneWidget);
    expect(find.text('Widget A'), findsOneWidget);

    await tester.tap(find.text('BOM-2026-0001'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('BOM-2026-0001'));
    await tester.pumpAndSettle();

    expect(adapter.bomDetailFetchCount, 1);
    expect(find.text('Bill of Materials'), findsOneWidget);
    // Material lines + line costs from the fake detail.
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('RM002 — Bolt'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('RM001 — Raw Material A'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('BOM create posts the new bill of materials', (tester) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToProduction(tester, adapter);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('BOM'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'New BOM'));
    await tester.pumpAndSettle();

    // BOM name + batch quantity.
    await tester.enterText(find.byType(TextFormField).at(0), 'Test BOM');
    await tester.enterText(find.byType(TextFormField).at(1), '5');

    // Finished item picker.
    await tester.tap(find.byType(SearchableSelect<int>).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FG001 — Widget A').last);
    await tester.pumpAndSettle();

    // One material line (the form starts with one empty row): Bolt × 3.
    await tester.tap(find.byType(SearchableSelect<int>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RM002 — Bolt').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(3), '3');

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final body = adapter.lastBomPostBody!;
    expect(body['bom_name'], 'Test BOM');
    expect(body['finished_item_id'], 1);
    expect(body['quantity'], 5.0);
    expect(body['is_active'], 0);
    final items = body['items'] as List;
    expect(items, hasLength(1));
    expect((items[0] as Map)['item_id'], 2);
    expect((items[0] as Map)['quantity'], 3);
    expect(find.text('BOM saved'), findsOneWidget);
  });

  testWidgets('forecast dashboard renders stats, alerts and top growing', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToForecasts(tester);

    // Stat cards from the fake /forecasts/dashboard summary. The value
    // '8' also appears in the accuracy tab (sampleSize), kept alive by
    // the shell's IndexedStack — findsWidgets covers both.
    expect(find.text('Tracked Items'), findsOneWidget);
    expect(find.text('8'), findsWidgets);
    expect(find.text('Need Restock'), findsOneWidget);
    expect(find.text('Critical Alerts'), findsOneWidget);
    expect(find.text('74%'), findsOneWidget);

    // Alert cards: critical badge + stock-vs-predicted line.
    expect(find.text('Widget A'), findsWidgets);
    expect(find.text('Critical'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);

    // Top-growing list with the trend badge. The demand grid (kept alive
    // by the shell's IndexedStack) shows the same 42% value, so the text
    // finder matches both — findsWidgets covers it.
    expect(find.text('Top Growing Items'), findsOneWidget);
    expect(find.text('42%'), findsWidgets);
    expect(find.text('Gadget'), findsWidgets);
  });

  testWidgets('forecast demand grid renders rows and filters by category', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToForecasts(tester, adapter: adapter, tab: 1);

    // Demand grid rows from the fake endpoint — scoped to the PlutoGrid
    // because the dashboard tab (alive in the IndexedStack) also shows
    // Widget A and Bolt in its alerts list.
    final grid = find.byType(PlutoGrid);
    expect(find.descendant(of: grid, matching: find.text('Widget A')), findsOneWidget);
    expect(find.descendant(of: grid, matching: find.text('Bolt')), findsOneWidget);
    expect(find.descendant(of: grid, matching: find.text('FG001')), findsOneWidget);
    // Filter bar selects present.
    expect(find.text('All Categories'), findsOneWidget);
    expect(find.text('All Trends'), findsOneWidget);
    expect(find.text('All Status'), findsOneWidget);

    // Pick the Parts category — the demand endpoint refetches with the
    // category query and returns only the filtered row.
    await tester.tap(find.byType(SearchableSelect<String?>).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Parts').last);
    await tester.pumpAndSettle();

    expect(adapter.lastForecastDemandQuery?['category'], 'Parts');
    // Bolt (Raw category) disappears from the grid; Widget A stays.
    expect(find.descendant(of: grid, matching: find.text('Widget A')), findsOneWidget);
    expect(find.descendant(of: grid, matching: find.text('Bolt')), findsNothing);
  });

  testWidgets('forecast demand reset button clears active filters', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToForecasts(tester, adapter: adapter, tab: 1);

    // The reset button is hidden until a filter is active.
    expect(
      find.byKey(const ValueKey('forecast-reset-filters')),
      findsNothing,
    );

    // Apply the category filter, then reset.
    await tester.tap(find.byType(SearchableSelect<String?>).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Parts').last);
    await tester.pumpAndSettle();
    expect(adapter.lastForecastDemandQuery?['category'], 'Parts');

    await tester.tap(find.byKey(const ValueKey('forecast-reset-filters')));
    await tester.pumpAndSettle();

    // The refetch dropped the category; both rows are back and the
    // button hides again.
    expect(adapter.lastForecastDemandQuery?['category'], isNull);
    expect(
      find.byKey(const ValueKey('forecast-reset-filters')),
      findsNothing,
    );
    final grid = find.byType(PlutoGrid);
    expect(
      find.descendant(of: grid, matching: find.text('Widget A')),
      findsOneWidget,
    );
    expect(find.descendant(of: grid, matching: find.text('Bolt')), findsOneWidget);
  });

  testWidgets('forecast dashboard view all resets filters and opens the demand tab', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToForecasts(tester, adapter: adapter, tab: 1);

    // Leave a category filter active on the demand tab.
    await tester.tap(find.byType(SearchableSelect<String?>).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Parts').last);
    await tester.pumpAndSettle();
    expect(adapter.lastForecastDemandQuery?['category'], 'Parts');

    // Jump back to the dashboard tab (nav rail of the forecast shell).
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Dashboard'),
      ),
    );
    await tester.pumpAndSettle();

    // View All from the alerts header — clears the demand filters and
    // switches to the demand tab.
    await tester.tap(find.text('View All'));
    await tester.pumpAndSettle();

    expect(adapter.lastForecastDemandQuery?['category'], isNull);
    expect(
      tester
          .widget<NavigationBar>(find.byType(NavigationBar))
          .selectedIndex,
      1,
    );
  });

  testWidgets('forecast accuracy computes and posts to the server', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToForecasts(tester, adapter: adapter, tab: 3);

    // Stat cards computed from the fake /forecasts/accuracy payload.
    // (8.0 + 22.0) / 2 = 15.0.
    expect(find.text('Avg MAPE'), findsOneWidget);
    expect(find.text('15.0%'), findsOneWidget);
    expect(find.text('Items Tracked'), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);
    // The Best Model stat card and the table's model column both render
    // the underscore-free type.
    expect(find.text('linear regression'), findsNWidgets(2));
    expect(find.text('moving average'), findsOneWidget);

    // Compute Accuracy posts and shows the server message.
    await tester.tap(find.widgetWithText(FilledButton, 'Compute Accuracy'));
    await tester.pumpAndSettle();
    expect(adapter.computeAccuracyCount, 1);
    expect(find.text('Accuracy computed for 14 records'), findsOneWidget);

    // Let the screen's 5s auto-hide banner timer fire so no pending
    // timer outlives the test.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Accuracy computed for 14 records'), findsNothing);
  });

  testWidgets('integrations screen renders service cards with server status', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToIntegrations(tester);

    // All six service cards render with their display names.
    expect(find.text('Email (SendGrid)'), findsOneWidget);
    expect(find.text('SMS Notifications (Twilio)'), findsOneWidget);
    expect(find.text('Weather (Weatherstack)'), findsOneWidget);
    expect(find.text('Phone Validation (Numverify)'), findsOneWidget);
    expect(find.text('Currency Exchange (Fixer)'), findsOneWidget);
    expect(find.text('Tax Calculation (TaxJar)'), findsOneWidget);

    // Status strip reflects the bare GET body: email configured but
    // disabled; notifications enabled but unconfigured.
    expect(find.text('Configured'), findsOneWidget);
    expect(find.text('Not configured'), findsNWidgets(5));

    // The email card's switch is off (disabled) while notifications'
    // is on (enabled) — scoped to each card.
    final emailCard = find.ancestor(
      of: find.text('Email (SendGrid)'),
      matching: find.byType(Card),
    );
    final notificationsCard = find.ancestor(
      of: find.text('SMS Notifications (Twilio)'),
      matching: find.byType(Card),
    );
    expect(
      tester.widget<SwitchListTile>(
        find.descendant(
          of: emailCard,
          matching: find.byType(SwitchListTile),
        ),
      ).value,
      isFalse,
    );
    expect(
      tester.widget<SwitchListTile>(
        find.descendant(
          of: notificationsCard,
          matching: find.byType(SwitchListTile),
        ),
      ).value,
      isTrue,
    );
  });

  testWidgets('integrations screen posts a per-service update for changed fields', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToIntegrations(tester, adapter: adapter);

    // Enable email, type an API key, and save — only non-blank fields
    // travel with the PUT.
    final emailCard = find.ancestor(
      of: find.text('Email (SendGrid)'),
      matching: find.byType(Card),
    );
    await tester.tap(
      find.descendant(
        of: emailCard,
        matching: find.byType(SwitchListTile),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find
          .descendant(
            of: emailCard,
            matching: find.byType(TextFormField),
          )
          .first,
      'SG.abcdef123456',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: emailCard,
        matching: find.widgetWithText(FilledButton, 'Save'),
      ),
    );
    await tester.pumpAndSettle();

    expect(adapter.lastIntegrationPutService, 'email');
    expect(adapter.lastIntegrationPutBody, {
      'enabled': true,
      'apiKey': 'SG.abcdef123456',
    });
    expect(find.text('Integration settings saved'), findsOneWidget);
  });

  testWidgets('integrations screen surfaces a failed save', (tester) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter()..rejectIntegrationSave = true;
    await bootToIntegrations(tester, adapter: adapter);

    final weatherCard = find.ancestor(
      of: find.text('Weather (Weatherstack)'),
      matching: find.byType(Card),
    );
    await tester.enterText(
      find
          .descendant(
            of: weatherCard,
            matching: find.byType(TextFormField),
          )
          .first,
      'ws-key',
    );
    await tester.pumpAndSettle();
    // The weather card sits below the fold on the wide test surface —
    // scroll it into view before tapping Save.
    final weatherSave = find.descendant(
      of: weatherCard,
      matching: find.widgetWithText(FilledButton, 'Save'),
    );
    await tester.ensureVisible(weatherSave);
    await tester.pumpAndSettle();
    await tester.tap(weatherSave);
    await tester.pumpAndSettle();

    // The server's 400 message surfaces in the toast; the card keeps its
    // typed key (still dirty → Save stays enabled).
    expect(find.text('Invalid API key'), findsOneWidget);
  });

  testWidgets('employees screen renders the grid with server data', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToEmployees(tester);

    // Active list by default: Ali + Sana (Bilal is inactive and excluded).
    expect(find.text('EMP-001'), findsOneWidget);
    expect(find.text('Ali Khan'), findsOneWidget);
    expect(find.text('EMP-002'), findsOneWidget);
    expect(find.text('Sana Ahmed'), findsOneWidget);
    // Column headers from the localized grid.
    expect(find.text('Full Name'), findsOneWidget);
    expect(find.text('Department'), findsOneWidget);

    // Summary strip over the loaded rows: 2 employees, 2 active,
    // 45,000 + 35,000 = 80,000.
    expect(find.text('2 employees'), findsOneWidget);
    expect(find.text('2 Active'), findsOneWidget);
    expect(find.text('80,000.00'), findsOneWidget);

    // Status badges render for both rows.
    expect(
      find.descendant(
        of: find.byType(StatusBadge),
        matching: find.text('Active'),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('employees screen department filter sends the server param', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToEmployees(tester, adapter: adapter);

    // The department options come from the loaded page: Production, Sales.
    await tester.tap(find.byKey(const ValueKey('employee-department-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Production').last);
    await tester.pumpAndSettle();

    expect(adapter.lastEmployeesQuery?['department'], 'Production');
    expect(find.text('Ali Khan'), findsOneWidget);
    expect(find.text('Sana Ahmed'), findsNothing);
  });

  testWidgets('employees screen creates an employee through the form', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToEmployees(tester, adapter: adapter);

    await tester.tap(find.widgetWithText(FilledButton, 'Add Employee'));
    await tester.pumpAndSettle();

    // The create form fetches the next code and shows it read-only.
    expect(adapter.employeeNextCodeFetchCount, 1);
    expect(find.text('EMP-004'), findsOneWidget);

    // Fill the two required fields (First Name, Last Name).
    final dialogFields = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(dialogFields.at(1), 'Zain');
    await tester.enterText(dialogFields.at(2), 'Malik');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(adapter.lastEmployeePostBody?['first_name'], 'Zain');
    expect(adapter.lastEmployeePostBody?['last_name'], 'Malik');
    expect(adapter.lastEmployeePostBody?['is_active'], isTrue);
    expect(find.text('Employee created successfully'), findsOneWidget);
  });

  testWidgets('employees screen pays salary from the detail dialog', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToEmployees(tester, adapter: adapter);

    // Open the detail dialog, then use its header Pay Salary button
    // (the grid row menu's popup items aren't reliably tappable inside
    // the PlutoGrid overlay).
    await tester.tap(find.text('Ali Khan'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Ali Khan'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(Dialog).first,
        matching: find.widgetWithText(FilledButton, 'Pay Salary'),
      ),
    );
    await tester.pumpAndSettle();

    // The salary dialog stacks over the detail dialog — its subtitle
    // shows the same header text, so scope to the top dialog.
    expect(
      find.descendant(
        of: find.byType(Dialog).last,
        matching: find.text('EMP-001 · Ali Khan'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Pay Salary').last);
    await tester.pumpAndSettle();

    expect(adapter.salaryPayCount, 1);
    expect(adapter.lastSalaryPayBody?['amount'], 45000);
    expect(adapter.lastSalaryPayBody?['payment_method'], 'Bank Transfer');
    expect(find.text('Salary payment recorded'), findsOneWidget);
  });

  testWidgets('employees screen surfaces a failed salary pay', (tester) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter()..rejectSalaryPay = true;
    await bootToEmployees(tester, adapter: adapter);

    await tester.tap(find.text('Ali Khan'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Ali Khan'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(Dialog).first,
        matching: find.widgetWithText(FilledButton, 'Pay Salary'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Pay Salary').last);
    await tester.pumpAndSettle();

    // The 422 message surfaces in the salary dialog's banner; the salary
    // dialog stays open (stacked over the detail dialog).
    expect(find.text('Valid amount is required'), findsOneWidget);
    expect(find.byType(Dialog), findsNWidgets(2));
  });

  testWidgets('employees screen opens the detail with salary history and documents', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToEmployees(tester, adapter: adapter);

    // Double-tap the first row to open the detail dialog.
    await tester.tap(find.text('Ali Khan'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Ali Khan'));
    await tester.pumpAndSettle();

    expect(find.text('EMP-001 · Ali Khan'), findsOneWidget);
    expect(find.text('Operator · Production'), findsOneWidget);

    // Salary History tab shows the fetched payment row.
    await tester.tap(find.text('Salary History'));
    await tester.pumpAndSettle();
    expect(adapter.salaryHistoryFetchCount, greaterThanOrEqualTo(1));
    expect(find.text('REF-1'), findsOneWidget);

    // Documents tab lists the fetched document.
    await tester.tap(find.text('Documents'));
    await tester.pumpAndSettle();
    expect(find.text('CNIC Copy'), findsOneWidget);
    expect(find.text('ID · 42101-1234567-1'), findsOneWidget);
  });

  testWidgets('employees screen uploads a document through multipart', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToEmployees(tester, adapter: adapter);

    await tester.tap(find.text('Ali Khan'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Ali Khan'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Documents'));
    await tester.pumpAndSettle();

    // Stub the file_picker pick channel to return a PDF.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
          (call) async {
            if (call.method == 'custom') {
              return [
                {
                  'name': 'passport.pdf',
                  'path': '/tmp/passport.pdf',
                  'size': 2048,
                  'identifier': 'passport',
                  'bytes': Uint8List.fromList(List.filled(2048, 0)),
                },
              ];
            }
            return null;
          },
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
            null,
          ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Add Document'));
    await tester.pumpAndSettle();

    // Fill the required name and pick the file.
    await tester.enterText(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextFormField),
      ).first,
      'Passport Copy',
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Select File'));
    await tester.pumpAndSettle();
    expect(find.text('passport.pdf'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Document added successfully'), findsOneWidget);
    expect(adapter.lastDocumentPostHasFile, isTrue);
    expect(adapter.lastDocumentPostFileName, 'passport.pdf');
    expect(adapter.lastDocumentPostFields?['document_name'], 'Passport Copy');
  });

  testWidgets('employees screen surfaces a failed document upload', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter()..rejectDocumentUpload = true;
    await bootToEmployees(tester, adapter: adapter);

    await tester.tap(find.text('Ali Khan'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Ali Khan'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Documents'));
    await tester.pumpAndSettle();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
          (call) async {
            if (call.method == 'custom') {
              return [
                {
                  'name': 'passport.pdf',
                  'path': '/tmp/passport.pdf',
                  'size': 2048,
                  'identifier': 'passport',
                  'bytes': Uint8List.fromList(List.filled(2048, 0)),
                },
              ];
            }
            return null;
          },
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
            null,
          ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Add Document'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextFormField),
      ).first,
      'Passport Copy',
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Select File'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // The error surfaces in the upload dialog (which stays open on top
    // of the detail dialog — 2 Dialogs total).
    expect(find.text('File type text/x-custom is not allowed'), findsOneWidget);
    expect(find.byType(Dialog), findsNWidgets(2));
  });

  testWidgets('employees screen surfaces a failed list load', (tester) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter()..failEmployees = true;
    await bootToEmployees(tester, adapter: adapter);

    // The grid collapses into the error panel with the server message.
    expect(find.text('Failed to fetch employees'), findsOneWidget);
    expect(find.byType(PlutoGrid), findsNothing);
  });

  testWidgets('admin screen renders the users grid with server data', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToAdmin(tester);

    // 'admin' appears in both the username and role columns; 'Fawad'
    // shows in the grid row AND the app bar's signed-in user label.
    expect(find.text('admin'), findsNWidgets(2));
    expect(find.text('Fawad'), findsNWidgets(2));
    expect(find.text('sales1'), findsOneWidget);
    expect(find.text('bob'), findsOneWidget);
    expect(find.text('bob@minierp.com'), findsOneWidget);
    // Status badges: admin + sales1 active, bob inactive.
    expect(
      find.descendant(
        of: find.byType(StatusBadge),
        matching: find.text('Active'),
      ),
      findsNWidgets(2),
    );
    expect(
      find.descendant(
        of: find.byType(StatusBadge),
        matching: find.text('Inactive'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('admin screen roles tab renders roles with permission counts', (
    tester,
  ) async {
    useWideSurface(tester);
    await bootToAdmin(tester, tab: 1);

    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('Full system access'), findsOneWidget);
    expect(find.text('Manager'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('admin screen creates a user through the form dialog', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToAdmin(tester, adapter: adapter);

    await tester.tap(find.widgetWithText(FilledButton, 'New User'));
    await tester.pumpAndSettle();

    final dialogFields = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(dialogFields.at(0), 'zain');
    await tester.enterText(dialogFields.at(1), 'Zain Malik');
    await tester.enterText(dialogFields.at(2), 'zain@example.com');
    await tester.enterText(dialogFields.at(3), 'secret123');
    await tester.pumpAndSettle();

    // Pick the Manager role from the roles dropdown.
    await tester.tap(find.byType(SearchableSelect<Role>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manager').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(adapter.lastUserPostBody?['username'], 'zain');
    expect(adapter.lastUserPostBody?['email'], 'zain@example.com');
    expect(adapter.lastUserPostBody?['full_name'], 'Zain Malik');
    expect(adapter.lastUserPostBody?['role_id'], 3);
    expect(adapter.lastUserPostBody?['password'], 'secret123');
    expect(find.text('User created successfully'), findsOneWidget);
  });

  testWidgets('admin screen surfaces a failed user create', (tester) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter()..rejectUserCreate = true;
    await bootToAdmin(tester, adapter: adapter);

    await tester.tap(find.widgetWithText(FilledButton, 'New User'));
    await tester.pumpAndSettle();
    final dialogFields = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(dialogFields.at(0), 'zain');
    await tester.enterText(dialogFields.at(1), 'Zain Malik');
    await tester.enterText(dialogFields.at(2), 'zain@example.com');
    await tester.enterText(dialogFields.at(3), 'secret123');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SearchableSelect<Role>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manager').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // The 409 message surfaces in the banner; the dialog stays open.
    expect(find.text('Username already exists'), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
  });

  testWidgets('admin screen toggles a user status through the row menu', (
    tester,
  ) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToAdmin(tester, adapter: adapter);

    // Row menu on the second row (sales1, id 2) — the admin row is the
    // current user, so its status/delete actions are disabled.
    // The popup menu opens over the grid. (Tapping popup items inside
    // PlutoGrid's overlay isn't reliable in the test harness — the grid
    // rebuilds and closes the popup — so the toggle PUT itself is
    // asserted in the repository tests; here we assert the menu renders
    // the status action for a non-self row.)
    await tester.tap(find.byIcon(Icons.more_vert).at(1));
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      find.widgetWithText(PopupMenuItem<String>, 'Deactivate'),
      findsOneWidget,
    );

    // The admin row is the signed-in user (id 1): its status and delete
    // items render but are disabled (self-actions are server-guarded too).
    // Escape closes the first popup (the overlay barrier doesn't take
    // outside taps in the PlutoGrid harness).
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pump(const Duration(milliseconds: 350));
    final selfDeactivate = tester.widget<PopupMenuItem<String>>(
      find.widgetWithText(PopupMenuItem<String>, 'Deactivate'),
    );
    expect(selfDeactivate.enabled, isFalse);
    expect(
      find.widgetWithText(PopupMenuItem<String>, 'Reset Password'),
      findsOneWidget,
    );
  });

  testWidgets('admin screen saves role permission changes', (tester) async {
    useWideSurface(tester);
    final adapter = _AuthFakeAdapter();
    await bootToAdmin(tester, adapter: adapter, tab: 1);

    // Double-tap the Manager row to open the permissions editor
    // (IndexedStack keeps the hidden Users grid alive, so its row icons
    // are also findable — the row text scopes to the Roles grid).
    await tester.tap(find.text('Manager'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Manager'));
    await tester.pumpAndSettle();
    expect(adapter.rolePermissionsFetchCount, greaterThanOrEqualTo(1));

    // Assigned by default: View Users + View Invoices (ids 1, 3). Toggle
    // the second tile (Create Users, id 2) on.
    await tester.tap(find.byType(CheckboxListTile).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(
      adapter.lastRolePermissionsIds,
      containsAll(<int>[1, 2, 3]),
    );
    expect(find.text('Permissions updated'), findsOneWidget);
  });
}
