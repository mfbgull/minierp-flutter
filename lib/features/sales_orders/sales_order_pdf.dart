// A4 sales order PDF generation — PORTING.md §12. The web app has no
// `SalesOrderTemplateA4.tsx` (only invoice/quotation), so this follows the
// same A4 conventions as `features/sales/invoice_pdf.dart` and
// `features/quotations/quotation_pdf.dart`, adapted to the sales-order
// vocabulary and the `SalesOrderDetail` shape:
//   header (company block + SALES ORDER title/no/status chip)
//   Bill To + Order Date / Delivery Date / Warehouse details
//   items table (Item | Qty | Delivered? | Rate | Amount — the Delivered
//     column appears only when any line has a delivered quantity)
//   summary (notes left; subtotal/total right)
//   footer ("Thank you for your business!" + contact line)
//
// Labels are English like the other PDF templates. Urdu/RTL PDF text needs
// an arabic-shaping font and is out of scope (the on-screen app remains
// fully localized).

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/utils/formatters.dart';
import '../../data/models/invoice.dart' show CompanyInfo;
import '../../data/models/sales_order.dart'
    show SalesOrderDetail, SalesOrderItem;
import '../sales/models/sales_forms.dart' show defaultCompany;

/// Accent color — the DESIGN.md emerald (matches the app's primary).
const PdfColor _accent = PdfColor.fromInt(0xFF059669);

/// Builds the A4 sales order PDF bytes for [salesOrder]. [company]
/// overrides the default company block (sales orders carry no company of
/// their own, so it falls back to [defaultCompany]).
Future<Uint8List> buildA4SalesOrderPdf({
  required SalesOrderDetail salesOrder,
  CompanyInfo? company,
}) async {
  final usedCompany = company ?? defaultCompany;
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      footer: (context) => _buildFooter(usedCompany),
      build: (context) => [
        _buildHeader(usedCompany, salesOrder),
        pw.SizedBox(height: 16),
        _buildInfoSection(salesOrder),
        pw.SizedBox(height: 16),
        _buildItemsTable(salesOrder),
        pw.SizedBox(height: 16),
        _buildSummarySection(salesOrder),
      ],
    ),
  );
  return doc.save();
}

// ── Header ──────────────────────────────────────────────────────────

pw.Widget _buildHeader(CompanyInfo company, SalesOrderDetail salesOrder) {
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
      // SALES ORDER title + number + status chip.
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text(
            'SALES ORDER',
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
              color: _accent,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            salesOrder.soNo.isEmpty ? 'N/A' : salesOrder.soNo,
            style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 6),
          _statusChip(salesOrder.status.isEmpty ? 'Draft' : salesOrder.status),
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

/// Status chip — same palette as `soStatusColors` in
/// `core/utils/so_status.dart` (draft blue-grey, confirmed blue,
/// delivered/completed green, invoiced teal, cancelled grey).
PdfColor _statusColor(String status) => switch (status) {
  'Confirmed' => PdfColor.fromInt(0xFF2563EB),
  'Delivered' || 'Completed' => PdfColor.fromInt(0xFF16A34A),
  'Invoiced' => PdfColor.fromInt(0xFF0D9488),
  'Cancelled' => PdfColor.fromInt(0xFF6B7280),
  _ => PdfColor.fromInt(0xFF64748B), // Draft + unknown
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

pw.Widget _buildInfoSection(SalesOrderDetail salesOrder) {
  final delivery = salesOrder.deliveryDate ?? '';
  final warehouse = salesOrder.warehouseName ?? '';
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
              salesOrder.customerName.trim().isEmpty
                  ? 'N/A'
                  : salesOrder.customerName,
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
            _detailRow('Order Date', Formatters.date(salesOrder.soDate)),
            pw.SizedBox(height: 3),
            _detailRow(
              // Plain '-' rather than an em-dash: Helvetica (the default
              // PDF font) has no U+2014 glyph, which renders as tofu.
              'Delivery Date',
              delivery.isEmpty ? '-' : Formatters.date(delivery),
            ),
            if (warehouse.trim().isNotEmpty) ...[
              pw.SizedBox(height: 3),
              _detailRow('Warehouse', warehouse.trim()),
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

pw.Widget _buildItemsTable(SalesOrderDetail salesOrder) {
  final items = salesOrder.items;
  // The Delivered column appears only when a line has a partial/full
  // delivery to report (conditional-column convention of the other A4
  // templates).
  final hasDelivered = items.any((i) => (i.deliveredQuantity ?? 0) > 0);

  final widths = <int, pw.TableColumnWidth>{
    for (final (index, width) in [
      const pw.FlexColumnWidth(3),
      const pw.FlexColumnWidth(0.8),
      if (hasDelivered) const pw.FlexColumnWidth(1),
      const pw.FlexColumnWidth(1.2),
      const pw.FlexColumnWidth(1.3),
    ].indexed)
      index: width,
  };

  final header = [
    _headerCell('Item'),
    _headerCell('Qty', right: true),
    if (hasDelivered) _headerCell('Delivered', right: true),
    _headerCell('Rate', right: true),
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
            children: _itemCell(item, hasDelivered: hasDelivered),
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
List<pw.Widget> _itemCell(SalesOrderItem item, {required bool hasDelivered}) {
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

  // Item name with the item code beneath it (A4-template convention).
  final nameCell = pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          item.itemName.trim().isEmpty ? 'N/A' : item.itemName,
          style: pw.TextStyle(fontSize: 9.5),
        ),
        if (item.itemCode.trim().isNotEmpty)
          pw.Text(
            item.itemCode.trim(),
            style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
      ],
    ),
  );

  return [
    nameCell,
    cell(_number(item.quantity), right: true),
    if (hasDelivered)
      cell(_number(item.deliveredQuantity ?? 0), right: true),
    cell(_currency(item.unitPrice), right: true),
    cell(_currency(_lineAmount(item)), right: true, bold: true),
  ];
}

/// The server derives `amount` from the line; fall back to qty × rate.
num _lineAmount(SalesOrderItem item) =>
    item.amount ?? item.quantity * item.unitPrice;

// ── Summary ─────────────────────────────────────────────────────────

pw.Widget _buildSummarySection(SalesOrderDetail salesOrder) {
  final notes = salesOrder.notes ?? '';
  final subtotal = _subtotal(salesOrder);

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      // Left: notes.
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
            pw.SizedBox(height: 5),
            pw.Container(
              height: 0.6,
              color: PdfColors.grey400,
            ),
            pw.SizedBox(height: 5),
            _totalRow('Total', _currency(salesOrder.totalAmount), bold: true),
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

/// Σ line amounts (with qty × rate fallback) — the SO has no line
/// discounts/taxes, so this equals the server's `total_amount`.
num _subtotal(SalesOrderDetail salesOrder) =>
    salesOrder.items.fold<num>(0, (sum, i) => sum + _lineAmount(i));

String _currency(num value) => Formatters.currency(value);

String _number(num value) => Formatters.number(value);
