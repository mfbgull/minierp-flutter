// Production form dialog (production_form_dialog.dart) — D6 joint-product
// outputs.
//
// The dialog must keep posting the legacy single-output shape for a
// single-product run (so existing productions are untouched) and switch to
// the server's `outputs[]` shape as soon as a co-product line is added,
// with the primary output first (the server validates the BOM against the
// FIRST line).

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/data/models/bom.dart';
import 'package:minierp_app/data/models/item.dart';
import 'package:minierp_app/data/models/production.dart';
import 'package:minierp_app/data/models/warehouse.dart';
import 'package:minierp_app/data/repositories/api_result.dart';
import 'package:minierp_app/data/repositories/production_repository.dart';
import 'package:minierp_app/data/repositories/repository_client.dart';
import 'package:minierp_app/features/production/production_form_dialog.dart';
import 'package:minierp_app/features/production/production_providers.dart';
import 'package:minierp_app/l10n/app_localizations.dart';
import 'package:minierp_app/widgets/searchable_select.dart';

/// Seed raw material consumed by the test BOM.
const _seed = Item(
  id: 1,
  itemCode: 'RM-001',
  itemName: 'Mustard Seed',
  unitOfMeasure: 'kg',
  currentStock: 500,
);

/// Primary output — priced, so the D6 allocation has a sales-value basis.
const _oil = Item(
  id: 2,
  itemCode: 'FG-002',
  itemName: 'Mustard Oil',
  unitOfMeasure: 'Litre',
  currentStock: 0,
  standardSellingPrice: 100,
  hasExpiry: true,
);

/// Co-product — unpriced, like the server fixture's mustard cake.
const _cake = Item(
  id: 3,
  itemCode: 'FG-003',
  itemName: 'Mustard Cake',
  unitOfMeasure: 'kg',
  currentStock: 0,
);

const _warehouse = Warehouse(id: 1, warehouseCode: 'WH-1', warehouseName: 'Main');

const _bomDetail = BomDetail(
  id: 7,
  bomNo: 'BOM-7',
  bomName: 'Oil Batch',
  finishedItemId: 2, // _oil
  finishedItemName: 'Mustard Oil',
  quantity: 10,
  items: [
    BomItem(id: 1, itemId: 1 /* _seed */, quantity: 100, standardCost: 10),
  ],
);

class _FakeProductionRepository extends ProductionRepository {
  _FakeProductionRepository() : super(RepositoryClient(Dio()));

  /// Body captured from the last `POST /productions`.
  Map<String, dynamic>? lastBody;

  @override
  Future<ApiResult<BomDetail>> bom(int id) async => const ApiSuccess(_bomDetail);

  @override
  Future<ApiResult<Production>> createProduction(
    Map<String, dynamic> body,
  ) async {
    lastBody = body;
    return const ApiSuccess(
      Production(
        id: 1,
        productionNo: 'PROD-2026-001',
        outputItemId: 2, // _oil
        outputQuantity: 10,
        warehouseId: 1,
        productionDate: '2026-09-12',
      ),
    );
  }
}

Future<void> _openDialog(WidgetTester tester, _FakeProductionRepository repo) async {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        productionRepositoryProvider.overrideWithValue(repo),
        productionOutputItemsProvider.overrideWith((ref) async => const [_oil, _cake]),
        productionAllItemsProvider.overrideWith(
          (ref) async => const [_seed, _oil, _cake],
        ),
        productionBomOptionsProvider.overrideWith((ref) async => const [_bomDetail]),
        productionWarehousesProvider.overrideWith((ref) async => const [_warehouse]),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showProductionFormDialog(context),
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

/// Drives the header: primary output item + its quantity.
Future<void> _pickPrimaryOutput(WidgetTester tester) async {
  await tester.tap(find.byType(SearchableSelect<int>).at(0));
  await tester.pumpAndSettle();
  await tester.tap(find.text('FG-002 — Mustard Oil').last);
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextFormField).at(0), '10');
  await tester.pumpAndSettle();
}

/// Picks the (required) finished-goods warehouse and the BOM whose
/// finished item is the primary output.
Future<void> _pickWarehouseAndBom(WidgetTester tester) async {
  await tester.tap(find.byType(SearchableSelect<int>).at(1));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Main').last);
  await tester.pumpAndSettle();

  await tester.tap(find.byType(SearchableSelect<int>).at(3));
  await tester.pumpAndSettle();
  await tester.tap(find.text('BOM-7 — Mustard Oil').last);
  await tester.pumpAndSettle();
}

/// Value shown in the labelled cost-preview tile (label Text, value Text).
String? _tileValue(WidgetTester tester, String label) {
  for (final column in tester.widgetList<Column>(find.byType(Column))) {
    final texts = column.children.whereType<Text>().toList();
    if (texts.length >= 2 && texts.first.data == label) return texts.last.data;
  }
  return null;
}

/// Extracts the number from a formatted currency like `Rs.1,234.50`
/// (the default symbol is `Rs.`, so naively stripping letters leaves a
/// stray leading dot).
num _parseCurrency(String formatted) {
  final match = RegExp(r'-?\d[\d,]*(?:\.\d+)?').stringMatch(formatted);
  return match == null ? 0 : num.parse(match.replaceAll(',', ''));
}

Future<void> _save(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Save'));
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('single-output run posts the legacy shape', (tester) async {
    final repo = _FakeProductionRepository();
    await _openDialog(tester, repo);

    await _pickPrimaryOutput(tester);
    await _pickWarehouseAndBom(tester);

    // Single-output: the per-unit figure is the whole cost over the one
    // output quantity (1,000 over 10).
    final perUnit = _tileValue(tester, 'Cost per Unit');
    expect(perUnit, isNotNull);
    expect(_parseCurrency(perUnit!), closeTo(100, 0.01));

    await _save(tester);

    final body = repo.lastBody;
    expect(body, isNotNull, reason: 'the form should have submitted');
    expect(body!['output_item_id'], _oil.id);
    expect(body['output_quantity'], 10);
    expect(body.containsKey('outputs'), isFalse);
  });

  testWidgets('adding a co-product switches the payload to outputs[]', (
    tester,
  ) async {
    final repo = _FakeProductionRepository();
    await _openDialog(tester, repo);

    await _pickPrimaryOutput(tester);
    await _pickWarehouseAndBom(tester);

    // Add one co-product line and fill it in.
    await tester.ensureVisible(find.text('Add output'));
    await tester.tap(find.text('Add output'));
    await tester.pumpAndSettle();

    // The extra row's item picker is now second in the tree.
    await tester.tap(find.byType(SearchableSelect<int>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FG-003 — Mustard Cake').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(1), '50');
    await tester.pumpAndSettle();

    // The per-unit tile must spread the joint cost over EVERY output unit
    // (60), not the primary's 10 — otherwise it contradicts the
    // allocation table beneath it (oil's own unit cost is 1000/10).
    final perUnit = _tileValue(tester, 'Cost per Unit');
    expect(perUnit, isNotNull);
    expect(_parseCurrency(perUnit!), closeTo(1000 / 60, 0.01));

    await _save(tester);

    final body = repo.lastBody;
    expect(body, isNotNull, reason: 'the form should have submitted');
    expect(body!.containsKey('output_item_id'), isFalse);
    expect(body.containsKey('output_quantity'), isFalse);

    final outputs = body['outputs'] as List<dynamic>;
    expect(outputs, hasLength(2), reason: 'primary + one co-product');
    // The primary must stay FIRST — the server validates the BOM against
    // the first line.
    expect(outputs[0], {'item_id': _oil.id, 'quantity': 10.0});
    expect(outputs[1], {'item_id': _cake.id, 'quantity': 50.0});
  });

  testWidgets('rejects a co-product that repeats the primary output', (
    tester,
  ) async {
    final repo = _FakeProductionRepository();
    await _openDialog(tester, repo);

    await _pickPrimaryOutput(tester);
    await _pickWarehouseAndBom(tester);

    await tester.ensureVisible(find.text('Add output'));
    await tester.tap(find.text('Add output'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SearchableSelect<int>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FG-002 — Mustard Oil').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(1), '5');
    await tester.pumpAndSettle();

    await _save(tester);

    // Blocked client-side, mirroring the server's guard.
    expect(repo.lastBody, isNull);
    expect(find.text('Each output item may appear only once'), findsOneWidget);
  });
}
