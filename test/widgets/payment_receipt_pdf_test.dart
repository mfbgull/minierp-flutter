import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/core/utils/formatters.dart';
import 'package:minierp_app/data/models/payment.dart';
import 'package:minierp_app/widgets/payment_receipt_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
