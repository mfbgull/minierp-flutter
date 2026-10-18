import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:minierp_app/core/api/api_client.dart';
import 'package:minierp_app/core/auth/auth_notifier.dart';
import 'package:minierp_app/core/theme/app_theme.dart';
import 'package:minierp_app/data/models/auth_user.dart';
import 'package:minierp_app/data/models/payment.dart';
import 'package:minierp_app/data/models/customer.dart';
import 'package:minierp_app/features/customers/customer_unapplied_cash_tab.dart';
import 'package:minierp_app/data/repositories/auth_repository.dart';
import 'package:minierp_app/data/repositories/repository_client.dart';
import 'package:minierp_app/features/payments/payment_detail_dialog.dart';
import 'package:minierp_app/features/payments/edit_payment_dialog.dart';
import 'package:minierp_app/features/payments/payments_screen.dart';
import 'package:minierp_app/features/customers/customer_payments_tab.dart';
import 'package:minierp_app/l10n/app_localizations.dart';
import '../../test_helpers.dart';

class SurfaceAuth extends AuthNotifier {
  SurfaceAuth(Dio dio, AuthUser user)
    : super(AuthRepository(RepositoryClient(dio)), FakeTokenStorage()) {
    state = AuthState(status: AuthStatus.authenticated, user: user);
  }
  @override
  Future<void> restoreSession() async {}
}

void main() {
  late Dio dio;
  late List<RequestOptions> writes;
  late String kind;
  late List<String> kinds;
  late AuthUser user;
  late bool includeCashReceipt;
  Map<String, dynamic> paymentJson(int id, String kind) => {
    'id': id,
    'payment_no': 'PAY-$id',
    'customer_id': 2,
    'customer_name': 'A long customer name for cash document history',
    'payment_date': '2026-10-17',
    'amount': kind == 'REFUND' ? -20 : 20,
    'payment_method': 'Cash',
    'payment_kind': kind,
  };
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    includeCashReceipt = false;
    writes = [];
    kind = 'REFUND';
    kinds = ['UNAPPLIED_RECEIPT', 'REFUND'];
    user = const AuthUser(id: 1, username: 'admin', role: 'admin');
    dio = Dio(BaseOptions(baseUrl: 'http://surface-test/api'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          if (request.method != 'GET') writes.add(request);
          Object data;
          if (request.path == '/customers/2/unapplied-cash') {
            data = {
              'success': true,
              'data': {
                'customer_id': 2,
                'operation_date': '2026-10-17',
                'remaining_amount': 15,
                'available_amount': 15,
                'refundable_amount': 15,
                'receipts': includeCashReceipt
                    ? [
                        {
                          'source_id': 1,
                          'payment_id': 1,
                          'payment_no': 'PAY-1',
                          'payment_date': '2026-10-17',
                          'payment_method': 'Cash',
                          'original_amount': 20,
                          'applied_amount': 0,
                          'refunded_amount': 0,
                          'remaining_amount': 20,
                          'voided_at': null,
                          'can_reverse': true,
                        },
                      ]
                    : [],
              },
              'pagination': {
                'currentPage': 1,
                'totalPages': 1,
                'totalItems': 0,
              },
            };
          } else if (request.path == '/customers/2/unapplied-cash/activity') {
            data = {
              'success': true,
              'data': [
                {
                  'application_id': 1,
                  'operation': 'APPLY',
                  'operation_date': '2026-10-17',
                  'total_amount': 10,
                  'payment_id': null,
                  'lines': [
                    {
                      'source_id': 1,
                      'invoice_id': 42,
                      'invoice_no': 'INV-F6-42',
                      'amount': 10,
                      'kind': 'APPLY',
                    },
                  ],
                },
              ],
              'pagination': {
                'currentPage': 1,
                'totalPages': 1,
                'totalItems': 1,
              },
            };
          } else if (request.path == '/payments/1') {
            data = {'success': true, 'data': paymentJson(1, kind)};
          } else {
            final unified = request.path == '/payments/unified';
            data = {
              'success': true,
              'data': [
                for (var index = 0; index < kinds.length; index++)
                  unified
                      ? {
                          'source': 'payment',
                          'source_id': index + 1,
                          'ref_no': 'PAY-${index + 1}',
                          'date': '2026-10-17',
                          'amount': 20,
                          'method': 'cash',
                          'type': 'customer',
                          'direction': kinds[index] == 'REFUND' ? 'out' : 'in',
                          'party': 'Customer',
                          'status': 'posted',
                          'payment_kind': kinds[index],
                        }
                      : paymentJson(index + 1, kinds[index]),
              ],
              'pagination': {
                'currentPage': 1,
                'totalPages': 1,
                'totalItems': kinds.length,
                'hasNext': false,
                'hasPrev': false,
              },
            };
          }
          handler.resolve(
            Response(requestOptions: request, statusCode: 200, data: data),
          );
        },
      ),
    );
  });

  Future<void> pump(
    WidgetTester tester, {
    String surface = 'detail',
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
          authProvider.overrideWith((ref) => SurfaceAuth(dio, user)),
        ],
        child: MaterialApp(
          theme: urdu ? AppTheme.dark : AppTheme.light,
          locale: Locale(urdu ? 'ur' : 'en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: surface == 'hub'
                ? const PaymentsScreen()
                : surface == 'history'
                ? const CustomerPaymentsTab(customerId: 2, sessionId: 3)
                : surface == 'cash'
                ? const CustomerUnappliedCashTab(
                    customer: Customer(
                      id: 2,
                      customerCode: 'C2',
                      customerName: 'Cash customer',
                      currentBalance: 0,
                    ),
                    sessionId: 3,
                  )
                : Builder(
                    builder: (context) => TextButton(
                      onPressed: () => surface == 'edit'
                          ? showPaymentEditDialog(
                              context,
                              payment: Payment.fromJson(paymentJson(1, kind)),
                            )
                          : showPaymentDetailDialog(context, paymentId: 1),
                      child: const Text('Open'),
                    ),
                  ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (surface == 'detail' || surface == 'edit') {
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }
  }

  for (final value in ['UNAPPLIED_RECEIPT', 'REFUND']) {
    testWidgets(
      '$value detail is read-only and displays correct cash direction',
      (tester) async {
        kind = value;
        await pump(tester);
        expect(
          find.text(value == 'REFUND' ? 'Customer refund' : 'Advance receipt'),
          findsOneWidget,
        );
        expect(find.text(value == 'REFUND' ? 'Out' : 'In'), findsOneWidget);
        expect(find.widgetWithText(TextButton, 'Delete'), findsNothing);
        expect(find.text('Edit Payment'), findsNothing);
        expect(find.textContaining('read-only here'), findsOneWidget);
        expect(find.byIcon(Icons.print_outlined), findsOneWidget);
        expect(writes, isEmpty);
      },
    );
    testWidgets('$value cannot open direct generic editor', (tester) async {
      kind = value;
      await pump(tester, surface: 'edit');
      expect(find.byType(TextFormField), findsNothing);
      expect(find.textContaining('read-only here'), findsOneWidget);
      expect(writes, isEmpty);
    });
  }
  testWidgets('ordinary receipt retains permitted edit and delete', (
    tester,
  ) async {
    kind = 'RECEIPT';
    await pump(tester);
    expect(find.widgetWithText(TextButton, 'Delete'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
  });
  for (final narrow in [false, true]) {
    testWidgets(
      'cash activity links invoices without creating a receipt narrow=$narrow',
      (tester) async {
        await pump(tester, surface: 'cash', narrow: narrow);
        await tester.tap(find.text('Applications & refunds'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(TextButton, 'INV-F6-42'), findsOneWidget);
        expect(find.textContaining('Rs. 10.00'), findsWidgets);
        expect(writes, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('cash receipt method is localized in Urdu', (tester) async {
    includeCashReceipt = true;
    await pump(tester, surface: 'cash', narrow: true, urdu: true);
    final urdu = await AppLocalizations.delegate.load(const Locale('ur'));
    final receiptsChip = find.text(urdu.cashReceipts);
    await tester.ensureVisible(receiptsChip);
    await tester.tap(receiptsChip);
    await tester.pumpAndSettle();
    final cashMethod = find.textContaining(urdu.paymentsMethodCash).first;
    await tester.ensureVisible(cashMethod);
    expect(
      find.text('${urdu.customersMethod}: ${urdu.paymentsMethodCash}'),
      findsOneWidget,
    );
  });
  testWidgets('compact reverse action has a localized accessibility tooltip', (
    tester,
  ) async {
    includeCashReceipt = true;
    await pump(tester, surface: 'cash', urdu: true);
    final urdu = await AppLocalizations.delegate.load(const Locale('ur'));
    final receiptsChip = find.text(urdu.cashReceipts);
    await tester.ensureVisible(receiptsChip);
    await tester.tap(receiptsChip);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('cash_reverse_1')))
          .tooltip,
      urdu.cashReverse,
    );
  });
  testWidgets('read-only user cannot edit or delete ordinary receipts', (
    tester,
  ) async {
    kind = 'RECEIPT';
    user = const AuthUser(
      id: 2,
      username: 'reader',
      permissions: [Permission(module: 'payments', action: 'read')],
    );
    await pump(tester);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
    expect(writes, isEmpty);
  });
  testWidgets('narrow Urdu dark refund detail wraps footer and scrolls', (
    tester,
  ) async {
    await pump(tester, narrow: true, urdu: true);
    expect(find.text('گاہک کو نقد واپسی'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.print_outlined), findsOneWidget);
  });
  testWidgets(
    'hub labels kinds and disables bulk delete for only cash documents',
    (tester) async {
      await pump(tester, surface: 'hub');
      expect(find.text('Advance receipt'), findsOneWidget);
      expect(find.text('Customer refund'), findsOneWidget);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Delete selected'),
      );
      expect(button.onPressed, isNull);
      expect(writes, isEmpty);
    },
  );
  testWidgets('customer history menu excludes edit/delete for advances', (
    tester,
  ) async {
    await pump(tester, surface: 'history');
    expect(find.text('Advance receipt'), findsOneWidget);
    expect(find.text('Customer refund'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    expect(find.text('Print Receipt'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete Payment'), findsNothing);
    expect(writes, isEmpty);
  });
  testWidgets(
    'hub kind labels update when locale changes on the mounted page',
    (tester) async {
      await pump(tester, surface: 'hub');
      expect(find.text('Customer refund'), findsOneWidget);
      await pump(tester, surface: 'hub', urdu: true);
      expect(find.text('گاہک کو نقد واپسی'), findsOneWidget);
      expect(find.text('Customer refund'), findsNothing);
    },
  );
  testWidgets(
    'mixed bulk selection dispatches only the ordinary receipt delete',
    (tester) async {
      kinds = ['RECEIPT', 'UNAPPLIED_RECEIPT', 'REFUND'];
      await pump(tester, surface: 'hub');
      for (var index = 0; index < 3; index++) {
        await tester.tap(find.byType(Checkbox).at(index));
        await tester.pump(const Duration(milliseconds: 350));
      }
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete selected'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'DELETE');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(writes.map((request) => '${request.method} ${request.path}'), [
        'DELETE /payments/1',
      ]);
      expect(find.textContaining('cannot be deleted here'), findsWidgets);
    },
  );
}
