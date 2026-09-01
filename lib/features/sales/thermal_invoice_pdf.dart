// Thermal (80mm) invoice PDF — PORTING.md §12. Generates a narrow receipt
// PDF for thermal printers using the `pdf` package. The layout mirrors the
// React reference `ThermalInvoiceTemplate.tsx`:
//   header (company name + contact)
//   invoice number + date
//   customer name + phone
//   items table (ITEM | QTY | AMOUNT)
//   totals (subtotal, tax, total, paid, balance due)
//   QR code
//   footer (thank-you + contact + payment terms)
//
// Labels are English like the reference template. Urdu/RTL PDF text needs
// an arabic-shaping font and is out of scope.

import 'dart:typed_data';

import 'package:flutter/painting.dart' show Color;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr_flutter/qr_flutter.dart' as qr;
import 'dart:ui' as ui;

import '../../data/models/invoice.dart' show CompanyInfo, Invoice;
import '../sales/models/sales_forms.dart' show defaultCompany;

/// Page width for 80mm thermal paper (~302pt at 96 DPI, ~315pt at 72 DPI).
/// We use 80mm ≈ 226.77pt (at 72 DPI, 1 inch = 72pt, 1mm = 2.8346pt).
const double _kThermalWidth = 226.77; // 80mm in points

/// Builds the thermal (80mm) invoice PDF bytes for [invoice].
/// [company] overrides the invoice's own company block.
Future<Uint8List> buildThermalInvoicePdf({
  required Invoice invoice,
  CompanyInfo? company,
}) async {
  final usedCompany = company ?? invoice.company ?? defaultCompany;

  // Pre-generate QR code image before building the document
  final qrData = 'INV:${invoice.invoiceNo}|TOTAL:${_fmtCurrency(invoice.totalAmount)}|';
  final qrImage = await _generateQrImage(qrData);

  final doc = pw.Document();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat(
        _kThermalWidth,
        PdfPageFormat.a4.height, // height is unlimited for roll paper
        marginAll: 12,
      ),
      margin: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      build: (context) => [
        _buildHeader(usedCompany),
        _buildDivider(),
        _buildInvoiceInfo(invoice),
        _buildDivider(),
        _buildCustomerInfo(invoice),
        _buildDivider(),
        _buildItemsTable(invoice),
        _buildDivider(),
        _buildTotals(invoice),
        _buildQrSection(invoice, qrImage),
        _buildDividerDouble(),
        _buildFooter(usedCompany, invoice),
      ],
    ),
  );

  return doc.save();
}

// ── Header ──────────────────────────────────────────────────────────

pw.Widget _buildHeader(CompanyInfo company) {
  final name = company.name.trim().isEmpty ? 'Mini ERP' : company.name.trim();
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.Text(
        name,
        style: pw.TextStyle(
          fontSize: 14,
          fontWeight: pw.FontWeight.bold,
        ),
        textAlign: pw.TextAlign.center,
      ),
      if (company.phone.trim().isNotEmpty || company.email.trim().isNotEmpty)
        pw.Text(
          [company.phone, company.email]
              .where((s) => s.trim().isNotEmpty)
              .join(' · '),
          style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          textAlign: pw.TextAlign.center,
        ),
    ],
  );
}

// ── Invoice Info ────────────────────────────────────────────────────

pw.Widget _buildInvoiceInfo(Invoice invoice) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _infoLine('Invoice: ${invoice.invoiceNo}'),
      _infoLine('Date: ${_fmtDate(invoice.invoiceDate)}'),
    ],
  );
}

// ── Customer Info ───────────────────────────────────────────────────

pw.Widget _buildCustomerInfo(Invoice invoice) {
  final name = invoice.customerName ?? 'N/A';
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        name,
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
      ),
      if (invoice.customerPhone != null && invoice.customerPhone!.isNotEmpty)
        _infoLine(invoice.customerPhone!),
    ],
  );
}

// ── Items Table ─────────────────────────────────────────────────────

pw.Widget _buildItemsTable(Invoice invoice) {
  final items = invoice.items ?? [];
  if (items.isEmpty) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Text(
        'No items',
        style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      // Header row
      pw.Row(
        children: [
          pw.Expanded(
            flex: 4,
            child: pw.Text(
              'ITEM',
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Expanded(
            flex: 1,
            child: pw.Text(
              'QTY',
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
              textAlign: pw.TextAlign.right,
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Text(
              'AMOUNT',
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
              textAlign: pw.TextAlign.right,
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 2),
      // Item rows
      for (final item in items)
        pw.Row(
          children: [
            pw.Expanded(
              flex: 4,
              child: pw.Text(
                item.itemName ?? item.itemCode ?? 'Item',
                style: pw.TextStyle(fontSize: 9),
                maxLines: 2,
                overflow: pw.TextOverflow.clip,
              ),
            ),
            pw.Expanded(
              flex: 1,
              child: pw.Text(
                _fmtNum(item.quantity),
                style: pw.TextStyle(fontSize: 9),
                textAlign: pw.TextAlign.right,
              ),
            ),
            pw.Expanded(
              flex: 2,
              child: pw.Text(
                _fmtCurrency(item.amount),
                style: pw.TextStyle(fontSize: 9),
                textAlign: pw.TextAlign.right,
              ),
            ),
          ],
        ),
    ],
  );
}

// ── Totals ──────────────────────────────────────────────────────────

pw.Widget _buildTotals(Invoice invoice) {
  final items = invoice.items ?? [];
  final subtotal = items.fold<num>(0, (s, i) => s + i.amount);
  final total = invoice.totalAmount;
  final paid = invoice.paidAmount;
  final balance = invoice.balanceAmount;
  final hasTax = items.any((i) => i.taxRate > 0);

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _totalRow('Subtotal', _fmtCurrency(subtotal)),
      if (hasTax) ...[
        // Compute total tax for display
        _totalRow(
          'Tax',
          _fmtCurrency(
            items.fold<num>(
              0,
              (s, i) => s + (i.amount * i.taxRate / 100),
            ),
          ),
        ),
      ],
      _totalRowBold('Total', _fmtCurrency(total)),
      if (paid > 0) ...[
        _totalRow('Paid', _fmtCurrency(paid)),
        if (invoice.returnedAmount > 0)
          _totalRow('Returned', _fmtCurrency(invoice.returnedAmount)),
        _totalRowBold('Balance Due', _fmtCurrency(balance)),
      ],
    ],
  );
}

// ── QR Code ─────────────────────────────────────────────────────────

pw.Widget _buildQrSection(Invoice invoice, pw.MemoryImage? qrImage) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.SizedBox(height: 4),
      if (qrImage != null)
        pw.Image(qrImage, width: 50, height: 50)
      else
        pw.SizedBox(width: 50, height: 50),
      pw.SizedBox(height: 2),
      pw.Text(
        invoice.invoiceNo,
        style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        textAlign: pw.TextAlign.center,
      ),
    ],
  );
}

/// Generate QR code as a PNG image for embedding in PDF.
Future<pw.MemoryImage?> _generateQrImage(String data) async {
  try {
    final qrPainter = qr.QrPainter(
      data: data,
      version: qr.QrVersions.auto,
      eyeStyle: const qr.QrEyeStyle(
        eyeShape: qr.QrEyeShape.square,
        color: Color(0xFF000000),
      ),
      dataModuleStyle: const qr.QrDataModuleStyle(
        dataModuleShape: qr.QrDataModuleShape.square,
        color: Color(0xFF000000),
      ),
    );

    final image = await qrPainter.toImage(100);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return null;

    return pw.MemoryImage(byteData.buffer.asUint8List());
  } catch (_) {
    return null;
  }
}

// ── Footer ──────────────────────────────────────────────────────────

pw.Widget _buildFooter(CompanyInfo company, Invoice invoice) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.Text(
        'Thank you for your business!',
        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        textAlign: pw.TextAlign.center,
      ),
      if (company.phone.trim().isNotEmpty)
        pw.Text(
          company.phone,
          style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          textAlign: pw.TextAlign.center,
        ),
      if (company.email.trim().isNotEmpty)
        pw.Text(
          company.email,
          style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          textAlign: pw.TextAlign.center,
        ),
      pw.SizedBox(height: 2),
      pw.Text(
        'Payment due within 14 days',
        style: pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
        textAlign: pw.TextAlign.center,
      ),
    ],
  );
}

// ── Helpers ─────────────────────────────────────────────────────────

pw.Widget _infoLine(String text) => pw.Text(
  text,
  style: pw.TextStyle(fontSize: 9),
);

pw.Widget _buildDivider() => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(vertical: 4),
  child: pw.Container(
    height: 0.5,
    color: PdfColors.grey400,
  ),
);

pw.Widget _buildDividerDouble() => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(vertical: 4),
  child: pw.Column(
    children: [
      pw.Container(height: 0.5, color: PdfColors.grey400),
      pw.SizedBox(height: 1),
      pw.Container(height: 0.5, color: PdfColors.grey400),
    ],
  ),
);

pw.Widget _totalRow(String label, String value) => pw.Row(
  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
  children: [
    pw.Text(label, style: pw.TextStyle(fontSize: 9)),
    pw.Text(value, style: pw.TextStyle(fontSize: 9)),
  ],
);

pw.Widget _totalRowBold(String label, String value) => pw.Row(
  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
  children: [
    pw.Text(
      label,
      style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
    ),
    pw.Text(
      value,
      style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
    ),
  ],
);

String _fmtDate(String iso) {
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return iso;
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[parsed.month - 1]} ${parsed.day}, ${parsed.year}';
}

String _fmtCurrency(num value) {
  return '\$${value.toStringAsFixed(2)}';
}

String _fmtNum(num value) {
  if (value == value.roundToDouble()) return '${value.toInt()}';
  return value.toStringAsFixed(2);
}
