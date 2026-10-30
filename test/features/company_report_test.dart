// Company Report tests — DTO parsing plus mounted-screen behaviour:
// card→route, all three views, archived company selection, paging,
// retry and the period transaction drilldown.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:minierp_app/data/models/company_report.dart';
import 'package:minierp_app/data/models/item.dart' show ItemCompany;
import 'package:minierp_app/features/reports/company_report_screen.dart';
import 'package:minierp_app/features/reports/report_providers.dart';
import 'package:minierp_app/features/reports/reports_dashboard_screen.dart';
import 'package:minierp_app/l10n/app_localizations.dart';
import 'package:minierp_app/widgets/date_range_picker.dart'
    show DateRangeFilter;

const _companies = [
  ItemCompany(id: 1, name: 'Acme Co', productCount: 2),
  ItemCompany(id: 2, name: 'Beta Co', productCount: 1),
  ItemCompany(id: 3, name: 'Old Co', isActive: false, productCount: 1),
];

CompanyStockReport _stock(int companyId, {int page = 1}) {
  final name = switch (companyId) {
    1 => 'Acme Stock',
    2 => 'Beta Stock',
    _ => 'Old Stock',
  };
  final value = switch (companyId) {
    1 => 500,
    2 => 700,
    _ => 900,
  };
  return CompanyStockReport(
    companyId: companyId,
    asOf: '2026-10-29T10:30:00.000Z',
    valuationBasis: 'remaining_batch_cost',
    rows: [
      CompanyStockRow(
        itemId: companyId * 10,
        itemCode: 'CODE-$companyId',
        itemName: page == 1 ? name : '${name}_Page$page',
        unitOfMeasure: 'Nos',
        quantity: 5,
        stockValue: value,
      ),
    ],
    totalStockValue: value,
    quantitiesByUom: const {'Nos': 5},
    pagination: CompanyReportPagination(
      page: page,
      limit: 25,
      total: 2,
      totalPages: 2,
    ),
  );
}

CompanyPeriodReport _period(
  int companyId,
  CompanyReportView view,
  String startDate,
  String endDate,
  int page,
) {
  final purchases = view == CompanyReportView.purchases;
  final gross = companyId == 1
      ? (purchases ? 300 : 1000)
      : (purchases ? 400 : 2000);
  final returned = gross * 0.1;
  final net = gross - returned;
  final product = purchases ? 'Purchase Widget' : 'Sale Widget';
  final documentNo = purchases ? 'GRN-1' : 'INV-1';
  return CompanyPeriodReport(
    companyId: companyId,
    view: purchases ? 'purchases' : 'sales',
    startDate: startDate,
    endDate: endDate,
    amountBasis: 'tax_inclusive_after_discounts_before_restocking_fees',
    rows: [
      CompanyPeriodRow(
        itemId: companyId * 10,
        itemCode: 'CODE-$companyId',
        itemName: product,
        unitOfMeasure: 'Nos',
        grossQuantity: 10,
        returnQuantity: 1,
        netQuantity: 9,
        grossValue: gross,
        returnValue: returned,
        netValue: net,
        transactions: [
          CompanyReportTransaction(
            itemId: companyId * 10,
            documentId: 1,
            documentNo: documentNo,
            documentType: purchases ? 'GOODS_RECEIPT' : 'INVOICE',
            date: endDate,
            quantity: 10,
            amount: gross,
            isReturn: false,
          ),
          CompanyReportTransaction(
            itemId: companyId * 10,
            documentId: 2,
            documentNo: 'RET-1',
            documentType: purchases ? 'PURCHASE_RETURN' : 'INVOICE_RETURN',
            date: endDate,
            quantity: 1,
            amount: returned,
            isReturn: true,
          ),
        ],
      ),
    ],
    totals: CompanyPeriodTotals(
      grossValue: gross,
      returnValue: returned,
      netValue: net,
      quantitiesByUom: const {
        'Nos': CompanyUomTotals(gross: 10, returns: 1, net: 9),
      },
    ),
    pagination: CompanyReportPagination(
      page: page,
      limit: 25,
      total: 1,
      totalPages: 1,
    ),
  );
}

Widget _app(
  Widget child, {
  Future<List<ItemCompany>> Function()? companies,
  Future<CompanyStockReport> Function(CompanyStockRequest)? stock,
  Future<CompanyPeriodReport> Function(CompanyPeriodRequest)? period,
}) {
  return ProviderScope(
    overrides: [
      reportCompaniesProvider.overrideWith(
        (ref) async => companies == null ? _companies : await companies(),
      ),
      companyStockReportProvider.overrideWith(
        (ref, request) async => stock == null
            ? _stock(request.companyId, page: request.page)
            : await stock(request),
      ),
      companyPeriodReportProvider.overrideWith(
        (ref, request) async => period == null
            ? _period(
                request.companyId,
                request.view,
                request.startDate,
                request.endDate,
                request.page,
              )
            : await period(request),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

Widget _routerApp() {
  final router = GoRouter(
    initialLocation: '/reports',
    routes: [
      GoRoute(
        path: '/reports',
        builder: (context, state) =>
            const Scaffold(body: ReportsDashboardScreen()),
        routes: [
          GoRoute(
            path: ':report',
            builder: (context, state) => Scaffold(
              body: state.pathParameters['report'] == 'company'
                  ? const CompanyReportScreen()
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      reportCompaniesProvider.overrideWith((ref) async => _companies),
      companyStockReportProvider.overrideWith(
        (ref, request) async => _stock(request.companyId, page: request.page),
      ),
      companyPeriodReportProvider.overrideWith(
        (ref, request) async => _period(
          request.companyId,
          request.view,
          request.startDate,
          request.endDate,
          request.page,
        ),
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  Future<List<ItemCompany>> Function()? companies,
  Future<CompanyStockReport> Function(CompanyStockRequest)? stock,
}) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _app(const CompanyReportScreen(), companies: companies, stock: stock),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectCompany(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('company-report-selector')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
  });

  group('DTO parsing', () {
    test('stock report parses rows, totals, UOM and pagination', () {
      final report = CompanyStockReport.fromJson({
        'company_id': 4,
        'as_of': '2026-10-29T10:30:00.000Z',
        'valuation_basis': 'remaining_batch_cost',
        'rows': [
          {
            'item_id': 12,
            'item_code': 'A-1',
            'item_name': 'Widget',
            'unit_of_measure': 'Kg',
            'quantity': 2.5,
            'stock_value': 125.75,
          },
        ],
        'totals': {
          'stock_value': 125.75,
          'quantities_by_uom': {'Kg': 2.5},
        },
        'pagination': {'page': 1, 'limit': 50, 'total': 1, 'totalPages': 1},
      });

      expect(report.companyId, 4);
      expect(report.rows.single.itemName, 'Widget');
      expect(report.rows.single.stockValue, 125.75);
      expect(report.totalStockValue, 125.75);
      expect(report.quantitiesByUom['Kg'], 2.5);
      expect(report.pagination.total, 1);
    });

    test(
      'period report keeps returns separate from gross and parses UOM totals',
      () {
        final report = CompanyPeriodReport.fromJson({
          'company_id': 4,
          'view': 'sales',
          'startDate': '2026-10-01',
          'endDate': '2026-10-31',
          'amount_basis': 'tax_inclusive',
          'rows': [
            {
              'item_id': 12,
              'item_code': 'A-1',
              'item_name': 'Widget',
              'unit_of_measure': 'Kg',
              'gross_quantity': 5,
              'return_quantity': 2,
              'net_quantity': 3,
              'gross_value': 200,
              'return_value': 50,
              'net_value': 150,
              'transactions': [
                {
                  'item_id': 12,
                  'document_id': 7,
                  'document_no': 'INV-7',
                  'document_type': 'INVOICE',
                  'date': '2026-10-05',
                  'quantity': 1,
                  'amount': 50,
                  'is_return': 1,
                },
              ],
            },
          ],
          'totals': {
            'gross_value': 200,
            'return_value': 50,
            'net_value': 150,
            'quantities_by_uom': {
              'Kg': {'gross': 5, 'returns': 2, 'net': 3},
            },
          },
          'pagination': {'page': 1, 'limit': 50, 'total': 1, 'totalPages': 1},
        });

        expect(report.rows.single.grossValue, 200);
        expect(report.rows.single.returnValue, 50);
        expect(report.rows.single.netValue, 150);
        expect(report.rows.single.transactions.single.isReturn, isTrue);
        expect(report.totals.quantitiesByUom['Kg']?.net, 3);
        expect(report.totals.netValue, 150);
      },
    );
  });

  testWidgets('stock view shows current stock, totals and archived companies', (
    tester,
  ) async {
    await _pumpScreen(tester);

    expect(
      find.text(
        'Current stock shows the latest values. The date range does not change it.',
      ),
      findsOneWidget,
    );
    expect(find.byType(DateRangeFilter), findsNothing);
    expect(find.text('Acme Stock'), findsOneWidget);
    expect(find.textContaining('500.00'), findsWidgets);

    await _selectCompany(tester, 'Old Co (Archived)');

    expect(find.text('Old Stock'), findsOneWidget);
    expect(find.textContaining('900.00'), findsWidgets);
    // The previous company's rows and totals are gone.
    expect(find.text('Acme Stock'), findsNothing);
    expect(find.textContaining('500.00'), findsNothing);
  });

  testWidgets('sales and purchases tabs use the date range and show returns', (
    tester,
  ) async {
    await _pumpScreen(tester);

    await tester.tap(find.text('Sales'));
    await tester.pumpAndSettle();
    expect(find.byType(DateRangeFilter), findsOneWidget);
    expect(find.text('Sale Widget'), findsOneWidget);
    expect(find.textContaining('1,000.00'), findsWidgets);
    expect(find.textContaining('100.00'), findsWidgets);
    expect(find.textContaining('900.00'), findsWidgets);

    await tester.tap(find.text('Purchases'));
    await tester.pumpAndSettle();
    expect(find.text('Purchase Widget'), findsOneWidget);
    expect(find.textContaining('300.00'), findsWidgets);
    expect(find.textContaining('30.00'), findsWidgets);
    expect(find.textContaining('270.00'), findsWidgets);
    expect(find.text('Sale Widget'), findsNothing);
  });

  testWidgets('paging requests the next page and a company change resets it', (
    tester,
  ) async {
    await _pumpScreen(tester);
    expect(find.text('Acme Stock'), findsOneWidget);

    await tester.tap(find.byTooltip('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Acme Stock_Page2'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CompanyReportScreen)),
    );
    expect(container.read(companyReportPageProvider), 2);

    await _selectCompany(tester, 'Beta Co');
    expect(container.read(companyReportPageProvider), 1);
    expect(find.text('Beta Stock'), findsOneWidget);
    expect(find.text('Acme Stock_Page2'), findsNothing);
  });

  testWidgets('period row double-tap opens the transaction drilldown', (
    tester,
  ) async {
    await _pumpScreen(tester);
    await tester.tap(find.text('Sales'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sale Widget'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Sale Widget'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('INV-1'), findsOneWidget);
    expect(find.text('RET-1'), findsOneWidget);
    expect(find.text('Invoice'), findsOneWidget);
    expect(find.text('Invoice return'), findsOneWidget);
  });

  testWidgets('company list failure shows an error and retries', (
    tester,
  ) async {
    var calls = 0;
    await _pumpScreen(
      tester,
      companies: () async {
        calls++;
        if (calls == 1) throw Exception('offline');
        return _companies;
      },
    );

    expect(find.text('Failed to load companies'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Refresh'));
    await tester.pumpAndSettle();

    expect(find.text('Failed to load companies'), findsNothing);
    expect(find.text('Acme Stock'), findsOneWidget);
  });

  testWidgets('empty company list shows guidance', (tester) async {
    await _pumpScreen(tester, companies: () async => const <ItemCompany>[]);

    expect(
      find.text('No companies yet. Add a company from Inventory.'),
      findsOneWidget,
    );
  });

  testWidgets('reports dashboard card opens the company report', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_routerApp());
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('Company Report'),
      find.byType(ReportsDashboardScreen),
      const Offset(0, -250),
    );
    await tester.tap(find.text('Company Report'));
    await tester.pumpAndSettle();

    expect(find.byType(CompanyReportScreen), findsOneWidget);
    expect(find.text('Acme Stock'), findsOneWidget);
  });
}
