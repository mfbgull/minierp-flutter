// Sales order form dialog (sales_order_form_dialog.dart) — BUG-006.
//
// Each line carries a tax rate and a discount (none / amount / percent).
// The form must send those to the server and show the shared line total,
// not a bare quantity x price. The server recomputes every amount, so the
// client never sends a total.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/data/models/invoice.dart' show DiscountType;
import 'package:minierp_app/data/models/customer.dart';
import 'package:minierp_app/data/models/item.dart';
import 'package:minierp_app/data/models/sales_order.dart';
import 'package:minierp_app/data/repositories/api_result.dart';
import 'package:minierp_app/data/repositories/repository_client.dart';
import 'package:minierp_app/data/repositories/sales_order_repository.dart';
import 'package:minierp_app/features/inventory/inventory_providers.dart';
import 'package:minierp_app/features/sales_orders/sales_order_form_dialog.dart';
import 'package:minierp_app/features/sales_orders/sales_order_providers.dart';
import 'package:minierp_app/l10n/app_localizations.dart';
import 'package:minierp_app/widgets/searchable_select.dart';

const _customer = Customer(
  id: 1,
  customerCode: 'C-001',
  customerName: 'Bilal Traders',
  currentBalance: 0,
);
const _item = Item(
  id: 7,
  itemCode: 'FG-007',
  itemName: 'Basmati Rice',
  unitOfMeasure: 'kg',
  currentStock: 100,
);

class _FakeSalesOrderRepository extends SalesOrderRepository {
  _FakeSalesOrderRepository() : super(RepositoryClient(Dio()));

  Map<String, dynamic>? lastBody;

  @override
  Future<ApiResult<SalesOrder>> create(Map<String, dynamic> body) async {
    lastBody = body;
    return const ApiSuccess(
      SalesOrder(
        id: 1,
        soNo: 'SO-2026-001',
        customerId: 1,
        customerName: 'Bilal Traders',
        soDate: '2026-11-01',
        status: 'Draft',
      ),
    );
  }
}

Future<void> _openDialog(
  WidgetTester tester,
  _FakeSalesOrderRepository repo, {
  Size size = const Size(1600, 1000),
  Locale? locale,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        salesOrderRepositoryProvider.overrideWithValue(repo),
        salesOrderCustomerOptionsProvider.overrideWith(
          (ref) async => const [_customer],
        ),
        soItemsProvider.overrideWith((ref) async => const [_item]),
        warehousesProvider.overrideWith((ref) async => const []),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showSalesOrderFormDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// The line's quantity / price / tax / discount-value fields, by key so
/// the form's notes field cannot be mistaken for one of them.
Finder _lineField(String name) => find.byKey(ValueKey('so-line-$name'));

/// Fills the single line: item, quantity, price, tax rate.
Future<void> _fillLine(
  WidgetTester tester, {
  String quantity = '2',
  String price = '100',
  String? tax,
}) async {
  await tester.tap(find.byType(SearchableSelect<int>).at(2));
  await tester.pumpAndSettle();
  await tester.tap(find.text('FG-007 — Basmati Rice').last);
  await tester.pumpAndSettle();
  await tester.enterText(_lineField('quantity'), quantity);
  await tester.enterText(_lineField('price'), price);
  if (tax != null) {
    await tester.enterText(_lineField('tax'), tax);
  }
  await tester.pumpAndSettle();
}

/// Picks the header customer (tree order: customer, warehouse, line item).
Future<void> _pickCustomer(WidgetTester tester) async {
  await tester.tap(find.byType(SearchableSelect<int>).at(0));
  await tester.pumpAndSettle();
  await tester.tap(find.text('C-001 — Bilal Traders').last);
  await tester.pumpAndSettle();
}

num _currencyValue(String formatted) {
  final match = RegExp(r'-?\d[\d,]*(?:\.\d+)?').stringMatch(formatted);
  return match == null ? 0 : num.parse(match.replaceAll(',', ''));
}

void main() {
  testWidgets('sends the tax rate and a percentage discount on the line', (
    tester,
  ) async {
    final repo = _FakeSalesOrderRepository();
    await _openDialog(tester, repo);
    await _fillLine(tester, quantity: '2', price: '100', tax: '17');
    await _pickCustomer(tester);

    // Discount kind: Amount / Percent / None dropdown.
    await tester.tap(find.byType(DropdownButtonFormField<DiscountType?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Percent').last);
    await tester.pumpAndSettle();
    await tester.enterText(_lineField('discount-value'), '10');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final items = repo.lastBody!['items'] as List<dynamic>;
    final line = items.first as Map<String, dynamic>;
    expect(line['item_id'], 7);
    expect(line['quantity'], 2);
    expect(line['unit_price'], 100);
    expect(line['tax_rate'], 17);
    expect(line['discount_type'], 'percentage');
    expect(line['discount_value'], 10);
    // The client never sends a total — the server owns it.
    expect(repo.lastBody!.containsKey('total_amount'), isFalse);
  });

  testWidgets('shows the tax-inclusive line amount, not qty x price', (
    tester,
  ) async {
    final repo = _FakeSalesOrderRepository();
    await _openDialog(tester, repo);
    await _fillLine(tester, quantity: '2', price: '100', tax: '17');
    await tester.pumpAndSettle();

    // 200 gross, 17% tax -> 234.00. The bare qty x price sum would be 200.
    // The line amount is the last widget inside the line row.
    final row = find.ancestor(
      of: find.byType(SearchableSelect<int>).at(2),
      matching: find.byType(Row),
    );
    final amountTexts = tester
        .widgetList<Text>(
          find.descendant(of: row.first, matching: find.byType(Text)),
        )
        .map((t) => t.data)
        .whereType<String>()
        .map(_currencyValue)
        .toList();
    expect(amountTexts, contains(234));
    expect(amountTexts, isNot(contains(200)));
  });

  testWidgets('a line with no tax or discount sends neither key', (
    tester,
  ) async {
    final repo = _FakeSalesOrderRepository();
    await _openDialog(tester, repo);
    await _fillLine(tester); // tax 0, no discount
    await _pickCustomer(tester);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final line =
        (repo.lastBody!['items'] as List<dynamic>).first as Map<String, dynamic>;
    expect(line['tax_rate'], 0);
    expect(line.containsKey('discount_type'), isFalse);
    expect(line.containsKey('discount_value'), isFalse);
  });

  testWidgets('lays out without overflow at a narrow width', (tester) async {
    // 500 px is below the 760 px one-line breakpoint, so the line fields
    // must wrap. Before the LayoutBuilder guard this overflowed by 278 px.
    final repo = _FakeSalesOrderRepository();
    await _openDialog(tester, repo, size: const Size(500, 768));
    await _fillLine(tester, tax: '17');
    await tester.pumpAndSettle();

    // A RenderFlex overflow is reported as a test exception. None is allowed.
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('so-line-tax')), findsOneWidget);
    expect(find.byKey(const ValueKey('so-line-discount-value')), findsOneWidget);
  });

  testWidgets('keeps the line on one row at a wide width', (tester) async {
    final repo = _FakeSalesOrderRepository();
    await _openDialog(tester, repo, size: const Size(1600, 1000));
    await _fillLine(tester, tax: '17');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // One line: every field sits at the same height, left to right in
    // source order (ignoring the label offset the shell adds).
    final qty = tester.getCenter(find.byKey(const ValueKey('so-line-quantity')));
    final tax = tester.getCenter(find.byKey(const ValueKey('so-line-tax')));
    final disc = tester.getCenter(
      find.byKey(const ValueKey('so-line-discount-value')),
    );
    expect(tax.dx, greaterThan(qty.dx));
    expect(disc.dx, greaterThan(tax.dx));
    // A wrapped row would put a later field on a much lower line.
    expect((disc.dy - qty.dy).abs(), lessThan(30));
  });

  testWidgets('lays out in Urdu (RTL) without overflow', (tester) async {
    final repo = _FakeSalesOrderRepository();
    await _openDialog(
      tester,
      repo,
      size: const Size(500, 768),
      locale: const Locale('ur'),
    );
    await _fillLine(tester, tax: '17');
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Form));
    expect(Directionality.of(context), TextDirection.rtl);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('so-line-tax')), findsOneWidget);
  });
}
