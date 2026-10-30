import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/data/repositories/api_result.dart';
import 'package:minierp_app/data/models/item.dart';
import 'package:minierp_app/data/repositories/paged_request.dart';
import 'package:minierp_app/data/repositories/inventory_repository.dart';
import 'package:minierp_app/data/repositories/repository_client.dart';
import 'package:minierp_app/features/inventory/item_form_dialog.dart';
import 'package:minierp_app/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Repository extends InventoryRepository {
  _Repository() : super(RepositoryClient(Dio()));
  final existing = const ItemCompany(id: 1, name: 'Existing');
  final added = const ItemCompany(id: 3, name: 'Acme');
  bool listFails = false;
  bool archived = false;
  int addCalls = 0;
  String? addedName;
  Map<String, dynamic>? submitted;
  Future<ApiResult<ItemCompany>>? addResult;
  bool didAdd = false;
  @override
  Future<ApiResult<List<String>>> categories() async => const ApiSuccess([]);
  @override
  Future<ApiResult<PagedResponse<ItemCompany>>> companies(PagedRequest request) async {
    if (listFails) return const ApiFailure(ApiError(message: 'Cannot load companies'));
    final values = [if (!archived) existing, if (didAdd) added];
    return ApiSuccess(PagedResponse(items: values, totalItems: values.length, currentPage: 1, totalPages: 1, hasNext: false, hasPrev: false));
  }
  @override
  Future<ApiResult<ItemCompany>> company(int id) async => ApiSuccess(id == 3 ? added : ItemCompany(id: 1, name: 'Existing', isActive: !archived));
  @override
  Future<ApiResult<ItemCompany>> addCompany(String name) async {
    addCalls++;
    addedName = name;
    final result = await (addResult ?? Future.value(ApiSuccess(added)));
    if (result is ApiSuccess<ItemCompany>) didAdd = true;
    return result;
  }
  @override
  Future<ApiResult<Item>> update(int id, Map<String, dynamic> body) async {
    submitted = body;
    return ApiSuccess(_item);
  }
  @override
  Future<ApiResult<List<String>>> unitsOfMeasure() async => const ApiSuccess(['Nos']);
}

const _item = Item(id: 1, itemCode: 'A', itemName: 'Product', manufacturerName: 'Existing', companyId: 1, unitOfMeasure: 'Nos', currentStock: 0);

Future<void> _boot(WidgetTester tester, _Repository repo, {Item? item}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [inventoryRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () => showItemFormDialog(context, item: item),
        child: const Text('Open'),
      ))),
    ),
  ));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('company plus expands inside the product form', (tester) async {
    await _boot(tester, _Repository());
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('item-company-inline')), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('cancel retains product edits and current selection', (tester) async {
    final repo = _Repository();
    await _boot(tester, repo, item: _item);
    await tester.enterText(find.byType(TextFormField).first, 'Product changed');
    await tester.tap(find.byKey(const ValueKey('item-company-add-toggle')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('item-company-name')), 'Draft');
    await tester.tap(find.byKey(const ValueKey('item-company-cancel')));
    await tester.pumpAndSettle();
    expect(find.text('Existing'), findsOneWidget);
    expect(find.text('Product changed'), findsOneWidget);
    expect(repo.addCalls, 0);
  });

  testWidgets('Enter adds canonical company without submitting product', (tester) async {
    final repo = _Repository();
    await _boot(tester, repo, item: _item);
    await tester.tap(find.byKey(const ValueKey('item-company-add-toggle')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('item-company-name')), '  acme  ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(repo.addedName, 'acme');
    expect(repo.submitted, isNull);
    expect(find.byKey(const ValueKey('item-company-inline')), findsNothing);
    expect(find.text('Acme'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(repo.submitted?['company_id'], 3);
    expect(repo.submitted?['manufacturer_name'], 'Acme');
  });

  testWidgets('failure retains name and prevents duplicate in-flight saves', (tester) async {
    final repo = _Repository();
    final pending = Completer<ApiResult<ItemCompany>>();
    repo.addResult = pending.future;
    await _boot(tester, repo, item: _item);
    await tester.tap(find.byKey(const ValueKey('item-company-add-toggle')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('item-company-name')), 'New company');
    await tester.tap(find.byKey(const ValueKey('item-company-save')));
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('item-company-save'))).onPressed, isNull);
    expect(repo.addCalls, 1);
    pending.complete(const ApiFailure(ApiError(message: 'Company could not be saved')));
    await tester.pumpAndSettle();
    expect(find.text('Company could not be saved'), findsOneWidget);
    expect(find.text('New company'), findsOneWidget);
    expect(repo.submitted, isNull);
  });

  testWidgets('blank company name never calls repository', (tester) async {
    final repo = _Repository();
    await _boot(tester, repo);
    await tester.tap(find.byKey(const ValueKey('item-company-add-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('item-company-save')));
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsOneWidget);
    expect(repo.addCalls, 0);
  });

  testWidgets('archived current company stays selected during unrelated edit', (tester) async {
    final repo = _Repository()..archived = true;
    await _boot(tester, repo, item: _item);
    expect(find.text('Existing (Inactive)'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'Updated');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(repo.submitted?['company_id'], 1);
  });

  testWidgets('company load failure can be retried', (tester) async {
    final repo = _Repository()..listFails = true;
    await _boot(tester, repo);
    expect(find.text('Cannot load companies'), findsOneWidget);
    repo.listFails = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Cannot load companies'), findsNothing);
  });
}
