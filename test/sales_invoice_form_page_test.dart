// Invoice form page (sales_invoice_form_page.dart) regression tests:
// the line-items PlutoGrid must survive parent rebuilds (e.g. selecting
// the customer) and Add Item must insert rows.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/data/models/customer.dart';
import 'package:minierp_app/data/models/invoice.dart';
import 'package:minierp_app/data/models/item.dart';
import 'package:minierp_app/data/repositories/api_result.dart';
import 'package:minierp_app/data/repositories/invoice_repository.dart';
import 'package:minierp_app/data/repositories/repository_client.dart';
import 'package:minierp_app/features/sales/invoice_providers.dart';
import 'package:minierp_app/features/sales/line_cells.dart' show DescriptionCell;
import 'package:minierp_app/features/sales/sales_invoice_form_page.dart';
import 'package:minierp_app/l10n/app_localizations.dart';
import 'package:pluto_grid/pluto_grid.dart';

/// Rows currently held by the grid's internal state manager (the widget
/// class does not expose it — the page captures it from `onLoaded`).
List<PlutoRow> gridRows(WidgetTester tester) {
  final element = tester.element(find.byType(PlutoGrid));
  final state = (element as StatefulElement).state;
  final manager = (state as dynamic).stateManager as PlutoGridStateManager;
  return manager.rows;
}

class _FakeInvoiceRepository extends InvoiceRepository {
  _FakeInvoiceRepository() : super(RepositoryClient(Dio()));

  @override
  Future<ApiResult<Invoice>> create(Map<String, dynamic> body) async =>
      ApiSuccess(Invoice.fromJson(const <String, dynamic>{}));

  @override
  Future<ApiResult<Invoice>> update(int id, Map<String, dynamic> body) async =>
      ApiSuccess(Invoice.fromJson(const <String, dynamic>{}));

  @override
  Future<ApiResult<Invoice>> invoice(int id) async =>
      ApiSuccess(Invoice.fromJson(const <String, dynamic>{}));

  @override
  Future<ApiResult<void>> delete(int id) async => const ApiSuccess(null);
}

Future<void> _pumpPage(WidgetTester tester) async {
  // The form (grid + always-visible payment panel) is taller than the
  // default 800×600 test surface — give the panel enough room.
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final customers = [
    Customer(
      id: 1,
      customerCode: 'C1',
      customerName: 'Acme Corp',
      currentBalance: 0,
    ),
  ];
  final items = [
    Item(
      id: 1,
      itemCode: 'ITM-1',
      itemName: 'Widget',
      unitOfMeasure: 'Nos',
      currentStock: 10,
      isFinishedGood: true,
    ),
    Item(
      id: 2,
      itemCode: 'ITM-2',
      itemName: 'Gadget',
      unitOfMeasure: 'Nos',
      currentStock: 5,
      isFinishedGood: true,
    ),
  ];

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        invoiceCustomersProvider.overrideWith((ref) async => customers),
        invoiceItemsProvider.overrideWith((ref) async => items),
        invoiceRepositoryProvider.overrideWithValue(_FakeInvoiceRepository()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SalesInvoiceFormPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('line-items grid survives customer selection', (tester) async {
    await _pumpPage(tester);

    expect(gridRows(tester).length, 1,
        reason: 'starts with one empty line');

    // Select the customer → setState rebuild of the whole page.
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acme Corp').last);
    await tester.pumpAndSettle();

    expect(gridRows(tester).length, 1,
        reason: 'rows must survive the customer-select rebuild');
    expect(gridRows(tester).first.cells['item']?.value, '',
        reason: 'the empty line must still be present');
  });

  testWidgets('Add Item inserts a row', (tester) async {
    await _pumpPage(tester);

    expect(gridRows(tester).length, 1);

    await tester.tap(find.text('Add Item'));
    await tester.pumpAndSettle();
    expect(gridRows(tester).length, 2,
        reason: 'Add Item must insert a second line');

    // The new line autofocuses its description cell, opening the item
    // dropdown (intended). Focus the editor, then Escape to dismiss it so
    // it doesn't cover the button below.
    await tester.tap(find.byType(TextField).first, warnIfMissed: false);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // Second insert — the earlier bug wiped rows on every sync, so a
    // repeat insert would also have been lost.
    await tester.tap(find.text('Add Item'));
    await tester.pumpAndSettle();
    expect(gridRows(tester).length, 3);

    // Inserted rows carry the full column-cell set (PlutoGrid crashes on
    // missing cells) and default to the empty line.
    for (final row in gridRows(tester)) {
      expect(row.cells.keys, containsAll(['item', 'qty', 'rate', 'tax']));
      expect(row.cells['item']?.value, '');
    }
  });

  // Repro for: "No products found" appears below the cell after selecting an
  // item — the editor's 50ms open timer must not reopen the dropdown after a
  // selection commit.
  testWidgets('selecting an item closes the dropdown for good',
      (tester) async {
    await _pumpPage(tester);

    // Enter the description cell (edit mode → dropdown opens).
    await tester.tap(find.byType(DescriptionCell).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump();
    expect(find.text('Widget'), findsOneWidget,
        reason: 'pool option listed');

    // Filter and select.
    await tester.enterText(find.byType(TextField).first, 'Wid');
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.text('Widget').first);
    await tester.pumpAndSettle();

    // Overlay must stay closed; the "no products" placeholder is the
    // symptom of the dropdown reopening with a cleared/stale filter, and
    // Gadget (present only in the dropdown, not selected) proves the popup
    // is gone. 'Widget' itself legitimately appears as the selected cell.
    expect(find.text('No products found'), findsNothing,
        reason: 'dropdown must not reopen after selection');
    expect(find.text('Gadget'), findsNothing,
        reason: 'dropdown must be closed after selection');
  });
}
