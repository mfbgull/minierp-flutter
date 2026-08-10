// Unit tests for the A4 invoice PDF builder (PORTING.md §12). These only
// verify the bytes are a well-formed PDF and that the builder survives
// edge-case invoices (no items, no customer, etc.) — layout rendering is
// covered by the reference `invoice-fixed.png` target.

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:minierp_app/data/models/invoice.dart';
import 'package:minierp_app/features/sales/invoice_pdf.dart';

void main() {
  setUpAll(() async {
    // Formatters.date needs the intl date symbols for the en locale.
    await initializeDateFormatting('en');
  });
  /// Reads the PDF magic header without decoding the whole document.
  String pdfHeader(List<int> bytes) =>
      String.fromCharCodes(bytes.take(5));

  test('buildA4InvoicePdf produces a well-formed PDF for a full invoice',
      () async {
    final invoice = Invoice(
      id: 1,
      invoiceNo: 'INV-0001',
      customerId: 7,
      customerName: 'Acme Corp',
      customerEmail: 'billing@acme.com',
      customerPhone: '+1 555 0100',
      customerAddress: '123 Main St, Springfield',
      invoiceDate: '2026-08-03',
      dueDate: '2026-08-17',
      totalAmount: 118.65,
      paidAmount: 50,
      balanceAmount: 68.65,
      status: 'Partially Paid',
      discountScope: 'invoice',
      discountType: 'flat',
      discountValue: 5,
      notes: 'Please reference INV-0001 on the wire transfer.',
      items: const [
        InvoiceItem(
          id: 1,
          invoiceId: 1,
          itemId: 10,
          itemName: 'Widget',
          itemCode: 'W-01',
          quantity: 3,
          unitPrice: 30,
          amount: 90,
          taxRate: 10,
          discountType: 'none',
          discountValue: 0,
          returnedQty: 0,
        ),
        InvoiceItem(
          id: 2,
          invoiceId: 1,
          itemId: 11,
          itemName: 'Gadget',
          itemCode: 'G-02',
          quantity: 1,
          unitPrice: 25,
          amount: 25,
          taxRate: 10,
          discountType: 'flat',
          discountValue: 5,
          returnedQty: 0,
        ),
      ],
    );
    final payments = const [
      InvoicePaymentRecord(
        id: 91,
        invoiceId: 1,
        paymentNo: 'PAY-001',
        paymentDate: '2026-08-05',
        amount: 50,
        method: 'Cash',
      ),
    ];

    final bytes = await buildA4InvoicePdf(invoice: invoice, payments: payments);

    expect(pdfHeader(bytes), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });

  test('buildA4InvoicePdf handles an invoice without items or customer', () async {
    final invoice = Invoice(
      id: 2,
      invoiceNo: 'INV-0002',
      customerId: 1,
      invoiceDate: '2026-08-03',
      totalAmount: 0,
      paidAmount: 0,
      balanceAmount: 0,
      status: 'Draft',
    );

    final bytes = await buildA4InvoicePdf(invoice: invoice);

    expect(pdfHeader(bytes), '%PDF-');
    expect(bytes.length, greaterThan(500));
  });

  test('buildA4InvoicePdf uses the default company block when none is set',
      () async {
    final invoice = Invoice(
      id: 3,
      invoiceNo: 'INV-0003',
      customerId: 2,
      customerName: 'A Customer',
      invoiceDate: '2026-08-04',
      totalAmount: 12.5,
      paidAmount: 12.5,
      balanceAmount: 0,
      status: 'Paid',
    );

    final bytes = await buildA4InvoicePdf(invoice: invoice);

    expect(pdfHeader(bytes), '%PDF-');
    // No company + no items: builder must still not throw.
    expect(bytes.length, greaterThan(500));
  });
}
