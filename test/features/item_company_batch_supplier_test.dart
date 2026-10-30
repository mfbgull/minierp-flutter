import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:minierp_app/data/models/item.dart';
import 'package:minierp_app/core/theme/app_theme.dart';
import 'package:minierp_app/data/models/stock_batch.dart';
import 'package:minierp_app/data/repositories/api_result.dart';
import 'package:minierp_app/data/repositories/inventory_repository.dart';
import 'package:minierp_app/data/repositories/paged_request.dart';
import 'package:minierp_app/data/repositories/repository_client.dart';
import 'package:minierp_app/features/inventory/batch_management_screen.dart';
import 'package:minierp_app/features/inventory/item_detail_dialog.dart';
import 'package:minierp_app/features/inventory/item_form_dialog.dart';
import 'package:minierp_app/features/inventory/items_screen.dart';
import 'package:minierp_app/l10n/app_localizations.dart';
import 'package:minierp_app/widgets/searchable_select.dart';

final _item = Item.fromJson({
  'id': 1,
  'item_code': 'MILK-1L',
  'item_name': 'Milk 1L',
  'manufacturer_name': 'Nestlé',
  'unit_of_measure': 'Ltr',
  'current_stock': 10,
});

class _Repository extends InventoryRepository {
  _Repository() : super(RepositoryClient(Dio()));
  Map<String, dynamic>? submitted;

  @override
  Future<ApiResult<List<String>>> categories() async => const ApiSuccess([]);
  @override
  Future<ApiResult<List<String>>> unitsOfMeasure() async =>
      const ApiSuccess(['Ltr']);
  @override
  Future<ApiResult<PagedResponse<ItemCompany>>> companies(
    PagedRequest request,
  ) async => ApiSuccess(
    PagedResponse(
      items: const [ItemCompany(id: 2, name: 'Acme')],
      totalItems: 1,
      currentPage: 1,
      totalPages: 1,
      hasNext: false,
      hasPrev: false,
    ),
  );
  @override
  Future<ApiResult<ItemCompany>> company(int id) async => ApiSuccess(
    id == 7
        ? const ItemCompany(id: 7, name: 'Nestlé')
        : const ItemCompany(id: 2, name: 'Acme'),
  );
  @override
  Future<ApiResult<ItemCompany>> addCompany(String name) async =>
      ApiSuccess(ItemCompany(id: 7, name: name));
  @override
  Future<ApiResult<ItemDetail>> itemDetail(int id) async =>
      ApiSuccess(ItemDetail(item: _item, stockByWarehouse: const []));
  @override
  Future<ApiResult<PagedResponse<Item>>> items(PagedRequest request) async =>
      ApiSuccess(
        PagedResponse(
          items: [_item],
          totalItems: 1,
          currentPage: 1,
          totalPages: 1,
          hasNext: false,
          hasPrev: false,
        ),
      );
  @override
  Future<ApiResult<Item>> create(Map<String, dynamic> body) async {
    submitted = body;
    return ApiSuccess(_item);
  }

  @override
  Future<ApiResult<Item>> update(int id, Map<String, dynamic> body) =>
      create(body);
  @override
  Future<ApiResult<List<StockBatch>>> getBatches({
    int? itemId,
    int? warehouseId,
  }) async => ApiSuccess([
    StockBatch.fromJson({
      'id': 1,
      'batch_no': 'BATCH-001',
      'item_id': 1,
      'warehouse_id': 1,
      'warehouse_name': 'Main',
      'source_type': 'TRANSFER',
      'source_id': 1,
      'quantity_original': 10,
      'quantity_remaining': 10,
      'unit_cost': 5,
      'received_date': '2026-10-28',
      'suppliers': [
        {'supplier_id': 1, 'supplier_name': 'ABC Traders'},
        {'supplier_id': 2, 'supplier_name': 'XYZ Distributors'},
      ],
    }),
    StockBatch.fromJson({
      'id': 2,
      'batch_no': 'BATCH-002',
      'item_id': 1,
      'warehouse_id': 1,
      'source_type': 'OPENING',
      'source_id': 2,
      'quantity_remaining': 1,
      'received_date': '2026-10-28',
      'suppliers': [
        {'supplier_id': null, 'supplier_name': null},
      ],
    }),
  ]);
}

const _phase = String.fromEnvironment('CAPTURE_PHASE', defaultValue: 'after');
const _captureEnabled = bool.fromEnvironment('CAPTURE_UI');
late final Directory _captureDirectory;
const _captureKey = ValueKey('company-qa-capture');

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  if (!_captureEnabled) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File(
      '${_captureDirectory.path}/$name-$_phase.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _boot(
  WidgetTester tester,
  _Repository repository,
  Widget screen, {
  String language = 'en',
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [inventoryRepositoryProvider.overrideWithValue(repository)],
      child: RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          key: UniqueKey(),
          debugShowCheckedModeBanner: false,
          locale: Locale(language),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme:
              (brightness == Brightness.dark ? AppTheme.dark : AppTheme.light)
                  .copyWith(
                    textTheme:
                        (brightness == Brightness.dark
                                ? AppTheme.dark
                                : AppTheme.light)
                            .textTheme
                            .apply(fontFamilyFallback: ['QaUrdu']),
                  ),
          home: Scaffold(body: screen),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    if (_captureEnabled) {
      _captureDirectory = Directory.systemTemp.createTempSync('minierp-company-qa-');
      debugPrint('Company UI evidence: ${_captureDirectory.path}');
    }
    final font = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    // Headless widget tests have no system fallback fonts. Use the local
    // Arabic-capable fallback for the optional Urdu screenshot evidence.
    final arabic = File('/usr/share/fonts/truetype/freefont/FreeSerif.ttf');
    if (arabic.existsSync()) {
      final fallback = FontLoader('QaUrdu')
        ..addFont(Future.value(ByteData.sublistView(arabic.readAsBytesSync())));
      await fallback.load();
    }
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final language in ['en', 'ur']) {
    for (final brightness in Brightness.values) {
      testWidgets('company surfaces $language ${brightness.name}', (
        tester,
      ) async {
        final repo = _Repository();
        final prefix = '$language-${brightness.name}';
        await _boot(
          tester,
          repo,
          const ItemsScreen(),
          language: language,
          brightness: brightness,
        );
        await _capture(tester, '$prefix-items');
        if (_phase == 'after') {
          expect(find.text('Nestlé'), findsOneWidget);
          final l10n = AppLocalizations.of(tester.element(find.byType(ItemsScreen)))!;
          expect(find.text(l10n.statusActive), findsOneWidget);
        }
        await _boot(
          tester,
          repo,
          const BatchManagementScreen(itemId: 1),
          language: language,
          brightness: brightness,
        );
        await _capture(tester, '$prefix-batches');
        if (_phase == 'after') {
          expect(find.textContaining('ABC Traders'), findsWidgets);
          expect(find.textContaining('XYZ Distributors'), findsWidgets);
          final pointer = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
          await pointer.addPointer(location: Offset.zero);
          await pointer.moveTo(tester.getCenter(find.textContaining('ABC Traders').first));
          await tester.pumpAndSettle(const Duration(milliseconds: 600));
          expect(find.text('ABC Traders, XYZ Distributors'), findsNWidgets(2));
          await _capture(tester, '$prefix-supplier-tooltip');
          await pointer.removePointer();
          await tester.pumpAndSettle(const Duration(milliseconds: 600));
          await tester.tap(find.textContaining('ABC Traders').first);
          await tester.pump(const Duration(milliseconds: 100));
          await tester.tap(find.textContaining('ABC Traders').first);
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
          await tester.pumpAndSettle();
          expect(
            tester.widget<EditableText>(find.byType(EditableText)).controller.text,
            'ABC Traders, XYZ Distributors',
          );
        }
        for (final edit in [false, true]) {
          await _boot(
            tester,
            repo,
            Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () =>
                      showItemFormDialog(context, item: edit ? _item : null),
                  child: const Text('Open'),
                ),
              ),
            ),
            language: language,
            brightness: brightness,
          );
          await tester.tap(find.text('Open'));
          await _capture(tester, '$prefix-${edit ? 'edit' : 'create'}');
        }
        await _boot(
          tester,
          repo,
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showItemDetailDialog(context, itemId: 1),
                child: const Text('Open'),
              ),
            ),
          ),
          language: language,
          brightness: brightness,
        );
        await tester.tap(find.text('Open'));
        await _capture(tester, '$prefix-detail');
        if (_phase == 'after') expect(find.text('Nestlé'), findsOneWidget);
      });
    }
  }

  testWidgets('creating submits a manufacturer through the form', (tester) async {
    if (_phase == 'before') return;
    final repo = _Repository();
    await _boot(tester, repo, Scaffold(body: Builder(builder: (context) => TextButton(
      onPressed: () => showItemFormDialog(context), child: const Text('Open'),
    ))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'MILK-NEW');
    await tester.enterText(find.byType(TextFormField).at(1), 'Milk 1L');
    await tester.tap(find.byKey(const ValueKey('item-company-add-toggle')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('item-company-name')),
      'Nestlé',
    );
    await tester.tap(find.byKey(const ValueKey('item-company-save')));
    await tester.pumpAndSettle();
    expect(find.text('Nestlé'), findsOneWidget);
    await tester.tap(find.byType(SearchableSelect<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ltr').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(repo.submitted?['manufacturer_name'], 'Nestlé');
    expect(repo.submitted?['company_id'], 7);
  });

  testWidgets('editing submits and clears manufacturer through the form', (
    tester,
  ) async {
    if (_phase == 'before') return;
    final repo = _Repository();
    await _boot(
      tester,
      repo,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showItemFormDialog(context, item: _item),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Nestlé'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('item-manufacturer')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acme').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(repo.submitted?['manufacturer_name'], 'Acme');
    expect(repo.submitted?['company_id'], 2);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Nestlé'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('item-company-clear')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(repo.submitted?['manufacturer_name'], '');
    expect(repo.submitted?['company_id'], isNull);
  });
}
