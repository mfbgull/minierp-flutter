import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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

import '../../test/test_helpers.dart';

List<String> parseCsvRecord(String record) {
  final cells = <String>[];
  var value = StringBuffer();
  var quoted = false;
  for (var index = 0; index < record.length; index++) {
    final character = record[index];
    if (character == '"') {
      if (quoted && index + 1 < record.length && record[index + 1] == '"') {
        value.write('"');
        index++;
      } else {
        quoted = !quoted;
      }
    } else if (character == ',' && !quoted) {
      cells.add(value.toString());
      value = StringBuffer();
    } else {
      value.write(character);
    }
  }
  if (quoted) {
    throw const FormatException('Unclosed CSV quoted field');
  }
  cells.add(value.toString());
  return cells;
}

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
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
        .toList();
    File(
      'accounting-audit/evidence/flutter-salary-carryover-widget.json',
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
        'actual_remaining_from_client_expression': 1000 - 200 - 200,
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
        'accounting-audit/evidence/flutter-balance-sheet.png',
      ).writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
        .toList();
    File(
      'accounting-audit/evidence/flutter-balance-sheet-widget.json',
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
            report.assets.cash,
        'displayed_asset_total': report.assets.total,
        'displayed_liability_components_sum':
            report.liabilities.accountsPayable,
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

  test('F-041 balance sheet CSV preserves monetary values in one cell', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final csv = buildBalanceSheetCsv(
      l10n,
      BalanceSheetReport.fromJson(balanceSheetFixture()),
    );
    File(
      'accounting-audit/evidence/flutter-balance-sheet.csv',
    ).writeAsStringSync(csv);
    final cashLine = csv
        .split('\n')
        .singleWhere((line) => line.startsWith('Cash,'));
    expect(parseCsvRecord('Cash,,"Rs. 1,000.00"'), [
      'Cash',
      '',
      'Rs. 1,000.00',
    ]);
    expect(parseCsvRecord('"A ""quoted"" label",,10'), [
      'A "quoted" label',
      '',
      '10',
    ]);
    final actualCells = parseCsvRecord(cashLine);
    File(
      'accounting-audit/evidence/flutter-csv-observation.json',
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
}
