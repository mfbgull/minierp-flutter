// Customer store-credit UI (task 41) — the payment panel half of the
// credit flow: the three required figures (available / used / remaining),
// partial application of a credit pool, and the disabled state while a
// payment is being saved.
//
// The ceiling rules themselves live in `clampCreditOffset` and are covered
// in test/calculations/invoice_calculations_test.dart; this file covers the
// panel surface and what it emits to the page.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/features/sales/payment_panel.dart';
import 'package:minierp_app/l10n/app_localizations.dart';

/// The credit-offset amount field, located by its decoration label so the
/// payment-method amount rows and the notes field are never matched.
final Finder _creditField = find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == 'Credit Offset',
  description: 'credit-offset TextField',
);

Widget _panel({
  num total = 1000,
  num paidAmount = 0,
  num balance = 1000,
  bool saving = false,
  num creditOffset = 0,
  num availableCredit = 0,
  ValueChanged<num>? onCreditOffsetChanged,
}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: SingleChildScrollView(
      child: PaymentPanel(
        isEdit: true, // _showForm gate — the credit UI lives in the form
        recordPayment: false,
        paymentDate: DateTime(2026, 1, 15),
        methods: const [],
        existingPayments: const [],
        deletedPayments: const {},
        total: total,
        paidAmount: paidAmount,
        balance: balance,
        saving: saving,
        onRecordChanged: (_) {},
        onPickPaymentDate: () {},
        onPaymentNotesChanged: (_) {},
        onAddMethod: () {},
        onRemoveMethod: (_) {},
        onUpdateMethod: (_, _, _) {},
        onRecord: () {},
        onDeletePayment: (_) {},
        onEditPayment: (_) {},
        creditOffset: creditOffset,
        availableCredit: availableCredit,
        onCreditOffsetChanged: onCreditOffsetChanged ?? (_) {},
      ),
    ),
  ),
);

void main() {
  group('display', () {
    testWidgets('shows available, used and remaining when credit exists', (
      tester,
    ) async {
      await tester.pumpWidget(
        _panel(availableCredit: 250, creditOffset: 50),
      );

      expect(find.text('Available credit'), findsOneWidget);
      expect(find.text('Credit remaining'), findsOneWidget);
      // 'Credit Offset' labels both the summary row and the amount field.
      expect(find.text('Credit Offset'), findsNWidgets(2));
      expect(_creditField, findsOneWidget);
    });

    testWidgets('hides the whole credit block when there is no credit', (
      tester,
    ) async {
      await tester.pumpWidget(_panel(availableCredit: 0, creditOffset: 0));

      expect(find.text('Available credit'), findsNothing);
      expect(find.text('Credit remaining'), findsNothing);
      expect(_creditField, findsNothing);
    });

    testWidgets('shows zero credit used and full remaining before use', (
      tester,
    ) async {
      await tester.pumpWidget(_panel(availableCredit: 250, creditOffset: 0));

      expect(find.text('Available credit'), findsOneWidget);
      // Credit Offset = the "used" summary row + the amount field's label.
      expect(find.text('Credit Offset'), findsNWidgets(2));
      expect(find.text('Credit remaining'), findsOneWidget);
      expect(_creditField, findsOneWidget);
    });
  });

  group('partial use', () {
    testWidgets('emits a part-applied amount rather than the whole pool', (
      tester,
    ) async {
      final emitted = <num>[];
      await tester.pumpWidget(
        _panel(availableCredit: 250, onCreditOffsetChanged: emitted.add),
      );

      await tester.enterText(_creditField, '75');
      await tester.pump();

      expect(emitted, <num>[75]);
    });

    testWidgets('a partial entry is not inflated to the full balance', (
      tester,
    ) async {
      final emitted = <num>[];
      await tester.pumpWidget(
        _panel(availableCredit: 250, onCreditOffsetChanged: emitted.add),
      );

      // Typing one digit at a time must not round-trip through a
      // toStringAsFixed() sync mid-keystroke.
      await tester.enterText(_creditField, '1');
      await tester.pump();
      await tester.enterText(_creditField, '10');
      await tester.pump();
      await tester.enterText(_creditField, '100');
      await tester.pump();

      expect(emitted.last, 100);
    });
  });

  group('full use', () {
    testWidgets('emits the full pool when the whole amount is typed', (
      tester,
    ) async {
      final emitted = <num>[];
      await tester.pumpWidget(
        _panel(availableCredit: 250, onCreditOffsetChanged: emitted.add),
      );

      await tester.enterText(_creditField, '250');
      await tester.pump();

      expect(emitted.last, 250);
    });

    testWidgets('reflects an externally applied full offset in the field', (
      tester,
    ) async {
      await tester.pumpWidget(
        _panel(availableCredit: 250, creditOffset: 250),
      );

      expect(find.text('250.00'), findsOneWidget);
    });
  });

  group('insufficient credit', () {
    testWidgets('cap hint shows the pool ceiling next to the field', (
      tester,
    ) async {
      await tester.pumpWidget(_panel(availableCredit: 250));

      // The field itself does not silently clamp; it advertises the
      // ceiling and the page clamps via clampCreditOffset.
      expect(find.textContaining('250'), findsWidgets);
    });
  });

  group('error handling', () {
    testWidgets('field is disabled while the payment is being saved', (
      tester,
    ) async {
      await tester.pumpWidget(
        _panel(availableCredit: 250, saving: true),
      );

      final field = tester.widget<TextField>(_creditField);
      expect(field.enabled, isFalse);
    });

    testWidgets('non-numeric input emits 0 instead of crashing', (
      tester,
    ) async {
      final emitted = <num>[];
      await tester.pumpWidget(
        _panel(availableCredit: 250, onCreditOffsetChanged: emitted.add),
      );

      await tester.enterText(_creditField, 'abc');
      await tester.pump();

      expect(emitted, <num>[0]);
    });

    testWidgets('clearing the field removes the applied credit', (
      tester,
    ) async {
      final emitted = <num>[];
      await tester.pumpWidget(
        _panel(availableCredit: 250, onCreditOffsetChanged: emitted.add),
      );

      await tester.enterText(_creditField, '75');
      await tester.pump();
      await tester.enterText(_creditField, '');
      await tester.pump();

      expect(emitted.last, 0);
    });
  });
}
