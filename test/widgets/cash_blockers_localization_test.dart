// UX-6 (audit/GLM-UX-REVIEW.md) — cash-blocker rows interpolate the raw
// journal reference_type and an ISO date straight into the sentence
// (cash_blockers_list.dart: `l10n.refundBlockedRow(blocker.type, blocker.date,
// ...)`), in BOTH languages. The user reads
// "receipt_overpayment · 2026-11-15" instead of a localized label and a
// formatted date.
//
// Pin: the rendered rows must not leak the raw enum or the raw ISO form.
// RED today by design — the fix maps the reference_type through localized
// labels and formats the date (Formatters.date).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/data/repositories/api_result.dart';
import 'package:minierp_app/widgets/cash_blockers_list.dart';

import '../test_helpers.dart';

void main() {
  testWidgets(
    'cash-blocker rows render localized labels and formatted dates, not raw enums or ISO dates',
    (tester) async {
      await tester.pumpWidget(
        buildTestable(
          const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: CashBlockersList(
                blockers: [
                  CashBlocker(
                    id: 1,
                    type: 'receipt_overpayment',
                    date: '2026-11-15',
                    amount: 120.5,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Rows do render (the amount is visible).
      expect(find.textContaining('120'), findsWidgets);

      // Neither the raw reference_type nor the raw ISO date may leak.
      expect(
        find.textContaining('receipt_overpayment'),
        findsNothing,
        reason: 'the journal enum must be mapped to a localized label',
      );
      expect(
        find.textContaining('2026-11-15'),
        findsNothing,
        reason: 'the date must be locale-formatted, not raw ISO',
      );
    },
    // RED-BY-DESIGN — UX-6 (audit/GLM-UX-REVIEW.md): the blocker row still
    // renders the raw reference_type and ISO date. Un-skip when UX-6 is
    // fixed. FAILURE_WHEN_FIXED.
    skip: true,
  );
}
