// A4 quotation PDF generation — PORTING.md §12. Dart port of the web
// `references/components/invoice/QuotationTemplateA4.tsx` layout using the
// `pdf` package (already a pubspec dependency). The print dialog lives in
// the quotation form (`quotation_form_dialog.dart`); this file only builds
// the bytes.
//
// Layout mirrors the reference template:
//   header (company block + QUOTATION title/no/status chip)
//   Quote To + Date/Valid-Until details
//   items table (Item | Qty | Rate | Discount? | Tax? | Amount — the
//     Discount/Tax columns appear only when any line uses them)
//   summary (notes + terms & conditions left; subtotal/discount/tax/total
//     right)
//   footer ("Thank you for considering our proposal!" + validity/contact
//     line)
//
// Labels are English like the reference template. Urdu/RTL PDF text needs
// an arabic-shaping font and is out of scope (the on-screen app remains
// fully localized).

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/utils/formatters.dart';
import '../../data/models/invoice.dart' show CompanyInfo;
import '../../data/models/quotation.dart'
    show QuotationDetail, QuotationItem;
import '../sales/models/sales_forms.dart' show defaultCompany;

/// Accent color — the DESIGN.md emerald (matches the app's primary).
const PdfColor _accent = PdfColor.fromInt(0xFF059669);

/// Builds the A4 quotation PDF bytes for [quotation]. [company] overrides
/// the default company block (quotations carry no company of their own,
/// unlike invoices, so it falls back to [defaultCompany]).
Future<Uint8List> buildA4QuotationPdf({
  required QuotationDetail quotation,
  CompanyInfo? company,
}) async {
  final usedCompany = company ?? defaultCompany;
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      footer: (context) => _buildFooter(usedCompany, quotation),
      build: (context) => [
        _buildHeader(usedCompany, quotation),
        pw.SizedBox(height: 16),
        _buildInfoSection(quotation),
        pw.SizedBox(height: 16),
        _buildItemsTable(quotation),
        pw.SizedBox(height: 16),
        _buildSummarySection(quotation),
      ],
    ),
  );
  return doc.save();
}

// ── Header ──────────────────────────────────────────────────────────

pw.Widget _buildHeader(CompanyInfo company, QuotationDetail quotation) {
  final brand = company.name.trim().isNotEmpty ? company.name.trim()[0] : 'M';
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      // Company block (logo placeholder = first letter).
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
                  if (company.taxId != null && company.taxId!.trim().isNotEmpty)
                    _detailLine('Tax ID: ${company.taxId}'),
                ],
              ),
            ),
          ],
        ),
      ),
      // QUOTATION title + number + status chip.
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text(
            'QUOTATION',
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
              color: _accent,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            quotation.quotationNo.isEmpty ? 'N/A' : quotation.quotationNo,
            style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 6),
          _statusChip(quotation.status.isEmpty ? 'Draft' : quotation.status),
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

/// Status chip — same vocabulary as `getStatusClass` in the reference
/// template (draft gray, sent blue, accepted green, rejected red,
/// converted violet, expired amber).
PdfColor _statusColor(String status) => switch (status) {
  'Accepted' => PdfColor.fromInt(0xFF16A34A),
  'Sent' => PdfColor.fromInt(0xFF2563EB),
  'Rejected' => PdfColor.fromInt(0xFFB91C1C),
  'Converted' => PdfColor.fromInt(0xFF7C3AED),
  'Expired' => PdfColor.fromInt(0xFFD97706),
  _ => PdfColor.fromInt(0xFF6B7280), // Draft + unknown
};

pw.Widget _statusChip(String status) {
  final color = _statusColor(status);
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: color, width: 0.8),
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Text(
      status,
      style: pw.TextStyle(
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
        color: color,
      ),
    ),
  );
}

// ── Quote To + details ──────────────────────────────────────────────

pw.Widget _buildInfoSection(QuotationDetail quotation) {
  final expiry = quotation.expiryDate ?? '';
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        flex: 3,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _sectionLabel('Quote To'),
            pw.SizedBox(height: 4),
            pw.Text(
              quotation.customerName.trim().isEmpty
                  ? 'N/A'
                  : quotation.customerName,
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
            _detailRow('Date', Formatters.date(quotation.quotationDate)),
            pw.SizedBox(height: 3),
            _detailRow(
              // Plain '-' rather than an em-dash: Helvetica (the default
              // PDF font) has no U+2014 glyph, which renders as tofu.
              'Valid Until',
              expiry.isEmpty ? '-' : Formatters.date(expiry),
            ),
          ],
        ),
      ),
    ],
  );
}

pw.Widget _sectionLabel(String text) => pw.Text(
  text,
  style: pw.TextStyle(
    fontSize: 9,
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.grey600,
    letterSpacing: 0.4,
  ),
);

pw.Widget _detailRow(String label, String value) => pw.Row(
  mainAxisAlignment: pw.MainAxisAlignment.end,
  children: [
    pw.Text(
      label,
      style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
    ),
    pw.SizedBox(width: 10),
    pw.Text(
      value,
      style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold),
    ),
  ],
);

// ── Items table ─────────────────────────────────────────────────────

pw.Widget _buildItemsTable(QuotationDetail quotation) {
  final items = quotation.items;
  final hasDiscount = items.any((i) => (i.discountValue ?? 0) > 0);
  final hasTax = items.any((i) => (i.taxRate ?? 0) > 0);

  // Sequential widths — the extra columns (discount/tax) appear only when
  // used, exactly like the reference template's conditional `colSpan`.
  final widths = <int, pw.TableColumnWidth>{
    for (final (index, width) in [
      const pw.FlexColumnWidth(3),
      const pw.FlexColumnWidth(0.8),
      const pw.FlexColumnWidth(1.2),
      if (hasDiscount) const pw.FlexColumnWidth(1.2),
      if (hasTax) const pw.FlexColumnWidth(0.9),
      const pw.FlexColumnWidth(1.3),
    ].indexed)
      index: width,
  };

  final header = [
    _headerCell('Item'),
    _headerCell('Qty', right: true),
    _headerCell('Rate', right: true),
    if (hasDiscount) _headerCell('Discount', right: true),
    if (hasTax) _headerCell('Tax', right: true),
    _headerCell('Amount', right: true),
  ];

  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.6),
    columnWidths: widths,
    children: [
      pw.TableRow(children: header),
      if (items.isEmpty)
        pw.TableRow(
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 8,
              ),
              child: pw.Text(
                'No items found',
                style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
              ),
            ),
            for (var i = 1; i < widths.length; i++)
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 8,
                ),
                child: pw.Text('', style: pw.TextStyle(fontSize: 9)),
              ),
          ],
        )
      else
        for (final item in items)
          pw.TableRow(
            children: _itemCell(
              item,
              hasDiscount: hasDiscount,
              hasTax: hasTax,
            ),
          ),
    ],
  );
}

pw.Widget _headerCell(String label, {bool right = false}) => pw.Container(
  color: PdfColors.grey100,
  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
  child: pw.Text(
    label,
    textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
    style: pw.TextStyle(
      fontSize: 8.5,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.grey800,
    ),
  ),
);

/// One item row — name + code stacked on the left, right-aligned numbers.
List<pw.Widget> _itemCell(
  QuotationItem item, {
  required bool hasDiscount,
  required bool hasTax,
}) {
  final name = item.itemName;
  final code = item.itemCode;
  pw.Widget cell(String text, {bool right = false, bool bold = false}) =>
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: pw.Text(
          text,
          textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
          style: pw.TextStyle(
            fontSize: 9.5,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );

  // Item name with the item code beneath it (reference template).
  final nameCell = pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          name.trim().isEmpty ? 'N/A' : name,
          style: pw.TextStyle(fontSize: 9.5),
        ),
        if (code.trim().isNotEmpty)
          pw.Text(
            code.trim(),
            style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
      ],
    ),
  );

  return [
    nameCell,
    cell(_number(item.quantity), right: true),
    cell(_currency(item.unitPrice), right: true),
    if (hasDiscount) cell(_discountLabel(item), right: true),
    if (hasTax)
      cell((item.taxRate ?? 0) > 0 ? '${_trimNum(item.taxRate!)}%' : '-',
          right: true),
    cell(_currency(_lineAmount(item)), right: true, bold: true),
  ];
}

/// `qty × rate`, minus line discount (flat or %) plus tax — the exact
/// `calculateItemTotal` math from the reference template.
num _lineAmount(QuotationItem item) {
  var subtotal = item.quantity * item.unitPrice;
  if (item.discountType == 'percentage') {
    subtotal -= subtotal * ((item.discountValue ?? 0) / 100);
  } else {
    subtotal -= item.discountValue ?? 0;
  }
  subtotal += subtotal * ((item.taxRate ?? 0) / 100);
  return subtotal < 0 ? 0 : subtotal;
}

String _discountLabel(QuotationItem item) {
  final value = item.discountValue ?? 0;
  if (value <= 0) return '-';
  return item.discountType == 'percentage'
      ? '${_trimNum(value)}%'
      : _currency(value);
}

// ── Summary ─────────────────────────────────────────────────────────

pw.Widget _buildSummarySection(QuotationDetail quotation) {
  final notes = quotation.notes ?? '';
  final terms = quotation.terms ?? '';
  final subtotal = _subtotal(quotation);
  final discount = _totalDiscount(quotation);
  final tax = _totalTax(quotation);

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      // Left: notes + terms & conditions.
      pw.Expanded(
        flex: 3,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (notes.trim().isNotEmpty) ...[
              _sectionLabel('Notes'),
              pw.SizedBox(height: 4),
              pw.Text(
                notes.trim(),
                style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
              ),
            ],
            if (terms.trim().isNotEmpty) ...[
              if (notes.trim().isNotEmpty) pw.SizedBox(height: 12),
              _sectionLabel('Terms & Conditions'),
              pw.SizedBox(height: 4),
              pw.Text(
                terms.trim(),
                style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
              ),
            ],
          ],
        ),
      ),
      pw.SizedBox(width: 20),
      // Right: totals column.
      pw.Expanded(
        flex: 2,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            _totalRow('Subtotal', _currency(subtotal)),
            if (discount > 0) ...[
              pw.SizedBox(height: 3),
              _totalRow(
                'Discount',
                '-${_currency(discount)}',
                color: PdfColor.fromInt(0xFFDC2626),
              ),
            ],
            if (tax > 0) ...[
              pw.SizedBox(height: 3),
              _totalRow('Tax', _currency(tax)),
            ],
            pw.SizedBox(height: 5),
            pw.Container(
              height: 0.6,
              color: PdfColors.grey400,
            ),
            pw.SizedBox(height: 5),
            _totalRow('Total', _currency(quotation.totalAmount), bold: true),
          ],
        ),
      ),
    ],
  );
}

pw.Widget _totalRow(String label, String value,
    {bool bold = false, PdfColor? color}) {
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.end,
    children: [
      pw.Text(
        label,
        style: pw.TextStyle(
          fontSize: 9.5,
          color: color ?? PdfColors.grey700,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
      pw.SizedBox(width: 12),
      pw.SizedBox(
        width: 74,
        child: pw.Text(
          value,
          textAlign: pw.TextAlign.right,
          style: pw.TextStyle(
            fontSize: 9.5,
            color: color,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ),
    ],
  );
}

// ── Footer ──────────────────────────────────────────────────────────

pw.Widget _buildFooter(CompanyInfo company, QuotationDetail quotation) {
  final expiry = quotation.expiryDate ?? '';
  final contact = company.email.trim().isEmpty
      ? 'support@minierp.com'
      : company.email.trim();
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
          'Thank you for considering our proposal!',
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          expiry.trim().isEmpty
              ? 'For questions, contact $contact.'
              : 'This quotation is valid until '
                    '${Formatters.date(expiry)}. For questions, contact '
                    '$contact.',
          style: pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
        ),
      ],
    ),
  );
}

// ── Totals math + formatting ────────────────────────────────────────

/// Σ qty × rate (reference `calculateSubtotal` — the server does not
/// return `subtotal`, so it is always derived from the lines).
num _subtotal(QuotationDetail quotation) =>
    quotation.items.fold<num>(0, (sum, i) => sum + i.quantity * i.unitPrice);

/// Line discounts (flat or %) summed (reference `totalDiscount`).
num _totalDiscount(QuotationDetail quotation) {
  return quotation.items.fold<num>(0, (sum, i) {
    final subtotal = i.quantity * i.unitPrice;
    if (i.discountType == 'percentage') {
      return sum + subtotal * ((i.discountValue ?? 0) / 100);
    }
    return sum + (i.discountValue ?? 0);
  });
}

/// Σ tax on the discounted line subtotals (reference `totalTax`).
num _totalTax(QuotationDetail quotation) {
  return quotation.items.fold<num>(0, (sum, i) {
    var subtotal = i.quantity * i.unitPrice;
    if (i.discountType == 'percentage') {
      subtotal -= subtotal * ((i.discountValue ?? 0) / 100);
    } else {
      subtotal -= i.discountValue ?? 0;
    }
    return sum + (subtotal < 0 ? 0 : subtotal) * ((i.taxRate ?? 0) / 100);
  });
}

String _currency(num value) => Formatters.currency(value);

String _number(num value) => Formatters.number(value);

/// 10 → "10", 12.5 → "12.5" (no trailing zeros).
String _trimNum(num value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}
