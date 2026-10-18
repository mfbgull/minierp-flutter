import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'package:minierp_app/features/customers/thermal_payment_receipt_pdf.dart';
import 'package:minierp_app/core/utils/formatters.dart';
import 'package:minierp_app/data/models/payment.dart';
import 'package:minierp_app/widgets/payment_receipt_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final kind in ['UNAPPLIED_RECEIPT', 'REFUND']) {
    test(
      '$kind prints its persisted kind and cash direction in both formats',
      () async {
        final payment = Payment(
          id: 4,
          paymentNo: 'F6-$kind',
          customerId: 2,
          customerName:
              'Long customer name for persisted cash document reprints',
          paymentDate: '2026-10-17',
          amount: kind == 'REFUND' ? -50.25 : 100.25,
          paymentMethod: 'Cash',
          paymentKind: kind,
        );
        expect(
          paymentReceiptTitle(payment),
          kind == 'REFUND' ? 'Customer refund' : 'Advance receipt',
        );
        expect(
          paymentReceiptPartyLabel(payment),
          kind == 'REFUND' ? 'Paid To' : 'Received From',
        );
        expect(
          paymentReceiptAmountLabel(payment),
          kind == 'REFUND' ? 'Amount Paid' : 'Amount Received',
        );
        final a4 = await buildPaymentReceiptPdf(payment);
        final thermal = await buildThermalPaymentReceiptPdf(
          payment,
          previousBalance: 999,
          allocations: [
            const PaymentAllocation(invoiceNo: 'MUST-NOT-PRINT', amount: 300),
          ],
        );
        expect(a4, isNotEmpty);
        expect(thermal, isNotEmpty);
        final directory = Platform.environment['F6_PDF_DIR'];
        if (directory != null) {
          await Directory(directory).create(recursive: true);
          await File('$directory/$kind-a4.pdf').writeAsBytes(a4);
          await File('$directory/$kind-thermal.pdf').writeAsBytes(thermal);
        }
      },
    );
  }

  test('formats payment receipt amounts with the configured currency', () {
    expect(formatPaymentReceiptAmount(1234.5), 'Rs. 1,234.50');
    expect(
      formatPaymentReceiptAmount(
        1234.5,
        formatter: const CurrencyFormatter(
          CurrencyConfig(symbol: r'$', code: 'USD'),
        ),
      ),
      r'$ 1,234.50',
    );
  });

  test('payment receipt still builds with a valid payment', () async {
    final bytes = await buildPaymentReceiptPdf(
      const Payment(
        id: 1,
        paymentNo: 'PAY-001',
        customerId: 1,
        customerName: 'Acme Corp',
        paymentDate: '2026-09-24',
        amount: 1234.5,
        paymentMethod: 'Cash',
      ),
    );
    expect(bytes, isNotEmpty);
  });
}
