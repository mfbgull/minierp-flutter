// Unit tests for the stock-ledger CSV export — the pure
// `buildStockLedgerCsv` / `stockLedgerBalances` helpers (the save helper
// is platform-interactive and covered by the widget tests via a mocked
// FilePicker channel).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:minierp_app/core/utils/csv_export.dart';
import 'package:minierp_app/data/models/purchase_order.dart';
import 'package:minierp_app/data/models/purchase_return.dart';
import 'package:minierp_app/data/models/quotation.dart';
import 'package:minierp_app/data/models/sales_order.dart';
import 'package:minierp_app/data/models/bom.dart' show Bom;
import 'package:minierp_app/data/models/customer.dart';
import 'package:minierp_app/data/models/expense.dart';
import 'package:minierp_app/data/models/invoice.dart';
import 'package:minierp_app/data/models/production.dart' show Production;
import 'package:minierp_app/data/models/report.dart';
import 'package:minierp_app/data/models/sales_return.dart';
import 'package:minierp_app/data/models/stock_movement.dart';
import 'package:minierp_app/l10n/app_localizations.dart';

StockMovement _movement({
  required int id,
  required String type,
  required num quantity,
  required String date,
  String? ref,
  String? warehouseCode,
}) => StockMovement(
  id: id,
  movementNo: 'SM-2026-$id',
  itemId: 1,
  warehouseId: 1,
  movementType: type,
  quantity: quantity,
  unitCost: null,
  referenceDocType: null,
  referenceDocNo: ref,
  remarks: null,
  movementDate: date,
  createdBy: 1,
  createdAt: '$date 09:00:00',
  itemCode: null,
  itemName: null,
  unitOfMeasure: null,
  warehouseCode: warehouseCode,
  warehouseName: null,
  createdByName: null,
);

void main() {
  // The builder uses intl DateFormat for the Date column — initialize the
  // en locale so dates render deterministically (same as the app does on
  // startup).
  setUpAll(() async {
    await initializeDateFormatting('en');
  });

  final movements = [
    // Newest-first, as the API returns.
    _movement(
      id: 3,
      type: 'TRANSFER',
      quantity: 2,
      date: '2026-02-03',
      warehouseCode: 'WH-RAW',
    ),
    _movement(
      id: 2,
      type: 'SALE',
      quantity: -3,
      date: '2026-02-02',
      ref: 'INV-2026-001',
      warehouseCode: 'WH-MAIN',
    ),
    _movement(
      id: 1,
      type: 'PURCHASE',
      quantity: 10,
      date: '2026-02-01',
      ref: 'PUR-2026-001',
      warehouseCode: 'WH-MAIN',
    ),
  ];

  test(
    'stockLedgerBalances walks oldest-first to the balance after each movement',
    () {
      final balances = stockLedgerBalances(movements);
      // PURCHASE +10 → 10; SALE -3 → 7; TRANSFER +2 → 9.
      expect(balances[1], 10);
      expect(balances[2], 7);
      expect(balances[3], 9);
    },
  );

  test(
    'buildStockLedgerCsv emits the header and the rows with in/out/balance',
    () {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final csv = buildStockLedgerCsv(l10n, movements);
      final lines = csv.trim().split('\r\n');

      expect(lines.length, 4);
      expect(lines.first, contains('Date'));
      expect(lines.first, contains('Type'));
      expect(lines.first, contains('Reference'));
      expect(lines.first, contains('Warehouse'));
      expect(lines.first, contains('In'));
      expect(lines.first, contains('Out'));
      expect(lines.first, contains('Balance'));

      // Transfer row: In=2, Balance=9.
      expect(lines[1], contains('Transfer'));
      expect(lines[1], contains('WH-RAW'));
      expect(lines[1], contains('2'));
      expect(lines[1], contains('9'));
      // Sale row: Out=3, Balance=7.
      expect(lines[2], contains('Sale'));
      expect(lines[2], contains('INV-2026-001'));
      expect(lines[2], contains('3'));
      expect(lines[2], contains('7'));
      // Purchase row: In=10, Balance=10.
      expect(lines[3], contains('Purchase'));
      expect(lines[3], contains('PUR-2026-001'));
      expect(lines[3], contains('10'));
    },
  );

  test('buildStockLedgerCsv on an empty list emits just the header', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final csv = buildStockLedgerCsv(l10n, const []);
    expect(csv.trim().split('\r\n'), hasLength(1));
    expect(csv, contains('Balance'));
  });

  group('sanitizeCsvCell', () {
    test('strips leading formula characters = + - @', () {
      expect(sanitizeCsvCell('=SUM(A1:A2)'), 'SUM(A1:A2)');
      expect(sanitizeCsvCell('+cmd'), 'cmd');
      expect(sanitizeCsvCell('-2+3'), '2+3');
      expect(sanitizeCsvCell('@HYPERLINK("x")'), 'HYPERLINK("x")');
    });

    test('strips repeated leading formula characters', () {
      expect(sanitizeCsvCell('==+@nested'), 'nested');
      expect(sanitizeCsvCell('=-@'), '');
    });

    test('leaves normal and empty values unchanged', () {
      expect(sanitizeCsvCell('SM-2026-0018'), 'SM-2026-0018');
      expect(sanitizeCsvCell('Raw Material A'), 'Raw Material A');
      expect(sanitizeCsvCell(''), '');
      expect(sanitizeCsvCell('—'), '—');
      // Embedded (non-leading) formula chars are preserved.
      expect(sanitizeCsvCell('INV+2026=001'), 'INV+2026=001');
    });
  });

  test('buildStockLedgerCsv sanitizes reference and warehouse cells', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final evil = _movement(
      id: 4,
      type: 'PURCHASE',
      quantity: 5,
      date: '2026-02-04',
      ref: '=HYPERLINK("http://evil")',
      warehouseCode: '+WH-MAIN',
    );
    final csv = buildStockLedgerCsv(l10n, [evil]);

    expect(csv, isNot(contains('=Hyperlink')));
    expect(csv, contains('HYPERLINK'));
    expect(csv, isNot(contains('+WH-MAIN')));
    expect(csv, contains('WH-MAIN'));
  });

  test('buildInvoiceReturnsCsv sanitizes item/customer/remarks cells', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final evil = SalesReturn(
      id: 4,
      itemId: 1,
      itemName: '=cmd',
      warehouseId: 1,
      warehouseName: '@WH',
      quantity: 2,
      unitCost: 5,
      movementNo: 'SM-R-4',
      remarks: '=-1+1',
      returnDate: '2026-02-04',
      customerName: '+Acme',
    );
    final csv = buildInvoiceReturnsCsv(l10n, [evil]);

    expect(csv, isNot(contains('=cmd')));
    expect(csv, contains('cmd'));
    expect(csv, isNot(contains('@WH')));
    expect(csv, contains('WH'));
    expect(csv, isNot(contains('+Acme')));
    expect(csv, contains('Acme'));
    expect(csv, isNot(contains('=-1+1')));
    expect(csv, contains('1+1')); // leading '-' stripped, rest preserved
  });

  test('buildPurchaseReturnsCsv sanitizes return/type/source cells', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final evil = PurchaseReturn(
      id: 4,
      returnNo: '=cmd', // sanitized
      returnDate: '2026-02-04',
      sourceNo: '@SRC', // sanitized
      totalQty: -2,
      totalAmount: 10,
      returnType: 'PURCHASE_RETURN',
      warehouseId: 1,
      warehouseName: 'Main',
      status: 'POSTED',
    );
    final csv = buildPurchaseReturnsCsv(l10n, [evil]);

    expect(csv, isNot(contains('=cmd')));
    expect(csv, contains('cmd'));
    expect(csv, isNot(contains('@SRC')));
    expect(csv, contains('SRC'));
  });

  test('computed numeric cells keep their sign (no over-sanitization)', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    // Single SALE of -3 → balance -3; the Balance cell must keep the '-'
    // even though '-' is a formula character (it is computed, not
    // user-controlled).
    final csv = buildStockLedgerCsv(l10n, [
      _movement(id: 9, type: 'SALE', quantity: -3, date: '2026-02-09'),
    ]);
    expect(csv, contains('-3'));
  });

  test('buildSalesOrdersCsv emits the grid columns and sanitizes cells', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final csv = buildSalesOrdersCsv(l10n, [
      SalesOrder(
        id: 1,
        soNo: 'SO-2026-001',
        soDate: '2026-01-20',
        customerId: 1,
        customerName: 'Acme Corp',
        deliveryDate: '2026-02-01',
        status: 'Confirmed',
        totalAmount: 1500,
      ),
      SalesOrder(
        id: 2,
        soNo: '=HYPERLINK("x")', // sanitized
        soDate: '2026-01-25',
        customerId: 2,
        customerName: '+Beta Ltd', // sanitized
        status: 'Completed',
        totalAmount: 2500,
      ),
    ]);
    final lines = csv.trim().split('\r\n');

    expect(lines.length, 3);
    expect(lines.first, contains('SO #'));
    expect(lines.first, contains('Status'));
    expect(lines.first, contains('Total'));
    expect(lines.first, contains('Delivery'));

    expect(csv, contains('SO-2026-001'));
    expect(csv, contains('Acme Corp'));
    expect(csv, contains('Confirmed')); // localized status label
    expect(csv, contains('1,500.00'));
    // Formula characters stripped from user-controlled string cells.
    expect(csv, isNot(contains('=Hyperlink')));
    expect(csv, contains('HYPERLINK'));
    expect(csv, isNot(contains('+Beta Ltd')));
    expect(csv, contains('Beta Ltd'));
    expect(csv, contains('2,500.00'));
  });

  test('csvSuggestedName date-stamps the stem with a .csv suffix', () {
    final name = csvSuggestedName('sales-orders');
    expect(name, startsWith('sales-orders-'));
    expect(name, endsWith('.csv'));
    // <stem>-yyyy-mm-dd.csv
    expect(name, matches(RegExp(r'^sales-orders-\d{4}-\d{2}-\d{2}\.csv$')));
  });

  test('buildPurchaseOrdersCsv emits the grid columns and sanitizes cells', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final csv = buildPurchaseOrdersCsv(l10n, [
      PurchaseOrder(
        id: 1,
        poNo: 'PO-2026-001',
        poDate: '2026-01-20',
        supplierId: 1,
        supplierName: 'Alpha Traders',
        status: 'Draft',
        totalAmount: 1500,
        expectedDeliveryDate: '2026-02-01',
      ),
      PurchaseOrder(
        id: 2,
        poNo: '=HYPERLINK("x")', // sanitized
        poDate: '2026-01-25',
        supplierId: 2,
        supplierName: '+Beta Suppliers', // sanitized
        status: 'Completed',
        totalAmount: 2500,
      ),
    ]);
    final lines = csv.trim().split('\r\n');

    expect(lines.length, 3);
    expect(lines.first, contains('PO No'));
    expect(lines.first, contains('Supplier'));
    expect(lines.first, contains('Status'));
    expect(lines.first, contains('Total'));
    expect(lines.first, contains('Expected Delivery'));

    expect(csv, contains('PO-2026-001'));
    expect(csv, contains('Alpha Traders'));
    expect(csv, contains('Draft')); // localized status label
    expect(csv, contains('1,500.00'));
    // Formula characters stripped from user-controlled string cells.
    expect(csv, isNot(contains('=Hyperlink')));
    expect(csv, contains('HYPERLINK'));
    expect(csv, isNot(contains('+Beta Suppliers')));
    expect(csv, contains('Beta Suppliers'));
    expect(csv, contains('2,500.00'));
  });

  test('buildQuotationsCsv emits the grid columns and sanitizes cells', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final csv = buildQuotationsCsv(l10n, [
      Quotation(
        id: 1,
        quotationNo: 'QT-2026-001',
        quotationDate: '2026-01-18',
        customerId: 1,
        customerName: 'Acme Corp',
        expiryDate: '2026-02-18',
        status: 'Sent',
        totalAmount: 1200,
      ),
      Quotation(
        id: 2,
        quotationNo: '=HYPERLINK("x")', // sanitized
        quotationDate: '2026-01-22',
        customerId: 2,
        customerName: '+Beta Ltd', // sanitized
        status: 'Accepted',
        totalAmount: 900,
      ),
    ]);
    final lines = csv.trim().split('\r\n');

    expect(lines.length, 3);
    expect(lines.first, contains('Quotation #'));
    expect(lines.first, contains('Customer'));
    expect(lines.first, contains('Status'));
    expect(lines.first, contains('Total'));
    expect(lines.first, contains('Expiry'));

    expect(csv, contains('QT-2026-001'));
    expect(csv, contains('Acme Corp'));
    expect(csv, contains('Sent')); // localized status label
    expect(csv, contains('1,200.00'));
    // Formula characters stripped from user-controlled string cells.
    expect(csv, isNot(contains('=Hyperlink')));
    expect(csv, contains('HYPERLINK'));
    expect(csv, isNot(contains('+Beta Ltd')));
    expect(csv, contains('Beta Ltd'));
    expect(csv, contains('900.00'));
  });

  group('production exports', () {
    test('buildProductionsCsv emits grid columns and sanitizes cells', () {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final csv = buildProductionsCsv(l10n, [
        Production(
          id: 5,
          productionNo: 'PROD-2026-011',
          outputItemId: 1,
          outputQuantity: 25,
          warehouseId: 1,
          productionDate: '2026-03-01',
          remarks: 'Winter batch',
          overheadCost: 50,
          batchNo: 'BATCH-26-PRD-0011',
          unitCost: 120.5,
          totalMaterialCost: 2000,
          totalBatchCost: 3012.5,
          outputItemName: 'Finished Widget',
          outputUom: 'pcs',
          finishedGoodsWarehouseName: 'FG WH',
        ),
        Production(
          id: 6,
          productionNo: 'PROD-2026-012',
          outputItemId: 2,
          outputQuantity: 3,
          warehouseId: 2,
          productionDate: '2026-03-03',
        ),
      ]);
      final lines = csv.trim().split('\r\n');
      expect(lines.length, 3);
      expect(lines.first, contains('Production No'));
      expect(lines.first, contains('Date'));
      expect(lines.first, contains('Output Item'));
      expect(lines.first, contains('Quantity'));
      expect(lines.first, contains('UOM'));
      expect(lines.first, contains('Finished Goods Warehouse'));
      expect(lines.first, contains('Unit Cost'));
      expect(lines.first, contains('Total Cost'));
      expect(lines.first, contains('Batch No'));
      expect(lines.first, contains('Remarks'));
      expect(csv, contains('PROD-2026-011'));
      expect(csv, contains('Finished Widget'));
      expect(csv, contains('120.50'));
      expect(csv, contains('3,012.50'));
      expect(csv, contains('BATCH-26-PRD-0011'));
      expect(csv, contains('Winter batch'));
      expect(csv, contains(',25,'));
    });

    test('buildBomsCsv emits BOM columns with sanitized names', () {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final csv = buildBomsCsv(l10n, [
        Bom(
          id: 1,
          bomNo: 'BOM-2026-001',
          bomName: '=Hyperlink("drop")', // sanitized
          finishedItemId: 1,
          finishedItemName: 'Widget +Kit', // sanitized
          quantity: 10,
          finishedUom: 'pcs',
          itemCount: 3,
          totalMaterialCost: 450.5,
          isActive: true,
        ),
        Bom(
          id: 2,
          bomNo: 'BOM-2026-002',
          bomName: 'KIT-2',
          finishedItemId: 2,
          finishedItemName: 'Gadget',
          quantity: 5,
          isActive: false,
        ),
      ]);
      final lines = csv.trim().split('\r\n');
      expect(lines.length, 3);
      expect(lines.first, contains('BOM No'));
      expect(lines.first, contains('BOM Name'));
      expect(lines.first, contains('Finished Item'));
      expect(lines.first, contains('Quantity'));
      expect(lines.first, contains('UOM'));
      expect(lines.first, contains('Materials'));
      expect(lines.first, contains('Material Cost'));
      expect(lines.first, contains('Status'));
      expect(csv, contains('BOM-2026-001'));
      expect(csv, isNot(contains('=BOM')));
      expect(csv, contains('BOM'));
      expect(csv, isNot(contains('+Widget Kit')));
      expect(csv, contains('Widget +Kit'));
      expect(csv, contains('450.50'));
      expect(csv, contains('Inactive')); // localized active/inactive label
      expect(csv, contains('Active'));
    });
  });

  test('buildInvoicesCsv emits the grid columns and sanitizes cells', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final csv = buildInvoicesCsv(l10n, [
      Invoice(
        id: 1,
        invoiceNo: 'INV-2026-440955',
        customerId: 1,
        customerName: 'Acme Corp',
        invoiceDate: '2026-05-22',
        status: 'Unpaid',
        totalAmount: 1500,
        paidAmount: 0,
        balanceAmount: 1500,
        createdByUsername: 'Fawad',
      ),
      Invoice(
        id: 2,
        invoiceNo: '=HYPERLINK("x")', // sanitized
        customerId: 2,
        customerName: '+Beta Ltd', // sanitized
        invoiceDate: '2026-05-10',
        status: 'Paid',
        totalAmount: 800,
        paidAmount: 800,
        balanceAmount: 0,
        createdByUsername: '+admin', // sanitized
      ),
    ]);
    final lines = csv.trim().split('\r\n');

    expect(lines.length, 3);
    expect(lines.first, contains('Invoice No'));
    expect(lines.first, contains('Customer'));
    expect(lines.first, contains('Status'));
    expect(lines.first, contains('Total'));
    expect(lines.first, contains('Paid'));
    expect(lines.first, contains('Due'));

    expect(csv, contains('INV-2026-440955'));
    expect(csv, contains('Acme Corp'));
    expect(csv, contains('Unpaid')); // localized status label
    expect(csv, contains('1,500.00'));
    // Formula characters stripped from user-controlled string cells.
    expect(csv, isNot(contains('=Hyperlink')));
    expect(csv, contains('HYPERLINK'));
    expect(csv, isNot(contains('+Beta Ltd')));
    expect(csv, contains('Beta Ltd'));
    expect(csv, isNot(contains('+admin')));
    expect(csv, contains('admin'));
    expect(csv, contains('800.00'));
  });

  test('buildCustomersCsv emits the grid columns and sanitizes cells', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final csv = buildCustomersCsv(l10n, [
      Customer(
        id: 1,
        customerCode: 'CUST001',
        customerName: 'Acme Corp',
        phone: '555-0101',
        email: 'a@acme.com',
        billingAddress: 'Gulhaji Plaza',
        creditLimit: 10000,
        currentBalance: 120.5,
        creditUtilizationPercent: 12,
        paymentTermsDays: 30,
        isActive: true,
      ),
      Customer(
        id: 2,
        customerCode: '=HYPERLINK("x")', // sanitized
        customerName: '+Beta Ltd', // sanitized
        phone: '555-0102',
        email: 'b@beta.com',
        currentBalance: 0,
        isActive: false,
      ),
    ]);
    final lines = csv.trim().split('\r\n');

    expect(lines.length, 3);
    expect(lines.first, contains('Customer Code'));
    expect(lines.first, contains('Customer Name'));
    expect(lines.first, contains('Phone'));
    expect(lines.first, contains('Email'));
    expect(lines.first, contains('Credit Limit'));
    expect(lines.first, contains('Current Balance'));
    expect(lines.first, contains('Credit Utilization'));
    expect(lines.first, contains('Payment Terms'));
    expect(lines.first, contains('Status'));

    expect(csv, contains('CUST001'));
    expect(csv, contains('Acme Corp'));
    expect(csv, contains('120.50'));
    expect(csv, contains('Active')); // localized status label
    // Formula characters stripped from user-controlled string cells.
    expect(csv, isNot(contains('=Hyperlink')));
    expect(csv, contains('HYPERLINK'));
    expect(csv, isNot(contains('+Beta Ltd')));
    expect(csv, contains('Beta Ltd'));
    expect(csv, contains('Inactive'));
  });

  test('buildExpensesCsv emits the grid columns and sanitizes cells', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final csv = buildExpensesCsv(l10n, [
      Expense(
        id: 1,
        expenseNo: 'EXP-2605-0001',
        expenseCategory: 'Fuel',
        description: 'Generator diesel',
        amount: 1000,
        expenseDate: '2026-05-22',
        paymentMethod: 'Cash',
        referenceNo: '34f3f33',
        vendorName: 'abc',
        project: null,
        status: 'Approved',
        createdByName: 'Fawad',
      ),
      Expense(
        id: 2,
        expenseNo: '=HYPERLINK("x")', // sanitized
        expenseCategory: '+Rent', // sanitized
        description: '@May rent', // sanitized
        amount: 500.5,
        expenseDate: '2026-05-23',
        paymentMethod: 'Bank Transfer',
        status: 'Draft',
      ),
    ]);
    final lines = csv.trim().split('\r\n');

    expect(lines.length, 3);
    expect(lines.first, contains('Expense No'));
    expect(lines.first, contains('Category'));
    expect(lines.first, contains('Description'));
    expect(lines.first, contains('Vendor'));
    expect(lines.first, contains('Reference No'));
    expect(lines.first, contains('Payment Method'));
    expect(lines.first, contains('Project'));
    expect(lines.first, contains('Amount'));
    expect(lines.first, contains('Status'));
    expect(lines.first, contains('Created By'));

    expect(csv, contains('EXP-2605-0001'));
    expect(csv, contains('Generator diesel'));
    expect(csv, contains('Approved')); // localized status label
    expect(csv, contains('1,000.00'));
    // Formula characters stripped from user-controlled string cells.
    expect(csv, isNot(contains('=Hyperlink')));
    expect(csv, contains('HYPERLINK'));
    expect(csv, isNot(contains('+Rent')));
    expect(csv, contains('Rent'));
    expect(csv, isNot(contains('@May rent')));
    expect(csv, contains('May rent'));
    expect(csv, contains('500.50'));
  });

  test('buildArAgingCsv emits the aging columns and sanitizes cells', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final csv = buildArAgingCsv(
      l10n,
      ArAgingReport(
        asOfDate: '2026-08-08',
        buckets: [
          ArAgingBucket(
            customerName: '=Acme Corp', // sanitized
            customerCode: 'CUST001',
            totalOutstanding: 120.5,
            currentAmount: 50,
            days1_30: 70.5,
            days31_60: 0,
            days61_90: 0,
            daysOver90: 0,
          ),
          ArAgingBucket(
            customerName: 'Beta Ltd',
            customerCode: '+CUST002', // sanitized
            totalOutstanding: 300,
            currentAmount: 0,
            days1_30: 0,
            days31_60: 100,
            days61_90: 0,
            daysOver90: 200,
          ),
        ],
        summary: const ArAgingSummary(
          totalReceivables: 420.5,
          currentAmount: 50,
          total1_30: 70.5,
          total31_60: 100,
          total61_90: 0,
          totalOver90: 200,
        ),
      ),
    );
    final lines = csv.trim().split('\r\n');

    expect(lines.length, 3);
    expect(lines.first, contains('Customer'));
    expect(lines.first, contains('Customer Code'));
    expect(lines.first, contains('Total Outstanding'));
    expect(lines.first, contains('Current'));
    expect(lines.first, contains('1-30 Days'));
    expect(lines.first, contains('90+ Days'));
    expect(csv, contains('Acme Corp')); // formula char stripped
    expect(csv, isNot(contains('=Acme Corp')));
    expect(csv, contains('CUST002'));
    expect(csv, isNot(contains('+CUST002')));
    // Per-bucket row values (the summary strip totals are not part of
    // the grid export).
    expect(csv, contains('120.50')); // Acme total outstanding
    expect(csv, contains('70.50')); // Acme 1-30 bucket
    expect(csv, contains('200.00')); // Beta 90+ bucket
  });
  test('buildDsoCsv emits the metric/value table', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final csv = buildDsoCsv(
      l10n,
      DSOMetric(
        dso: 18.65,
        avgReceivables: 50000,
        totalCreditSales: 101895,
        totalSales: 101895,
        totalAR: 50000,
        avgInvoiceValue: 33965,
        startDate: '2026-07-01',
        endDate: '2026-08-08',
      ),
    );
    final lines = csv.trim().split('\r\n');

    expect(lines.length, 6);
    expect(lines.first, contains('Metric'));
    expect(lines.first, contains('Value'));
    expect(csv, contains('Days Sales Outstanding'));
    expect(csv, contains('18.65'));
    expect(csv, contains('Total AR'));
    expect(csv, contains('50,000.00'));
    expect(csv, contains('Total Sales'));
    expect(csv, contains('101,895.00'));
  });

  test('buildCashFlowCsv emits the inflow/outflow/net table', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final csv = buildCashFlowCsv(
      l10n,
      CashFlowReport(
        startDate: '2026-07-01',
        endDate: '2026-08-08',
        totalInflow: 52895,
        totalOutflow: 1000,
        netCashFlow: 51895,
      ),
    );
    final lines = csv.trim().split('\r\n');

    expect(lines.length, 4);
    expect(lines.first, contains('Metric'));
    expect(lines.first, contains('Value'));
    expect(csv, contains('Total Cash Inflow'));
    expect(csv, contains('52,895.00'));
    expect(csv, contains('Total Cash Outflow'));
    expect(csv, contains('1,000.00'));
    expect(csv, contains('Net Cash Flow'));
    expect(csv, contains('51,895.00'));
  });

  test('buildProfitLossCsv emits the P&L metric table with margins', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final csv = buildProfitLossCsv(
      l10n,
      ProfitLossReport(
        startDate: '2026-07-01',
        endDate: '2026-08-08',
        totalRevenue: 101895,
        totalCogs: 271315.5,
        grossProfit: -169420.5,
        expenses: const [ProfitLossExpense(category: 'Marketing', total: 2000)],
        totalExpenses: 2000,
        netProfit: -171420.5,
        grossProfitMargin: -166.27,
        netProfitMargin: -168.23,
      ),
    );
    final lines = csv.trim().split('\r\n');

    expect(lines.length, 8);
    expect(lines.first, contains('Metric'));
    expect(lines.first, contains('Value'));
    expect(csv, contains('Total Revenue'));
    expect(csv, contains('101,895.00'));
    expect(csv, contains('Cost of Goods Sold (COGS)'));
    expect(csv, contains('271,315.50'));
    expect(csv, contains('Gross Profit'));
    expect(csv, contains('-169,420.50'));
    expect(csv, contains('Net Profit'));
    expect(csv, contains('-166.27%')); // gross margin value
    expect(csv, contains('-168.23%')); // net margin value
  });


  test('buildTopDebtorsCsv emits debtor columns', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final csv = buildTopDebtorsCsv(l10n, [
      TopDebtorRow(
        customerName: '=Awees Super Store', // sanitized
        customerCode: 'CUST-006',
        totalOutstanding: 50000,
        outstandingBalance: 50000,
        totalInvoiced: 50000,
        invoiceCount: 1,
      ),
      TopDebtorRow(
        customerName: 'Gulhaji Plaza',
        customerCode: 'CUST-002',
        totalOutstanding: 18000,
        outstandingBalance: 18000,
        totalInvoiced: 70000,
        invoiceCount: 1,
      ),
    ]);
    final lines = csv.trim().split('\r\n');

    expect(lines.length, 3);
    expect(lines.first, contains('Customer'));
    expect(lines.first, contains('Customer Code'));
    expect(lines.first, contains('Total Outstanding'));
    expect(lines.first, contains('Total Invoiced'));
    expect(lines.first, contains('Invoice Count'));
    expect(csv, contains('Awees Super Store'));
    expect(csv, isNot(contains('=Awees Super Store')));
    expect(csv, contains('50,000.00'));
    expect(csv, contains('Gulhaji Plaza'));
  });
}
