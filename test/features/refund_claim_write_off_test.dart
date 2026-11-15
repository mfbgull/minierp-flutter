// PRET-002 — the refund write-off role gate. A write-off above Rs 1,000
// needs the admin role; at or below it, any user with the permission may
// post. The dialog disables the action and states the rule up front, so the
// user is not surprised by a 403 after typing a reason.
//
// The threshold must stay in step with CLAIM_WRITE_OFF_APPROVAL_THRESHOLD on
// the server (supplierRefundClaimController). A drift here means the dialog
// enables an action the server then refuses.

import 'package:flutter_test/flutter_test.dart';

import 'package:minierp_app/features/purchases/refund_claim_write_off_dialog.dart';

void main() {
  group('writeOffNeedsAdmin', () {
    test('below the threshold: no admin needed', () {
      expect(writeOffNeedsAdmin(999.99, isAdmin: false), isFalse);
    });

    test('exactly at the threshold: no admin needed', () {
      expect(writeOffNeedsAdmin(1000, isAdmin: false), isFalse);
    });

    test('above the threshold: a non-admin is blocked', () {
      expect(writeOffNeedsAdmin(1000.01, isAdmin: false), isTrue);
    });

    test('above the threshold: an admin is allowed', () {
      expect(writeOffNeedsAdmin(5000, isAdmin: true), isFalse);
    });

    test('a large amount is blocked for a non-admin', () {
      expect(writeOffNeedsAdmin(250000, isAdmin: false), isTrue);
    });
  });

  test('threshold matches the server constant', () {
    expect(kClaimWriteOffAdminThreshold, 1000);
  });
}
