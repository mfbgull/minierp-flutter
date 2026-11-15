// ACCT-013 / PRET-002 — the cash guard's 409 carries a per-line blocker list
// under `details`. The client used to read only `error.blockedBy` (the
// unapplied-cash shape), so a rejected receipt void showed a message and threw
// the list away. These tests pin the new `cashBlockers` field and, just as
// importantly, pin that `blockedBy` behaviour did not change.

import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/data/repositories/api_result.dart';

ApiError _parse(Object body) => ApiError.fromResponse(
  message: 'blocked',
  statusCode: 409,
  body: body,
);

void main() {
  group('cashBlockers — cash-guard 409 details', () {
    test('parses a well-formed details list', () {
      final error = _parse({
        'error': 'Insufficient funds in Cash on 2026-08-05: balance would be -50.00.',
        'details': [
          {'id': 7, 'date': '2026-08-05', 'amount': 120.5, 'type': 'EXPENSE'},
          {'id': 9, 'date': '2026-08-05', 'amount': 30.0, 'type': 'SUPPLIER_REFUND'},
        ],
      });

      expect(error.statusCode, 409);
      expect(error.cashBlockers, hasLength(2));
      expect(error.cashBlockers.first.id, 7);
      expect(error.cashBlockers.first.date, '2026-08-05');
      expect(error.cashBlockers.first.amount, 120.5);
      expect(error.cashBlockers.first.type, 'EXPENSE');
      expect(error.cashBlockers.last.type, 'SUPPLIER_REFUND');
    });

    test('a 409 with no details yields an empty list, not a throw', () {
      final error = _parse({'error': 'Insufficient funds'});
      expect(error.cashBlockers, isEmpty);
    });

    test('malformed rows are skipped rather than throwing', () {
      final error = _parse({
        'error': 'Insufficient funds',
        'details': [
          {'id': 7, 'date': '2026-08-05', 'amount': 10.0, 'type': 'EXPENSE'},
          {'id': 'seven', 'date': '2026-08-05', 'amount': 10.0, 'type': 'X'},
          {'id': 8, 'date': '2026-08-05', 'amount': 'ten', 'type': 'X'},
          {'id': 9},
          'not a map',
          null,
        ],
      });

      expect(error.cashBlockers, hasLength(1));
      expect(error.cashBlockers.single.id, 7);
    });

    test('a non-list details value yields an empty list', () {
      expect(_parse({'error': 'x', 'details': 'nope'}).cashBlockers, isEmpty);
      expect(_parse({'error': 'x', 'details': 42}).cashBlockers, isEmpty);
    });
  });

  group('blockedBy is unchanged', () {
    test('the unapplied-cash shape still parses', () {
      final error = _parse({
        'error': {
          'code': 'UNAPPLIED_ALREADY_APPLIED',
          'message': 'Receipt used',
          'blockedBy': [
            {'sourceId': 1, 'consumed': 40, 'invoices': [9]},
          ],
        },
      });

      expect(error.code, 'UNAPPLIED_ALREADY_APPLIED');
      expect(error.blockedBy.single.sourceId, 1);
      expect(error.blockedBy.single.consumed, 40);
      expect(error.blockedBy.single.invoices, [9]);
      // The two shapes are separate fields; a cash-guard body must not bleed
      // into blockedBy.
      expect(error.cashBlockers, isEmpty);
    });

    test('a cash-guard body leaves blockedBy empty', () {
      final error = _parse({
        'error': 'Insufficient funds',
        'details': [
          {'id': 7, 'date': '2026-08-05', 'amount': 120.5, 'type': 'EXPENSE'},
        ],
      });

      expect(error.blockedBy, isEmpty);
    });
  });
}
