// P1 UI audit — the select popup must stay anchored to its field when
// the surrounding form scrolls.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/widgets/searchable_select.dart';

void main() {
  testWidgets('popup follows the field when the form scrolls', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: SingleChildScrollView(
              controller: controller,
              child: Column(
                children: [
                  const SizedBox(height: 80),
                  SearchableSelect<String>(
                    items: const ['Alpha', 'Beta'],
                    hint: 'Pick an item',
                    labelBuilder: (value) => value,
                    onChanged: (_) {},
                  ),
                  const SizedBox(height: 600),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Pick an item'));
    await tester.pumpAndSettle();

    final popup = find.byKey(const Key('searchable_select_popup'));
    expect(popup, findsOneWidget);
    final before = tester.getTopLeft(popup).dy;

    controller.jumpTo(40);
    await tester.pump();

    final after = tester.getTopLeft(popup).dy;
    expect(after, closeTo(before - 40, 0.5));
  });
}
