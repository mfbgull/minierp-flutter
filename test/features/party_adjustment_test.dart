import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:minierp_app/core/api/api_client.dart';
import 'package:minierp_app/core/theme/app_theme.dart';
import 'package:minierp_app/data/models/party.dart';
import 'package:minierp_app/features/parties/party_adjustment_dialog.dart';
import 'package:minierp_app/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Dio dio;
  late List<RequestOptions> writes;
  var fail = false;
  final position = PartyPosition.fromJson({
    'id': 1, 'display_name': 'Ahmed Traders',
    'customer': {'id': 2, 'code': 'C002', 'name': 'Ahmed Traders', 'is_active': 1},
    'supplier': {'id': 3, 'code': 'S003', 'name': 'Ahmed Traders', 'is_active': 1},
    'customer_balance': 2000, 'supplier_balance': 1000, 'net_balance': 1000,
    'customer_credit': 0, 'supplier_advance': 0,
    'eligible_receivables': 2000, 'eligible_payables': 1000, 'maximum_adjustment': 1000,
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    writes = [];
    fail = false;
    dio = Dio(BaseOptions(baseUrl: 'http://party-test/api'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      if (options.method == 'POST') {
        writes.add(options);
        if (fail) {
          handler.reject(DioException(requestOptions: options,
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(requestOptions: options, statusCode: 409,
              data: {'error': 'Balance changed. Refresh and retry.'})));
          return;
        }
        handler.resolve(Response<dynamic>(requestOptions: options, statusCode: 201,
          data: {'success': true, 'data': {
            'id': 9, 'adjustment_no': 'ADJ-9', 'party_id': 1,
            'customer_id': 2, 'supplier_id': 3, 'adjustment_date': '2026-11-07',
            'amount': 1000, 'status': 'posted', 'receivables': [], 'payables': [],
          }}));
      } else {
        handler.resolve(Response<dynamic>(requestOptions: options, statusCode: 200,
          data: {'success': true, 'data': {
            'receivables': [{'id': 10, 'reference': 'INV-10', 'date': '2026-01-01', 'balance_amount': 2000}],
            'payables': [{'kind': 'purchase', 'id': 20, 'reference': 'PUR-20', 'date': '2026-01-01', 'balance_amount': 1000}],
          }}));
      }
    }));
  });
  Future<void> pump(WidgetTester tester, {String locale = 'en'}) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(overrides: [dioProvider.overrideWithValue(dio)],
      child: MaterialApp(theme: AppTheme.light, locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: PartyAdjustmentDialog(position: position)))));
    await tester.pumpAndSettle();
  }
  Future<void> allocate(WidgetTester tester, String receivable, String payable) async {
    await tester.enterText(find.byKey(const Key('party_amount_invoice_10')), receivable);
    await tester.enterText(find.byKey(const Key('party_amount_purchase_20')), payable);
    await tester.pump();
  }
  testWidgets('posts equal allocations without a cash payment', (tester) async {
    await pump(tester);
    await allocate(tester, '1000', '1000');
    await tester.tap(find.byKey(const Key('party_adjust_submit')));
    await tester.pumpAndSettle();
    expect(writes, hasLength(1));
    expect(writes.single.path, '/parties/1/adjustments');
    expect(writes.single.headers['Idempotency-Key'], isA<String>());
    final body = writes.single.data as Map<String, dynamic>;
    expect(body['amount'], 1000);
    expect(body['receivables'], [{'invoice_id': 10, 'amount': 1000}]);
    expect(body['payables'], [{'kind': 'purchase', 'id': 20, 'amount': 1000}]);
    expect(body.containsKey('payment_method'), isFalse);
  });
  testWidgets('rejects unequal and excessive amounts without posting', (tester) async {
    await pump(tester);
    await allocate(tester, '900', '1000');
    await tester.tap(find.byKey(const Key('party_adjust_submit')));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    await allocate(tester, '1100', '1100');
    await tester.tap(find.byKey(const Key('party_adjust_submit')));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
  });
  testWidgets('retains retry key for unchanged submissions and rotates after editing', (tester) async {
    fail = true;
    await pump(tester);
    await allocate(tester, '1000', '1000');
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const Key('party_adjust_submit')));
      await tester.pumpAndSettle();
    }
    expect(writes, hasLength(2));
    expect(writes[0].headers['Idempotency-Key'], writes[1].headers['Idempotency-Key']);
    await allocate(tester, '900', '900');
    await tester.tap(find.byKey(const Key('party_adjust_submit')));
    await tester.pumpAndSettle();
    expect(writes[2].headers['Idempotency-Key'], isNot(writes[1].headers['Idempotency-Key']));
  });
  testWidgets('supports Urdu allocation fields without layout errors', (tester) async {
    await pump(tester, locale: 'ur');
    await allocate(tester, '1000', '1000');
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('party_adjust_submit')), findsOneWidget);
  });
}
