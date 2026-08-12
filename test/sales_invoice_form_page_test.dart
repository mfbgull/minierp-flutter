// Invoice form page (sales_invoice_form_page.dart) regression tests:
// the line-items PlutoGrid must survive parent rebuilds (e.g. selecting
// the customer) and Add Item must insert rows.

import 'dart:async';

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
    show GridNavController, LineColumn;
import 'package:minierp_app/features/sales/models/sales_forms.dart'
    show DiscountScope;
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

  /// Last body passed to [create] (for in-flight-commit assertions).
  Map<String, dynamic>? lastCreateBody;

  /// Last body passed to [update] (edit-mode in-flight-commit assertions).
  Map<String, dynamic>? lastUpdateBody;

  @override
  Future<ApiResult<Invoice>> create(Map<String, dynamic> body) async {
    lastCreateBody = body;
    return ApiSuccess(Invoice.fromJson(const <String, dynamic>{}));
  }

  @override
  Future<ApiResult<Invoice>> update(int id, Map<String, dynamic> body) async {
    lastUpdateBody = body;
    return ApiSuccess(Invoice.fromJson(const <String, dynamic>{}));
  }

  @override
  Future<ApiResult<List<InvoicePaymentRecord>>> invoicePayments(int id) async =>
      const ApiSuccess(<InvoicePaymentRecord>[]);

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
Finder rateCell() =>
    find.byWidgetPredicate((w) => w is LineCell && w.column == LineColumn.rate);

/// The customer popup's search field — the only TextField with a search
/// prefix icon (the grid editor and the payment/notes fields don't have
/// one, and `.first` would hit the payment panel instead of the overlay).
Finder customerPopupSearch() => find.byWidgetPredicate(
  (w) =>
      w is TextField &&
      w.decoration?.prefixIcon is Icon &&
      (w.decoration!.prefixIcon! as Icon).icon == Icons.search,
);

Future<void> _pumpPage(
  WidgetTester tester, {
  _FakeInvoiceRepository? repo,
  Invoice? invoice,
  Future<List<Item>>? itemsFuture,
  bool settle = true,
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
    // Second customer so popup arrow-navigation can be exercised.
    Customer(
      id: 2,
      customerCode: 'C2',
      customerName: 'Beta Ltd',
      currentBalance: 0,
    ),
  ];
  final items = _testItemPool();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        invoiceCustomersProvider.overrideWith((ref) async => customers),
        invoiceItemsProvider.overrideWith(
          (ref) => itemsFuture ?? Future.value(items),
        ),
        invoiceRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SalesInvoiceFormPage(invoice: invoice),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // One frame renders the first build; the caller pumps further (a
    // pending item pool keeps the grid placeholder's spinner animating,
    // so pumpAndSettle would never settle).
    await tester.pump();
  }
}

/// Shared item pool for the invoice form tests (Widget / Gadget packed,
/// Sugar loose).
List<Item> _testItemPool() => [
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

/// An invoice with one prefilled line (Widget ×10 @100) — used by the
/// edit-mode tests. The line carries `item_id` but no `description`, so
/// the grid resolves the item name from the search pool (the imported-
/// line fallback path, spec §8.19).
Invoice _editInvoice() => const Invoice(
  id: 42,
  invoiceNo: 'INV-EDIT-1',
  customerId: 1,
  invoiceDate: '2026-08-11',
  totalAmount: 1000,
  paidAmount: 0,
  balanceAmount: 1000,
  status: 'Unpaid',
  discountScope: 'invoice',
  items: [
    InvoiceItem(
      id: 1,
      invoiceId: 42,
      itemId: 1,
      quantity: 10,
      unitPrice: 100,
      amount: 1000,
      taxRate: 0,
      discountType: 'none',
      discountValue: 0,
      returnedQty: 0,
    ),
  ],
);

void main() {
  testWidgets('line-items grid survives customer selection', (tester) async {
    await _pumpPage(tester);

    expect(gridRows(tester).length, 1, reason: 'starts with one empty line');

    // The customer popup auto-opens on load (create mode); selecting
    // rebuilds the whole page and hands focus to the grid.
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
    // Dismiss the auto-opened customer popup so it doesn't cover the form.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

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

  testWidgets('selecting an item closes the dropdown for good', (tester) async {
    await _pumpPage(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // Enter the description cell — typing opens the dropdown.
    await tester.tap(find.byType(DescriptionCell).first);
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'Wid');
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('Widget'), findsOneWidget, reason: 'pool option listed');

    // Select.
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

  testWidgets('keyboard: Tab walks fields, Enter appends, Ctrl+Up steppers', (
    tester,
  ) async {
    await _pumpPage(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    // Invoice scope → discount column hidden, so the walk is
    // qty → rate → tax → amount (the per-item default inserts a
    // discount cell into the walk).
    await tester.tap(find.text('Invoice'));
    await tester.pumpAndSettle();

    // Search-selection of the loose item lands on the qty editor.
    await tester.tap(find.byType(DescriptionCell).first);
    await tester.pump();
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

  testWidgets('keyboard: Ctrl+ArrowUp steppers a number cell; tax clamps', (
    tester,
  ) async {
    await _pumpPage(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    // Invoice scope hides the discount column, keeping the first '0'
    // unambiguous (the per-item default shows discount '0' before tax).
    await tester.tap(find.text('Invoice'));
    await tester.pumpAndSettle();

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

  testWidgets('item search: Escape closes the dropdown without selecting', (
    tester,
  ) async {
    await _pumpPage(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DescriptionCell).first);
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'Wid');
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

  testWidgets('item search: unmatched query shows the fallback text', (
    tester,
  ) async {
    await _pumpPage(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DescriptionCell).first);
    await tester.pump();
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

  testWidgets(
    'discount scope: per-item is the default and shows the discount column; invoice hides it',
    (tester) async {
      await _pumpPage(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      bool hasDiscountColumn() =>
          gridColumns(tester).any((c) => c.field == 'discount');

      // New invoices default to per-item scope → discount column visible.
      expect(
        hasDiscountColumn(),
        isTrue,
        reason: 'per-item is the default → discount column visible',
      );
      expect(
        find.descendant(
          of: find.byType(PlutoGrid),
          matching: find.text('Discount'),
        ),
        findsOneWidget,
        reason: 'column header is visible in the grid by default',
      );
      final perItemChip = tester.widget<ChoiceChip>(
        find.ancestor(
          of: find.text('Per Item'),
          matching: find.byType(ChoiceChip),
        ),
      );
      expect(
        perItemChip.selected,
        isTrue,
        reason: 'the Per Item chip is selected by default',
      );

      await tester.tap(find.text('Invoice'));
      await tester.pumpAndSettle();
      expect(
        hasDiscountColumn(),
        isFalse,
        reason: 'invoice scope hides the column',
      );

      await tester.tap(find.text('Per Item'));
      await tester.pumpAndSettle();
      expect(
        hasDiscountColumn(),
        isTrue,
        reason: 'item scope reveals it again',
      );
    },
  );

  // ── Loose / packed lines (spec: sales-invoice-loose-lines) ──

  testWidgets('loose line: unit-of-measure badge next to the packed qty', (
    tester,
  ) async {
    await _pumpPage(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DescriptionCell).first);
    await tester.pump();
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

  testWidgets('payment panel: record toggle hides/shows the method form', (
    tester,
  ) async {
    await _pumpPage(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

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

  testWidgets(
    'price history: hint shows on rate edit and closes on outside tap',
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

      // Customer is required for the hint — the popup is already open.
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
    },
  );

  testWidgets('price history: no hint when item/customer are unset', (
    tester,
  ) async {
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

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // No customer selected, no item → editing the rate must not fetch/show.
    await tester.tap(rateCell());
    await tester.pumpAndSettle();
    expect(gridEditor(), findsOneWidget);
    expect(find.textContaining('Price history'), findsNothing);
  });

  // ── New keyboard/focus flow (spec: invoice-form-keyboard) ──

  testWidgets('customer popup auto-opens on load (create mode)', (
    tester,
  ) async {
    await _pumpPage(tester);

    expect(
      find.text('Acme Corp'),
      findsOneWidget,
      reason: 'the customer popup opens automatically on load',
    );
    expect(
      find.byType(TextField),
      findsWidgets,
      reason: 'the popup search field is present',
    );
  });

  testWidgets(
    'customer selection hands focus to the first item cell, no dropdown',
    (tester) async {
      await _pumpPage(tester);

      await tester.tap(find.text('Acme Corp').last);
      await tester.pumpAndSettle();

      expect(
        gridEditor(),
        findsOneWidget,
        reason: 'first-row description cell enters edit mode',
      );
      expect(
        find.text('Widget'),
        findsNothing,
        reason: 'dropdown stays closed until typing starts',
      );
    },
  );

  testWidgets('grid cell editors hold focus when entered (keyboard-ready)', (
    tester,
  ) async {
    await _pumpPage(tester);

    // Customer handoff → the description editor must hold focus (not just
    // render): otherwise the IME never connects and typing does nothing.
    // Regression: TextField autofocus only registers a scope candidate, so
    // the editor rendered focus-less in the real app (spec §2.3).
    await tester.tap(find.text('Acme Corp').last);
    await tester.pumpAndSettle();
    final handoffEditor = tester.widget<TextField>(gridEditor());
    expect(
      handoffEditor.focusNode?.hasFocus,
      isTrue,
      reason: 'handoff editor must hold focus (IME-ready)',
    );

    // A real key through the focus system must reach the editor: Escape
    // exits edit mode (blocked Enter means no append can prove delivery).
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      gridEditor(),
      findsNothing,
      reason: 'Escape reached the focused editor and exited edit mode',
    );

    // Mouse-click the item cell → its editor holds focus too.
    await tester.tap(find.byType(DescriptionCell).first);
    await tester.pumpAndSettle();
    final clickedEditor = tester.widget<TextField>(gridEditor());
    expect(
      clickedEditor.focusNode?.hasFocus,
      isTrue,
      reason: 'mouse-clicked cell editor must hold focus',
    );

    // Same for a number cell (qty display '1').
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is LineCell && w.column == LineColumn.quantity,
      ),
    );
    await tester.pumpAndSettle();
    final qtyEditor = tester.widget<TextField>(gridEditor());
    expect(
      qtyEditor.focusNode?.hasFocus,
      isTrue,
      reason: 'number-cell editor must hold focus',
    );
  });

  testWidgets(
    'grid editors pass character keys to the IME (not swallowed by the FocusScope)',
    (tester) async {
      await _pumpPage(tester);

      // Customer handoff → description editor active.
      await tester.tap(find.text('Acme Corp').last);
      await tester.pumpAndSettle();
      expect(gridEditor(), findsOneWidget);

      // Watch PlutoGrid's key-manager subject: the grid's FocusScope
      // returns `handled` for every key that bubbles past the cell editor,
      // which blocks the platform IME on desktop — the real-app bug where
      // typing in the cell did nothing. A character key that escapes the
      // scope (the editor arms the one-shot `skip` flag via `passToIME`,
      // which the scope honors by returning `ignored`) is never forwarded
      // here, so `forwarded` stays false.
      final element = tester.element(find.byType(PlutoGrid));
      final state = (element as StatefulElement).state;
      final manager = (state as dynamic).stateManager as PlutoGridStateManager;
      var forwarded = false;
      final sub = manager.keyManager!.subject.listen((_) => forwarded = true);
      addTearDown(sub.cancel);

      // The editor must hold focus for the key to reach our handler at all
      // (otherwise the probe could pass vacuously with the key bypassing
      // the grid entirely).
      expect(
        tester.widget<TextField>(gridEditor()).focusNode?.hasFocus,
        isTrue,
        reason: 'premise: the editor holds focus before the key is sent',
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.pump();

      expect(
        forwarded,
        isFalse,
        reason: 'the character key escaped the FocusScope unconsumed',
      );
    },
  );

  testWidgets(
    'typing several characters keeps the caret (no re-select on rebuild)',
    (tester) async {
      await _pumpPage(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // Enter the description cell and type the first character (simulates
      // the platform IME commit — real keystrokes aren't reproducible in
      // widget tests). `_filter` rebuilds the editor on every keystroke.
      await tester.tap(find.byType(DescriptionCell).first);
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'W');
      await tester.pump();

      final editor = tester.widget<TextField>(gridEditor());
      final sel = editor.controller!.selection;
      expect(
        sel.isCollapsed,
        isTrue,
        reason:
            'the caret stays collapsed after typing — a full re-select '
            'would make the next commit replace the text (one-character bug)',
      );
      expect(
        sel.baseOffset,
        1,
        reason: 'the caret sits at the end of the typed text',
      );

      // The next IME commit inserts at the caret instead of replacing.
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: editor.controller!.text.replaceRange(sel.start, sel.end, 'i'),
          selection: TextSelection.collapsed(offset: sel.baseOffset + 1),
        ),
      );
      await tester.pump();
      expect(
        tester.widget<TextField>(gridEditor()).controller!.text,
        'Wi',
        reason: 'the second character is inserted, not replacing the first',
      );
    },
  );

  testWidgets(
    'arrow boundary: Right at the last editable cell stays in edit mode (packed)',
    (tester) async {
      await _pumpPage(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      // Invoice scope → tax is the last editable cell for packed lines.
      await tester.tap(find.text('Invoice'));
      await tester.pumpAndSettle();

      // Select packed Widget → qty editor active.
      await tester.tap(find.byType(DescriptionCell).first);
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'Wid');
      await tester.pump();
      await tester.tap(find.text('Widget').last);
      await tester.pumpAndSettle();

      // Walk qty → rate → tax (invoice scope: tax is the last editable
      // cell for a packed line — amount is read-only).
      await tester.enterText(gridEditor(), '2');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.enterText(gridEditor(), '30');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(gridEditor(), findsOneWidget, reason: 'tax editor is active');

      // Type an in-flight value, then Right — the boundary must do nothing:
      // no commit, no move, edit mode stays alive with the value in the
      // editor (the old code committed first and ended edit mode).
      await tester.enterText(gridEditor(), '5');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(
        gridEditor(),
        findsOneWidget,
        reason: 'Right at the last editable cell keeps edit mode alive',
      );
      expect(
        tester.widget<TextField>(gridEditor()).controller?.text,
        '5',
        reason: 'the in-flight value is preserved (no commit, no move)',
      );
    },
  );

  testWidgets(
    'arrow boundary: Right at the loose amount cell stays in edit mode',
    (tester) async {
      await _pumpPage(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      // Invoice scope → amount is the last editable cell for loose lines.
      await tester.tap(find.text('Invoice'));
      await tester.pumpAndSettle();

      // Select loose Sugar → qty editor active.
      await tester.tap(find.byType(DescriptionCell).first);
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'Sug');
      await tester.pump();
      await tester.tap(find.text('Sugar').last);
      await tester.pumpAndSettle();

      // Walk qty → rate → tax → amount (loose: amount is editable and is
      // the last cell).
      await tester.enterText(gridEditor(), '2');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.enterText(gridEditor(), '50');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.enterText(gridEditor(), '5');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(gridEditor(), findsOneWidget, reason: 'amount editor is active');

      await tester.enterText(gridEditor(), '200');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(
        gridEditor(),
        findsOneWidget,
        reason: 'Right at the loose amount cell keeps edit mode alive',
      );
      expect(
        tester.widget<TextField>(gridEditor()).controller?.text,
        '200',
        reason: 'the in-flight amount is preserved',
      );
    },
  );

  testWidgets(
    'arrow boundary: Left at the last editable cell moves left normally',
    (tester) async {
      await _pumpPage(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      // Invoice scope → tax is the last editable cell for packed lines.
      await tester.tap(find.text('Invoice'));
      await tester.pumpAndSettle();

      // Select packed Widget → qty editor active; walk to tax.
      await tester.tap(find.byType(DescriptionCell).first);
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'Wid');
      await tester.pump();
      await tester.tap(find.text('Widget').last);
      await tester.pumpAndSettle();
      await tester.enterText(gridEditor(), '2');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.enterText(gridEditor(), '30');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      // Type an in-flight tax, then Left from the last editable cell: it
      // commits the tax and moves back to the rate editor (edit mode stays
      // alive — Left is NOT a boundary no-op, only Right is).
      await tester.enterText(gridEditor(), '5');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(
        gridEditor(),
        findsOneWidget,
        reason: 'Left moves to the rate editor',
      );
      expect(
        gridRows(tester).first.cells['tax']?.value,
        5,
        reason: 'the last cell is committed before the left move',
      );
      expect(
        tester.widget<TextField>(gridEditor()).controller?.text,
        '30',
        reason: 'the rate editor is active (its in-flight value is retained)',
      );
    },
  );

  testWidgets(
    'arrow boundary: Up at the top row / Down at the last row do nothing',
    (tester) async {
      await _pumpPage(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // Select packed Widget → qty editor active (single row = top & last).
      await tester.tap(find.byType(DescriptionCell).first);
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'Wid');
      await tester.pump();
      await tester.tap(find.text('Widget').last);
      await tester.pumpAndSettle();
      expect(gridEditor(), findsOneWidget, reason: 'qty editor is active');

      await tester.enterText(gridEditor(), '2');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        gridEditor(),
        findsOneWidget,
        reason: 'Down at the last row stays editing (no append, no exit)',
      );
      expect(
        tester.widget<TextField>(gridEditor()).controller?.text,
        '2',
        reason: 'the in-flight qty is preserved',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(
        gridEditor(),
        findsOneWidget,
        reason: 'Up at the top row stays editing',
      );
      expect(
        tester.widget<TextField>(gridEditor()).controller?.text,
        '2',
        reason: 'the in-flight qty is preserved across Up too',
      );
    },
  );

  test('GridNavController: character keys arm the PlutoGrid skip flag', () {
    final row = PlutoRow(cells: {'qty': PlutoCell(value: 1)});
    final result = PlutoGridKeyEventResult();
    final nav = GridNavController(
      scopeOf: () => DiscountScope.invoice,
      rowsOf: () => [row],
      onGridChanged: () {},
      onMoveResolved: (_) {},
    )..keyEventResult = result;

    final keyA = KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.keyA,
      logicalKey: LogicalKeyboardKey.keyA,
      character: 'a',
      timeStamp: Duration.zero,
    );
    final handled = nav.handleEditKey(
      row,
      LineColumn.quantity,
      keyA,
      isLastRow: true,
      isTextCaretStart: false,
      isTextCaretEnd: false,
    );
    expect(handled, KeyEventResult.ignored);
    expect(
      result.isSkip,
      isTrue,
      reason:
          'the skip flag is armed so the grid FocusScope lets the key through',
    );
  });

  testWidgets('item dropdown opens only after typing and closes when cleared', (
    tester,
  ) async {
    await _pumpPage(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DescriptionCell).first);
    await tester.pump();
    expect(gridEditor(), findsOneWidget);
    expect(
      find.text('Widget'),
      findsNothing,
      reason: 'no auto-open on edit-mode entry',
    );

    await tester.enterText(find.byType(TextField).first, 'Wid');
    await tester.pump();
    expect(find.text('Widget'), findsOneWidget, reason: 'opens on typing');

    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump();
    expect(
      find.text('Widget'),
      findsNothing,
      reason: 'clearing the text closes the dropdown',
    );
  });

  testWidgets(
    'item dropdown: Up/Down arrows move the highlight and scroll the open list',
    (tester) async {
      // A pool large enough to overflow the 300px dropdown (52px rows) so
      // scrolling is actually exercised.
      final bigPool = [
        for (var i = 1; i <= 20; i++)
          Item(
            id: i,
            itemCode: 'ITM-$i',
            itemName: 'Item $i',
            unitOfMeasure: 'Nos',
            currentStock: 10,
            isFinishedGood: true,
            standardSellingPrice: 10,
          ),
      ];
      await _pumpPage(tester, itemsFuture: Future.value(bigPool));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // Type a query matching every item → the dropdown opens.
      await tester.tap(find.byType(DescriptionCell).first);
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'Item');
      await tester.pump();
      expect(find.text('Item 1'), findsOneWidget, reason: 'dropdown is open');

      // The dropdown lives in a separate overlay tree — `setState` in the
      // cell does NOT re-render it. Without an explicit overlay refresh the
      // highlight stays frozen on the first row and the list never scrolls
      // (the real-app bug). Press Down far enough that the highlight is off
      // the visible viewport.
      for (var i = 0; i < 12; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
      }

      // The option list must have scrolled (scroll offset > 0) — the
      // Scrollable ancestor of a now-visible option is the dropdown list's.
      final scrollableFinder = find
          .ancestor(of: find.text('Item 13'), matching: find.byType(Scrollable))
          .first;
      final scrollable = tester.state<ScrollableState>(scrollableFinder);
      expect(
        scrollable.position.pixels,
        greaterThan(0),
        reason: 'the dropdown list scrolled to keep the highlight in view',
      );

      // The highlight followed the arrows: Enter selects the 13th option
      // (index 12) and hands off to the qty editor.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        gridRows(tester).first.cells['description']?.value,
        'Item 13',
        reason: 'Enter selects the arrow-highlighted item (index 12)',
      );
      expect(
        gridEditor(),
        findsOneWidget,
        reason: 'selection hands off to qty',
      );
    },
  );

  testWidgets(
    'item cell: Right arrow selects the highlighted item and moves to qty',
    (tester) async {
      await _pumpPage(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DescriptionCell).first);
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'Wid');
      await tester.pump();
      expect(find.text('Widget'), findsOneWidget, reason: 'dropdown is open');

      // Right while the dropdown is open = select the highlighted item and
      // move to qty (mirrors the reference's ArrowRight → save + focus qty).
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        gridRows(tester).first.cells['description']?.value,
        'Widget',
        reason: 'Right selects the highlighted item',
      );
      expect(gridRows(tester).first.cells['item']?.value, '1');
      expect(
        gridEditor(),
        findsOneWidget,
        reason: 'focus moves to the qty editor',
      );
    },
  );

  testWidgets('item cell: Right with an item already chosen moves to qty', (
    tester,
  ) async {
    await _pumpPage(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // Select Widget → focus lands on the qty editor.
    await tester.tap(find.byType(DescriptionCell).first);
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'Wid');
    await tester.pump();
    await tester.tap(find.text('Widget').last);
    await tester.pumpAndSettle();
    expect(gridEditor(), findsOneWidget, reason: 'qty editor active');

    // Walk back to the description cell (Shift+Tab), then Right — the row
    // already has an item, so Right commits and moves forward to qty.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(gridEditor(), findsOneWidget, reason: 'description editor active');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(
      gridEditor(),
      findsOneWidget,
      reason: 'Right with an item chosen moves to the qty editor',
    );
    expect(
      tester.widget<TextField>(gridEditor()).controller?.text,
      '1',
      reason: 'the qty editor prefills the default quantity',
    );
  });

  testWidgets('no-match Enter is blocked (a real item is required)', (
    tester,
  ) async {
    await _pumpPage(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DescriptionCell).first);
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'zzz');
    await tester.pump();
    expect(find.text('No products found'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      gridEditor(),
      findsOneWidget,
      reason: 'Enter is blocked; the cell keeps editing',
    );
    expect(gridRows(tester).first.cells['description']?.value, '');
    expect(gridRows(tester).first.cells['item']?.value, '');
  });

  testWidgets('Shift+Tab walks to the previous cell', (tester) async {
    await _pumpPage(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // Select Widget → qty editor active.
    await tester.tap(find.byType(DescriptionCell).first);
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'Wid');
    await tester.pump();
    await tester.tap(find.text('Widget').last);
    await tester.pumpAndSettle();
    expect(gridEditor(), findsOneWidget, reason: 'qty editor is active');

    await tester.enterText(gridEditor(), '2');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(
      gridRows(tester).first.cells['qty']?.value,
      2,
      reason: 'Shift+Tab commits',
    );
    expect(
      gridEditor(),
      findsOneWidget,
      reason: 'focus returns to the description editor',
    );
  });

  testWidgets('Ctrl+S commits the in-flight cell before saving', (
    tester,
  ) async {
    final repo = _FakeInvoiceRepository();
    await _pumpPage(tester, repo: repo);

    // Select the customer (popup already open) → hands focus to the grid.
    await tester.tap(find.text('Acme Corp').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Wid');
    await tester.pump();
    await tester.tap(find.text('Widget').last);
    await tester.pumpAndSettle();

    // Type a quantity without leaving the cell.
    await tester.enterText(gridEditor(), '7');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(repo.lastCreateBody, isNotNull);
    expect(repo.lastCreateBody!['customer_id'], 1);
    expect(
      repo.lastCreateBody!['discount_scope'],
      'item',
      reason: 'new invoices default to per-item discount scope',
    );
    expect(repo.lastCreateBody!['discount_value'], 0);
    final items = repo.lastCreateBody!['items'] as List;
    expect(
      (items.first as Map)['quantity'],
      7,
      reason: 'the in-flight quantity is committed before saving',
    );
  });

  testWidgets('Alt+C opens the customer popup', (tester) async {
    await _pumpPage(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Acme Corp'), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(
      find.text('Acme Corp'),
      findsOneWidget,
      reason: 'Alt+C reopens the customer popup',
    );
  });

  testWidgets('Shift+Enter focuses the payment amount field (spec §7/§8.20)', (
    tester,
  ) async {
    await _pumpPage(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // The first method's Amount field is the only payment TextField with
    // an explicit focusNode (others are null) — a unique focus probe.
    bool amountFocused() => tester.any(
      find.byWidgetPredicate(
        (w) => w is TextField && w.focusNode != null && w.focusNode!.hasFocus,
      ),
    );

    // Record-payment on (default): the field exists already.
    expect(find.text('Cash'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(amountFocused(), isTrue, reason: 'amount field focused');

    // Record-payment off: the payment form (and its fields) unmount.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('Cash'), findsNothing, reason: 'form hidden');
    expect(amountFocused(), isFalse);

    // Shift+Enter flips it back on and focuses the amount field once the
    // panel has rebuilt (the one-frame-later rebuild must be waited for).
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('Cash'), findsOneWidget, reason: 'form restored');
    expect(amountFocused(), isTrue, reason: 'amount focused after flip-on');
  });

  // ── Edit mode (spec §2.2 / §8.19) ─────────────────────────────

  testWidgets(
    'edit mode: first item cell auto-focuses on load, dropdown closed',
    (tester) async {
      final repo = _FakeInvoiceRepository();
      await _pumpPage(tester, repo: repo, invoice: _editInvoice());

      expect(
        gridRows(tester).length,
        1,
        reason: 'the prefilled line row is present',
      );
      expect(
        gridEditor(),
        findsOneWidget,
        reason: 'the first-row description cell is in edit mode on load',
      );

      // Open-on-type: the dropdown stays closed until the user types.
      expect(find.text('Gadget'), findsNothing);

      // Edit mode must NOT auto-open the customer popup — 'Acme Corp'
      // appears exactly once (the trigger's selected label), not twice
      // (label + popup option).
      expect(find.text('Acme Corp'), findsOneWidget);
    },
  );

  testWidgets('edit mode: prefilled description is select-all-able', (
    tester,
  ) async {
    final repo = _FakeInvoiceRepository();
    await _pumpPage(tester, repo: repo, invoice: _editInvoice());

    final editor = tester.widget<TextField>(gridEditor());
    expect(editor.controller, isNotNull);
    expect(
      editor.controller!.text,
      'Widget',
      reason:
          'editor prefills the item-name fallback (imported lines carry no description)',
    );
    final sel = editor.controller!.selection;
    expect(sel.isValid, isTrue);
    expect(sel.start, 0);
    expect(
      sel.end,
      'Widget'.length,
      reason: 'all text is selected so typing replaces it',
    );
  });

  testWidgets('edit mode: Ctrl+S PUTs with the in-flight cell committed', (
    tester,
  ) async {
    final repo = _FakeInvoiceRepository();
    await _pumpPage(tester, repo: repo, invoice: _editInvoice());

    // Tap the qty display ('10') → qty editor active (the description
    // cell blocks Tab, so the click-to-edit path is used).
    await tester.tap(find.text('10'));
    await tester.pumpAndSettle();
    expect(gridEditor(), findsOneWidget, reason: 'qty editor active');

    // Type a new quantity without leaving the cell.
    await tester.enterText(gridEditor(), '7');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(repo.lastCreateBody, isNull, reason: 'edit mode must not create');
    expect(repo.lastUpdateBody, isNotNull, reason: 'edit mode PUTs');
    expect(repo.lastUpdateBody!['customer_id'], 1);
    final items = repo.lastUpdateBody!['items'] as List;
    expect(items, hasLength(1));
    expect((items.first as Map)['item_id'], 1);
    expect(
      (items.first as Map)['quantity'],
      7,
      reason: 'the in-flight quantity is committed before the PUT',
    );
  });

  // ── Customer popup edge cases (spec §8.15–§8.18) ─────────────

  testWidgets(
    'customer popup: typing auto-highlights, arrows wrap, Escape closes',
    (tester) async {
      await _pumpPage(tester);

      // Popup auto-opens on load; the search field holds focus.
      expect(find.text('Acme Corp'), findsOneWidget);

      // Typing narrows to a single match which auto-highlights — Enter
      // selects it directly (no arrow needed) and hands off to the grid.
      await tester.enterText(customerPopupSearch(), 'Acm');
      await tester.pump();
      expect(find.text('Acme Corp'), findsOneWidget);
      expect(find.text('Beta Ltd'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        gridEditor(),
        findsOneWidget,
        reason: 'Enter on the auto-highlighted match selects and hands off',
      );

      // Reopen (Alt+C). An empty filter lists both customers; arrows wrap
      // the highlight (Down→Down→Down back to Acme, Up wraps to Beta) and
      // Enter selects the highlighted one — functional arrow proof.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(find.text('Beta Ltd'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // wraps → Acme
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp); // wraps → Beta
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        find.text('Beta Ltd'),
        findsOneWidget,
        reason: 'the trigger shows the arrow-selected customer',
      );

      // Escape closes without selecting; a second Escape is a no-op and the
      // previously selected customer is kept.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        find.text('Acme Corp'),
        findsNothing,
        reason: 'popup closed, nothing re-selected',
      );
      expect(
        find.text('Beta Ltd'),
        findsOneWidget,
        reason: 'the trigger keeps the previously selected customer',
      );

      // A no-match query makes arrows and Enter inert (spec §8.17): nothing
      // gets selected, the popup stays open, and Escape still closes it.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      await tester.enterText(customerPopupSearch(), 'zzz');
      await tester.pump();
      expect(
        find.text('No results'),
        findsOneWidget,
        reason: 'no-match fallback',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        find.text('Beta Ltd'),
        findsOneWidget,
        reason:
            'arrows/Enter are inert on a no-match list — Beta stays selected',
      );
      expect(
        find.text('No results'),
        findsOneWidget,
        reason: 'the popup stays open after the inert keys',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        find.text('No results'),
        findsNothing,
        reason: 'Escape still closes',
      );
    },
  );

  testWidgets(
    'items resolving while the customer popup is open: no crash, no stale pool',
    (tester) async {
      final repo = _FakeInvoiceRepository();
      final completer = Completer<List<Item>>();
      await _pumpPage(
        tester,
        repo: repo,
        itemsFuture: completer.future,
        settle: false,
      );

      // The customer popup auto-opens on load — wait (bounded) for it while
      // the item pool is still loading (the grid shows its placeholder).
      for (
        var i = 0;
        i < 10 && find.text('Acme Corp').evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Acme Corp'), findsOneWidget);
      expect(
        find.byType(CircularProgressIndicator),
        findsOneWidget,
        reason: 'grid placeholder while the item pool is pending',
      );

      // Items arrive while the popup is open — no crash, and the popup is
      // unaffected (the pool is independent of the customer list).
      completer.complete(_testItemPool());
      await tester.pumpAndSettle();
      expect(
        find.text('Acme Corp'),
        findsOneWidget,
        reason: 'popup still open after the item pool resolves',
      );

      // Selecting the customer hands off to a working item dropdown.
      await tester.tap(find.text('Acme Corp').last);
      await tester.pumpAndSettle();
      expect(gridEditor(), findsOneWidget, reason: 'handoff reached the grid');
      await tester.enterText(find.byType(TextField).first, 'Wid');
      await tester.pump();
      expect(
        find.text('Widget'),
        findsOneWidget,
        reason: 'the late pool drives the item dropdown',
      );
    },
  );

  testWidgets(
    'grid-click while the customer popup is open closes it without entering a cell',
    (tester) async {
      await _pumpPage(tester);

      // Popup open, nothing selected yet.
      expect(find.text('Acme Corp'), findsOneWidget);

      // Tap an amount cell — the popup's option list covers the first
      // row's LEFT cells in the fixed layout, so the amount cell (right
      // of the list) is under the full-screen barrier. The barrier
      // swallows the click: popup closes, no cell is entered, no customer
      // is selected.
      await tester.tap(
        find
            .byWidgetPredicate(
              (w) => w is LineCell && w.column == LineColumn.amount,
            )
            .first,
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Acme Corp'),
        findsNothing,
        reason: 'the barrier tap closed the popup',
      );
      expect(
        gridEditor(),
        findsNothing,
        reason: 'the click did not pass through to a grid cell',
      );

      // A second click now reaches a cell.
      await tester.tap(find.byType(DescriptionCell).first);
      await tester.pumpAndSettle();
      expect(
        gridEditor(),
        findsOneWidget,
        reason: 'second click enters the cell',
      );
    },
  );
}
