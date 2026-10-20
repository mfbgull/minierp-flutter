import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/data/models/item.dart';
import 'package:minierp_app/features/purchase_orders/widgets/purchase_order_line_row.dart';

import '../../test_helpers.dart';

void main() {
  late TextEditingController quantity;
  late TextEditingController price;
  late TextEditingController tax;
  late GlobalKey<FormState> formKey;

  setUp(() {
    quantity = TextEditingController(text: '2');
    price = TextEditingController(text: '10');
    tax = TextEditingController(text: '0');
    formKey = GlobalKey<FormState>();
  });

  tearDown(() {
    quantity.dispose();
    price.dispose();
    tax.dispose();
  });

  Item stock({int id = 1, bool hasExpiry = false}) => Item.fromJson({
        'id': id,
        'item_code': 'ITEM$id',
        'item_name': 'Stock $id',
        'has_expiry': hasExpiry,
      });

  Widget harness({
    List<Item> items = const [],
    String selectedItemId = '',
    bool canRemove = true,
    bool submitting = false,
    VoidCallback? onRemove,
    VoidCallback? onPickExpiry,
  }) {
    return buildTestable(
      Scaffold(
        body: Form(
          key: formKey,
          child: PurchaseOrderLineRow(
            index: 0,
            items: items,
            selectedItemId: selectedItemId,
            quantityController: quantity,
            priceController: price,
            taxController: tax,
            amount: 20,
            expiryDate: null,
            submitting: submitting,
            canRemove: canRemove,
            onItemChanged: (_) {},
            onValueChanged: () {},
            onRemove: onRemove ?? () {},
            onPickExpiry: onPickExpiry ?? () {},
          ),
        ),
      ),
    );
  }

  IconButton removeButton(WidgetTester tester) => tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.remove_circle_outline),
      );

  Finder fieldFor(TextEditingController controller) =>
      find.byWidgetPredicate((w) => w is TextFormField && w.controller == controller);

  testWidgets('the last remaining line cannot be removed', (tester) async {
    await tester.pumpWidget(harness(canRemove: false));
    await tester.pumpAndSettle();
    expect(removeButton(tester).onPressed, isNull);
  });

  testWidgets('a removable line exposes an active remove action', (
    tester,
  ) async {
    var removed = false;
    await tester.pumpWidget(
      harness(canRemove: true, onRemove: () => removed = true),
    );
    await tester.pumpAndSettle();
    final button = removeButton(tester);
    expect(button.onPressed, isNotNull);
    await tester.tap(find.byIcon(Icons.remove_circle_outline));
    await tester.pumpAndSettle();
    expect(removed, isTrue);
  });

  testWidgets('the remove action exposes a localized accessible name', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    final remove = tester.getSemantics(
      find.widgetWithIcon(IconButton, Icons.remove_circle_outline),
    );
    expect(remove.tooltip, 'Remove');
    semantics.dispose();
  });

  testWidgets('the remove action is disabled while the form submits', (
    tester,
  ) async {
    await tester.pumpWidget(harness(canRemove: true, submitting: true));
    await tester.pumpAndSettle();
    expect(removeButton(tester).onPressed, isNull);
  });

  testWidgets('input tax rejects negative and non-numeric values', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    final taxField = find.byKey(const ValueKey('po-input-tax-0'));
    expect(taxField, findsOneWidget);

    await tester.enterText(taxField, '-1');
    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Required'), findsOneWidget);

    await tester.enterText(taxField, 'abc');
    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Required'), findsOneWidget);

    await tester.enterText(taxField, '15');
    expect(formKey.currentState!.validate(), isTrue);
    await tester.pump();
    expect(find.text('Required'), findsNothing);
  });

  testWidgets('quantity and unit price are required', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.enterText(fieldFor(quantity), '');
    await tester.enterText(fieldFor(price), '');
    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Required'), findsNWidgets(2));
  });

  testWidgets('the expiry control appears only for expiry-tracked items', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(items: [stock(hasExpiry: true)], selectedItemId: '1'),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.calendar_today_outlined), findsOneWidget);
  });

  testWidgets('a non-expiry item hides the expiry control', (tester) async {
    await tester.pumpWidget(
      harness(items: [stock(hasExpiry: false)], selectedItemId: '1'),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.calendar_today_outlined), findsNothing);
  });

  testWidgets('an unselected item hides the expiry control', (tester) async {
    await tester.pumpWidget(harness(items: [stock(hasExpiry: true)]));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.calendar_today_outlined), findsNothing);
  });
}
