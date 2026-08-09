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
import 'package:minierp_app/data/models/price_history.dart'
    show ItemPriceHistory;
import 'package:minierp_app/data/repositories/api_result.dart';
import 'package:minierp_app/data/repositories/invoice_repository.dart';
import 'package:minierp_app/data/repositories/repository_client.dart';
import 'package:minierp_app/features/sales/invoice_providers.dart';
import 'package:minierp_app/features/sales/line_cells.dart'
    show DescriptionCell, LineCell;
import 'package:minierp_app/features/sales/line_items_grid.dart'
    show LineColumn;
import 'package:minierp_app/features/sales/sales_invoice_form_page.dart';
import 'package:minierp_app/l10n/app_localizations.dart';
import 'package:minierp_app/widgets/searchable_select.dart';
import 'package:pluto_grid/pluto_grid.dart';

/// Rows currently held by the grid's internal state manager (the widget
/// class does not expose it — the page captures it from `onLoaded`).
List<PlutoRow> gridRows(WidgetTester tester) {
  final element = tester.element(find.byType(PlutoGrid));
  final state = (element as StatefulElement).state;
  final manager = (state as dynamic).stateManager as PlutoGridStateManager;
  return manager.rows;
}

/// Columns (visible only — hidden columns are excluded by the grid).
List<PlutoColumn> gridColumns(WidgetTester tester) {
  final element = tester.element(find.byType(PlutoGrid));
  final state = (element as StatefulElement).state;
  final manager = (state as dynamic).stateManager as PlutoGridStateManager;
  return manager.columns;
}

class _FakeInvoiceRepository extends InvoiceRepository {
  _FakeInvoiceRepository() : super(RepositoryClient(Dio()));

  /// Price-history the repo returns on demand (null = no history).
  ItemPriceHistory? priceHistory;

  /// Bodies posted via `createInvoicePayment`.
  final List<Map<String, dynamic>> postedPayments = [];

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

  @override
  Future<ApiResult<ItemPriceHistory>> itemCustomerPriceHistory({
    required int itemId,
    required int customerId,
  }) async => ApiSuccess(
    priceHistory ??
        const ItemPriceHistory(
          lastPrice: 0,
          lowestPrice: 0,
          highestPrice: 0,
          avgPrice: 0,
          transactionCount: 0,
        ),
  );

  @override
  Future<ApiResult<InvoicePaymentRecord>> createInvoicePayment(
    Map<String, dynamic> body,
  ) async {
    postedPayments.add(body);
    return ApiSuccess(
      InvoicePaymentRecord(
        id: postedPayments.length,
        amount: (body['amount'] as num?) ?? 0,
        method: (body['payment_method'] as String?) ?? '',
      ),
    );
  }
}

/// The single editing cell inside the grid (display cells have no
/// TextField; the payment panel's fields live outside the PlutoGrid).
Finder gridEditor() => find.descendant(
  of: find.byType(PlutoGrid),
  matching: find.byType(TextField),
);

/// The rate cell of the first line (rate and amount both display floating
/// point strings with two decimals, so text targeting alone is ambiguous).
Finder rateCell() => find.byWidgetPredicate(
  (w) => w is LineCell && w.column == LineColumn.rate,
);

Future<void> _pumpPage(
  WidgetTester tester, {
  _FakeInvoiceRepository? repo,
}) async {
  // The form (grid + always-visible payment panel) is taller than the
  // default 800×600 test surface — give the panel enough room.
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final repository = repo ?? _FakeInvoiceRepository();

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
      standardSellingPrice: 25,
    ),
    Item(
      id: 2,
      itemCode: 'ITM-2',
      itemName: 'Gadget',
      unitOfMeasure: 'Nos',
      currentStock: 5,
      isFinishedGood: true,
      standardSellingPrice: 40,
    ),
    // Loose (weighed) item — amount cell is editable for it.
    Item(
      id: 3,
      itemCode: 'SUG-1',
      itemName: 'Sugar',
      unitOfMeasure: 'Kg',
      currentStock: 20,
      isPurchased: true,
      saleType: SaleType.loose,
      standardSellingPrice: 10,
    ),
  ];

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        invoiceCustomersProvider.overrideWith((ref) async => customers),
        invoiceItemsProvider.overrideWith((ref) async => items),
        invoiceRepositoryProvider.overrideWithValue(repository),
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

    expect(gridRows(tester).length, 1, reason: 'starts with one empty line');

    // Select the customer → setState rebuild of the whole page.
    await tester.tap(find.byType(SearchableSelect<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acme Corp').last);
    await tester.pumpAndSettle();

    expect(
      gridRows(tester).length,
      1,
      reason: 'rows must survive the customer-select rebuild',
    );
    expect(
      gridRows(tester).first.cells['item']?.value,
      '',
      reason: 'the empty line must still be present',
    );
  });

  testWidgets('Add Item inserts a row', (tester) async {
    await _pumpPage(tester);

    expect(gridRows(tester).length, 1);

    await tester.tap(find.text('Add Item'));
    await tester.pumpAndSettle();
    expect(
      gridRows(tester).length,
      2,
      reason: 'Add Item must insert a second line',
    );

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
  testWidgets('selecting an item closes the dropdown for good', (tester) async {
    await _pumpPage(tester);

    // Enter the description cell (edit mode → dropdown opens).
    await tester.tap(find.byType(DescriptionCell).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump();
    expect(find.text('Widget'), findsOneWidget, reason: 'pool option listed');

    // Filter and select.
    await tester.enterText(find.byType(TextField).first, 'Wid');
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.text('Widget').first);
    await tester.pumpAndSettle();

    // Overlay must stay closed; the "no products" placeholder is the
    // symptom of the dropdown reopening with a cleared/stale filter, and
    // Gadget (present only in the dropdown, not selected) proves the popup
    // is gone. 'Widget' itself legitimately appears as the selected cell.
    expect(
      find.text('No products found'),
      findsNothing,
      reason: 'dropdown must not reopen after selection',
    );
    expect(
      find.text('Gadget'),
      findsNothing,
      reason: 'dropdown must be closed after selection',
    );
  });

  // ── Scenario-per-spec: keyboard walk (sales-invoice-keyboard-nav) ──

  testWidgets('keyboard: Tab walks fields, Enter appends, Ctrl+Up steppers',
      (tester) async {
    await _pumpPage(tester);

    // Search-selection of the loose item lands on the qty editor.
    await tester.tap(find.byType(DescriptionCell).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80)); // let the dropdown open
    await tester.enterText(find.byType(TextField).first, 'Sug');
    await tester.pump(const Duration(milliseconds: 80));
    // The dropdown renders in an overlay later in the tree than the cell's
    // EditableText, so the option is the last 'Sugar'.
    await tester.tap(find.text('Sugar').last);
    await tester.pumpAndSettle();

    PlutoRow row() => gridRows(tester).first;
    expect(row().cells['description']?.value, 'Sugar');
    expect(
      row().cells['sale_type']?.value,
      SaleType.loose.value,
      reason: 'item sale type must flow into the line',
    );

    // Focus lands on the quantity editor ('1' selected) — Tab walks to the
    // next field and commits (invoice-scope order: qty → rate → tax → amount).
    // enterText focuses the editor, so key delivery is deterministic.
    await tester.enterText(gridEditor(), '2');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(row().cells['qty']?.value, 2, reason: 'Tab commits the qty');

    expect(gridEditor(), findsOneWidget, reason: 'rate editor is active');
    await tester.enterText(gridEditor(), '50');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(row().cells['rate']?.value, 50);

    expect(gridEditor(), findsOneWidget);
    await tester.enterText(gridEditor(), '5');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(row().cells['tax']?.value, 5);

    // Amount cell for a loose line is editable; editing it makes amount the
    // driver → qty recomputes as amount / rate (200 / 50 = 4).
    expect(gridEditor(), findsOneWidget);
    await tester.enterText(gridEditor(), '200');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(row().cells['amount']?.value, 200);
    expect(
      row().cells['qty']?.value,
      closeTo(4, 1e-9),
      reason: 'amount-driven loose line recomputes quantity',
    );

    // Tab past the last column of the last row appends a fresh row.
    expect(gridRows(tester).length, 2, reason: 'end-of-row Tab appends');
  });

  testWidgets('keyboard: Ctrl+ArrowUp steppers a number cell; tax clamps',
      (tester) async {
    await _pumpPage(tester);

    // Enter the tax cell (shows '0').
    await tester.tap(find.text('0').first);
    await tester.pumpAndSettle();
    expect(gridEditor(), findsOneWidget);

    // Focus the editor explicitly (autofocus alone may not win the focus
    // race in tests), then Ctrl+ArrowUp increments by one.
    await tester.tap(gridEditor(), warnIfMissed: false);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(gridRows(tester).first.cells['tax']?.value, 1);

    // Clamp: 120 + Ctrl+ArrowUp stays at 100.
    await tester.enterText(gridEditor(), '120');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(gridRows(tester).first.cells['tax']?.value, 100);

    // Never below zero.
    await tester.enterText(gridEditor(), '0');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(gridRows(tester).first.cells['tax']?.value, 0);
  });

  testWidgets('item search: Escape closes the dropdown without selecting',
      (tester) async {
    await _pumpPage(tester);

    await tester.tap(find.byType(DescriptionCell).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('Widget'), findsOneWidget, reason: 'pool option listed');

    // Focus the editor explicitly, then Escape closes the dropdown while the
    // cell keeps editing.
    await tester.tap(find.byType(TextField).first, warnIfMissed: false);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      find.text('Widget'),
      findsNothing,
      reason: 'Escape closes the dropdown but leaves the cell editing',
    );
    expect(gridEditor(), findsOneWidget);

    // A second Escape exits edit mode (nothing typed → reverts to empty).
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(gridEditor(), findsNothing);
  });

  testWidgets('item search: unmatched query shows the fallback text',
      (tester) async {
    await _pumpPage(tester);

    await tester.tap(find.byType(DescriptionCell).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80)); // dropdown open
    await tester.enterText(find.byType(TextField).first, 'nonsense');
    await tester.pump(const Duration(milliseconds: 80));

    expect(
      find.text('No products found'),
      findsOneWidget,
      reason: 'free-text fallback when nothing matches',
    );
    expect(gridEditor(), findsOneWidget);
  });

  // ── Discount scope (spec: sales-invoice-discount-scope) ──

  testWidgets('discount scope: item scope shows the discount column, invoice hides it',
      (tester) async {
    await _pumpPage(tester);

    bool hasDiscountColumn() =>
        gridColumns(tester).any((c) => c.field == 'discount');

    // Default: invoice scope → discount column hidden in the grid.
    expect(hasDiscountColumn(), isFalse);

    await tester.tap(find.text('Per Item'));
    await tester.pumpAndSettle();
    expect(hasDiscountColumn(), isTrue, reason: 'item scope reveals the column');
    expect(
      find.descendant(
        of: find.byType(PlutoGrid),
        matching: find.text('Discount'),
      ),
      findsOneWidget,
      reason: 'column header becomes visible in the grid',
    );

    await tester.tap(find.text('Invoice'));
    await tester.pumpAndSettle();
    expect(hasDiscountColumn(), isFalse, reason: 'invoice scope hides it again');
  });

  // ── Loose / packed lines (spec: sales-invoice-loose-lines) ──

  testWidgets('loose line: unit-of-measure badge next to the packed qty',
      (tester) async {
    await _pumpPage(tester);

    await tester.tap(find.byType(DescriptionCell).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.enterText(find.byType(TextField).first, 'Sug');
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.text('Sugar').last);
    await tester.pumpAndSettle();

    // Commit the qty (Enter on the last row) so the cell leaves edit mode;
    // then the unit-of-measure badge shows next to the value.
    await tester.tap(gridEditor(), warnIfMissed: false);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      find.text('Kg'),
      findsOneWidget,
      reason: 'unit-of-measure badge renders from the line UoM',
    );
  });

  // ── Payment panel (spec: sales-invoice-payment-panel) ──

  testWidgets('payment panel: record toggle hides/shows the method form',
      (tester) async {
    await _pumpPage(tester);

    // Create mode → one default Cash row and an Amount field per method.
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('Amount'), findsWidgets);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(
      find.text('Cash'),
      findsNothing,
      reason: 'unchecking record-payment hides the method rows',
    );

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(
      find.text('Cash'),
      findsOneWidget,
      reason: 're-checking restores the form',
    );
  });

  // ── Price history (spec: sales-invoice-price-history) ──

  testWidgets('price history: hint shows on rate edit and closes on outside tap',
      (tester) async {
    final repo = _FakeInvoiceRepository()
      ..priceHistory = const ItemPriceHistory(
        lastPrice: 10,
        lowestPrice: 8,
        highestPrice: 12,
        avgPrice: 10,
        transactionCount: 5,
        customerName: 'Acme Corp',
      );
    await _pumpPage(tester, repo: repo);

    // Customer is required for the hint.
    await tester.tap(find.byType(SearchableSelect<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acme Corp').last);
    await tester.pumpAndSettle();

    // Pick an item so the line has item_id / rate (Widget sells at 25).
    await tester.tap(find.byType(DescriptionCell).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.enterText(find.byType(TextField).first, 'Wid');
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.text('Widget').last);
    await tester.pumpAndSettle();

    // Edit the rate cell (Widget sells at 25) — rate and amount both show
    // '25.00', so target the rate cell by type.
    await tester.tap(rateCell());
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Price history'),
      findsOneWidget,
      reason: 'hint renders for an item with transaction history',
    );

    // Click outside the hint (blank header area, above the form) → closes
    // without the tap stealing the rate editor's focus.
    await tester.tapAt(const Offset(600, 20));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Price history'),
      findsNothing,
      reason: 'outside tap dismisses the hint',
    );
    expect(gridEditor(), findsOneWidget, reason: 'rate editor keeps focus');
  });

  testWidgets('price history: no hint when item/customer are unset',
      (tester) async {
    await _pumpPage(
      tester,
      repo: _FakeInvoiceRepository()
        ..priceHistory = const ItemPriceHistory(
          lastPrice: 10,
          lowestPrice: 8,
          highestPrice: 12,
          avgPrice: 10,
          transactionCount: 5,
        ),
    );

    // No customer selected, no item → editing the rate must not fetch/show.
    await tester.tap(rateCell());
    await tester.pumpAndSettle();
    expect(gridEditor(), findsOneWidget);
    expect(find.textContaining('Price history'), findsNothing);
  });
}
