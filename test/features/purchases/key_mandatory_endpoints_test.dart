// Every key-mandatory endpoint reached from the UI must carry an
// Idempotency-Key on the ACTUAL request. Reading the repository is not proof:
// a dialog can call a method that forgets the header, and nothing fails until
// a user hits the route and gets a 400.
//
// This spec drives each dialog through the real widget tree, intercepts the
// RequestOptions, and asserts on the wire. It exists because
// `writeOffClaim` and `voidRefund` shipped without the header while their
// neighbours in the same repository file had it — a gap only a wire-level
// test catches.
//
// The list is the client side of the server's
// `startRequiredIdempotentRequest` call sites. When one is added server-side,
// add its dialog here.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/data/repositories/purchase_repository.dart';
import 'package:minierp_app/features/purchases/refund_claim_write_off_dialog.dart';
import 'package:minierp_app/features/purchases/void_refund_dialog.dart';

import '../../test_helpers.dart';

/// One UI path to one key-mandatory endpoint.
class _Case {
  const _Case({
    required this.name,
    required this.method,
    required this.path,
    required this.open,
  });

  final String name;

  /// The HTTP method the endpoint is reachable through.
  final String method;

  /// The request path, as Dio records it (relative to the api base URL).
  final String path;

  /// A builder that renders a button which opens the dialog under test.
  final Widget Function() open;
}

final _cases = <_Case>[
  _Case(
    name: 'refund claim write-off',
    method: 'POST',
    path: '/supplier-refunds/claims/7/write-off',
    open: () => Builder(
      builder: (context) => TextButton(
        onPressed: () => showRefundClaimWriteOffDialog(
          context,
          claim: const RefundClaim(
            id: 7,
            claimNo: 'RC-1',
            supplierId: 1,
            supplierName: 'Vendor',
            claimDate: '2026-09-01',
            amount: 200,
            receivedAmount: 0,
            writtenOffAmount: 0,
            remaining: 200,
            status: 'EXPECTED',
          ),
          isAdmin: true,
        ),
        child: const Text('Open'),
      ),
    ),
  ),
  _Case(
    name: 'refund receipt void',
    method: 'POST',
    path: '/supplier-refunds/7/void',
    open: () => Builder(
      builder: (context) => TextButton(
        onPressed: () => showVoidRefundDialog(
          context,
          refundId: 7,
          label: 'REF-1',
        ),
        child: const Text('Open'),
      ),
    ),
  ),
];

void main() {
  for (final testCase in _cases) {
    testWidgets(
      '${testCase.name} sends an Idempotency-Key, stable on retry and '
      'rotated when the reason changes',
      (tester) async {
        final requests = <RequestOptions>[];
        final dio = createFakeDio({});
        dio.interceptors.insert(
          0,
          InterceptorsWrapper(
            onRequest: (options, handler) {
              if (options.method == 'POST') {
                requests.add(options);
              }
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.receiveTimeout,
                ),
              );
            },
          ),
        );

        await tester.pumpWidget(buildTestable(Scaffold(body: testCase.open()), dio: dio));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        final reason = find.byType(TextField).first;
        final submit = find
            .byWidgetPredicate((widget) => widget is FilledButton)
            .last;

        // A retry of the same reason must replay the same key.
        await tester.enterText(reason, 'short paid');
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pumpAndSettle();
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pumpAndSettle();

        // An edited reason is a different operation and must mint a new key.
        await tester.enterText(reason, 'short paid, corrected');
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pumpAndSettle();

        expect(requests, isNotEmpty, reason: '${testCase.name} sent no request');
        for (final request in requests) {
          expect(request.method, testCase.method);
          expect(request.path, testCase.path);
        }

        final keys = requests
            .map((request) => request.headers['Idempotency-Key'])
            .toList();
        expect(
          keys.first,
          isA<String>().having(
            (value) => value.length,
            'length',
            greaterThanOrEqualTo(8),
          ),
          reason: '${testCase.name} sent no Idempotency-Key header',
        );
        expect(keys, hasLength(3));
        expect(keys[1], keys[0], reason: 'a retry must replay the same key');
        expect(keys[2], isNot(keys[0]),
            reason: 'an edited reason must rotate the key');
      },
    );
  }
}
