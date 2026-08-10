// A4 invoice PDF generation — PORTING.md §12. Dart port of the web
// `references/components/invoice/InvoiceTemplateA4.tsx` layout using the
// `pdf` package (already a pubspec dependency). The print dialog lives in
// the invoice form (`sales_invoice_form_page.dart`); this file only builds
// the bytes.
//
// Layout mirrors the reference template:
//   header (company block + INVOICE title/no/status chip)
//   Bill-To + invoice-date/due-date details
//   items table (Item | Qty | Rate | Discount? | Tax? | Amount — the
//     Discount/Tax columns appear only when any line uses them)
//   summary (notes + payment history left; subtotal/discount/tax/total/
//     paid/returned/balance-due right)
//   footer ("Thank you for your business!" + contact line)
//
// Labels are English like the reference template. Urdu/RTL PDF text needs
// an arabic-shaping font and is out of scope (the on-screen app remains
// fully localized).

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/utils/formatters.dart';
import '../../data/models/invoice.dart'
    show CompanyInfo, Invoice, InvoiceItem, InvoicePaymentRecord;
import 'models/sales_forms.dart' show defaultCompany;

/// Accent color — the DESIGN.md emerald (matches the app's primary).
const PdfColor _accent = PdfColor.fromInt(0xFF059669);

/// Builds the A4 invoice PDF bytes for [invoice]. [payments] renders the
/// payment-history table; [company] overrides the invoice's own company
/// block (which itself falls back to [defaultCompany]).
Future<Uint8List> buildA4InvoicePdf({
  required Invoice invoice,
  List<InvoicePaymentRecord> payments = const [],
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
        _buildHeader(usedCompany, invoice),
        pw.SizedBox(height: 16),
        _buildInfoSection(invoice),
        pw.SizedBox(height: 16),
        _buildItemsTable(invoice),
        pw.SizedBox(height: 16),
        _buildSummarySection(invoice, payments),
      ],
    ),
  );
  return doc.save();
}

// ── Header ──────────────────────────────────────────────────────────

pw.Widget _buildHeader(CompanyInfo company, Invoice invoice) {
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
      // INVOICE title + number + status chip.
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text(
            'INVOICE',
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
              color: _accent,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            invoice.invoiceNo.isEmpty ? 'N/A' : invoice.invoiceNo,
            style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 6),
          _statusChip(invoice.status.isEmpty ? 'Unpaid' : invoice.status),
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

/// Status chip — same vocabulary/colors as `getStatusClass` in the
/// reference template (green/amber/red per bucket).
PdfColor _statusColor(String status) => switch (status) {
  'Paid' => PdfColor.fromInt(0xFF16A34A),
  'Partially Paid' => PdfColor.fromInt(0xFFD97706),
  'Overdue' => PdfColor.fromInt(0xFFB91C1C),
  'Draft' || 'Cancelled' || 'Returned' || 'Partially Returned' =>
    PdfColor.fromInt(0xFF6B7280),
  _ => PdfColor.fromInt(0xFFDC2626), // Unpaid + unknown
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

// ── Bill To + details ───────────────────────────────────────────────

pw.Widget _buildInfoSection(Invoice invoice) {
  final dueDate = invoice.dueDate ?? '';
  final terms = invoice.terms ?? '';
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        flex: 3,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _sectionLabel('Bill To'),
            pw.SizedBox(height: 4),
            pw.Text(
              (invoice.customerName ?? '').trim().isEmpty
                  ? 'N/A'
                  : invoice.customerName!,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            if ((invoice.customerAddress ?? '').trim().isNotEmpty)
              _detailLine(invoice.customerAddress!),
            if ((invoice.customerPhone ?? '').trim().isNotEmpty)
              _detailLine(invoice.customerPhone!),
            if ((invoice.customerEmail ?? '').trim().isNotEmpty)
              _detailLine(invoice.customerEmail!),
          ],
        ),
      ),
      pw.Expanded(
        flex: 2,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            _detailRow('Invoice Date', Formatters.date(invoice.invoiceDate)),
            pw.SizedBox(height: 3),
            _detailRow(
              // Plain '-' rather than an em-dash: Helvetica (the default
              // PDF font) has no U+2014 glyph, which renders as tofu.
              'Due Date',
              dueDate.isEmpty ? '-' : Formatters.date(dueDate),
            ),
            if (terms.trim().isNotEmpty) ...[
              pw.SizedBox(height: 3),
              _detailRow('Payment Terms', terms.trim()),
            ],
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

pw.Widget _buildItemsTable(Invoice invoice) {
  final items = invoice.items ?? const <InvoiceItem>[];
  final hasDiscount =
      items.any((i) => i.discountValue > 0) || (invoice.discountValue ?? 0) > 0;
  final hasTax = items.any((i) => i.taxRate > 0);

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
  InvoiceItem item, {
  required bool hasDiscount,
  required bool hasTax,
}) {
  final name = item.itemName ?? '';
  final code = item.itemCode ?? '';
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
      cell(item.taxRate > 0 ? '${_trimNum(item.taxRate)}%' : '-', right: true),
    cell(_currency(_lineAmount(item)), right: true, bold: true),
  ];
}

/// `qty × rate`, minus line discount (flat or %) plus tax — the exact
/// `calculateItemTotal` math from the reference template.
num _lineAmount(InvoiceItem item) {
  var subtotal = item.quantity * item.unitPrice;
  if (item.discountType == 'percentage') {
    subtotal -= subtotal * (item.discountValue / 100);
  } else {
    subtotal -= item.discountValue;
  }
  subtotal += subtotal * (item.taxRate / 100);
  return subtotal < 0 ? 0 : subtotal;
}

String _discountLabel(InvoiceItem item) {
  if (item.discountValue <= 0) return '-';
  return item.discountType == 'percentage'
      ? '${_trimNum(item.discountValue)}%'
      : _currency(item.discountValue);
}

// ── Summary ─────────────────────────────────────────────────────────

pw.Widget _buildSummarySection(
  Invoice invoice,
  List<InvoicePaymentRecord> payments,
) {
  final notes = invoice.notes ?? '';
  final subtotal = _subtotal(invoice);
  final discount = _totalDiscount(invoice);
  final tax = _totalTax(invoice);
  final paid = invoice.paidAmount;
  final returned = invoice.returnedAmount;

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      // Left: notes + payment history.
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
            if (payments.isNotEmpty) ...[
              if (notes.trim().isNotEmpty) pw.SizedBox(height: 12),
              _sectionLabel('Payment History'),
              pw.SizedBox(height: 4),
              _paymentsTable(payments),
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
            _totalRow('Total', _currency(invoice.totalAmount), bold: true),
            if (paid > 0) ...[
              pw.SizedBox(height: 3),
              _totalRow('Paid', _currency(paid)),
              if (returned > 0) ...[
                pw.SizedBox(height: 3),
                _totalRow('Returned', _currency(returned)),
              ],
              pw.SizedBox(height: 3),
              _totalRow('Balance Due', _currency(invoice.balanceAmount),
                  bold: true),
            ],
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

pw.Widget _paymentsTable(List<InvoicePaymentRecord> payments) {
  final totalPaid = payments.fold<num>(0, (sum, p) => sum + p.amount);
  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.6),
    columnWidths: const {
      0: pw.FlexColumnWidth(1.2),
      1: pw.FlexColumnWidth(1.2),
      2: pw.FlexColumnWidth(1.4),
      3: pw.FlexColumnWidth(1),
    },
    children: [
      pw.TableRow(
        children: [
          for (final label in ['Date', 'Method', 'Reference', 'Amount'])
            _headerCell(label, right: label == 'Amount'),
        ],
      ),
      for (final p in payments)
        pw.TableRow(
          children: [
            _paymentCell(Formatters.date(p.paymentDate ?? '')),
            _paymentCell(p.method),
            _paymentCell((p.referenceNo ?? '').trim().isEmpty
                ? '-'
                : p.referenceNo!),
            _paymentCell(_currency(p.amount), right: true),
          ],
        ),
      pw.TableRow(
        children: [
          pw.Container(
            color: PdfColors.grey100,
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 5,
            ),
            child: pw.Text(
              'Total Paid',
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          for (var i = 0; i < 2; i++)
            pw.Container(
              color: PdfColors.grey100,
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 5,
              ),
              child: pw.Text('', style: pw.TextStyle(fontSize: 9)),
            ),
          pw.Container(
            color: PdfColors.grey100,
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 5,
            ),
            child: pw.Text(
              _currency(totalPaid),
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

pw.Widget _paymentCell(String text, {bool right = false}) => pw.Container(
  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
  child: pw.Text(
    text,
    textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
    style: pw.TextStyle(fontSize: 9),
  ),
);

// ── Footer ──────────────────────────────────────────────────────────

pw.Widget _buildFooter(CompanyInfo company) {
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
          'Thank you for your business!',
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'For questions, contact $contact.',
          style: pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
        ),
      ],
    ),
  );
}

// ── Totals math + formatting ────────────────────────────────────────

/// Σ qty × rate (reference `getSubtotal`).
num _subtotal(Invoice invoice) => (invoice.items ?? const <InvoiceItem>[])
    .fold<num>(0, (sum, i) => sum + i.quantity * i.unitPrice);

/// Line discounts (flat or %) + invoice-level discount on the subtotal
/// (reference `getTotalDiscount`).
num _totalDiscount(Invoice invoice) {
  final items = invoice.items ?? const <InvoiceItem>[];
  var discount = items.fold<num>(0, (sum, i) {
    final subtotal = i.quantity * i.unitPrice;
    if (i.discountType == 'percentage') {
      return sum + subtotal * (i.discountValue / 100);
    }
    return sum + i.discountValue;
  });
  final invoiceDiscount = invoice.discountValue ?? 0;
  if (invoiceDiscount > 0 && invoice.discountType != null) {
    final subtotal = _subtotal(invoice);
    if (invoice.discountType == 'percentage') {
      discount += subtotal * (invoiceDiscount / 100);
    } else {
      discount += invoiceDiscount;
    }
  }
  return discount < 0 ? 0 : discount;
}

/// Σ tax on the discounted line subtotals (reference `getTotalTax`).
num _totalTax(Invoice invoice) => (invoice.items ?? const <InvoiceItem>[])
    .fold<num>(0, (sum, i) {
      var subtotal = i.quantity * i.unitPrice;
      if (i.discountType == 'percentage') {
        subtotal -= subtotal * (i.discountValue / 100);
      } else {
        subtotal -= i.discountValue;
      }
      return sum + (subtotal < 0 ? 0 : subtotal) * (i.taxRate / 100);
    });

String _currency(num value) => Formatters.currency(value);

String _number(num value) => Formatters.number(value);

/// 10 → "10", 12.5 → "12.5" (no trailing zeros).
String _trimNum(num value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}
