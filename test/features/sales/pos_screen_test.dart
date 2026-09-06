// POS screen widget tests — covers cart operations, barcode scanner,
// and checkout flow.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/features/sales/pos_models.dart';
import 'package:minierp_app/features/sales/pos_providers.dart';
import 'package:minierp_app/features/sales/pos_screen.dart';
import 'package:minierp_app/l10n/app_localizations.dart';

/// Creates a PosItem for testing.
PosItem _testItem({
  int id = 1,
  String code = 'ITEM001',
  String name = 'Test Item',
  double price = 100.0,
  int stock = 50,
  String? category,
}) =>
    PosItem(
      id: id,
      itemCode: code,
      itemName: name,
      unitOfMeasure: 'Nos',
      standardSellingPrice: price,
      currentStock: stock,
      category: category,
    );

LogicalKeyboardKey _logicalKeyFor(String char) {
  if (char == '0') return LogicalKeyboardKey.digit0;
  if (char == '1') return LogicalKeyboardKey.digit1;
  if (char == '2') return LogicalKeyboardKey.digit2;
  if (char == '3') return LogicalKeyboardKey.digit3;
  if (char == '4') return LogicalKeyboardKey.digit4;
  if (char == '5') return LogicalKeyboardKey.digit5;
  if (char == '6') return LogicalKeyboardKey.digit6;
  if (char == '7') return LogicalKeyboardKey.digit7;
  if (char == '8') return LogicalKeyboardKey.digit8;
  if (char == '9') return LogicalKeyboardKey.digit9;
  return LogicalKeyboardKey.keyA;
}

/// Pumps [PosScreen] inside a ProviderScope with hermetic POS providers
/// (catalog overridden per test, warehouses stubbed empty so the picker
/// never hits the network) and the app's localization delegates (the
/// screen reads `AppLocalizations.of(context)` during build).
Future<void> _pumpPos(
  WidgetTester tester, {
  List<PosItem> items = const [],
}) =>
    tester.pumpWidget(
      ProviderScope(
        overrides: [
          posCatalogProvider.overrideWith((ref) => items),
          posWarehousesProvider.overrideWith((ref) => const <PosWarehouse>[]),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // PosScreen is a branch body — it expects a Scaffold ancestor
          // (its date/warehouse pickers use Material ink widgets).
          home: const Scaffold(body: PosScreen()),
        ),
      ),
    );

void main() {
  group('POS Cart', () {
    testWidgets('empty cart shows the add-items prompt', (tester) async {
      await _pumpPos(tester);
      await tester.pumpAndSettle();

      expect(find.text('Add items from the catalog'), findsOneWidget);
      expect(find.text('Cart (0 items)'), findsOneWidget);
    });

    testWidgets('tapping a catalog item adds it to the cart', (tester) async {
      final items = [_testItem()];

      await _pumpPos(tester, items: items);
      await tester.pumpAndSettle();

      expect(find.text('Test Item'), findsWidgets);
      expect(find.text('Cart (0 items)'), findsOneWidget);

      await tester.tap(find.text('Test Item').first);
      await tester.pumpAndSettle();

      expect(find.text('Cart (1 items)'), findsOneWidget);
      expect(find.text('Add items from the catalog'), findsNothing);
    });

    testWidgets('cart shows item count after adding', (tester) async {
      final items = [_testItem()];

      await _pumpPos(tester, items: items);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Test Item').first);
      await tester.pumpAndSettle();

      // The cart row + the catalog card both show the name.
      expect(find.text('Test Item'), findsWidgets);
      expect(find.text('Cart (1 items)'), findsOneWidget);
    });
  });

  group('POS Catalog', () {
    testWidgets('catalog renders item cards from provider', (tester) async {
      final items = [
        _testItem(id: 1, name: 'Widget A', code: 'WA001'),
        _testItem(id: 2, name: 'Widget B', code: 'WB002'),
      ];

      await _pumpPos(tester, items: items);
      await tester.pumpAndSettle();

      expect(find.text('Widget A'), findsWidgets);
      expect(find.text('Widget B'), findsWidgets);
    });

    testWidgets('search field exists for filtering catalog', (tester) async {
      await _pumpPos(tester);
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsWidgets);
      expect(find.text('Search items...'), findsOneWidget);
    });
  });

  group('POS Barcode Scanner (spec 4.3)', () {
    /// Simulates a hardware scan: the code's character keys arrive with
    /// short gaps (well under the 100ms human-typing threshold) followed
    /// by Enter. Character keys map to their logical keys so the capture
    /// path sees the scanned string.
    Future<void> scanCode(WidgetTester tester, String code) async {
      for (final char in code.split('')) {
        await tester.sendKeyEvent(
          _logicalKeyFor(char),
          character: char,
        );
        // ~20ms between keys — a scanner's cadence, not a human's.
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
    }

    testWidgets('scanned code adds the matching item to the cart', (
      tester,
    ) async {
      final items = [
        _testItem(id: 1, name: 'Widget A', code: 'WA001'),
        _testItem(id: 2, name: 'Widget B', code: 'WB002'),
      ];

      await _pumpPos(tester, items: items);
      await tester.pumpAndSettle();

      await scanCode(tester, 'WA001');
      await tester.pumpAndSettle();

      expect(find.text('Cart (1 items)'), findsOneWidget);
      expect(find.text('Widget A'), findsWidgets);
    });

    testWidgets('unknown barcode shows an item-not-found toast', (
      tester,
    ) async {
      final items = [_testItem(id: 1, name: 'Widget A', code: 'WA001')];

      await _pumpPos(tester, items: items);
      await tester.pumpAndSettle();

      await scanCode(tester, 'ZZ999');
      await tester.pumpAndSettle();

      expect(find.textContaining('Item not found'), findsOneWidget);
      expect(find.text('Cart (0 items)'), findsOneWidget);
    });
  });

  group('POS Models', () {
    test('PosItem fromJson handles optional fields', () {
      final json = {
        'id': 1,
        'item_code': 'TEST',
        'item_name': 'Test',
        'unit_of_measure': 'Nos',
        'standard_selling_price': 25.5,
        'current_stock': 10,
      };
      final item = PosItem.fromJson(json);
      expect(item.id, 1);
      expect(item.category, isNull);
    });

    test('PosItem toJson includes category when set', () {
      final item = _testItem(category: 'Finished Goods');
      final json = item.toJson();
      expect(json['category'], 'Finished Goods');
    });

    test('PosCartItem lineTotal is quantity * unitPrice', () {
      final item = _testItem(price: 25.0);
      final cartItem = PosCartItem(item: item, quantity: 4, unitPrice: 25.0);
      expect(cartItem.lineTotal, 100.0);
    });

    test('PosCartItem availableStock comes from item', () {
      final item = _testItem(stock: 42);
      final cartItem = PosCartItem(item: item, quantity: 1, unitPrice: 10);
      expect(cartItem.availableStock, 42);
    });
  });
}
