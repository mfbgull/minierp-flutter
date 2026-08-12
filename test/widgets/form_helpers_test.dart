// Enter-to-submit tests for the shared form helpers — every single-line
// field in the create/edit dialogs wires `onFieldSubmitted:
// submitOnEnter(_submit)` so pressing Enter saves without reaching for
// the Save button. Multi-line fields (description/address/notes) are
// deliberately left unwired (Enter keeps inserting newlines), and the
// dialogs' own Save buttons still work for them.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:minierp_app/widgets/form_helpers.dart';

void main() {
  group('submitOnEnter', () {
    test('returns a handler that invokes the submit callback', () {
      var calls = 0;
      final handler = submitOnEnter(() => calls++);
      handler('ignored');
      expect(calls, 1);
    });

    testWidgets('the action key on a wired field submits the form',
        (tester) async {
      var submitted = 0;
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Form(
              child: Column(
                children: [
                  TextFormField(
                    controller: controller,
                    onFieldSubmitted: submitOnEnter(() => submitted++),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextFormField), 'abc');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(submitted, 1);
    });

    testWidgets('fields without the handler ignore the action key',
        (tester) async {
      var submitted = 0;
      final unwired = TextEditingController();
      final wired = TextEditingController();
      addTearDown(unwired.dispose);
      addTearDown(wired.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Form(
              child: Column(
                children: [
                  // e.g. a multi-line notes/description field the dialogs
                  // leave unwired so Enter keeps adding newlines.
                  TextFormField(controller: unwired),
                  TextFormField(
                    controller: wired,
                    onFieldSubmitted: submitOnEnter(() => submitted++),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextFormField).at(0), 'notes');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(submitted, 0);

      await tester.enterText(find.byType(TextFormField).at(1), 'abc');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(submitted, 1);
    });
  });
}
