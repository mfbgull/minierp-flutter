// UX-7 — the Urdu write-off wording must describe an accounting write-off,
// not forgiveness.
//
// A write-off is a deliberate accounting write-down: the uncollected claim
// balance is booked Dr 7300 Refund Write-offs / Cr AP. It is NOT the supplier
// being forgiven, and it is NOT the debt being cancelled. The Urdu UI used
// معاف / معافی ("forgive" / "forgiveness"), which tells an Urdu-reading
// accountant the wrong thing about what the button posts.
//
// Decision (Gull, 2026-11-26): use دستبرد — removal from the books.
//
// This test reads the .arb source of truth, so it catches a regression in the
// translation before gen-l10n regenerates the Dart output.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _arb(String file) {
  final text = File('lib/l10n/$file').readAsStringSync();
  return jsonDecode(text) as Map<String, dynamic>;
}

void main() {
  group('UX-7 Urdu write-off wording', () {
    const writeOffKeys = <String>[
      'refundClaimWriteOff',
      'refundClaimWriteOffTitle',
      'refundClaimWriteOffReasonRequired',
      'refundClaimWriteOffAdminOnly',
    ];

    final ur = _arb('ur.arb');

    test('the Urdu write-off strings never say "forgive"', () {
      for (final key in writeOffKeys) {
        final value = ur[key] as String?;
        expect(value, isNotNull, reason: '$key is missing from ur.arb');
        // معاف / معافی — forgive / forgiveness.
        expect(
          value!.contains('معاف'),
          isFalse,
          reason: '$key still reads as forgiveness: "$value"',
        );
      }
    });

    test('the Urdu write-off strings use the accounting term', () {
      for (final key in writeOffKeys) {
        final value = ur[key] as String?;
        expect(
          value!.contains('دستبرد'),
          isTrue,
          reason: '$key does not use دستبرد: "$value"',
        );
      }
    });

    test('the English write-off strings are unchanged', () {
      final en = _arb('en.arb');
      expect(en['refundClaimWriteOff'], 'Write off');
      expect(en['refundClaimWriteOffTitle'], 'Write off refund claim');
      for (final key in writeOffKeys) {
        expect((en[key] as String).toLowerCase().contains('forgive'), isFalse);
      }
    });
  });
}
