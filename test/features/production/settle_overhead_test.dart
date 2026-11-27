import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/features/production/settle_overhead_dialog.dart';
import 'package:minierp_app/l10n/app_localizations.dart';
import 'package:minierp_app/widgets/movable_dialog.dart';

import '../../test_helpers.dart';

/// D30 — "Settle overhead" (Gull, 2026-11-27).
///
/// The dialog must send the payment Gull entered to
/// `POST /accounting/overhead/settle` with a mandatory Idempotency-Key, and
/// show what the server did with the split: the accrued part clears 2200,
/// the excess books as an expense (Gull's Q3 answer B).
void main() {
  late Dio dio;
  late List<RequestOptions> posts;
  late Map<String, Object> results;

  setUp(() {
    posts = [];
    results = {};
    dio = Dio(BaseOptions(baseUrl: 'http://settle-test/api'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          posts.add(options);
          // Exact path match, as in the rest of the suite.
          if (options.method != 'POST' ||
              options.path != '/accounting/overhead/settle') {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.badResponse,
                response: Response<dynamic>(
                  requestOptions: options,
                  statusCode: 404,
                  data: {
                    'success': false,
                    'error': {'code': 'NOT_FOUND', 'message': 'Not found'},
                  },
                ),
              ),
            );
            return;
          }
          final key = options.headers['Idempotency-Key'] as String;
          // Same key → same answer, exactly like the server's replay.
          final data = results.putIfAbsent(key, () {
            final body = options.data as Map;
            final amount = (body['amount'] as num).toDouble();
            final accrued = amount > 4000 ? 4000.0 : amount;
            return <String, Object>{
              'id': 11,
              'settlement_no': 'OHS-2611-00001',
              'settlement_date': body['settlement_date'],
              'amount_paid': amount,
              'accrued_amount': accrued,
              'excess_amount': amount - accrued,
              'payment_method': body['payment_method'],
              'reference_note': body['reference_note'] ?? '',
            };
          });
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 201,
              data: {'success': true, 'data': data},
            ),
          );
        },
      ),
    );
  });

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(buildTestable(const _Host(), dio: dio));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('sends the payment with an Idempotency-Key and reports the split',
      (tester) async {
    await openDialog(tester);

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.productionSettleOverheadTitle), findsOneWidget);

    // Gull's real case: 4,000 accrued, the real bill is 5,000.
    await tester.enterText(find.byType(TextFormField).at(0), '5000');
    await tester.pump();
    await tester.tap(
      find.widgetWithText(FilledButton, l10n.productionSettleOverhead),
    );
    await tester.pumpAndSettle();

    expect(posts, hasLength(1));
    final body = posts.single.data as Map;
    expect(body['amount'], 5000);
    expect(body['payment_method'], 'Cash');
    expect(
      (posts.single.headers['Idempotency-Key'] as String).isNotEmpty,
      isTrue,
    );

    // Dialog closes and the toast names both parts of the split:
    // 4,000 cleared the accrued box, 1,000 booked as the expense above it.
    expect(
      find.widgetWithText(MovableDialog, l10n.productionSettleOverheadTitle),
      findsNothing,
    );
    expect(find.textContaining('4,000'), findsOneWidget);
    expect(find.textContaining('1,000'), findsOneWidget);
  });

  testWidgets('refuses a zero amount without calling the server',
      (tester) async {
    await openDialog(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.enterText(find.byType(TextFormField).at(0), '0');
    await tester.pump();
    await tester.tap(
      find.widgetWithText(FilledButton, l10n.productionSettleOverhead),
    );
    await tester.pumpAndSettle();

    expect(posts, isEmpty);
    expect(find.text(l10n.productionSettleOverheadError), findsOneWidget);
  });
}

/// Minimal host: a button that opens the dialog, so the test drives the
/// same entry point the toolbar uses.
class _Host extends StatelessWidget {
  const _Host();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () => SettleOverheadDialog.show(context),
          child: const Text('Open'),
        ),
      ),
    ),
  );
}
