import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:csv/csv.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:minierp_app/core/utils/csv_export.dart';
import 'package:minierp_app/core/utils/formatters.dart';
import 'package:minierp_app/data/models/report.dart';
import 'package:minierp_app/features/reports/balance_sheet_report_screen.dart';
import 'package:minierp_app/features/reports/report_providers.dart';
import 'package:minierp_app/l10n/app_localizations.dart';
import 'package:minierp_app/features/employees/employee_models.dart';
import 'package:minierp_app/features/employees/employee_providers.dart';
import 'package:minierp_app/features/employees/loan_providers.dart';
import 'package:minierp_app/features/employees/salary_pay_dialog.dart';

import '../test_helpers.dart';


// Audit-only input: independent balanced accounting equation, no database or writes.
// Cash 1,000 + inventory 200 + AR 300 + other assets 400 = assets 1,900.
// AP 500 + tax payable 60 + other liabilities 70 + equity 1,270 = 1,900.
Map<String, dynamic> balanceSheetFixture() => {
  'asOfDate': '2026-10-25',
  'assets': {
    'inventory': 200,
    'accounts_receivable': 300,
    'cash': 1000,
    'other': 400,
    'total': 1900,
  },
  'liabilities': {
    'accounts_payable': 500,
    'tax_payable': 60,
    'other': 70,
    'total': 630,
  },
  'equity': {
    'opening_retained_earnings': 1000,
    'owner_capital': 300,
    'owner_drawings': -30,
    'net_income_ytd': 0,
    'revenue_ytd': 0,
    'cogs_ytd': 0,
    'expenses_ytd': 0,
    'total': 1270,
  },
  'totals': {
    'total_assets': 1900,
    'total_liabilities': 630,
    'total_equity': 1270,
    'total_liab_and_equity': 1900,
    'balanced': true,
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('en');
    final loader = FontLoader('AuditFont');
    loader.addFont(
      Future.value(
        ByteData.view(
          File('assets/fonts/Inter-Regular.ttf').readAsBytesSync().buffer,
        ),
      ),
    );
    await loader.load();
    final materialFont = File('${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts/MaterialIcons-Regular.otf');
    final icons = FontLoader('MaterialIcons');
    icons.addFont(materialFont.readAsBytes().then(ByteData.sublistView));
    await icons.load();
  });
  testWidgets('F-042 salary remaining counts carryover only once', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    const employee = Employee(
      id: 1,
      employeeCode: 'AUDIT',
      firstName: 'Audit',
      lastName: 'Fixture',
      salary: 1000,
      isActive: true,
    );
    final capture =
        jsonDecode(
              File(
                'accounting-audit/evidence/flutter-payroll-api-fixture.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final capturedRow = capture['row'] as Map<String, dynamic>;
    // Only relabel the fixture's selected month to match the dialog's default
    // today. All financial fields are the exact mounted backend response.
    final row = SalaryMonthSummary.fromJson({
      ...capturedRow,
      'pay_period': month,
    });
    await tester.pumpWidget(
      buildTestable(
        const Scaffold(body: SalaryPayDialog(employee: employee)),
        overrides: [
          employeeSalaryHistoryProvider(1).overrideWith((ref) async => [row]),
          employeeActiveLoansProvider(1).overrideWith((ref) => []),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '800');
    await tester.pumpAndSettle();
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
        .toList();
    File(
      'accounting-audit/remediation/flutter-salary-carryover-widget.json',
    ).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'fixture': {
          'salary': 1000,
          'total_paid_including_advance': 200,
          'advance_carryover': 200,
          'remaining': 800,
          'pay_period': month,
        },
        'source_capture': capture,
        'fixture_adaptation':
            'pay_period relabeled to current month for default-date dialog; financial fields unchanged',
        'visible_text': texts,
        'expected_remaining': 800,
      }),
    );
    expect(tester.takeException(), isNull);
    expect(
      find.textContaining('Remaining Balance: ${Formatters.currency(800)}'),
      findsOneWidget,
      reason:
          'The server total_paid already includes carryover; it must not be deducted twice.',
    );
  });

  testWidgets('F-040 balance sheet displays all nonzero API categories', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fixture = balanceSheetFixture();
    final report = BalanceSheetReport.fromJson(fixture);
    await tester.pumpWidget(
      buildTestable(
        RepaintBoundary(
          key: const ValueKey('audit-balance-sheet'),
          child: Theme(
            data: ThemeData(fontFamily: 'AuditFont'),
            child: const Scaffold(body: BalanceSheetReportScreen()),
          ),
        ),
        overrides: [balanceSheetProvider.overrideWith((ref) async => report)],
      ),
    );
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('audit-balance-sheet')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File(
        'accounting-audit/remediation/flutter-balance-sheet.png',
      ).writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
        .toList();
    File(
      'accounting-audit/remediation/flutter-balance-sheet-widget.json',
    ).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'input': fixture,
        'visible_text': texts,
        'expected_nonzero_categories': {
          'other_assets': 400,
          'tax_payable': 60,
          'other_liabilities': 70,
        },
        'displayed_asset_components_sum':
            report.assets.inventory +
            report.assets.accountsReceivable +
            report.assets.cash + report.assets.other,
        'displayed_asset_total': report.assets.total,
        'displayed_liability_components_sum':
            report.liabilities.accountsPayable + report.liabilities.taxPayable + report.liabilities.other,
        'displayed_liability_total': report.liabilities.total,
      }),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Balanced'), findsOneWidget);
    expect(
      find.text(Formatters.currency(400)),
      findsOneWidget,
      reason:
          'Other assets supplied by the API must remain visible to reconcile the asset total.',
    );
    expect(find.text(Formatters.currency(60)), findsOneWidget);
    expect(find.text(Formatters.currency(70)), findsOneWidget);
  });

  testWidgets('fully covered salary submits zero cash through the dialog', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const employee = Employee(id: 7, employeeCode: 'COVERED', firstName: 'Covered', lastName: 'Salary', salary: 1000, isActive: true);
    final now = DateTime.now();
    final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final row = SalaryMonthSummary.fromJson({'pay_period': month, 'employee_salary': 1000, 'total_paid': 1000, 'remaining': 0, 'advance_carryover': 1000, 'status': 'paid'});
    Map<String, dynamic>? submitted;
    final dio = createFakeDio({'/employees/7/salary/pay': successEnvelope({'id': 99})});
    dio.interceptors.insert(0, InterceptorsWrapper(onRequest: (options, handler) {
      if (options.path == '/employees/7/salary/pay') submitted = Map<String, dynamic>.from(options.data as Map);
      handler.next(options);
    }));
    await tester.pumpWidget(buildTestable(Scaffold(body: Builder(builder: (context) => TextButton(
      onPressed: () => showDialog<void>(context: context, builder: (_) => const SalaryPayDialog(employee: employee)),
      child: const Text('Open payroll'),
    ))), dio: dio, overrides: [
      employeeSalaryHistoryProvider(7).overrideWith((ref) async => [row]),
      employeeActiveLoansProvider(7).overrideWith((ref) => []),
    ]));
    await tester.tap(find.text('Open payroll'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '0');
    await tester.tap(find.widgetWithText(FilledButton, 'Pay Salary'));
    await tester.pumpAndSettle();
    expect(submitted?['amount'], 0);
    expect(submitted?['payment_type'], 'full');
    expect(find.byType(SalaryPayDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('F-041 balance sheet CSV preserves monetary values in one cell', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final csv = buildBalanceSheetCsv(
      l10n,
      BalanceSheetReport.fromJson(balanceSheetFixture()),
    );
    File(
      'accounting-audit/remediation/flutter-balance-sheet.csv',
    ).writeAsStringSync(csv);
    final cashLine = csv
        .split('\n')
        .singleWhere((line) => line.startsWith('Cash,'));
    final records = Csv().decode(csv);
    expect(records.every((row) => row.length == 3), isTrue);
    final actualCells = records.singleWhere((row) => row.first == 'Cash');
    File(
      'accounting-audit/remediation/flutter-csv-observation.json',
    ).writeAsStringSync(
      jsonEncode({
        'actual_line': cashLine,
        'expected_cells': ['Cash', '', 'Rs. 1,000.00'],
        'actual_cells': actualCells,
        'expected_columns': 3,
        'actual_columns': actualCells.length,
      }),
    );
    expect(
      actualCells,
      ['Cash', '', 'Rs. 1,000.00'],
      reason:
          'Thousands separators must be quoted to prevent splitting currency into extra columns.',
    );
  });
  for (final width in [390.0, 1440.0]) {
    for (final dark in [false, true]) {
      testWidgets('balance sheet ${width.toInt()} ${dark ? 'dark' : 'light'} refreshes and scrolls', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var loads = 0;
        final key = GlobalKey();
        await tester.pumpWidget(buildTestable(RepaintBoundary(key: key, child: Theme(
          data: ThemeData(brightness: dark ? Brightness.dark : Brightness.light, fontFamily: 'AuditFont'),
          child: const Scaffold(body: BalanceSheetReportScreen()),
        )), overrides: [balanceSheetProvider.overrideWith((ref) async {
          loads++;
          return BalanceSheetReport.fromJson(balanceSheetFixture());
        })]));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.refresh));
        await tester.pumpAndSettle();
        expect(loads, 2);
        expect(tester.takeException(), isNull);
        Future<void> capture(String position) async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            File('accounting-audit/remediation/balance-${width.toInt()}-${dark ? 'dark' : 'light'}-$position.png').writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await capture('top');
        await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, -1800));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture('bottom');
      });
    }
  }
}
