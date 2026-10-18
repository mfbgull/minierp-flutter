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
import 'package:minierp_app/features/customers/unapplied_cash_apply_dialog.dart';
import 'package:minierp_app/l10n/app_localizations.dart';
import '../../test_helpers.dart';

class ApplyTestAuth extends AuthNotifier {
  ApplyTestAuth(Dio dio, AuthUser user)
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
    customerName: 'Apply customer',
    currentBalance: 900,
    creditBalance: 0,
  );
  late Dio dio;
  late AuthUser user;
  late List<RequestOptions> writes;
  late List<int> pages;
  late List<String> dates;
  late bool timeout;
  late String? conflict;
  late int summaryReads;
  late num capacity;
  late num firstBalance;
  late int effects;
  late Completer<void>? gate;
  final seen = <String>{};
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
    user = const AuthUser(id: 7, username: 'admin', role: 'admin');
    writes = [];
    pages = [];
    dates = [];
    timeout = false;
    conflict = null;
    summaryReads = 0;
    capacity = 100.25;
    firstBalance = 60.10;
    effects = 0;
    gate = null;
    seen.clear();
    dio = Dio(BaseOptions(baseUrl: 'http://apply-test/api'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          Object? data;
          Map<String, dynamic> pagination = {
            'currentPage': 1,
            'totalPages': 1,
            'totalItems': 1,
          };
          if (options.method == 'POST') {
            writes.add(options);
            if (gate != null) await gate!.future;
            if (conflict != null) {
              if (conflict == 'INVOICE_OVERALLOCATION') {
                firstBalance = 10;
              } else {
                capacity = 10;
              }
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response<dynamic>(
                    requestOptions: options,
                    statusCode: 409,
                    data: {
                      'error': {'code': conflict, 'message': 'Changed'},
                    },
                  ),
                  type: DioExceptionType.badResponse,
                ),
              );
              return;
            }
            if (seen.add(options.headers['Idempotency-Key'] as String)) {
              effects++;
            }
            if (timeout) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.receiveTimeout,
                ),
              );
              return;
            }
            data = {'paymentId': null, 'applicationId': 8, 'amount': 100.25};
          } else if (options.path.endsWith('/capabilities')) {
            data = {'apply': 'permanent-application-v1'};
          } else if (options.path == '/invoices') {
            final page = options.queryParameters['page'] as int;
            pages.add(page);
            data = page == 1
                ? [
                    invoice(1, firstBalance),
                    invoice(9, 30, date: '2099-01-01'),
                    invoice(10, 50, status: 'Cancelled'),
                    invoice(11, 10, status: 'Deleted'),
                    invoice(12, 0),
                  ]
                : [invoice(2, 80.20, date: '2026-01-02')];
            pagination = {
              'currentPage': page,
              'totalPages': 2,
              'totalItems': 6,
            };
          } else {
            summaryReads++;
            dates.add(options.queryParameters['operation_date'] as String);
            data = {
              'customer_id': 3,
              'operation_date': options.queryParameters['operation_date'],
              'remaining_amount': 250,
              'available_amount': capacity,
              'refundable_amount': capacity,
              'receipts': [],
            };
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
  Future<void> pump(
    WidgetTester tester, {
    bool narrow = false,
    bool urdu = false,
  }) async {
    tester.view.physicalSize = narrow
        ? const Size(390, 844)
        : const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(dio),
          authProvider.overrideWith((ref) => ApplyTestAuth(dio, user)),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: urdu ? ThemeMode.dark : ThemeMode.light,
          locale: Locale(urdu ? 'ur' : 'en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showUnappliedCashApplyDialog(context, customer: customer),
                child: const Text('Open apply'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open apply'));
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, int id, String amount) async {
    final field = find.byKey(Key('cash_apply_$id'));
    await tester.ensureVisible(field);
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, amount);
    await tester.pump();
    expect(tester.widget<TextFormField>(field).controller!.text, amount);
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('cash_apply_submit')));
    await tester.pumpAndSettle();
  }

  for (final urdu in [false, true]) {
    testWidgets('Escape closes apply without submitting (urdu=$urdu)', (
      tester,
    ) async {
      await pump(tester, urdu: urdu);
      expect(find.byKey(const Key('cash_apply_submit')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cash_apply_submit')), findsNothing);
      expect(writes, isEmpty);
    });
  }

  testWidgets(
    'all invoice pages are loaded online and ineligible invoices excluded',
    (tester) async {
      await pump(tester);
      expect(pages, [1, 2]);
      expect(find.text('INV1'), findsOneWidget);
      expect(find.text('INV2'), findsOneWidget);
      for (final id in [9, 10, 11, 12]) {
        expect(find.text('INV$id'), findsNothing);
      }
      expect(find.byKey(const Key('cash_receive_method')), findsNothing);
      expect(find.text('Cash'), findsNothing);
      expect(dates.single, isNotEmpty);
    },
  );
  testWidgets(
    'partial multi invoice allocation posts exact body without collecting cash',
    (tester) async {
      await pump(tester);
      await enter(tester, 1, '60.10');
      await enter(tester, 2, '40.15');
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('cash_apply_1')))
            .controller!
            .text,
        '60.10',
      );
      await submit(tester);
      expect(writes.single.path, '/unapplied-cash/apply');
      expect(writes.single.data, {
        'customer_id': 3,
        'operation_date': dates.single,
        'allocations': [
          {'invoice_id': 1, 'amount': 60.1},
          {'invoice_id': 2, 'amount': 40.15},
        ],
      });
      expect(effects, 1);
      expect(find.textContaining('Application ID: 8'), findsOneWidget);
    },
  );
  testWidgets(
    'fractional over pool and invoice balance validation prevent POST',
    (tester) async {
      await pump(tester);
      await enter(tester, 1, '60.11');
      await submit(tester);
      expect(writes, isEmpty);
      await enter(tester, 1, '60.10');
      await enter(tester, 2, '40.16');
      await submit(tester);
      expect(writes, isEmpty);
      await enter(tester, 2, '1.001');
      await submit(tester);
      expect(writes, isEmpty);
    },
  );
  testWidgets(
    'auto allocate uses oldest first and requires explicit confirmation',
    (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('cash_apply_auto')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('cash_apply_1')))
            .controller!
            .text,
        '60.10',
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('cash_apply_2')))
            .controller!
            .text,
        '40.15',
      );
      expect(writes, isEmpty);
    },
  );
  testWidgets(
    'stale pool conflict refreshes data without discarding allocations or resubmitting',
    (tester) async {
      conflict = 'INSUFFICIENT_UNAPPLIED_CASH';
      await pump(tester);
      await enter(tester, 1, '50');
      await submit(tester);
      expect(summaryReads, 2);
      expect(writes.length, 1);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('cash_apply_1')))
            .controller!
            .text,
        '50',
      );
      expect(find.textContaining('Balances changed'), findsOneWidget);
      conflict = null;
      await submit(tester);
      expect(writes.length, 1);
    },
  );
  testWidgets(
    'lost response close reopen retries immutable request despite reduced pool',
    (tester) async {
      timeout = true;
      await pump(tester);
      await enter(tester, 1, '50');
      await submit(tester);
      expect(writes.length, 1);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      capacity = 0;
      timeout = false;
      await tester.tap(find.text('Open apply'));
      await tester.pumpAndSettle();
      await submit(tester);
      expect(writes.length, 2);
      expect(jsonEncode(writes[0].data), jsonEncode(writes[1].data));
      expect(
        writes[0].headers['Idempotency-Key'],
        writes[1].headers['Idempotency-Key'],
      );
      expect(effects, 1);
    },
  );
  testWidgets(
    'stale invoice conflict preserves draft and rechecks its new balance',
    (tester) async {
      conflict = 'INVOICE_OVERALLOCATION';
      await pump(tester);
      await enter(tester, 1, '50');
      await submit(tester);
      expect(summaryReads, 2);
      expect(pages, [1, 2, 1, 2]);
      expect(writes.length, 1);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('cash_apply_1')))
            .controller!
            .text,
        '50',
      );
      conflict = null;
      await submit(tester);
      expect(writes.length, 1);
    },
  );
  testWidgets('search does not drop allocations outside visible results', (
    tester,
  ) async {
    await pump(tester);
    await enter(tester, 1, '50');
    await tester.enterText(find.byKey(const Key('cash_apply_search')), 'INV2');
    await tester.pumpAndSettle();
    expect(find.text('INV1'), findsNothing);
    await enter(tester, 2, '40.15');
    await submit(tester);
    expect((writes.single.data as Map)['allocations'], [
      {'invoice_id': 1, 'amount': 50.0},
      {'invoice_id': 2, 'amount': 40.15},
    ]);
  });
  testWidgets(
    'changing operation date refetches capacity and invoice eligibility',
    (tester) async {
      await pump(tester);
      capacity = 0;
      await tester.tap(find.byKey(const Key('cash_apply_date')));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      final dateInput = find.descendant(
        of: find.byType(InputDatePickerFormField),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(dateInput, '01/01/2025');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(dates.last, '2025-01-01');
      expect(summaryReads, 2);
      expect(pages, [1, 2, 1, 2]);
      expect(
        find.text('No eligible open invoices on this date.'),
        findsOneWidget,
      );
      expect(writes, isEmpty);
    },
  );
  testWidgets(
    'allocation editor keeps select all shortcuts inside the amount field',
    (tester) async {
      await pump(tester);
      await enter(tester, 1, '60.10');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      final selection = tester
          .widget<TextFormField>(find.byKey(const Key('cash_apply_1')))
          .controller!
          .selection;
      expect(selection.start, 0);
      expect(selection.end, 5);
    },
  );
  testWidgets('duplicate confirm taps dispatch only once', (tester) async {
    await pump(tester);
    await enter(tester, 1, '50');
    gate = Completer<void>();
    await tester.tap(find.byKey(const Key('cash_apply_submit')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const Key('cash_apply_submit')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(writes.length, 1);
    gate!.complete();
    await tester.pumpAndSettle();
  });
  testWidgets(
    'invoice permission missing explains access instead of empty results',
    (tester) async {
      user = const AuthUser(
        id: 7,
        username: 'updater',
        role: 'user',
        permissions: [
          Permission(module: 'payments', action: 'update'),
          Permission(module: 'payments', action: 'read'),
        ],
      );
      await pump(tester);
      expect(pages, isEmpty);
      expect(
        find.textContaining('permission to read invoices'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('cash_apply_submit')), findsNothing);
    },
  );
  testWidgets('update permission missing prevents reads and writes', (
    tester,
  ) async {
    user = const AuthUser(
      id: 7,
      username: 'reader',
      role: 'user',
      permissions: [
        Permission(module: 'payments', action: 'read'),
        Permission(module: 'invoices', action: 'read'),
      ],
    );
    await pump(tester);
    expect(summaryReads, 0);
    expect(pages, isEmpty);
    expect(find.byKey(const Key('cash_apply_submit')), findsNothing);
  });
  for (final urdu in [false, true]) {
    testWidgets('narrow apply layout usable urdu=$urdu', (tester) async {
      await pump(tester, narrow: true, urdu: urdu);
      await enter(tester, 1, '50');
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('cash_apply_submit')), findsOneWidget);
    });
  }
}
