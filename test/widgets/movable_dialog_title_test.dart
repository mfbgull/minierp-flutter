import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/widgets/movable_dialog.dart';

void main() {
  testWidgets('a supplied dialog title is visible and exposed as a heading', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MovableDialog(
            title: 'Record supplier advance',
            child: Text('Advance details'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Record supplier advance'), findsOneWidget);
    final heading = find.ancestor(
      of: find.text('Record supplier advance'),
      matching: find.byType(Semantics),
    );
    expect(
      heading.evaluate().any(
        (e) => (e.widget as Semantics).properties.header == true,
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}
