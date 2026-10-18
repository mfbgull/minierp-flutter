import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:minierp_app/data/models/payment.dart';
import 'package:minierp_app/data/models/unified_payment.dart';
import 'package:minierp_app/features/payments/unified_payment_labels.dart';
import 'package:minierp_app/core/utils/csv_export.dart';
import 'package:minierp_app/l10n/app_localizations_en.dart';

void main() {
  setUpAll(() => initializeDateFormatting());
  final l10n = AppLocalizationsEn();
  Payment payment(String? kind, {num amount = 20, String? voided}) =>
      Payment.fromJson({
        'id': 1,
        'payment_no': 'PAY-1',
        'customer_id': 2,
        'payment_date': '2026-10-17',
        'amount': amount,
        'payment_method': 'Cash',
        'payment_kind': ?kind,
        'voided_at': ?voided,
      });
  UnifiedPayment unified(String? kind, {String direction = 'in'}) =>
      UnifiedPayment.fromJson({
        'source': 'payment',
        'source_id': 1,
        'ref_no': 'PAY-1',
        'date': '2026-10-17',
        'amount': 20,
        'method': 'cash',
        'type': 'customer',
        'direction': direction,
        'party': 'Customer',
        'status': 'posted',
        'payment_kind': ?kind,
      });

  test('legacy missing kind remains an ordinary mutable receipt', () {
    expect(payment(null).canModify, isTrue);
    expect(unified(null).canDeleteGenerically, isTrue);
    expect(paymentKindLabel(l10n, payment(null).paymentKind), 'Receipt');
  });
  test('advance refund unknown and voided documents reject generic writes', () {
    for (final kind in ['UNAPPLIED_RECEIPT', 'REFUND', 'future_kind']) {
      expect(payment(kind).canModify, isFalse);
      expect(unified(kind).canDeleteGenerically, isFalse);
    }
    expect(payment('RECEIPT', voided: '2026-10-17').canModify, isFalse);
  });
  test('refund is outflow and round-trips persisted kind and void state', () {
    final refund = payment('REFUND', amount: -20);
    expect(refund.isCashOutflow, isTrue);
    expect(payment('UNAPPLIED_RECEIPT').isCashOutflow, isFalse);
    expect(Payment.fromJson(refund.toJson()).paymentKind, 'REFUND');
    expect(unified('REFUND', direction: 'out').direction, 'out');
  });
  test('hub and CSV distinguish advances receipts and signed refunds', () {
    expect(
      unifiedPaymentLabel(l10n, unified('UNAPPLIED_RECEIPT')),
      'Advance receipt',
    );
    expect(unifiedPaymentLabel(l10n, unified('RECEIPT')), 'Receipt');
    final csv = buildPaymentsCsv(l10n, [unified('REFUND', direction: 'out')]);
    expect(csv, contains('Customer refund'));
    expect(csv, contains('-Rs. 20.00'));
    expect(csv, contains('Out'));
  });
}
