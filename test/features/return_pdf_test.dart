// Smoke test for the M5 print artifacts (spec §6.3): the A4 invoice PDF
// must embed the seven-section return story when returns exist and still
// render for a legacy invoice with no `invoice_returns` rows, and the
// standalone Return Receipt must build for one return.
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:minierp_app/data/models/invoice.dart';
import 'package:minierp_app/data/models/sales_return.dart';
import 'package:minierp_app/features/sales/invoice_pdf.dart';
import 'package:minierp_app/features/sales/return_receipt_pdf.dart';

Invoice _invoice({
  List<ReturnDocument>? returns,
  InvoicePosition? position,
  List<TimelineEvent>? timeline,
}) =>
    Invoice(
      id: 1,
      invoiceNo: 'INV-1001',
      customerId: 7,
      invoiceDate: '2026-09-01',
      dueDate: '2026-09-16',
      totalAmount: 1800,
      paidAmount: 1800,
      balanceAmount: 0,
      status: 'Partially Returned',
      customerName: 'Acme Trading',
      items: [
        InvoiceItem(
          id: 10,
          invoiceId: 1,
          itemId: 3,
          itemCode: 'WIDGET-01',
          itemName: 'Widget',
          quantity: 6,
          unitPrice: 300,
          amount: 1800,
          taxRate: 0,
          discountType: 'flat',
          discountValue: 0,
          returnedQty: 4,
        ),
      ],
      returnedAmount: returns != null && returns.isNotEmpty ? 1200 : 0,
      returns: returns ?? const [],
      position: position,
      timeline: timeline ?? const [],
    );

ReturnDocument _return() => ReturnDocument(
      id: 41,
      returnNo: 'RET-0001',
      returnDate: '2026-09-10',
      status: 'Settled',
      feeType: 'percentage',
      feeValue: 10,
      returnedAmount: 1200,
      feeAmount: 120,
      netAmount: 1080,
      settledAmount: 1080,
      items: [
        ReturnDocumentItem(
          itemId: 3,
          quantity: 4,
          unitPrice: 300,
          taxAmount: 0,
          lineAmount: 1200,
        ),
      ],
      settlements: [
        ReturnSettlement(
          settlementNo: 'STL-0001',
          type: 'refund',
          amount: 1080,
          method: 'cash',
          reference: 'CASH-77',
          settledDate: '2026-09-10',
        ),
      ],
    );

InvoicePosition _position() => const InvoicePosition(
      originalTotal: 1800,
      totalReturned: 1200,
      currentInvoiceValue: 600,
      totalPaid: 1800,
      totalFees: 120,
      netPosition: 0,
      refundCreditDue: 0,
      totalSettled: 1080,
      remainingRefundDue: 0,
      balanceDue: 0,
      remainingSettlementCapacity: 0,
    );
void main() {
  setUpAll(() async {
    // The PDF builders load Noto Sans from the asset bundle.
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting();
  });
  test('A4 PDF builds the full return story when returns exist', () async {

    final bytes = await buildA4InvoicePdf(
      invoice: _invoice(
        returns: [_return()],
        position: _position(),
        timeline: [
          TimelineEvent(
            type: 'INVOICE',
            reference: 'INV-1001',
            amount: 1800,
            date: '2026-09-01',
          ),
          TimelineEvent(
            type: 'RETURN',
            reference: 'RET-0001',
            amount: 1200,
            date: '2026-09-10',
          ),
        ],
      ),
      payments: [
        InvoicePaymentRecord(
          id: 5,
          invoiceId: 1,
          paymentNo: 'PAY-0001',
          paymentDate: '2026-09-02',
          amount: 1800,
          method: 'cash',
        ),
      ],
    );
    expect(bytes, isNotEmpty);
  });

  test('A4 PDF falls back gracefully for a legacy invoice', () async {
    // Legacy invoice: returned_amount set by the pre-migration flow but no
    // invoice_returns rows — the new sections must not render (D11) and
    // the document must still build.
    final bytes = await buildA4InvoicePdf(
      invoice: _invoice(returns: const []),
      payments: const [],
    );
    expect(bytes, isNotEmpty);
  });

  test('Return Receipt PDF builds for one return', () async {
    final bytes = await buildReturnReceiptPdf(
      returnDoc: _return(),
      invoice: _invoice(returns: [_return()], position: _position()),
    );
    expect(bytes, isNotEmpty);
  });
}
