import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:minierp_app/core/api/api_client.dart';
import 'package:minierp_app/core/auth/auth_notifier.dart';
import 'package:minierp_app/core/theme/app_theme.dart';
import 'package:minierp_app/data/models/auth_user.dart';
import 'package:minierp_app/data/models/customer.dart';
import 'package:minierp_app/data/repositories/auth_repository.dart';
import 'package:minierp_app/data/repositories/repository_client.dart';
import 'package:minierp_app/features/customers/store_credit_apply_dialog.dart';
import 'package:minierp_app/l10n/app_localizations.dart';
import '../../test_helpers.dart';

class CreditTestAuth extends AuthNotifier {
  CreditTestAuth(Dio dio, AuthUser user)
    : super(AuthRepository(RepositoryClient(dio)), FakeTokenStorage()) {
    state = AuthState(status: AuthStatus.authenticated, user: user);
  }
  @override
  Future<void> restoreSession() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const customer = Customer(
    id: 3,
    customerCode: 'C003',
    customerName: 'Credit apply customer',
    currentBalance: 400,
    creditBalance: 130,
  );
  late Dio dio;
  late List<RequestOptions> writes;
  Map<String, dynamic> invoice(
    int id,
    num balance, {
    String date = '2026-01-01',
    String status = 'Unpaid',
  }) => {
    'id': id,
    'customer_id': 3,
    'invoice_no': 'INV$id',
    'invoice_date': date,
    'balance_amount': balance,
    'total_amount': balance,
    'paid_amount': 0,
    'status': status,
  };

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    writes = [];
    dio = Dio(BaseOptions(baseUrl: 'http://credit-test/api'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          Object? data;
          final pagination = {
            'currentPage': 1,
            'totalPages': 1,
            'totalItems': 2,
          };
          if (options.method == 'POST') {
            writes.add(options);
            data = {'paymentId': null, 'applicationId': 12, 'amount': 60.10};
          } else if (options.path.endsWith('/capabilities')) {
            data = {'storeCreditApply': 'permanent-application-v1'};
          } else if (options.path == '/invoices') {
            data = [invoice(1, 60.10), invoice(2, 80.20, date: '2026-01-02')];
          } else {
            data = const <String, dynamic>{};
          }
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {'success': true, 'data': data, 'pagination': pagination},
            ),
          );
        },
      ),
    );
  });

  Future<void> pump(WidgetTester tester, {bool urdu = false}) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(dio),
          authProvider.overrideWith(
            (ref) => CreditTestAuth(dio, const AuthUser(id: 7, username: 'admin', role: 'admin')),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          locale: Locale(urdu ? 'ur' : 'en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showStoreCreditApplyDialog(context, customer: customer),
                child: const Text('Open credit apply'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open credit apply'));
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, int id, String amount) async {
    final field = find.byKey(Key('credit_apply_$id'));
    await tester.ensureVisible(field);
    await tester.enterText(field, amount);
    await tester.pump();
  }

  testWidgets('applies store credit with one keyed POST and shows the receipt', (
    tester,
  ) async {
    await pump(tester);
    expect(find.textContaining('130'), findsWidgets);
    await enter(tester, 1, '60.10');
    await tester.tap(find.byKey(const Key('credit_apply_submit')));
    await tester.pumpAndSettle();

    expect(writes, hasLength(1));
    final options = writes.single;
    expect(options.path, '/customers/3/store-credit/apply');
    expect(options.headers['Idempotency-Key'], isA<String>());
    final body = options.data as Map<String, dynamic>;
    expect(body['allocations'], [
      {'invoice_id': 1, 'amount': 60.10},
    ]);
    expect(find.text('Store credit applied'), findsOneWidget);
  });

  testWidgets('rejects an allocation above the invoice balance without writing', (
    tester,
  ) async {
    await pump(tester);
    await enter(tester, 1, '99');
    await tester.tap(find.byKey(const Key('credit_apply_submit')));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
  });

  testWidgets('rejects a total above the store credit pool without writing', (
    tester,
  ) async {
    await pump(tester);
    await enter(tester, 1, '60.10');
    await enter(tester, 2, '80.20');
    await tester.tap(find.byKey(const Key('credit_apply_submit')));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
  });

  for (final urdu in [false, true]) {
    testWidgets('dialog opens in locale urdu=$urdu', (tester) async {
      await pump(tester, urdu: urdu);
      expect(find.byKey(const Key('credit_apply_submit')), findsOneWidget);
      expect(find.byKey(const Key('credit_apply_1')), findsOneWidget);
      expect(find.byKey(const Key('credit_apply_2')), findsOneWidget);
    });
  }
}
