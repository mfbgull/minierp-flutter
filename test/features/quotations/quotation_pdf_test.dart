// Unit tests for the A4 quotation PDF builder (PORTING.md §12). These only
// verify the bytes are a well-formed PDF and that the builder survives
// edge-case quotations (no items, empty customer, etc.) — layout rendering
// mirrors the reference `QuotationTemplateA4.tsx` target.

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:minierp_app/data/models/quotation.dart';
import 'package:minierp_app/features/quotations/quotation_pdf.dart';

void main() {
  setUpAll(() async {
    // Formatters.date needs the intl date symbols for the en locale.
    await initializeDateFormatting('en');
  });

  /// Reads the PDF magic header without decoding the whole document.
  String pdfHeader(List<int> bytes) => String.fromCharCodes(bytes.take(5));

  test('buildA4QuotationPdf produces a well-formed PDF for a full quotation',
      () async {
    final quotation = QuotationDetail(
      id: 1,
      quotationNo: 'QT-2026-001',
      quotationDate: '2026-08-05',
      customerId: 7,
      customerName: 'Acme Corp',
      expiryDate: '2026-09-05',
      status: 'Sent',
      totalAmount: 99,
      notes: 'Prices valid for 30 days.',
      terms: '50% advance, balance on delivery.',
      items: const [
        QuotationItem(
          id: 1,
          itemId: 10,
          itemName: 'Widget',
          itemCode: 'W-01',
          quantity: 3,
          unitPrice: 30,
          amount: 90,
          taxRate: 10,
          discountType: 'none',
          discountValue: 0,
        ),
        QuotationItem(
          id: 2,
          itemId: 11,
          itemName: 'Gadget',
          itemCode: 'G-02',
          quantity: 1,
          unitPrice: 40,
          amount: 40,
          discountType: 'percentage',
          discountValue: 25,
          taxRate: 0,
        ),
      ],
    );

    final bytes = await buildA4QuotationPdf(quotation: quotation);

    expect(pdfHeader(bytes), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });

  test('buildA4QuotationPdf handles a quotation without items or dates',
      () async {
    final quotation = QuotationDetail(
      id: 2,
      quotationNo: 'QT-2026-002',
      quotationDate: '2026-08-05',
      customerId: 1,
      customerName: '',
      status: 'Draft',
      totalAmount: 0,
      items: const [],
    );

    final bytes = await buildA4QuotationPdf(quotation: quotation);

    expect(pdfHeader(bytes), '%PDF-');
    // No company + no items + empty customer: builder must still not throw.
    expect(bytes.length, greaterThan(500));
  });

  test('buildA4QuotationPdf uses the default company block when none is set',
      () async {
    final quotation = QuotationDetail(
      id: 3,
      quotationNo: 'QT-2026-003',
      quotationDate: '2026-08-06',
      customerId: 2,
      customerName: 'A Customer',
      status: 'Accepted',
      totalAmount: 12.5,
      items: const [
        QuotationItem(
          itemId: 5,
          itemName: 'Bolt',
          itemCode: 'B-05',
          quantity: 5,
          unitPrice: 2.5,
          amount: 12.5,
        ),
      ],
    );

    final bytes = await buildA4QuotationPdf(quotation: quotation);

    expect(pdfHeader(bytes), '%PDF-');
    expect(bytes.length, greaterThan(500));
  });
}
