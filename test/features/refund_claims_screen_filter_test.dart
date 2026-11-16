// UX-1 (audit/GLM-UX-REVIEW.md) — the "Open only" filter on the claims
// screen used to send `status: null` in BOTH chip states
// (refund_claims_screen.dart: `status: _openOnly ? null : null`), so the
// toggle never reached the server and open claims on later pages looked
// like they did not exist.
//
// Pin: with "Open only" selected the claims request carries the open
// statuses; toggled off it carries no status filter at all. The server
// (SupplierRefundClaimModel.list) accepts a comma-separated status list
// and returns EVERY claim when no status is sent.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/features/purchases/refund_claims_screen.dart';

import '../test_helpers.dart';

void main() {
  testWidgets(
    '"Open only" sends the open-status filter to the claims endpoint and toggling it off removes the filter',
    (tester) async {
      final claimGets = <RequestOptions>[];
      final dio = createFakeDio({
        '/supplier-refunds/claims': pagedEnvelope([
          {
            'id': 1,
            'claim_no': 'SRC-1',
            'supplier_id': 7,
            'supplier_name': 'Test supplier',
            'claim_date': '2026-11-01',
            'amount': 100,
            'received_amount': 0,
            'written_off_amount': 0,
            'status': 'EXPECTED',
          },
          {
            'id': 2,
            'claim_no': 'SRC-2',
            'supplier_id': 7,
            'supplier_name': 'Test supplier',
            'claim_date': '2026-11-02',
            'amount': 100,
            'received_amount': 100,
            'written_off_amount': 0,
            'status': 'RECEIVED',
          },
        ]),
        '/supplier-refunds/claims/due': {
          'success': true,
          'data': <Object?>[],
          'total_due': 100,
        },
      });
      dio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (options, handler) {
            // Exact match: excludes the /claims/due memo fetch.
            if (options.method == 'GET' &&
                options.uri.path.endsWith(
                  '/supplier-refunds/claims',
                )) {
              claimGets.add(options);
            }
            handler.next(options);
          },
        ),
      );

      await tester.pumpWidget(
        buildTestable(const Scaffold(body: RefundClaimsScreen()), dio: dio),
      );
      await tester.pumpAndSettle();

      expect(claimGets, hasLength(1));
      expect(
        claimGets.single.queryParameters['status'],
        'EXPECTED,PARTIAL',
        reason: 'open-only must filter server-side, not page-side',
      );

      // Toggle off: every claim, no status filter.
      await tester.tap(find.text('Open only'));
      await tester.pumpAndSettle();

      expect(claimGets, hasLength(2));
      expect(
        claimGets.last.queryParameters['status'],
        isNull,
        reason: 'with the chip off, the server must return every claim',
      );
    },
  );
}
