import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:minierp_app/features/customers/customer_detail_screen.dart';
import 'package:minierp_app/features/customers/unapplied_cash_receive_dialog.dart';
import 'package:minierp_app/features/customers/unapplied_cash_operation.dart';
import 'package:minierp_app/data/models/unapplied_cash.dart';
import 'package:minierp_app/l10n/app_localizations.dart';
import '../../test_helpers.dart';

class CashTestAuth extends AuthNotifier {
  CashTestAuth(Dio dio, AuthUser user)
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
    customerName: 'Advance customer',
    currentBalance: 0,
    creditBalance: 0,
  );
  late Dio dio;
  late List<RequestOptions> writes;
  late Map<String, Object> results;
  late bool offline;
  late bool timeout;
  late String? rejection;
  late Completer<void>? gate;
  late int cashReads;
  late num held;
  late bool includeReceipt;
  late AuthUser user;
  const admin = AuthUser(id: 7, username: 'cashier', role: 'admin');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    writes = [];
    results = {};
    offline = false;
    timeout = false;
    rejection = null;
    gate = null;
    cashReads = 0;
    held = 0;
    includeReceipt = false;
    user = admin;
    dio = Dio(BaseOptions(baseUrl: 'http://cash-test/api'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (offline) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
              ),
            );
            return;
          }
          Object? data;
          if (options.method == 'POST') {
            writes.add(options);
            if (gate != null) await gate!.future;
            if (rejection != null) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response<dynamic>(
                    requestOptions: options,
                    statusCode: 409,
                    data: {
                      'success': false,
                      'error': {
                        'code': rejection,
                        'message': 'Domain conflict',
                      },
                    },
                  ),
                ),
              );
              return;
            }
            final key = options.headers['Idempotency-Key'] as String;
            data = results.putIfAbsent(key, () {
              final body = options.data as Map;
              held += body['amount'] as num;
              return {
                'paymentId': 12,
                'applicationId': null,
                'amount': body['amount'],
              };
            });
            if (timeout) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.receiveTimeout,
                ),
              );
              return;
            }
          } else if (options.path.endsWith('/capabilities')) {
            data = {'receive': 'durable-v1'};
          } else if (options.path.endsWith('/unapplied-cash')) {
            cashReads++;
            data = {
              'customer_id': 3,
              'operation_date': '2026-10-01',
              'remaining_amount': held,
              'available_amount': held,
              'refundable_amount': held,
              'receipts': includeReceipt
                  ? [
                      {
                        'source_id': 1,
                        'payment_id': 12,
                        'payment_no': 'PAY0012',
                        'payment_date': '2026-10-01',
                        'payment_method': 'Cash',
                        'original_amount': held,
                        'applied_amount': 0,
                        'refunded_amount': 0,
                        'remaining_amount': held,
                        'voided_at': null,
                        'can_reverse': true,
                      },
                    ]
                  : [],
            };
          } else if (options.path == '/customers/3') {
            data = customer.toJson();
          } else {
            data = [];
          }
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'success': true,
                'data': data,
                'pagination': {
                  'currentPage': 1,
                  'totalPages': 0,
                  'totalItems': 0,
                  'limit': 20,
                },
              },
            ),
          );
        },
      ),
    );
  });

  Future<void> pump(
    WidgetTester tester, {
    bool page = false,
    Size size = const Size(1440, 900),
    Locale locale = const Locale('en'),
    bool dark = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(dio),
          authProvider.overrideWith((ref) => CashTestAuth(dio, user)),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: page
                ? const CustomerDetailScreen(customerId: 3)
                : Builder(
                    builder: (context) => Center(
                      child: FilledButton(
                        onPressed: () => showUnappliedCashReceiveDialog(
                          context,
                          customer: customer,
                        ),
                        child: const Text('Open advance'),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (!page) {
      await tester.tap(find.text('Open advance'));
      await tester.pumpAndSettle();
    }
  }

  testWidgets(
    'customer detail exposes a sixth cash tab and distinct advance action',
    (tester) async {
      await pump(tester, page: true);
      expect(find.text('Unapplied Cash'), findsOneWidget);
      expect(find.text('Record Payment'), findsOneWidget);
      expect(find.text('Receive Advance'), findsOneWidget);
      await tester.tap(find.text('Unapplied Cash'));
      await tester.pumpAndSettle();
      expect(find.text('No advance receipts yet'), findsOneWidget);
      expect(find.text('Store credit'), findsOneWidget);
      expect(cashReads, greaterThan(0));
    },
  );

  testWidgets(
    'receive without invoices posts only the strict body and shows payment identity',
    (tester) async {
      await pump(tester);
      expect(find.text('Advance customer'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('cash_receive_amount')),
        '500.25',
      );
      await tester.tap(find.byKey(const Key('cash_receive_submit')));
      await tester.pumpAndSettle();
      expect(writes.length, 1);
      expect(writes.single.path, '/customers/3/unapplied-cash');
      final body = writes.single.data as Map;
      expect(body.keys.toSet(), {'amount', 'operation_date', 'payment_method'});
      expect(body['amount'], 500.25);
      expect(body['payment_method'], 'Cash');
      expect(body['operation_date'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      expect(find.text('Advance received'), findsOneWidget);
      expect(find.textContaining('12'), findsWidgets);
    },
  );

  testWidgets('bad currency and missing amount never send money', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('cash_receive_submit')));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    await tester.enterText(
      find.byKey(const Key('cash_receive_amount')),
      '1.001',
    );
    await tester.tap(find.byKey(const Key('cash_receive_submit')));
    await tester.pumpAndSettle();
    expect(
      find.text('Enter a positive amount with at most two decimal places.'),
      findsOneWidget,
    );
    expect(writes, isEmpty);
  });

  testWidgets('desktop receipts update their text after changing language', (
    tester,
  ) async {
    includeReceipt = true;
    held = 250;
    await pump(tester, page: true);
    await tester.tap(find.text('Unapplied Cash'));
    await tester.pumpAndSettle();
    expect(find.text('Remaining'), findsOneWidget);
    await pump(tester, page: true, locale: const Locale('ur'));
    final context = tester.element(find.byType(CustomerDetailScreen));
    expect(
      find.text(AppLocalizations.of(context)!.cashRemaining),
      findsOneWidget,
    );
    expect(find.text('Remaining'), findsNothing);
    await pump(tester, page: true, locale: const Locale('ur'), dark: true);
    expect(find.text('PAY0012'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('amount and date expose their labels to assistive technology', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);
    expect(
      tester
          .getSemantics(find.byKey(const Key('cash_receive_amount')))
          .getSemanticsData()
          .label,
      contains('Amount'),
    );
    expect(
      tester
          .getSemantics(find.byKey(const Key('cash_receive_date')))
          .getSemanticsData()
          .label,
      contains('Operation date'),
    );
    semantics.dispose();
  });

  for (final locale in const [Locale('en'), Locale('ur')]) {
    testWidgets(
      'Escape closes the receive dialog without submitting (${locale.languageCode})',
      (tester) async {
        await pump(tester, locale: locale);
        expect(find.byKey(const Key('cash_receive_amount')), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('cash_receive_amount')), findsNothing);
        expect(writes, isEmpty);
      },
    );
  }

  testWidgets(
    'create-only users can receive without reading a fabricated zero balance',
    (tester) async {
      user = const AuthUser(
        id: 7,
        username: 'creator',
        role: 'user',
        permissions: [Permission(module: 'payments', action: 'create')],
      );
      await pump(tester, page: true);
      await tester.tap(find.text('Unapplied Cash'));
      await tester.pumpAndSettle();
      expect(
        find.text('You do not have permission to view unapplied cash.'),
        findsOneWidget,
      );
      expect(cashReads, 0);
      await tester.tap(find.text('Receive Advance'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('cash_receive_amount')), '5');
      await tester.tap(find.byKey(const Key('cash_receive_submit')));
      await tester.pumpAndSettle();
      expect(writes.length, 1);
    },
  );

  testWidgets('read-only users cannot submit an advance', (tester) async {
    user = const AuthUser(
      id: 7,
      username: 'reader',
      role: 'user',
      permissions: [Permission(module: 'payments', action: 'read')],
    );
    await pump(tester);
    expect(find.byKey(const Key('cash_receive_submit')), findsNothing);
    expect(writes, isEmpty);
  });

  testWidgets(
    'existing-credit conflict is actionable and does not claim success',
    (tester) async {
      rejection = 'CUSTOMER_ALREADY_IN_CREDIT';
      await pump(tester);
      await tester.enterText(find.byKey(const Key('cash_receive_amount')), '5');
      await tester.tap(find.byKey(const Key('cash_receive_submit')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'This customer is already in credit. Settle that credit before receiving an advance.',
        ),
        findsOneWidget,
      );
      expect(find.text('Advance received'), findsNothing);
    },
  );

  testWidgets(
    'duplicate taps lock the form while the first request is pending',
    (tester) async {
      gate = Completer<void>();
      await pump(tester);
      await tester.enterText(find.byKey(const Key('cash_receive_amount')), '5');
      await tester.tap(find.byKey(const Key('cash_receive_submit')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('cash_receive_submit')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(writes.length, 1);
      gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Advance received'), findsOneWidget);
    },
  );

  testWidgets(
    'lost response retries the exact request after close and reopen',
    (tester) async {
      timeout = true;
      await pump(tester);
      await tester.enterText(find.byKey(const Key('cash_receive_amount')), '5');
      await tester.tap(find.byKey(const Key('cash_receive_submit')));
      await tester.pumpAndSettle();
      expect(find.text('Advance received'), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open advance'));
      await tester.pumpAndSettle();
      timeout = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(writes.length, 2);
      expect(
        writes.first.headers['Idempotency-Key'],
        writes.last.headers['Idempotency-Key'],
      );
      expect(jsonEncode(writes.first.data), jsonEncode(writes.last.data));
      expect(held, 5);
      expect(find.text('Advance received'), findsOneWidget);
    },
  );

  testWidgets('offline capability check prevents any advance POST', (
    tester,
  ) async {
    offline = true;
    await pump(tester);
    await tester.enterText(find.byKey(const Key('cash_receive_amount')), '5');
    await tester.tap(find.byKey(const Key('cash_receive_submit')));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    expect(
      find.text(
        'Connect to the server to load cash or confirm this operation.',
      ),
      findsOneWidget,
    );
  });

  for (final locale in [const Locale('en'), const Locale('ur')]) {
    testWidgets(
      'narrow ${locale.languageCode} cash workspace and receive dialog remain usable',
      (tester) async {
        held = 500;
        includeReceipt = true;
        await pump(
          tester,
          page: true,
          size: const Size(390, 844),
          locale: locale,
          dark: locale.languageCode == 'ur',
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(CustomerDetailScreen)),
        )!;
        await tester.ensureVisible(find.text(l10n.cashTab));
        await tester.tap(find.text(l10n.cashTab));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.textContaining('PAY0012'),
          150,
          scrollable: find
              .descendant(
                of: find.byType(ListView).last,
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(find.textContaining('PAY0012'), findsOneWidget);
        await tester.tap(find.text(l10n.cashReceiveAdvance));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('cash_receive_amount')),
          '1.25',
        );
        await tester.ensureVisible(
          find.byKey(const Key('cash_receive_submit')),
        );
        await tester.tap(find.byKey(const Key('cash_receive_submit')));
        await tester.pumpAndSettle();
        expect(find.text(l10n.cashReceived), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(writes.length, 1);
      },
    );
  }

  testWidgets(
    'another customer pending request cannot be retried from this dialog',
    (tester) async {
      await CashPendingStore().save(
        (server: 'http://cash-test/api', userId: 7),
        PendingCashOperation(
          request: CashRequest.receive(
            customerId: 99,
            amountMinor: 100,
            date: '2026-10-01',
          ),
          key: 'other-customer-fixture',
          firstDispatchedAt: DateTime.utc(2026),
          replayPolicy: 'durable-v1',
        ),
      );
      await pump(tester);
      expect(
        find.text(
          'Another customer or cash workflow has a pending request. Recover that original operation before receiving more cash.',
        ),
        findsOneWidget,
      );
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('cash_receive_submit')),
      );
      expect(button.onPressed, isNull);
      expect(writes, isEmpty);
    },
  );
}
