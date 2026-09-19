// Standalone Return Receipt PDF (spec §6.3 / D10) — one printable
// document per invoice return. Mirrors the A4 invoice's visual language
// (emerald accent, grey tables) but is a self-contained page: RET-
// number + date, returned items at their original rates, the financial
// summary (returned value / fee with type / net), the settlement
// allocations, and the parent invoice reference.
//
// Like invoice_pdf.dart, labels are English only (PDF text shaping for
// Urdu needs an arabic-shaping font and is out of scope).

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/utils/formatters.dart';
import '../../data/models/invoice.dart' show CompanyInfo, Invoice;
import '../../data/models/sales_return.dart' show ReturnDocument, ReturnSettlement;
import 'models/sales_forms.dart' show defaultCompany;

const PdfColor _accent = PdfColor.fromInt(0xFF059669);

/// Builds the Return Receipt bytes for [returnDoc] (one return of
Future<Uint8List> buildReturnReceiptPdf({
  required ReturnDocument returnDoc,
  required Invoice invoice,
  CompanyInfo? company,
}) async {
  final usedCompany = company ?? invoice.company ?? defaultCompany;
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      footer: (context) => _buildFooter(usedCompany),
      build: (context) => [
        _buildHeader(usedCompany, returnDoc),
        pw.SizedBox(height: 16),
        _buildMetaSection(returnDoc, invoice),
        pw.SizedBox(height: 16),
        _buildItemsTable(returnDoc),
        pw.SizedBox(height: 16),
        _buildFinancialSummary(returnDoc),
        if (returnDoc.settlements.isNotEmpty) ...[
          pw.SizedBox(height: 16),
          _buildSettlementsTable(returnDoc.settlements),
        ],
        if ((returnDoc.reason ?? '').trim().isNotEmpty) ...[
          pw.SizedBox(height: 16),
          _buildReason(returnDoc),
        ],
      ],
    ),
  );
  return doc.save();
}

// ── Header ──────────────────────────────────────────────────────────

pw.Widget _buildHeader(CompanyInfo company, ReturnDocument ret) {
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
                    company.name.trim().isEmpty
                        ? 'Mini ERP'
                        : company.name.trim(),
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                      color: _accent,
                    ),
                  ),
                  if (company.address.trim().isNotEmpty)
                    pw.Text(
                      company.address.trim(),
                      style: const pw.TextStyle(
                        fontSize: 8.5,
                        color: PdfColors.grey700,
                      ),
                    ),
                  if (company.phone.trim().isNotEmpty ||
                      company.email.trim().isNotEmpty)
                    pw.Text(
                      [
                        if (company.phone.trim().isNotEmpty) company.phone.trim(),
                        if (company.email.trim().isNotEmpty) company.email.trim(),
                      ].join(' | '),
                      style: const pw.TextStyle(
                        fontSize: 8.5,
                        color: PdfColors.grey700,
                      ),
                    ),
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
            'RETURN RECEIPT',
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            ret.returnNo,
            style: pw.TextStyle(
              fontSize: 11,
              color: PdfColors.grey700,
            ),
          ),
        ],
      ),
    ],
  );
}

pw.Widget _buildMetaSection(ReturnDocument ret, Invoice invoice) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      color: PdfColors.grey100,
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _metaLabel('Invoice'),
              _metaValue(invoice.invoiceNo),
              pw.SizedBox(height: 6),
              _metaLabel('Return Date'),
              _metaValue(_fmtDate(ret.returnDate)),
            ],
          ),
        ),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _metaLabel('Status'),
              _metaValue(ret.status),
              pw.SizedBox(height: 6),
              _metaLabel('Issued'),
              _metaValue(_fmtDate(DateTime.now().toIso8601String())),
            ],
          ),
        ),
      ],
    ),
  );
}

pw.Text _metaLabel(String text) => pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 7.5,
        color: PdfColors.grey600,
      ),
    );

pw.Text _metaValue(String text) => pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 10,
        fontWeight: pw.FontWeight.bold,
      ),
    );

// ── Items ───────────────────────────────────────────────────────────

pw.Widget _buildItemsTable(ReturnDocument ret) {
  final items = ret.items;
  return pw.Table(
    tableWidth: pw.TableWidth.max,
    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
    columnWidths: const {
      1: pw.FixedColumnWidth(46),
      2: pw.FixedColumnWidth(68),
      3: pw.FixedColumnWidth(68),
      4: pw.FixedColumnWidth(86),
    },
    children: [
      pw.TableRow(
        children: _headerCells(['Item', 'Qty', 'Rate', 'Tax', 'Returned Value']),
      ),
      for (final item in items)
        pw.TableRow(
          children: _cells([
            'Item #${item.itemId}',
            _trimNum(item.quantity),
            _currency(item.unitPrice),
            _currency(item.taxAmount),
            _currency(item.lineAmount),
          ], lastRight: true),
        ),
    ],
  );
}

pw.Widget _buildFinancialSummary(ReturnDocument ret) {
  final feeType = ret.feeType ?? 'none';
  final feeLabel = feeType == 'percentage'
      ? 'Restocking Fee (${_trimNum(ret.feeValue)}%)'
      : feeType == 'fixed'
          ? 'Restocking Fee (fixed)'
          : 'Restocking Fee';
  return pw.Align(
    alignment: pw.Alignment.centerRight,
    child: pw.Container(
      constraints: const pw.BoxConstraints(maxWidth: 280),
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _summaryRow('Returned Value', _currency(ret.returnedAmount)),
          _summaryRow(feeLabel, _currency(ret.feeAmount)),
          _summaryRow('Net Refund/Credit', _currency(ret.netAmount), bold: true),
          if (ret.settledAmount > 0.005)
            _summaryRow('Settled', _currency(ret.settledAmount)),
        ],
      ),
    ),
  );
}

pw.Widget _buildSettlementsTable(List<ReturnSettlement> settlements) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Text(
          'Settlement Allocations',
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: _accent,
          ),
        ),
      ),
      pw.Table(
        tableWidth: pw.TableWidth.max,
        border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
        columnWidths: const {
          0: pw.FixedColumnWidth(84),
          1: pw.FixedColumnWidth(84),
          3: pw.FixedColumnWidth(78),
        },
        children: [
          pw.TableRow(
            children: _headerCells([
              'Date',
              'Type',
              'Method/Reference',
              'Amount',
            ]),
          ),
          for (final s in settlements)
            pw.TableRow(
              children: _cells([
                _fmtDate(s.settledDate),
                s.type,
                [
                  if (s.method != null && s.method!.isNotEmpty) s.method!,
                  if (s.reference != null && s.reference!.isNotEmpty)
                    s.reference!,
                ].join(' - '),
                _currency(s.amount),
              ], lastRight: true),
            ),
        ],
      ),
    ],
  );
}

pw.Widget _buildReason(ReturnDocument ret) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Reason',
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: _accent,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(ret.reason!),
      ],
    );

// ── Footer ──────────────────────────────────────────────────────────

pw.Widget _buildFooter(CompanyInfo company) {
  final contact =
      company.email.trim().isEmpty ? 'support@minierp.com' : company.email.trim();
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 14),
    padding: const pw.EdgeInsets.only(top: 8),
    decoration: pw.BoxDecoration(
      border: pw.Border(
        top: pw.BorderSide(color: PdfColors.grey300, width: 0.6),
      ),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Goods returned in good order.',
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'For questions, contact $contact.',
          style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
        ),
      ],
    ),
  );
}

// ── Table helpers ───────────────────────────────────────────────────

List<pw.Widget> _headerCells(List<String> labels) => [
      for (final label in labels)
        pw.Container(
          color: PdfColors.grey200,
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
    ];

List<pw.Widget> _cells(List<String> values, {bool lastRight = false}) => [
      for (var i = 0; i < values.length; i++)
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          alignment:
              (lastRight && i == values.length - 1) ? pw.Alignment.centerRight : null,
          child: pw.Text(values[i], style: const pw.TextStyle(fontSize: 8.5)),
        ),
    ];

pw.Widget _summaryRow(String label, String value, {bool bold = false}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 9.5)),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 9.5,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ],
      ),
    );

String _currency(num value) => Formatters.currency(value);

/// 10 → "10", 12.5 → "12.5" (no trailing zeros).
String _trimNum(num value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}

/// ISO date → "yyyy-MM-dd".
String _fmtDate(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  return iso.length >= 10 ? iso.substring(0, 10) : iso;
}
