import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:minierp_app/core/auth/auth_notifier.dart';
import 'package:minierp_app/data/models/auth_user.dart';
import 'package:minierp_app/data/models/company_supplier.dart';
import 'package:minierp_app/data/models/item.dart';
import 'package:minierp_app/data/models/supplier.dart';
import 'package:minierp_app/data/repositories/api_result.dart';
import 'package:minierp_app/data/repositories/auth_repository.dart';
import 'package:minierp_app/data/repositories/inventory_repository.dart';
import 'package:minierp_app/data/repositories/paged_request.dart';
import 'package:minierp_app/data/repositories/repository_client.dart';
import 'package:minierp_app/data/repositories/supplier_repository.dart';
import 'package:minierp_app/features/inventory/items_screen.dart';
import 'package:minierp_app/features/inventory/manage_companies_dialog.dart';
import 'package:minierp_app/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

PagedResponse<T> _page<T>(List<T> all, int page, int limit) {
  final start = (page - 1) * limit;
  final items = start >= all.length
      ? <T>[]
      : all.sublist(start, (start + limit).clamp(0, all.length));
  return PagedResponse(
    items: items,
    totalItems: all.length,
    currentPage: page,
    totalPages: all.isEmpty ? 1 : (all.length + limit - 1) ~/ limit,
    hasNext: page * limit < all.length,
    hasPrev: page > 1,
  );
}

const _item = Item(
  id: 1,
  itemCode: 'IT-1',
  itemName: 'Widget',
  manufacturerName: 'Existing',
  companyId: 1,
  category: 'Hardware',
  unitOfMeasure: 'Nos',
  currentStock: 5,
);

class _Repository extends InventoryRepository {
  _Repository() : super(RepositoryClient(Dio()));

  final List<ItemCompany> records = [
    const ItemCompany(id: 1, name: 'Existing', productCount: 1),
    const ItemCompany(id: 2, name: 'Archived Co', isActive: false),
    const ItemCompany(
      id: 3,
      name:
          'A very long company name that must not break the dialog layout '
          'when it is rendered in a list row or the detail header',
      productCount: 0,
    ),
  ];

  final List<CompanySupplier> suppliers = [
    const CompanySupplier(
      supplierId: 5,
      supplierName: 'Acme Supplies',
      contactPerson: 'Sam',
      phone: '555-0100',
      linked: true,
      purchased: true,
      productCount: 1,
      lastPurchaseDate: '2026-10-02',
    ),
    const CompanySupplier(
      supplierId: 6,
      supplierName: 'History Only',
      purchased: true,
      productCount: 2,
      lastPurchaseDate: '2026-09-14',
    ),
  ];

  bool failListOnce = false;
  bool denyLink = false;
  int nextId = 10;

  @override
  Future<ApiResult<PagedResponse<ItemCompany>>> companies(
    PagedRequest request,
  ) async {
    if (failListOnce) {
      failListOnce = false;
      return const ApiFailure(ApiError(message: 'Could not load companies'));
    }
    final status = request.extra?['status'] as String? ?? 'active';
    final search = (request.search ?? '').toLowerCase();
    final filtered = records
        .where(
          (company) => status == 'all'
              ? true
              : status == 'archived'
              ? !company.isActive
              : company.isActive,
        )
        .where((company) => company.name.toLowerCase().contains(search))
        .toList();
    return ApiSuccess(_page(filtered, request.page, request.limit));
  }

  @override
  Future<ApiResult<ItemCompany>> addCompany(String name) async {
    if (records.any(
      (company) => company.name.toLowerCase() == name.toLowerCase(),
    )) {
      return const ApiFailure(
        ApiError(message: 'A company with this name already exists'),
      );
    }
    final company = ItemCompany(id: nextId++, name: name);
    records.add(company);
    return ApiSuccess(company);
  }

  @override
  Future<ApiResult<ItemCompany>> updateCompany(int id, String name) async {
    if (records.any(
      (company) =>
          company.id != id &&
          company.name.toLowerCase() == name.toLowerCase(),
    )) {
      return const ApiFailure(
        ApiError(message: 'A company with this name already exists'),
      );
    }
    final index = records.indexWhere((company) => company.id == id);
    final updated = ItemCompany(
      id: id,
      name: name,
      isActive: records[index].isActive,
      productCount: records[index].productCount,
    );
    records[index] = updated;
    return ApiSuccess(updated);
  }

  @override
  Future<ApiResult<ItemCompany>> company(int id) async {
    final company = records.where((company) => company.id == id).firstOrNull;
    if (company == null) {
      return const ApiFailure(ApiError(message: 'Company not found'));
    }
    return ApiSuccess(company);
  }

  @override
  Future<ApiResult<ItemCompany>> archiveCompany(int id) =>
      _setActive(id, false);

  @override
  Future<ApiResult<ItemCompany>> restoreCompany(int id) => _setActive(id, true);

  Future<ApiResult<ItemCompany>> _setActive(int id, bool active) async {
    final index = records.indexWhere((company) => company.id == id);
    final updated = ItemCompany(
      id: id,
      name: records[index].name,
      isActive: active,
      productCount: records[index].productCount,
    );
    records[index] = updated;
    return ApiSuccess(updated);
  }

  @override
  Future<ApiResult<void>> deleteCompany(int id) async {
    final company = records.firstWhere((company) => company.id == id);
    if (company.productCount > 0) {
      return const ApiFailure(
        ApiError(
          message: 'Company is assigned to products; archive it instead',
        ),
      );
    }
    records.removeWhere((company) => company.id == id);
    return const ApiSuccess(null);
  }

  @override
  Future<ApiResult<PagedResponse<Item>>> companyProducts(
    int id,
    PagedRequest request,
  ) async {
    final values = id == 1 ? const [_item] : const <Item>[];
    return ApiSuccess(_page(values.toList(), request.page, request.limit));
  }

  @override
  Future<ApiResult<PagedResponse<CompanySupplier>>> companySuppliers(
    int companyId,
    PagedRequest request,
  ) async {
    final values = companyId == 1 ? suppliers : const <CompanySupplier>[];
    return ApiSuccess(_page(values.toList(), request.page, request.limit));
  }

  @override
  Future<ApiResult<void>> setCompanySupplierLink(
    int companyId,
    int supplierId,
    bool linked,
  ) async {
    if (denyLink) {
      return const ApiFailure(
        ApiError(message: 'Company and supplier must be active to add a link'),
      );
    }
    final index = suppliers.indexWhere(
      (supplier) => supplier.supplierId == supplierId,
    );
    if (index >= 0) {
      final current = suppliers[index];
      suppliers[index] = CompanySupplier(
        supplierId: current.supplierId,
        supplierName: current.supplierName,
        contactPerson: current.contactPerson,
        phone: current.phone,
        email: current.email,
        isActive: current.isActive,
        linked: linked,
        purchased: current.purchased,
        productCount: current.productCount,
        lastPurchaseDate: current.lastPurchaseDate,
      );
    } else if (linked) {
      const names = {7: 'New Linkable'};
      suppliers.add(
        CompanySupplier(
          supplierId: supplierId,
          supplierName: names[supplierId] ?? 'Supplier $supplierId',
          linked: true,
        ),
      );
    }
    return const ApiSuccess(null);
  }

  @override
  Future<ApiResult<ItemDetail>> itemDetail(int id) async =>
      const ApiSuccess(ItemDetail(item: _item, stockByWarehouse: []));

  @override
  Future<ApiResult<PagedResponse<Item>>> items(PagedRequest request) async =>
      ApiSuccess(_page([_item], request.page, request.limit));

  @override
  Future<ApiResult<List<String>>> unitsOfMeasure() async =>
      const ApiSuccess(['Nos']);

  @override
  Future<ApiResult<List<String>>> categories() async =>
      const ApiSuccess(['Hardware']);
}

const _supplierValues = [
  Supplier(
    id: 5,
    supplierCode: 'S-005',
    supplierName: 'Acme Supplies',
  ),
  Supplier(
    id: 6,
    supplierCode: 'S-006',
    supplierName: 'History Only',
  ),
  Supplier(
    id: 7,
    supplierCode: 'S-007',
    supplierName: 'New Linkable',
  ),
];

class _Suppliers extends SupplierRepository {
  _Suppliers() : super(RepositoryClient(Dio()));

  @override
  Future<ApiResult<PagedResponse<Supplier>>> list(PagedRequest request) async =>
      ApiSuccess(_page(_supplierValues.toList(), request.page, request.limit));
}

class _TestAuth extends AuthNotifier {
  _TestAuth(Dio dio, AuthUser user)
    : super(AuthRepository(RepositoryClient(dio)), FakeTokenStorage()) {
    state = AuthState(status: AuthStatus.authenticated, user: user);
  }

  @override
  Future<void> restoreSession() async {}
}

const _admin = AuthUser(id: 1, username: 'admin', role: 'admin');
const _reader = AuthUser(id: 2, username: 'reader', role: 'staff');

Future<void> _boot(
  WidgetTester tester,
  _Repository repo, {
  AuthUser user = _admin,
  Widget? home,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1280, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inventoryRepositoryProvider.overrideWithValue(repo),
        supplierRepositoryProvider.overrideWithValue(_Suppliers()),
        authProvider.overrideWith((ref) => _TestAuth(Dio(), user)),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home:
            home ??
            Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showManageCompaniesDialog(context),
                  child: const Text('Open'),
                ),
              ),
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (home == null) {
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }
}

Future<void> _openCompanyDetail(WidgetTester tester, int companyId) async {
  await tester.tap(find.byKey(ValueKey('company-row-$companyId')));
  await tester.pumpAndSettle();
}

Future<void> _openMenu(WidgetTester tester, int companyId) async {
  await tester.tap(find.byKey(ValueKey('company-menu-$companyId')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('items screen toolbar opens the manage dialog', (tester) async {
    await _boot(
      tester,
      _Repository(),
      home: const Scaffold(body: ItemsScreen()),
    );
    await tester.tap(find.text('Manage Companies'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('manage-companies-search')), findsOneWidget);
  });

  testWidgets('create company keeps the list and pagination in sync', (
    tester,
  ) async {
    final repo = _Repository();
    await _boot(tester, repo);
    await tester.tap(find.byKey(const ValueKey('manage-companies-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('company-name-field')),
      'Brand New Co',
    );
    await tester.tap(find.byKey(const ValueKey('company-name-save')));
    await tester.pumpAndSettle();
    expect(find.text('Brand New Co'), findsOneWidget);
    expect(repo.records.any((company) => company.name == 'Brand New Co'), isTrue);
  });

  testWidgets('duplicate create keeps the entered name and shows the error', (
    tester,
  ) async {
    final repo = _Repository();
    await _boot(tester, repo);
    await tester.tap(find.byKey(const ValueKey('manage-companies-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('company-name-field')),
      'Existing',
    );
    await tester.tap(find.byKey(const ValueKey('company-name-save')));
    await tester.pumpAndSettle();
    expect(find.text('A company with this name already exists'), findsOneWidget);
    expect(find.text('Existing'), findsWidgets);
    expect(repo.records.length, 3);
  });

  testWidgets('rename updates the row', (tester) async {
    final repo = _Repository();
    await _boot(tester, repo);
    await _openMenu(tester, 1);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('company-name-field')),
      'Renamed Co',
    );
    await tester.tap(find.byKey(const ValueKey('company-name-save')));
    await tester.pumpAndSettle();
    expect(find.text('Renamed Co'), findsOneWidget);
    expect(repo.records[0].name, 'Renamed Co');
  });

  testWidgets('referenced delete shows the server conflict message', (
    tester,
  ) async {
    await _boot(tester, _Repository());
    await _openMenu(tester, 1);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(
      find.text('Company is assigned to products; archive it instead'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('company-row-1')), findsOneWidget);
  });

  testWidgets('archive then restore follows the status filter', (tester) async {
    await _boot(tester, _Repository());
    await _openMenu(tester, 1);
    await tester.tap(find.text('Archive Company'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('company-row-1')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('company-filter-archived')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('company-row-1')), findsOneWidget);

    await _openMenu(tester, 1);
    await tester.tap(find.text('Restore Company'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('company-row-1')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('company-filter-active')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('company-row-1')), findsOneWidget);
  });

  testWidgets('product rows open the existing item detail', (tester) async {
    await _boot(tester, _Repository());
    await _openCompanyDetail(tester, 1);
    await tester.tap(find.byKey(const ValueKey('company-product-1')));
    await tester.pumpAndSettle();
    expect(find.text('Widget'), findsWidgets);
  });

  testWidgets('unlink keeps the purchased history badge', (tester) async {
    final repo = _Repository();
    await _boot(tester, repo);
    await _openCompanyDetail(tester, 1);
    await tester.tap(find.widgetWithText(Tab, 'Suppliers'));
    await tester.pumpAndSettle();
    expect(find.text('Linked'), findsOneWidget);
    expect(find.text('Purchased'), findsWidgets);

    await tester.tap(
      find.byKey(const ValueKey('company-supplier-menu-5')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unlink supplier'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Unlink supplier'));
    await tester.pumpAndSettle();

    expect(repo.suppliers.first.linked, isFalse);
    expect(repo.suppliers.first.purchased, isTrue);
    expect(find.text('Linked'), findsNothing);
    expect(find.text('Purchased'), findsWidgets);
  });

  testWidgets('supplier picker links an active supplier', (tester) async {
    final repo = _Repository();
    await _boot(tester, repo);
    await _openCompanyDetail(tester, 1);
    await tester.tap(find.widgetWithText(Tab, 'Suppliers'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('company-add-supplier')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('company-supplier-search')), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('supplier-picker-option-7')),
    );
    await tester.pumpAndSettle();
    final linked = repo.suppliers.firstWhere(
      (supplier) => supplier.supplierId == 7,
    );
    expect(linked.linked, isTrue);
    expect(find.text('New Linkable'), findsOneWidget);
  });

  testWidgets('denied supplier link shows the server message', (tester) async {
    final repo = _Repository()..denyLink = true;
    await _boot(tester, repo);
    await _openCompanyDetail(tester, 1);
    await tester.tap(find.widgetWithText(Tab, 'Suppliers'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('company-supplier-menu-6')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Link supplier'));
    await tester.pumpAndSettle();
    expect(
      find.text('Company and supplier must be active to add a link'),
      findsOneWidget,
    );
    expect(repo.suppliers.last.linked, isFalse);
  });

  testWidgets('supplier rows open the supplier detail route', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showManageCompaniesDialog(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/suppliers/:id',
          builder: (context, state) =>
              Scaffold(body: Text('Supplier ${state.pathParameters['id']}')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inventoryRepositoryProvider.overrideWithValue(_Repository()),
          supplierRepositoryProvider.overrideWithValue(_Suppliers()),
          authProvider.overrideWith((ref) => _TestAuth(Dio(), _admin)),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await _openCompanyDetail(tester, 1);
    await tester.tap(find.widgetWithText(Tab, 'Suppliers'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('company-supplier-menu-5')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open supplier'));
    await tester.pumpAndSettle();
    expect(find.text('Supplier 5'), findsOneWidget);
  });

  testWidgets('read-only user sees no mutation controls', (tester) async {
    await _boot(tester, _Repository(), user: _reader);
    expect(find.byKey(const ValueKey('manage-companies-add')), findsNothing);
    expect(find.byKey(const ValueKey('company-menu-1')), findsNothing);
  });

  testWidgets('list failure can be retried', (tester) async {
    final repo = _Repository()..failListOnce = true;
    await _boot(tester, repo);
    expect(find.text('Could not load companies'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('company-row-1')), findsOneWidget);
  });

  testWidgets('long company names render without overflow', (tester) async {
    await _boot(tester, _Repository());
    await tester.tap(find.byKey(const ValueKey('company-filter-all')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await _openCompanyDetail(tester, 3);
    expect(tester.takeException(), isNull);
  });
}
