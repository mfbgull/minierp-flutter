import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Tristate;
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
import 'package:minierp_app/data/models/unapplied_cash.dart';
import 'package:minierp_app/data/repositories/auth_repository.dart';
import 'package:minierp_app/data/repositories/repository_client.dart';
import 'package:minierp_app/features/customers/unapplied_cash_refund_dialog.dart';
import 'package:minierp_app/features/customers/unapplied_cash_reverse_dialog.dart';
import 'package:minierp_app/l10n/app_localizations.dart';
import 'package:minierp_app/features/customers/unapplied_cash_operation.dart';
import 'package:minierp_app/widgets/movable_dialog.dart';
import '../../test_helpers.dart';

class CorrectionTestAuth extends AuthNotifier {
  CorrectionTestAuth(Dio dio, AuthUser user)
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
    customerName: 'Cash correction customer',
    currentBalance: 0,
    creditBalance: 0,
  );
  late Dio dio;
  late AuthUser user;
  late List<RequestOptions> writes;
  late List<String> dates;
  late bool timeout;
  late bool used;
  late bool paged;
  late bool voided;
  late String kind;
  late String? rejection;
  late num capacity;
  late int reads;
  late int effects;
  late Completer<void>? gate;
  final seen = <String>{};
  Map<String, dynamic> receiptJson() => {
    'source_id': 1,
    'payment_id': 12,
    'payment_no': 'ADV0012',
    'payment_date': '2026-10-01',
    'payment_method': 'Cash',
    'original_amount': 100.25,
    'applied_amount': used ? 10 : 0,
    'refunded_amount': 0,
    'remaining_amount': used ? 90.25 : 100.25,
    'voided_at': voided ? '2026-10-17' : null,
    'can_reverse': !used && !voided,
  };
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    user = const AuthUser(id: 7, username: 'admin', role: 'admin');
    writes = [];
    dates = [];
    timeout = false;
    used = false;
    paged = false;
    voided = false;
    kind = 'UNAPPLIED_RECEIPT';
    rejection = null;
    capacity = 100.25;
    reads = 0;
    effects = 0;
    gate = null;
    seen.clear();
    dio = Dio(BaseOptions(baseUrl: 'http://correction-test/api'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          Object? data;
          if (options.method == 'POST') {
            writes.add(options);
            if (gate != null) await gate!.future;
            if (rejection != null) {
              if (rejection == 'UNAPPLIED_ALREADY_APPLIED') used = true;
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response<dynamic>(
                    requestOptions: options,
                    statusCode: 409,
                    data: {
                      'error': {
                        'code': rejection,
                        'message': 'Rejected',
                        'blockedBy': rejection == 'UNAPPLIED_ALREADY_APPLIED'
                            ? [
                                {
                                  'sourceId': 1,
                                  'consumed': 10,
                                  'invoices': [42],
                                },
                              ]
                            : [],
                      },
                    },
                  ),
                ),
              );
              return;
            }
            if (seen.add(options.headers['Idempotency-Key'] as String)) {
              effects++;
            }
            if (options.path.endsWith('/reverse')) voided = true;
            if (timeout) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.receiveTimeout,
                ),
              );
              return;
            }
            data = options.path.endsWith('/reverse')
                ? {'paymentId': 12, 'voided': true}
                : {
                    'paymentId': 13,
                    'applicationId': 8,
                    'amount': (options.data as Map)['amount'],
                  };
          } else if (options.path.endsWith('/capabilities')) {
            data = {
              'refund': 'permanent-application-v1',
              'reverse': 'guarded-status-v1',
            };
          } else if (options.path == '/payments/12') {
            reads++;
            data = {
              'id': 12,
              'customer_id': 3,
              'payment_no': 'ADV0012',
              'payment_date': '2026-10-01',
              'payment_method': 'Cash',
              'amount': 100.25,
              'payment_kind': kind,
              'voided_at': voided ? '2026-10-17' : null,
            };
          } else {
            reads++;
            dates.add(
              options.queryParameters['operation_date'] as String? ?? '',
            );
            data = {
              'customer_id': 3,
              'operation_date':
                  options.queryParameters['operation_date'] ?? '2026-10-17',
              'remaining_amount': 100.25,
              'available_amount': capacity,
              'refundable_amount': capacity,
              'receipts': [
                if (paged && options.queryParameters['page'] == 1)
                  {...receiptJson(), 'source_id': 99, 'payment_id': 99}
                else
                  receiptJson(),
              ],
            };
          }
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'success': true,
                'data': data,
                'pagination': {
                  'currentPage': options.queryParameters['page'] ?? 1,
                  'totalPages': paged ? 2 : 1,
                  'totalItems': 1,
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
    bool reverse = false,
    bool narrow = false,
    bool urdu = false,
    bool openDialog = true,
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
          authProvider.overrideWith((ref) => CorrectionTestAuth(dio, user)),
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
                onPressed: () => reverse
                    ? showUnappliedCashReverseDialog(
                        context,
                        customer: customer,
                        receipt: CashReceipt(receiptJson()),
                      )
                    : showUnappliedCashRefundDialog(
                        context,
                        customer: customer,
                      ),
                child: const Text('Open action'),
              ),
            ),
          ),
        ),
      ),
    );
    if (openDialog) {
      await tester.tap(find.text('Open action'));
      await tester.pumpAndSettle();
    }
  }

  Future<void> draft(
    WidgetTester tester, {
    bool reverse = false,
    String amount = '50.25',
  }) async {
    final field = find.byKey(
      Key(reverse ? 'cash_action_reason' : 'cash_action_amount'),
    );
    await tester.ensureVisible(field);
    await tester.enterText(
      field,
      reverse ? ' Correct duplicate advance ' : amount,
    );
    await tester.tap(find.byKey(const Key('cash_action_review')));
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('cash_action_confirm')));
    await tester.pumpAndSettle();
  }

  for (final reverse in [false, true]) {
    for (final urdu in [false, true]) {
      testWidgets(
        'Escape closes ${reverse ? 'reverse' : 'refund'} without submitting (urdu=$urdu)',
        (tester) async {
          await pump(tester, reverse: reverse, urdu: urdu);
          expect(find.byKey(const Key('cash_action_review')), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('cash_action_review')), findsNothing);
          expect(writes, isEmpty);
        },
      );
    }
  }

  for (final reverse in [false, true]) {
    for (final urdu in [false, true]) {
      testWidgets(
        'Escape restores keyboard focus to ${reverse ? 'reverse' : 'refund'} launcher (urdu=$urdu)',
        (tester) async {
          final semantics = tester.ensureSemantics();
          await pump(tester, reverse: reverse, urdu: urdu, openDialog: false);
          final launcher = find.widgetWithText(TextButton, 'Open action');
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          expect(
            tester.getSemantics(launcher).flagsCollection.isFocused,
            Tristate.isTrue,
          );

          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('cash_action_review')), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();

          expect(
            tester.getSemantics(launcher).flagsCollection.isFocused,
            Tristate.isTrue,
          );
          semantics.dispose();
        },
      );
    }
  }

  for (final reverse in [false, true]) {
    testWidgets(
      'Escape keeps ${reverse ? 'reverse' : 'refund'} open while its request is pending',
      (tester) async {
        gate = Completer<void>();
        await pump(tester, reverse: reverse);
        await draft(tester, reverse: reverse);
        await tester.tap(find.byKey(const Key('cash_action_confirm')));
        await tester.pump(const Duration(milliseconds: 100));
        expect(writes, hasLength(1));

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.byType(Dialog), findsOneWidget);
        expect(writes, hasLength(1));
        gate!.complete();
        await tester.pumpAndSettle();
      },
    );
  }

  for (final reverse in [false, true]) {
    for (final urdu in [false, true]) {
      testWidgets(
        'Tab traversal stays inside ${reverse ? 'reverse' : 'refund'} (urdu=$urdu)',
        (tester) async {
          await pump(tester, reverse: reverse, urdu: urdu);
          for (var index = 0; index < 12; index++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pump();
            final focusedContext =
                tester.binding.focusManager.primaryFocus?.context;
            expect(
              focusedContext?.findAncestorWidgetOfExactType<MovableDialog>(),
              isNotNull,
              reason: 'Tab ${index + 1} should remain inside the dialog',
            );
          }
        },
      );
    }
  }

  testWidgets('partial refund reviews cash out before exact keyed POST', (
    tester,
  ) async {
    await pump(tester);
    await draft(tester);
    expect(writes, isEmpty);
    expect(find.textContaining('50.25'), findsWidgets);
    await confirm(tester);
    expect(writes.single.path, '/unapplied-cash/refund');
    expect(writes.single.data, {
      'customer_id': 3,
      'amount': 50.25,
      'operation_date': dates.first,
      'payment_method': 'Cash',
    });
    expect(find.textContaining('Payment ID: 13'), findsOneWidget);
  });
  testWidgets(
    'over refundable capacity and fractional input never reach confirmation',
    (tester) async {
      await pump(tester);
      await draft(tester, amount: '100.26');
      expect(find.byKey(const Key('cash_action_confirm')), findsNothing);
      await draft(tester, amount: '1.001');
      expect(writes, isEmpty);
    },
  );
  testWidgets(
    'refund insufficient bank cash retains values and explains funds failure',
    (tester) async {
      final semantics = tester.ensureSemantics();
      rejection = 'INSUFFICIENT_CASH';
      await pump(tester);
      await tester.tap(find.byKey(const Key('cash_action_method')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bank').last);
      await tester.pumpAndSettle();
      await draft(tester);
      await confirm(tester);
      expect(writes.single.data['payment_method'], 'Bank');
      expect(find.textContaining('cash or bank balance'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.textContaining('cash or bank balance'))
            .getSemanticsData()
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('cash_action_amount')))
            .controller!
            .text,
        '50.25',
      );
      semantics.dispose();
    },
  );
  testWidgets('reversal confirmation keeps a visible focus outline', (
    tester,
  ) async {
    await pump(tester, reverse: true);
    await draft(tester, reverse: true);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('cash_action_confirm')),
    );

    expect(
      button.style?.side?.resolve({WidgetState.focused}),
      BorderSide(color: AppTheme.light.colorScheme.onError, width: 2),
    );
  });
  testWidgets('refund date change reloads date eligible refundable capacity', (
    tester,
  ) async {
    await pump(tester);
    capacity = 0;
    await tester.tap(find.byKey(const Key('cash_action_date')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(InputDatePickerFormField),
        matching: find.byType(TextFormField),
      ),
      '01/01/2025',
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(dates.last, '2025-01-01');
    await draft(tester);
    expect(writes, isEmpty);
  });
  testWidgets(
    'unknown refund retries original body and key after reduced pool',
    (tester) async {
      timeout = true;
      await pump(tester);
      await draft(tester);
      await confirm(tester);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      capacity = 0;
      timeout = false;
      await tester.tap(find.text('Open action'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cash_action_retry')));
      await tester.pumpAndSettle();
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
    'reverse verifies unused advance and sends only reason without editable date',
    (tester) async {
      await pump(tester, reverse: true);
      expect(reads, greaterThanOrEqualTo(2));
      expect(find.byKey(const Key('cash_action_date')), findsNothing);
      expect(find.text('ADV0012'), findsOneWidget);
      await draft(tester, reverse: true);
      expect(writes, isEmpty);
      await confirm(tester);
      expect(writes.single.path, '/payments/12/reverse');
      expect(writes.single.data, {'reason': 'Correct duplicate advance'});
      expect(find.text('Receipt reversed'), findsOneWidget);
    },
  );
  testWidgets('reversal live source lookup loads beyond first page', (
    tester,
  ) async {
    paged = true;
    await pump(tester, reverse: true);
    expect(reads, 3);
    await draft(tester, reverse: true);
    expect(find.byKey(const Key('cash_action_confirm')), findsOneWidget);
  });
  testWidgets(
    'foreign pending reversal cannot be dispatched for another receipt',
    (tester) async {
      await CashPendingStore().save(
        (server: 'http://correction-test/api', userId: 7),
        PendingCashOperation(
          request: CashRequest.reverse(
            customerId: 3,
            paymentId: 99,
            reason: 'Original',
          ),
          key: 'old-pending-999',
          firstDispatchedAt: DateTime.now(),
          replayPolicy: 'guarded-status-v1',
        ),
      );
      await pump(tester, reverse: true);
      expect(writes, isEmpty);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('cash_action_retry')))
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets('editing refund review returns to draft without dispatch', (
    tester,
  ) async {
    await pump(tester);
    await draft(tester);
    await tester.tap(find.text('Edit details'));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('cash_action_amount')))
          .enabled,
      isTrue,
    );
    await draft(tester, amount: '40');
    await confirm(tester);
    expect(writes.single.data['amount'], 40);
  });
  testWidgets('duplicate reversal confirmations produce one request', (
    tester,
  ) async {
    await pump(tester, reverse: true);
    await draft(tester, reverse: true);
    gate = Completer<void>();
    await tester.tap(find.byKey(const Key('cash_action_confirm')));
    await tester.pump(const Duration(milliseconds: 100));
    final retry = find.byKey(const Key('cash_action_retry'));
    expect(tester.widget<FilledButton>(retry).onPressed, isNull);
    await tester.tap(retry);
    await tester.pump(const Duration(milliseconds: 100));
    expect(writes.length, 1);
    gate!.complete();
    await tester.pumpAndSettle();
    expect(effects, 1);
  });
  testWidgets('reverse requires a reason', (tester) async {
    await pump(tester, reverse: true);
    await tester.tap(find.byKey(const Key('cash_action_review')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cash_action_confirm')), findsNothing);
    expect(writes, isEmpty);
  });
  testWidgets('used receipt is not offered for reversal', (tester) async {
    used = true;
    await pump(tester, reverse: true);
    expect(find.textContaining('cannot be reversed'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('cash_action_review')),
    );
    expect(button.onPressed, isNull);
    expect(writes, isEmpty);
  });
  testWidgets('ordinary payment cannot enter reversal flow', (tester) async {
    kind = 'RECEIPT';
    await pump(tester, reverse: true);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('cash_action_review')))
          .onPressed,
      isNull,
    );
    await draft(tester, reverse: true);
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    expect(find.byKey(const Key('cash_action_confirm')), findsNothing);
  });
  testWidgets(
    'raced reversal dependencies display source and invoice blockers',
    (tester) async {
      rejection = 'UNAPPLIED_ALREADY_APPLIED';
      await pump(tester, reverse: true);
      await draft(tester, reverse: true);
      await confirm(tester);
      expect(writes.length, 1);
      expect(find.textContaining('Source #1'), findsOneWidget);
      expect(find.text('Invoice #42'), findsOneWidget);
      expect(find.textContaining('cannot be reversed'), findsWidgets);
    },
  );
  testWidgets(
    'closed original receipt period is actionable and does not invent a reversal date',
    (tester) async {
      rejection = 'PERIOD_CLOSED';
      await pump(tester, reverse: true);
      await draft(tester, reverse: true);
      await confirm(tester);
      expect(find.textContaining('closed accounting period'), findsOneWidget);
      expect(find.byKey(const Key('cash_action_date')), findsNothing);
      expect(writes.single.data, {'reason': 'Correct duplicate advance'});
    },
  );
  testWidgets(
    'lost reverse response verifies already voided state instead of sending twice',
    (tester) async {
      timeout = true;
      await pump(tester, reverse: true);
      await draft(tester, reverse: true);
      await confirm(tester);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      timeout = false;
      await tester.tap(find.text('Open action'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cash_action_retry')));
      await tester.pumpAndSettle();
      expect(writes.length, 1);
      expect(effects, 1);
      expect(find.textContaining('already reversed'), findsOneWidget);
    },
  );
  for (final reverse in [false, true]) {
    testWidgets('missing permission blocks action reverse=$reverse', (
      tester,
    ) async {
      user = const AuthUser(
        id: 7,
        username: 'reader',
        role: 'user',
        permissions: [Permission(module: 'payments', action: 'read')],
      );
      await pump(tester, reverse: reverse);
      expect(reads, 0);
      expect(find.byKey(const Key('cash_action_review')), findsNothing);
      expect(writes, isEmpty);
    });
    testWidgets('narrow Urdu dark action remains usable reverse=$reverse', (
      tester,
    ) async {
      await pump(tester, reverse: reverse, narrow: true, urdu: true);
      await draft(tester, reverse: reverse);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('cash_action_confirm')), findsOneWidget);
    });
  }
}
