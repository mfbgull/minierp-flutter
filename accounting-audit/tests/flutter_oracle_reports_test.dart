import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/core/utils/formatters.dart';
import 'package:minierp_app/data/models/report.dart';
import 'package:minierp_app/features/reports/profit_loss_report_screen.dart';
import 'package:minierp_app/features/reports/report_providers.dart';
import 'package:minierp_app/features/reports/balance_sheet_report_screen.dart';

import '../../test/test_helpers.dart';

void main() {
  final path = Platform.environment['FLUTTER_AUDIT_ORACLE'];
  if (path == null) {
    throw StateError(
      'FLUTTER_AUDIT_ORACLE must point to verified retail API events',
    );
  }
  final events = (jsonDecode(File(path).readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  Map<String, dynamic> data(String endpoint) {
    final event = events.firstWhere(
      (event) =>
          (event['url'] as String).startsWith('/api/reports/$endpoint?') &&
          event['status'] == 200,
    );
    return (event['response'] as Map<String, dynamic>)['data']
        as Map<String, dynamic>;
  }

  test(
    'retail API responses preserve independent financial oracle in Dart models',
    () {
      final pnl = ProfitLossReport.fromJson(data('profit-loss'));
      final sheet = BalanceSheetReport.fromJson(data('balance-sheet'));
      final trial = TrialBalanceReport.fromJson(data('trial-balance'));
      final cash = CashFlowReport.fromJson(data('cash-flow'));
      final ar = ArAgingReport.fromJson(data('ar-aging'));
      final ap = ApAgingReport.fromJson(data('ap-aging'));
      final stock = InventoryValuationReport.fromJson(
        data('inventory-valuation'),
      );
      final observed = <String, num>{
        'revenue': pnl.totalRevenue,
        'cogs': pnl.totalCogs,
        'profit': pnl.netProfit,
        'cash': sheet.assets.cash,
        'ar': sheet.assets.accountsReceivable,
        'ap': sheet.liabilities.accountsPayable,
        'inventory': sheet.assets.inventory,
        'equity': sheet.equity.total,
        'trialDebit': trial.totalDebit,
        'trialCredit': trial.totalCredit,
        'cashFlowNet': cash.netCashFlow,
        'arAging': ar.summary.totalReceivables,
        'apAging': ap.summary.totalPayables,
        'stockQty': stock.totalPhysical.qty,
        'stockValue': stock.totalPhysical.value,
      };
      final expected = <String, num>{
        'revenue': 210,
        'cogs': 140,
        'profit': 50,
        'cash': 10170,
        'ar': 30,
        'ap': 700,
        'inventory': 550,
        'equity': 10050,
        'trialDebit': 11490,
        'trialCredit': 11490,
        'cashFlowNet': 10170,
        'arAging': 30,
        'apAging': 700,
        'stockQty': 55,
        'stockValue': 550,
      };
      File(
        'accounting-audit/evidence/flutter-oracle-models.json',
      ).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'source_events': path,
          'expected': expected,
          'actual': observed,
          'basis':
              'Owner capital10000; credit purchase70x10; sale15x15 collected; three returns1 each/refund15 each; resale2x15 unpaid; one damaged unit written off10; operating expense10. No other transactions at checkpoint.',
        }),
      );
      expect(observed, expected);
      expect(sheet.totals.balanced, isTrue);
      expect(trial.balanced, isTrue);
      expect(sheet.asOfDate, '2026-10-31');
    },
  );

  testWidgets('retail P&L displays authoritative amounts and refresh reloads', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final report = ProfitLossReport.fromJson(data('profit-loss'));
    var calls = 0;
    await tester.pumpWidget(
      buildTestable(
        const Scaffold(body: ProfitLossReportScreen()),
        overrides: [
          profitLossReportProvider.overrideWith((ref) async {
            calls++;
            return report;
          }),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(Formatters.currency(210)), findsOneWidget);
    expect(find.text(Formatters.currency(140)), findsOneWidget);
    expect(find.text(Formatters.currency(70)), findsOneWidget);
    expect(find.text(Formatters.currency(50)), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(calls, 1);
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text(Formatters.currency(210)), findsOneWidget);
    File(
      'accounting-audit/evidence/flutter-oracle-pnl-widget.json',
    ).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'source_events': path,
        'provider_loads_after_refresh_tap': calls,
        'visible_text': tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
            .toList(),
      }),
    );
  });

  testWidgets('retail balance sheet displays actual backend amounts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final report = BalanceSheetReport.fromJson(data('balance-sheet'));
    await tester.pumpWidget(
      buildTestable(
        const Scaffold(body: BalanceSheetReportScreen()),
        overrides: [balanceSheetProvider.overrideWith((ref) async => report)],
      ),
    );
    await tester.pumpAndSettle();
    for (final value in [550, 30, 10170, 10050]) {
      expect(find.text(Formatters.currency(value)), findsOneWidget);
    }
    expect(find.text('Balanced'), findsOneWidget);
    expect(tester.takeException(), isNull);
    File(
      'accounting-audit/evidence/flutter-oracle-balance-widget.json',
    ).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'source_events': path,
        'visible_text': tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
            .toList(),
      }),
    );
  });

  test('F-043 P&L expense-category rows reconcile to expense total', () {
    final raw = data('profit-loss');
    final report = ProfitLossReport.fromJson(raw);
    final categories = report.expenses.fold<num>(
      0,
      (sum, row) => sum + row.total,
    );
    File(
      'accounting-audit/evidence/flutter-pnl-breakdown.json',
    ).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'source_events': path,
        'api_response': raw,
        'independent_expected_operating_expense': 10,
        'independent_expected_damage_loss': 10,
        'expected_breakdown_total': 20,
        'actual_breakdown_total': categories,
        'authoritative_expense_total': report.totalExpenses,
        'profit_is_correct': report.netProfit == 50,
      }),
    );
    expect(
      categories,
      report.totalExpenses,
      reason:
          'Expenses by Category omits the damaged-stock loss and cannot explain Total Expenses.',
    );
  }, tags: ['known-defect']);
}
