// P1 UI audit — Escape must close dialogs by default, and dragging the
// dialog must not rebuild its form subtree.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/widgets/movable_dialog.dart';

void main() {
  testWidgets('Escape closes a MovableDialog by default', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const MovableDialog(
                    child: Text('dialog body'),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('dialog body'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('dialog body'), findsNothing);
  });

  testWidgets('dragging the dialog does not rebuild its child', (
    tester,
  ) async {
    var builds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MovableDialog(
            child: Builder(
              builder: (_) {
                builds++;
                return const Text('form body');
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final initialBuilds = builds;
    expect(initialBuilds, greaterThan(0));

    await tester.drag(
      find.byKey(kMovableDialogHandleKey),
      const Offset(60, 40),
    );
    await tester.pumpAndSettle();

    expect(
      builds,
      initialBuilds,
      reason: 'Panning should move the dialog, not rebuild its form body',
    );
  });
}
