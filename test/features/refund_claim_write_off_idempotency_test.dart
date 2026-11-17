// UX-2 (audit/GLM-UX-REVIEW.md) — the write-off route
// (POST /supplier-refunds/claims/:id/write-off) mandates an Idempotency-Key
// (supplierRefundClaimController.ts: startRequiredIdempotentRequest, scope
// SUPPLIER_REFUND_CLAIM_WRITE_OFF), but the dialog/repo sent none, so every
// write-off from the UI failed with 400.
//
// This test pins the contract: the first submit carries a key, an unchanged
// retry replays with the same key, and editing the amount rotates it (a
// different amount is a different operation, not a retry).

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/data/repositories/purchase_repository.dart';
import 'package:minierp_app/features/purchases/refund_claim_write_off_dialog.dart';

import '../test_helpers.dart';

void main() {
  testWidgets(
    'write-off carries an Idempotency-Key, keeps it on retry, rotates it when the amount is edited',
    (tester) async {
      final requests = <RequestOptions>[];
      final dio = createFakeDio({});
      dio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.method == 'POST') {
              requests.add(options);
              // Simulate a lost response after the server may have committed:
              // the dialog stays open, the user retries.
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.receiveTimeout,
                ),
              );
            } else {
              handler.next(options);
            }
          },
        ),
      );

      const claim = RefundClaim(
        id: 1,
        claimNo: 'SRC-1',
        supplierId: 7,
        supplierName: 'Test supplier',
        claimDate: '2026-11-01',
        amount: 5000,
        receivedAmount: 0,
        writtenOffAmount: 0,
        remaining: 5000,
        status: 'PARTIAL',
      );

      await tester.pumpWidget(
        buildTestable(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showRefundClaimWriteOffDialog(
                  context,
                  claim: claim,
                  isAdmin: true,
                ),
                child: const Text('Open write-off'),
              ),
            ),
          ),
          dio: dio,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open write-off'));
      await tester.pumpAndSettle();

      Future<void> submit() async {
        final submitButton = find
            .byWidgetPredicate((widget) => widget is FilledButton)
            .last;
        await tester.ensureVisible(submitButton);
        await tester.tap(submitButton);
        await tester.pumpAndSettle();
      }

      // First field is the amount (prefilled with the remaining balance),
      // the last is the mandatory reason.
      await tester.enterText(find.byType(TextField).first, '2000');
      await tester.enterText(find.byType(TextField).last, 'Damaged goods');
      await submit();

      // Unchanged retry: same body, must replay with the same key.
      await tester.enterText(find.byType(TextField).first, '2000');
      await tester.enterText(find.byType(TextField).last, 'Damaged goods');
      await submit();

      // Edited amount: a different operation, so the key must rotate.
      await tester.enterText(find.byType(TextField).first, '3000');
      await tester.enterText(find.byType(TextField).last, 'Damaged goods');
      await submit();

      expect(requests, hasLength(3));
      for (final request in requests) {
        expect(request.path, '/supplier-refunds/claims/1/write-off');
      }
      expect(requests[0].data['reason'], 'Damaged goods');
      expect(requests[0].data['amount'], 2000);
      expect(requests[0].data['write_off_date'], isA<String>());

      final keys = requests
          .map((r) => r.headers['Idempotency-Key'])
          .toList();
      expect(
        keys[0],
        isA<String>().having(
          (value) => value.length,
          'length',
          greaterThanOrEqualTo(8),
        ),
        reason: 'the write-off endpoint mandates an Idempotency-Key',
      );
      expect(keys[1], keys[0], reason: 'an unchanged retry replays');
      expect(
        keys[2],
        isNot(keys[0]),
        reason: 'an edited amount is a new operation, not a retry',
      );
      expect(requests[2].data['amount'], 3000);
    },
  );
}
