// PRET-002 — refund claim list models and the refunds-due memo.
//
// These pin the client-side parse of `GET /supplier-refunds/claims` rows and
// `GET /supplier-refunds/claims/due`, plus the `isOpen` rule the list screen
// filters on. `remaining` is computed (amount − received − written off)
// rather than read, so a server field rename cannot silently zero it.

import 'package:flutter_test/flutter_test.dart';

import 'package:minierp_app/data/repositories/purchase_repository.dart'
    show RefundClaim, RefundsDue;

Map<String, dynamic> _row({
  Object? amount = 1000,
  Object? received = 0,
  Object? writtenOff = 0,
  String status = 'EXPECTED',
}) => {
  'id': 7,
  'claim_no': 'RFC-0007',
  'supplier_id': 3,
  'supplier_name': 'Acme Traders',
  'claim_date': '2026-11-01',
  'amount': amount,
  'received_amount': received,
  'written_off_amount': writtenOff,
  'status': status,
  'return_no': 'PR-0012',
  'credit_no': 'CN-0009',
};

void main() {
  group('RefundClaim.fromJson', () {
    test('reads the joined columns', () {
      final claim = RefundClaim.fromJson(_row());
      expect(claim.id, 7);
      expect(claim.claimNo, 'RFC-0007');
      expect(claim.supplierId, 3);
      expect(claim.supplierName, 'Acme Traders');
      expect(claim.claimDate, '2026-11-01');
      expect(claim.returnNo, 'PR-0012');
      expect(claim.creditNo, 'CN-0009');
    });

    test('remaining is amount minus received minus written off', () {
      final claim = RefundClaim.fromJson(
        _row(amount: 1000, received: 400, writtenOff: 100),
      );
      expect(claim.remaining, 500);
      expect(claim.receivedAmount, 400);
      expect(claim.writtenOffAmount, 100);
    });

    test('a standalone claim has null return/credit numbers', () {
      final json = _row()..remove('return_no')..remove('credit_no');
      final claim = RefundClaim.fromJson(json);
      expect(claim.returnNo, isNull);
      expect(claim.creditNo, isNull);
    });

    test('missing amounts default to zero, so remaining stays numeric', () {
      final json = _row()..remove('received_amount')..remove('written_off_amount');
      final claim = RefundClaim.fromJson(json);
      expect(claim.receivedAmount, 0);
      expect(claim.writtenOffAmount, 0);
      expect(claim.remaining, 1000);
    });
  });

  group('RefundClaim.isOpen', () {
    test('EXPECTED and PARTIAL are open', () {
      expect(RefundClaim.fromJson(_row(status: 'EXPECTED')).isOpen, isTrue);
      expect(RefundClaim.fromJson(_row(status: 'PARTIAL')).isOpen, isTrue);
    });

    test('RECEIVED and CANCELLED are closed', () {
      expect(RefundClaim.fromJson(_row(status: 'RECEIVED')).isOpen, isFalse);
      expect(RefundClaim.fromJson(_row(status: 'CANCELLED')).isOpen, isFalse);
    });

    test('an unknown status is not open', () {
      expect(RefundClaim.fromJson(_row(status: 'SOMETHING')).isOpen, isFalse);
    });
  });

  group('RefundsDue.fromJson', () {
    test('parses rows and the total-due memo figure', () {
      final due = RefundsDue.fromJson({
        'data': [_row(amount: 500, received: 100)],
        'total_due': 400,
      });
      expect(due.rows, hasLength(1));
      expect(due.rows.single.remaining, 400);
      expect(due.totalDue, 400);
    });

    test('an empty memo is zero, not null', () {
      final due = RefundsDue.fromJson({'data': <dynamic>[], 'total_due': 0});
      expect(due.rows, isEmpty);
      expect(due.totalDue, 0);
    });

    test('a missing row list parses as empty', () {
      final due = RefundsDue.fromJson({'total_due': 0});
      expect(due.rows, isEmpty);
    });
  });
}
