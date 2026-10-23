// P1 UI audit — a KPI failure must be visible, announced, and retryable
// with text and an icon, not a lone red dash.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/features/dashboard/kpi_error_strip.dart';
import 'package:minierp_app/l10n/app_localizations.dart';

void main() {
  testWidgets('KPI errors show an icon, message, live region, and retry', (
    tester,
  ) async {
    var retried = false;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: KpiErrorStrip(
            message: 'Server unreachable',
            onRetry: () => retried = true,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.textContaining('Server unreachable'), findsOneWidget);

    final liveRegions = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .where((widget) => widget.properties.liveRegion == true);
    expect(liveRegions, isNotEmpty);

    await tester.tap(find.byIcon(Icons.refresh));
    expect(retried, isTrue);
  });
}
