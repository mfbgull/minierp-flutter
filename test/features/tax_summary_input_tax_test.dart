import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/data/models/report.dart';
import 'package:minierp_app/features/reports/report_providers.dart';
import 'package:minierp_app/features/reports/tax_summary_report_screen.dart';

import '../test_helpers.dart';

void main() {
  testWidgets(
    'tax summary displays output tax, recoverable input tax and net tax',
    (tester) async {
      final report = TaxSummaryReport.fromJson({
        'total_tax': 20,
        'input_tax': 15,
        'net_tax': 5,
      });
      await tester.pumpWidget(
        buildTestable(
          const Scaffold(body: TaxSummaryReportScreen()),
          overrides: [taxSummaryProvider.overrideWith((ref) async => report)],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Recoverable input tax'), findsOneWidget);
      expect(find.text('Net tax'), findsOneWidget);
      expect(find.textContaining('15.00'), findsOneWidget);
      expect(find.textContaining('5.00'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
}
