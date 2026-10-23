// P1 UI audit — the bulk action bar must enter/leave without jumping
// the grid under the pointer.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/l10n/app_localizations.dart';
import 'package:minierp_app/widgets/screen_toolbar.dart';

Widget harness(Widget child, {bool reduceMotion = false}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('bulk bar insertion is animated', (tester) async {
    await tester.pumpWidget(
      harness(
        BulkActionBar(
          count: 3,
          onClearSelection: () {},
          actions: [
            TextButton(onPressed: () {}, child: const Text('Export')),
          ],
        ),
      ),
    );

    expect(find.byType(AnimatedSize), findsOneWidget);
  });

  testWidgets('bulk bar animation collapses under reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        BulkActionBar(count: 3, onClearSelection: () {}),
        reduceMotion: true,
      ),
    );

    final animatedSize = tester.widget<AnimatedSize>(find.byType(AnimatedSize));
    expect(animatedSize.duration, Duration.zero);
  });
}
