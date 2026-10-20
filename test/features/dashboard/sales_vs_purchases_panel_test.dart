import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/data/models/dashboard_summary.dart';
import 'package:minierp_app/features/dashboard/dashboard_providers.dart';
import 'package:minierp_app/features/dashboard/dashboard_screen.dart';

import '../../test_helpers.dart';

void main() {
  for (final series in ['empty', 'salesByDay', 'purchasesByDay']) {
    testWidgets('dashboard chart renders $series zero-valued series', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final summary = DashboardSummary.fromJson({
        if (series != 'empty')
          series: [
            {'date': '2026-09-01', 'total': 0},
          ],
      });
      await tester.pumpWidget(buildTestable(
        const Scaffold(body: DashboardScreen()),
        overrides: [
          dashboardBootProvider.overrideWith((ref) async => DashboardBootSnapshot(
            summary: summary,
            layout: null,
            kpis: {},
            cash: null,
            ar: null,
            expiryAlerts: [],
            topCustomers: [],
          )),
        ],
      ));
      await tester.pumpAndSettle();
      expect(find.text('Sales vs Purchases (Last 7 Days)'), findsOneWidget);
      expect(find.text('9/1'), series == 'empty' ? findsNothing : findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
