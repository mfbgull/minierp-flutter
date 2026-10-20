import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/data/models/invoice.dart' show InvoiceItem;
import 'package:minierp_app/data/models/sales_return.dart' show InvoicePosition;
import 'package:minierp_app/data/models/stock_batch.dart'
    show BatchLocation, StockBatch;
import 'package:minierp_app/features/sales/widgets/invoice_return_views.dart';

import '../../test_helpers.dart';

void main() {
  late TextEditingController quantity;

  setUp(() => quantity = TextEditingController());
  tearDown(() => quantity.dispose());

  InvoiceItem line({double quantityValue = 10, double returned = 2}) =>
      InvoiceItem(
        id: 1,
        invoiceId: 1,
        itemId: 7,
        itemCode: 'FG001',
        itemName: 'Widget A',
        quantity: quantityValue,
        unitPrice: 5,
        amount: 50,
        taxRate: 0,
        discountType: 'none',
        discountValue: 0,
        returnedQty: returned,
      );

  StockBatch batch() => StockBatch(
        id: 3,
        batchNo: 'B-001',
        itemId: 7,
        warehouseId: 1,
        sourceType: 'purchase',
        sourceId: 1,
        quantityOriginal: 10,
        quantityRemaining: 6,
        unitCost: 4,
        receivedDate: '2026-09-01',
        locations: const [
          BatchLocation(
            locationId: 1,
            locationCode: 'LOC-A',
            quantityPhysical: 6,
            quantityReserved: 1,
            quantityAvailable: 5,
          ),
        ],
      );

  Widget harness({
    bool autofocus = false,
    bool enabled = true,
    List<StockBatch>? batches,
    bool expanded = false,
    VoidCallback? onToggleExpanded,
    VoidCallback? onChanged,
    VoidCallback? onSubmit,
  }) {
    return buildTestable(
      Scaffold(
        body: Form(
          child: InvoiceReturnLineRow(
            item: line(),
            controller: quantity,
            autofocus: autofocus,
            enabled: enabled,
            batches: batches,
            expanded: expanded,
            onToggleExpanded: onToggleExpanded,
            onChanged: onChanged ?? () {},
            onSubmit: onSubmit ?? () {},
          ),
        ),
      ),
    );
  }

  testWidgets('the batches chip is hidden when the item has no batches', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(find.text('batches'), findsNothing);
  });

  testWidgets('the batches chip appears and reports the disclosure toggle', (
    tester,
  ) async {
    var toggled = false;
    await tester.pumpWidget(
      harness(batches: [batch()], onToggleExpanded: () => toggled = true),
    );
    await tester.pumpAndSettle();
    expect(find.text('batches'), findsOneWidget);
    await tester.tap(find.text('batches'));
    await tester.pumpAndSettle();
    expect(toggled, isTrue);
  });

  testWidgets('batch details stay hidden until the row is expanded', (
    tester,
  ) async {
    await tester.pumpWidget(harness(batches: [batch()], expanded: false));
    await tester.pumpAndSettle();
    expect(find.text('B-001'), findsNothing);
    expect(find.text('LOC-A'), findsNothing);
  });

  testWidgets('expanded rows show the batch and location breakdown', (
    tester,
  ) async {
    await tester.pumpWidget(harness(batches: [batch()], expanded: true));
    await tester.pumpAndSettle();
    expect(find.text('B-001'), findsOneWidget);
    expect(find.text('LOC-A'), findsOneWidget);
    expect(find.textContaining('Phys:'), findsOneWidget);
    expect(find.textContaining('Avail:'), findsOneWidget);
  });

  testWidgets('editing the quantity reports the change to the parent', (
    tester,
  ) async {
    var changes = 0;
    await tester.pumpWidget(harness(onChanged: () => changes++));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '3');
    await tester.pumpAndSettle();
    expect(changes, greaterThan(0));
    expect(quantity.text, '3');
  });

  testWidgets('Enter on the quantity field submits the return', (
    tester,
  ) async {
    var submitted = false;
    await tester.pumpWidget(
      harness(onSubmit: () => submitted = true),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '3');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(submitted, isTrue);
  });

  testWidgets('a quantity above the available amount is rejected', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '99');
    expect(tester.widget<TextFormField>(find.byType(TextFormField)).validator!('99'), isNotNull);
  });

  Widget preview({
    double fee = 0,
    double gross = 100,
    double net = 90,
    InvoicePosition? position,
  }) {
    return buildTestable(
      Scaffold(
        body: InvoiceReturnPositionPreview(
          grossReturn: gross,
          fee: fee,
          net: net,
          position:
              position ?? const InvoicePosition(balanceDue: 0, refundCreditDue: 0),
        ),
      ),
    );
  }

  testWidgets('the position preview hides a fee at or below 0.005', (
    tester,
  ) async {
    await tester.pumpWidget(preview(fee: 0.005));
    await tester.pumpAndSettle();
    expect(find.text('Restocking Fee'), findsNothing);
  });

  testWidgets('the position preview shows a fee above 0.005', (tester) async {
    await tester.pumpWidget(preview(fee: 0.006));
    await tester.pumpAndSettle();
    expect(find.text('Restocking Fee'), findsOneWidget);
  });

  testWidgets('the position preview always shows the returned, net and due rows', (
    tester,
  ) async {
    await tester.pumpWidget(preview());
    await tester.pumpAndSettle();
    expect(find.text('Returned Value'), findsOneWidget);
    expect(find.text('Net'), findsOneWidget);
    expect(find.text('Balance Due'), findsOneWidget);
    expect(find.text('Refund/Credit Due'), findsOneWidget);
  });
}
