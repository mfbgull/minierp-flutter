// A4 purchase order PDF generation — PORTING.md §12. Dart port of the web
// `references/components/invoice/PurchaseOrderTemplateA4.tsx` layout using
// the `pdf` package (already a pubspec dependency). The print dialog lives
// in the PO form and detail dialog; this file only builds the bytes.
//
// Layout mirrors the reference template:
//   header (company block + PURCHASE ORDER title/no/status chip)
//   Supplier + PO Date / Expected Delivery / Warehouse details (the
//     delivery/warehouse rows render only when present)
//   items table (Item | Qty | UOM | Unit Price | Total)
//   summary (notes left; Total Amount right)
//   footer ("Thank you for your prompt service!" + contact line)
//
// Labels are English like the reference template. Urdu/RTL PDF text needs
// an arabic-shaping font and is out of scope (the on-screen app remains
// fully localized).

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/utils/formatters.dart';
import '../../data/models/invoice.dart' show CompanyInfo;
import '../../data/models/purchase_order.dart'
    show PurchaseOrderDetail, PurchaseOrderItem;
import '../sales/models/sales_forms.dart' show defaultCompany;

/// Accent color — the DESIGN.md emerald (matches the app's primary).
const PdfColor _accent = PdfColor.fromInt(0xFF059669);

/// Builds the A4 purchase order PDF bytes for [purchaseOrder]. [company]
/// overrides the default company block (POs carry no company of their
/// own, so it falls back to [defaultCompany]).
Future<Uint8List> buildA4PurchaseOrderPdf({
  required PurchaseOrderDetail purchaseOrder,
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
        _buildHeader(usedCompany, purchaseOrder),
        pw.SizedBox(height: 16),
        _buildInfoSection(purchaseOrder),
        pw.SizedBox(height: 16),
        _buildItemsTable(purchaseOrder),
        pw.SizedBox(height: 16),
        _buildSummarySection(purchaseOrder),
      ],
    ),
  );
  return doc.save();
}

// ── Header ──────────────────────────────────────────────────────────

pw.Widget _buildHeader(CompanyInfo company, PurchaseOrderDetail purchaseOrder) {
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
                ],
              ),
            ),
          ],
        ),
      ),
      // PURCHASE ORDER title + number + status chip.
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text(
            'PURCHASE ORDER',
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
              color: _accent,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            purchaseOrder.poNo.isEmpty ? 'N/A' : purchaseOrder.poNo,
            style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 6),
          _statusChip(
            purchaseOrder.status.isEmpty ? 'Draft' : purchaseOrder.status,
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

/// Status chip — same palette as `poStatusColors` in
/// `core/utils/po_status.dart` (draft blue-grey, submitted blue,
/// partially-received amber, completed green, cancelled grey).
PdfColor _statusColor(String status) => switch (status) {
  'Submitted' => PdfColor.fromInt(0xFF2563EB),
  'Partially Received' => PdfColor.fromInt(0xFFD97706),
  'Completed' => PdfColor.fromInt(0xFF16A34A),
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

// ── Supplier + details ──────────────────────────────────────────────

pw.Widget _buildInfoSection(PurchaseOrderDetail purchaseOrder) {
  final expected = purchaseOrder.expectedDeliveryDate ?? '';
  final warehouse = purchaseOrder.warehouseName ?? '';
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        flex: 3,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _sectionLabel('Supplier'),
            pw.SizedBox(height: 4),
            pw.Text(
              purchaseOrder.supplierName.trim().isEmpty
                  ? 'N/A'
                  : purchaseOrder.supplierName,
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
            _detailRow('PO Date', Formatters.date(purchaseOrder.poDate)),
            // Delivery + warehouse render only when present (reference
            // template's conditional rows).
            if (expected.trim().isNotEmpty) ...[
              pw.SizedBox(height: 3),
              _detailRow('Expected Delivery', Formatters.date(expected)),
            ],
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

pw.Widget _buildItemsTable(PurchaseOrderDetail purchaseOrder) {
  final items = purchaseOrder.items;

  const widths = <int, pw.TableColumnWidth>{
    0: pw.FlexColumnWidth(3),
    1: pw.FlexColumnWidth(0.8),
    2: pw.FlexColumnWidth(1),
    3: pw.FlexColumnWidth(1.2),
    4: pw.FlexColumnWidth(1.3),
  };

  final header = [
    _headerCell('Item'),
    _headerCell('Qty', right: true),
    _headerCell('UOM', right: true),
    _headerCell('Unit Price', right: true),
    _headerCell('Total', right: true),
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
          pw.TableRow(children: _itemCell(item)),
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
List<pw.Widget> _itemCell(PurchaseOrderItem item) {
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
    // Reference template defaults the UOM to 'Nos' when empty.
    cell(item.unitOfMeasure.trim().isEmpty ? 'Nos' : item.unitOfMeasure,
        right: true),
    cell(_currency(item.unitPrice), right: true),
    cell(_currency(_lineAmount(item)), right: true, bold: true),
  ];
}

/// The server derives `amount` from the line; fall back to qty × rate
/// (reference template's `safeParseFloat(item.amount ?? qty * rate)`).
num _lineAmount(PurchaseOrderItem item) =>
    item.amount ?? item.quantity * item.unitPrice;

// ── Summary ─────────────────────────────────────────────────────────

pw.Widget _buildSummarySection(PurchaseOrderDetail purchaseOrder) {
  final notes = purchaseOrder.notes ?? '';

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
      // Right: the reference shows a single grand Total Amount row.
      pw.Expanded(
        flex: 2,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.SizedBox(height: 5),
            pw.Container(
              height: 0.6,
              color: PdfColors.grey400,
            ),
            pw.SizedBox(height: 5),
            _totalRow(
              'Total Amount',
              _currency(purchaseOrder.totalAmount),
              bold: true,
            ),
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
          'Thank you for your prompt service!',
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

// ── Formatting ──────────────────────────────────────────────────────

String _currency(num value) => Formatters.currency(value);

String _number(num value) => Formatters.number(value);
