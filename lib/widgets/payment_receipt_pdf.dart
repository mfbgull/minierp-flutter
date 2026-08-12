// A4 payment-receipt PDF — companion to the invoice A4 template
// (`features/sales/invoice_pdf.dart`), built with the same `pdf` package
// conventions (company block header, document title, details table,
// footer). Rendered/printed by the customer + supplier detail Payments
// tabs and the Record Payment success screens.
//
// Labels are English like the reference receipt; Urdu/RTL PDF text needs
// an arabic-shaping font and is out of scope (on-screen stays localized).

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/models/invoice.dart' show CompanyInfo;
import '../data/models/payment.dart' show Payment;
import '../features/sales/models/sales_forms.dart' show defaultCompany;

const PdfColor _accent = PdfColor.fromInt(0xFF059669);

/// Builds the A4 payment-receipt PDF bytes for [payment]. [company]
/// overrides the default company block; [entityName] overrides the
/// customer/supplier name shown on the receipt (used when the payment
/// record itself doesn't carry the name, e.g. right after creation).
Future<Uint8List> buildPaymentReceiptPdf(
  Payment payment, {
  CompanyInfo? company,
  String? entityName,
}) async {
  final usedCompany = company ?? defaultCompany;
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      footer: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 8),
        child: pw.Text(
          '${usedCompany.name} • ${usedCompany.phone} • ${usedCompany.email}',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ),
      build: (context) => [
        _buildHeader(usedCompany, payment),
        pw.SizedBox(height: 20),
        _buildDetails(payment, entityName),
        pw.SizedBox(height: 24),
        _buildAmountBox(payment),
      ],
    ),
  );
  return doc.save();
}

pw.Widget _buildHeader(CompanyInfo company, Payment payment) {
  final brand = company.name.trim().isNotEmpty ? company.name.trim()[0] : 'M';
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: 34,
              height: 34,
              alignment: pw.Alignment.center,
              decoration: pw.BoxDecoration(
                color: _accent,
                shape: pw.BoxShape.circle,
              ),
              child: pw.Text(
                brand,
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    company.name.trim().isEmpty ? 'Mini ERP' : company.name,
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  if (company.address.trim().isNotEmpty)
                    _detailLine(company.address),
                  if (company.phone.trim().isNotEmpty)
                    _detailLine(company.phone),
                  if (company.email.trim().isNotEmpty)
                    _detailLine(company.email),
                ],
              ),
            ),
          ],
        ),
      ),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text(
            'PAYMENT RECEIPT',
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: _accent,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            payment.paymentNo.isEmpty ? 'N/A' : payment.paymentNo,
            style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
        ],
      ),
    ],
  );
}

pw.Widget _detailLine(String text) => pw.Padding(
  padding: const pw.EdgeInsets.only(top: 1),
  child: pw.Text(
    text,
    style: pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
  ),
);

pw.Widget _buildDetails(Payment payment, String? entityName) {
  final isSupplier = payment.supplierId != null;
  final resolvedName =
      entityName?.trim().isNotEmpty == true
          ? entityName!
          : isSupplier
          ? (payment.supplierName?.trim().isNotEmpty == true
                ? payment.supplierName!
                : 'Supplier #${payment.supplierId}')
          : payment.customerName?.trim().isNotEmpty == true
          ? payment.customerName!
          : 'Customer #${payment.customerId}';
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        flex: 3,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _sectionLabel(isSupplier ? 'Paid To' : 'Received From'),
            pw.SizedBox(height: 4),
            pw.Text(
              resolvedName,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      pw.Expanded(
        flex: 2,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            _detailRow('Payment Date', _fmtDate(payment.paymentDate)),
            pw.SizedBox(height: 3),
            _detailRow('Method', payment.paymentMethod),
            if (payment.referenceNo?.trim().isNotEmpty == true) ...[
              pw.SizedBox(height: 3),
              _detailRow('Reference', payment.referenceNo!),
            ],
          ],
        ),
      ),
    ],
  );
}

pw.Widget _buildAmountBox(Payment payment) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(16),
    decoration: pw.BoxDecoration(
      color: PdfColor.fromInt(0xFFF0FDF4),
      border: pw.Border.all(color: _accent, width: 1),
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          payment.supplierId != null ? 'AMOUNT PAID' : 'AMOUNT RECEIVED',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          '${_currencySymbol()}${payment.amount.toStringAsFixed(2)}',
          style: pw.TextStyle(
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
            color: _accent,
          ),
        ),
      ],
    ),
  );
}

pw.Widget _sectionLabel(String text) => pw.Text(
  text,
  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
);

pw.Widget _detailRow(String label, String value) => pw.Row(
  mainAxisSize: pw.MainAxisSize.min,
  children: [
    pw.Text(
      '$label: ',
      style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
    ),
    pw.Text(
      value,
      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
    ),
  ],
);

String _fmtDate(String iso) {
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return iso.isEmpty ? '-' : iso;
  return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
}

String _currencySymbol() {
  // Mirrors the settings currency; PDF labels are English-only so keep
  // the plain $ like the reference receipt.
  return r'$';
}
