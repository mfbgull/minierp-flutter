import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:minierp_app/core/api/api_client.dart';
import 'package:minierp_app/core/auth/auth_notifier.dart';
import 'package:minierp_app/core/auth/token_storage.dart';
import 'package:minierp_app/core/theme/app_theme.dart';
import 'package:minierp_app/data/models/auth_user.dart';
import 'package:minierp_app/data/models/customer.dart';
import 'package:minierp_app/data/models/unapplied_cash.dart';
import 'package:minierp_app/data/repositories/auth_repository.dart';
import 'package:minierp_app/data/repositories/repository_client.dart';
import 'package:minierp_app/data/repositories/unapplied_cash_repository.dart';
import 'package:minierp_app/features/customers/customer_unapplied_cash_tab.dart';
import 'package:minierp_app/features/customers/unapplied_cash_operation.dart';
import 'package:minierp_app/features/customers/unapplied_cash_receive_dialog.dart';
import 'package:minierp_app/features/customers/unapplied_cash_apply_dialog.dart';
import 'package:minierp_app/features/customers/unapplied_cash_refund_dialog.dart';
import 'package:minierp_app/features/customers/unapplied_cash_reverse_dialog.dart';
import 'package:minierp_app/l10n/app_localizations.dart';

class RuntimeTokenStorage implements TokenStorage {
  @override
  Future<void> clear() async {}
  @override
  Future<String?> readToken() async => null;
  @override
  Future<String?> readRefreshToken() async => null;
  @override
  Future<void> writeToken(String value) async {}
  @override
  Future<void> writeRefreshToken(String value) async {}
}

class RuntimeAuth extends AuthNotifier {
  RuntimeAuth(Dio dio, AuthUser user)
    : super(AuthRepository(RepositoryClient(dio)), RuntimeTokenStorage()) {
    state = AuthState(status: AuthStatus.authenticated, user: user);
  }
  @override
  Future<void> restoreSession() async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const base = 'http://127.0.0.1:4327/api';
  const phase = String.fromEnvironment('F7_PHASE', defaultValue: 'journeys');
  final control = Dio(
    BaseOptions(
      baseUrl: 'http://127.0.0.1:4328',
      headers: {'X-Fixture-Token': 'mini-erp-f7-local'},
    ),
  );
  final dio = Dio(
    BaseOptions(baseUrl: base, receiveTimeout: const Duration(seconds: 10)),
  );
  late AuthUser user;
  late Map<String, dynamic> health;
  late SharedPreferences preferences;
  var instance = 0;

  Future<Map<String, dynamic>> command(Map<String, dynamic> body) async =>
      Map<String, dynamic>.from(
        (await control.post('/command', data: body)).data as Map,
      );
  Future<Map<String, dynamic>> status() async =>
      Map<String, dynamic>.from((await control.get('/status')).data as Map);
  Future<Customer> customer() async =>
      Customer.fromJson(await command({'action': 'customer'}));
  Future<void> assertInvariants() async {
    final result = await status();
    expect(result['canonicalUnchanged'], isTrue);
    expect((result['gl'] as Map)['groups'], isEmpty);
    expect((result['gl'] as Map)['totalDiff'], closeTo(0, 0.001));
    for (final entry in (result['violations'] as Map).entries) {
      expect(entry.value, isEmpty, reason: '${entry.key}');
    }
  }

  setUpAll(() async {
    health = Map<String, dynamic>.from(
      (await control.get('/health')).data as Map,
    );
    expect(health['fixture'], 'mini-erp-unapplied-cash-f7');
    expect(health['api'], base);
    final directory = health['directory'] as String;
    expect(directory, contains('/server/.tmp-test/ui-f7-'));
    expect(File('$directory/fixture-id').readAsStringSync(), health['marker']);
    expect(Platform.environment['XDG_DATA_HOME'], startsWith('$directory/'));
    expect(Platform.environment['XDG_CONFIG_HOME'], startsWith('$directory/'));
    final login =
        (await dio.post(
              '/auth/login',
              data: {
                'username': 'admin',
                'password': 'ui-f7-isolated-password',
              },
            )).data
            as Map;
    dio.options.headers['Authorization'] =
        'Bearer ${(login['data'] as Map)['token']}';
    user = AuthUser.fromJson(
      Map<String, dynamic>.from((login['data'] as Map)['user'] as Map),
    );
    preferences = await SharedPreferences.getInstance();
  });

  Future<void> until(WidgetTester tester, bool Function() condition) async {
    for (var attempt = 0; attempt < 150 && !condition(); attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      condition(),
      isTrue,
      reason: 'Runtime UI did not reach expected state',
    );
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await until(tester, () => finder.evaluate().isNotEmpty);
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pump(const Duration(milliseconds: 150));
  }

  Future<void> mount(
    WidgetTester tester,
    Customer customer, {
    CashReceipt? receipt,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        key: ValueKey(++instance),
        overrides: [
          dioProvider.overrideWithValue(dio),
          authProvider.overrideWith((ref) => RuntimeAuth(dio, user)),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: Builder(
                    builder: (context) => Column(
                      children: [
                        Wrap(
                          children: [
                            TextButton(
                              key: const Key('receive'),
                              onPressed: () => showUnappliedCashReceiveDialog(
                                context,
                                customer: customer,
                              ),
                              child: const Text('Receive'),
                            ),
                            TextButton(
                              key: const Key('apply'),
                              onPressed: () => showUnappliedCashApplyDialog(
                                context,
                                customer: customer,
                              ),
                              child: const Text('Apply'),
                            ),
                            TextButton(
                              key: const Key('refund'),
                              onPressed: () => showUnappliedCashRefundDialog(
                                context,
                                customer: customer,
                              ),
                              child: const Text('Refund'),
                            ),
                            if (receipt != null)
                              TextButton(
                                key: const Key('reverse'),
                                onPressed: () => showUnappliedCashReverseDialog(
                                  context,
                                  customer: customer,
                                  receipt: receipt,
                                ),
                                child: const Text('Reverse'),
                              ),
                          ],
                        ),
                        Expanded(
                          child: CustomerUnappliedCashTab(
                            customer: customer,
                            sessionId: 7,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> close(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, 'Close').last);
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> receive(
    WidgetTester tester,
    Customer customer,
    String amount,
  ) async {
    await mount(tester, customer);
    await tap(tester, 'receive');
    await until(
      tester,
      () => find.byKey(const Key('cash_receive_amount')).evaluate().isNotEmpty,
    );
    await tester.enterText(
      find.byKey(const Key('cash_receive_amount')),
      amount,
    );
    await tap(tester, 'cash_receive_submit');
    await until(
      tester,
      () => find.textContaining('Advance received').evaluate().isNotEmpty,
    );
    await close(tester);
  }

  if (phase == 'journeys') {
    testWidgets(
      'receive 500 apply 400 refund 100 settles the invoice without another receipt',
      (tester) async {
        final person = await customer();
        await receive(tester, person, '500');
        final invoice = await command({
          'action': 'invoice',
          'customerId': person.id,
        });
        final current = Customer.fromJson(
          Map<String, dynamic>.from(
            (await dio.get('/customers/${person.id}')).data['data'] as Map,
          ),
        );
        await mount(tester, current);
        await tap(tester, 'apply');
        await until(
          tester,
          () => find.byKey(const Key('cash_apply_auto')).evaluate().isNotEmpty,
        );
        await tap(tester, 'cash_apply_auto');
        await tap(tester, 'cash_apply_submit');
        await until(
          tester,
          () => find.textContaining('Cash applied').evaluate().isNotEmpty,
        );
        await close(tester);
        await tap(tester, 'refund');
        await until(
          tester,
          () =>
              find.byKey(const Key('cash_action_amount')).evaluate().isNotEmpty,
        );
        await tester.enterText(
          find.byKey(const Key('cash_action_amount')),
          '100',
        );
        await tap(tester, 'cash_action_review');
        await tap(tester, 'cash_action_confirm');
        await until(
          tester,
          () => find.textContaining('Paid out').evaluate().isNotEmpty,
        );
        await close(tester);
        final result = await status();
        final payments = (result['payments'] as List)
            .where((row) => row['customer_id'] == person.id)
            .toList();
        expect(
          payments.map((row) => [row['amount'], row['payment_kind']]).toList(),
          [
            [500, 'UNAPPLIED_RECEIPT'],
            [-100, 'REFUND'],
          ],
        );
        final saved = (result['invoices'] as List).singleWhere(
          (row) => row['id'] == invoice['invoiceId'],
        );
        expect(saved['paid_amount'], 400);
        expect(saved['balance_amount'], 0);
        final summary = await UnappliedCashRepository(
          RepositoryClient(dio),
        ).summary(person.id);
        expect(summary.requireData.remainingMinor, 0);
        await assertInvariants();
      },
    );
    testWidgets('unused receipt reverses and cannot be refunded afterward', (
      tester,
    ) async {
      final person = await customer();
      await receive(tester, person, '60');
      final summary = (await UnappliedCashRepository(
        RepositoryClient(dio),
      ).summary(person.id)).requireData;
      await mount(tester, person, receipt: summary.receipts.items.single);
      await tap(tester, 'reverse');
      await until(
        tester,
        () => find.byKey(const Key('cash_action_reason')).evaluate().isNotEmpty,
      );
      await tester.enterText(
        find.byKey(const Key('cash_action_reason')),
        'F7 runtime reversal',
      );
      await tap(tester, 'cash_action_review');
      await tap(tester, 'cash_action_confirm');
      await until(
        tester,
        () => find.textContaining('has been reversed').evaluate().isNotEmpty,
      );
      await close(tester);
      final blocked = await dio.post(
        '/unapplied-cash/refund',
        data: {
          'customer_id': person.id,
          'operation_date': health['date'],
          'amount': 1,
          'payment_method': 'Cash',
        },
        options: Options(
          headers: {'Idempotency-Key': 'f7-voided-refund'},
          validateStatus: (_) => true,
        ),
      );
      expect(blocked.statusCode, 409);
      expect(
        (await UnappliedCashRepository(
          RepositoryClient(dio),
        ).summary(person.id)).requireData.remainingMinor,
        0,
      );
      await assertInvariants();
    });
    testWidgets(
      'closed period and offline reads fail without financial writes',
      (tester) async {
        final person = await customer();
        final before = await status();
        await command({'action': 'period', 'closed': true});
        try {
          await mount(tester, person);
          await tap(tester, 'receive');
          await until(
            tester,
            () => find
                .byKey(const Key('cash_receive_amount'))
                .evaluate()
                .isNotEmpty,
          );
          await tester.enterText(
            find.byKey(const Key('cash_receive_amount')),
            '5',
          );
          await tap(tester, 'cash_receive_submit');
          await until(
            tester,
            () => find
                .textContaining('closed accounting period')
                .evaluate()
                .isNotEmpty,
          );
          expect((await status())['payments'], before['payments']);
          await close(tester);
        } finally {
          await command({'action': 'period', 'closed': false});
        }
        await command({'action': 'offline', 'enabled': true});
        try {
          await tap(tester, 'refund');
          await until(
            tester,
            () => find
                .textContaining('Connect to the server')
                .evaluate()
                .isNotEmpty,
          );
          expect(
            tester
                .widget<FilledButton>(
                  find.byKey(const Key('cash_action_review')),
                )
                .onPressed,
            isNull,
          );
          expect((await status())['payments'], before['payments']);
          await close(tester);
        } finally {
          await command({'action': 'offline', 'enabled': false});
        }
        await assertInvariants();
      },
    );
    testWidgets(
      'another session changes capacity without silently changing the draft',
      (tester) async {
        final person = await customer();
        await receive(tester, person, '500');
        final invoice = await command({
          'action': 'invoice',
          'customerId': person.id,
        });
        await tap(tester, 'apply');
        await until(
          tester,
          () => find.byKey(const Key('cash_apply_auto')).evaluate().isNotEmpty,
        );
        await tap(tester, 'cash_apply_auto');
        await dio.post(
          '/unapplied-cash/refund',
          data: {
            'customer_id': person.id,
            'amount': 200,
            'operation_date': health['date'],
            'payment_method': 'Cash',
          },
          options: Options(headers: {'Idempotency-Key': 'f7-race-refund'}),
        );
        await tap(tester, 'cash_apply_submit');
        await until(
          tester,
          () => find.textContaining('Balances changed').evaluate().isNotEmpty,
        );
        final saved = ((await status())['invoices'] as List).singleWhere(
          (row) => row['id'] == invoice['invoiceId'],
        );
        expect(saved['paid_amount'], 0);
        expect(saved['balance_amount'], 400);
        expect(
          (await UnappliedCashRepository(
            RepositoryClient(dio),
          ).summary(person.id)).requireData.availableMinor,
          30000,
        );
        await close(tester);
        await assertInvariants();
      },
    );
    testWidgets(
      'read-only and partial roles are denied by both UI and mounted API',
      (tester) async {
        final admin = user;
        final authorization = dio.options.headers['Authorization'];
        final person = await customer();
        try {
          for (final role in ['read', 'partial']) {
            final account = await command({'action': 'role', 'kind': role});
            user = AuthUser.fromJson(
              Map<String, dynamic>.from(account['user'] as Map),
            );
            dio.options.headers['Authorization'] = 'Bearer ${account['token']}';
            final before = await status();
            await mount(tester, person);
            await tap(tester, role == 'read' ? 'receive' : 'apply');
            await until(
              tester,
              () => find
                  .textContaining(
                    role == 'read'
                        ? 'permission to receive'
                        : 'permission to read invoices',
                  )
                  .evaluate()
                  .isNotEmpty,
            );
            expect((await status())['writeRequests'], before['writeRequests']);
            await close(tester);
            final denied = await dio.post(
              '/customers/${person.id}/unapplied-cash',
              data: {
                'amount': 1,
                'operation_date': health['date'],
                'payment_method': 'Cash',
              },
              options: Options(
                headers: {'Idempotency-Key': 'f7-denied-$role'},
                validateStatus: (_) => true,
              ),
            );
            expect(denied.statusCode, 403);
            expect((await status())['payments'], before['payments']);
          }
        } finally {
          user = admin;
          dio.options.headers['Authorization'] = authorization;
        }
        await assertInvariants();
      },
    );
  } else if (phase == 'lost') {
    testWidgets(
      'committed receive loses its response and persists the original request',
      (tester) async {
        final person = await customer();
        await preferences.setInt('f7-recovery-customer', person.id);
        await preferences.setString(
          'f7-fixture-marker',
          health['marker'] as String,
        );
        await command({
          'action': 'drop',
          'path': '/api/customers/${person.id}/unapplied-cash',
        });
        await mount(tester, person);
        await tap(tester, 'receive');
        await until(
          tester,
          () => find
              .byKey(const Key('cash_receive_amount'))
              .evaluate()
              .isNotEmpty,
        );
        await tester.enterText(
          find.byKey(const Key('cash_receive_amount')),
          '70',
        );
        await tap(tester, 'cash_receive_submit');
        await until(
          tester,
          () => find.textContaining('Retry').evaluate().isNotEmpty,
        );
        final scope = (server: base, userId: user.id);
        final pending = (await CashPendingStore().load(scope))!;
        await CashPendingStore().save(
          scope,
          PendingCashOperation(
            request: pending.request,
            key: pending.key,
            firstDispatchedAt: DateTime.utc(2020),
            replayPolicy: pending.replayPolicy,
          ),
        );
        expect((await command({'action': 'prune'}))['pruned'], greaterThan(0));
        expect(
          (await status())['payments']
              .where((row) => row['customer_id'] == person.id)
              .length,
          1,
        );
        await assertInvariants();
      },
    );
  } else if (phase == 'resume') {
    testWidgets(
      'a new client process resumes after pruning but fails closed without capability',
      (tester) async {
        expect(preferences.getString('f7-fixture-marker'), health['marker']);
        final personId = preferences.getInt('f7-recovery-customer')!;
        final person = Customer.fromJson(
          Map<String, dynamic>.from(
            (await dio.get('/customers/$personId')).data['data'] as Map,
          ),
        );
        final before = await status();
        await command({'action': 'capabilities', 'unsupported': true});
        await mount(tester, person);
        await tap(tester, 'receive');
        await until(tester, () => find.text('Retry').evaluate().isNotEmpty);
        await tap(tester, 'cash_receive_submit');
        await until(
          tester,
          () => find
              .textContaining('No new request has been sent')
              .evaluate()
              .isNotEmpty,
        );
        expect((await status())['writeRequests'], before['writeRequests']);
        await close(tester);
        await command({'action': 'capabilities', 'unsupported': false});
        await tap(tester, 'receive');
        await until(tester, () => find.text('Retry').evaluate().isNotEmpty);
        await tap(tester, 'cash_receive_submit');
        await until(
          tester,
          () => find.textContaining('Advance received').evaluate().isNotEmpty,
        );
        final after = await status();
        final payments = (after['payments'] as List)
            .where((row) => row['customer_id'] == personId)
            .toList();
        expect(payments.length, 1);
        expect(payments.single['amount'], 70);
        expect(
          await CashPendingStore().load((server: base, userId: user.id)),
          isNull,
        );
        await assertInvariants();
      },
    );
  } else {
    throw StateError('Unknown isolated integration phase');
  }
}
