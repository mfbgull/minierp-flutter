// POS thermal (80mm) receipt PDF — built from a completed [PosSale].
// Mirrors the invoice thermal template (`thermal_invoice_pdf.dart`) but
// for the walk-in POS flow: no customer ledger, no payment history — just
// the sale lines, totals, cash tendered, and change.
//
// Labels are English (the POS thermal printer is a retail device); Urdu/
// RTL thermal text is out of scope (PORTING.md §12).

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show Color;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr_flutter/qr_flutter.dart' as qr;

import 'pos_models.dart';

/// Page width for 80mm thermal paper (~226.77pt at 72 DPI).
const double _kPosThermalWidth = 226.77;

/// Builds the POS thermal receipt PDF bytes for [sale].
Future<Uint8List> buildPosThermalReceiptPdf(PosSale sale) async {
  final qrData =
      'POS:${sale.transactionNo}|TOTAL:${_fmtCurrency(sale.total)}|'
      'CASH:${_fmtCurrency(sale.cashReceived)}|'
      'CHANGE:${_fmtCurrency(sale.change)}';
  final qrImage = await _generateQrImage(qrData);

  final doc = pw.Document();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat(
        _kPosThermalWidth,
        PdfPageFormat.a4.height, // roll paper — height is unlimited
        marginAll: 12,
      ),
      margin: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      build: (context) => [
        _buildHeader(),
        _buildDivider(),
        _buildTransactionInfo(sale),
        _buildDivider(),
        _buildCustomerInfo(sale),
        _buildDivider(),
        _buildItemsTable(sale),
        _buildDivider(),
        _buildTotals(sale),
        _buildQr(qrImage),
        _buildDivider(),
        _buildFooter(),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _buildHeader() => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          'MINIERP',
          style: pw.TextStyle(
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.Text(
          'Point of Sale Receipt',
          style: pw.TextStyle(fontSize: 10),
        ),
      ],
    );

pw.Widget _buildDivider() => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Container(
        height: 0.5,
        color: PdfColors.grey400,
      ),
    );

pw.Widget _buildTransactionInfo(PosSale sale) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _infoLine('Transaction: ${sale.transactionNo}'),
        _infoLine('Date: ${sale.saleDate}'),
        _infoLine('Warehouse: ${sale.warehouseName}'),
      ],
    );

pw.Widget _buildCustomerInfo(PosSale sale) => _infoLine(
      'Customer: ${sale.customerName.isEmpty ? "Walk-in" : sale.customerName}',
    );

pw.Widget _buildItemsTable(PosSale sale) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          children: [
            pw.Expanded(
              flex: 4,
              child: pw.Text(
                'ITEM',
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Expanded(
              flex: 1,
              child: pw.Text(
                'QTY',
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                ),
                textAlign: pw.TextAlign.right,
              ),
            ),
            pw.Expanded(
              flex: 2,
              child: pw.Text(
                'AMOUNT',
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                ),
                textAlign: pw.TextAlign.right,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 2),
        for (final line in sale.items)
          pw.Row(
            children: [
              pw.Expanded(
                flex: 4,
                child: pw.Text(
                  line.itemName,
                  style: const pw.TextStyle(fontSize: 9),
                  maxLines: 2,
                  overflow: pw.TextOverflow.clip,
                ),
              ),
              pw.Expanded(
                flex: 1,
                child: pw.Text(
                  '${line.quantity}',
                  style: const pw.TextStyle(fontSize: 9),
                  textAlign: pw.TextAlign.right,
                ),
              ),
              pw.Expanded(
                flex: 2,
                child: pw.Text(
                  _fmtCurrency(line.lineTotal),
                  style: const pw.TextStyle(fontSize: 9),
                  textAlign: pw.TextAlign.right,
                ),
              ),
            ],
          ),
      ],
    );

pw.Widget _buildTotals(PosSale sale) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _totalRow('Subtotal', _fmtCurrency(sale.subtotal)),
        _totalRowBold('Total', _fmtCurrency(sale.total)),
        _totalRow('Cash Received', _fmtCurrency(sale.cashReceived)),
        _totalRowBold('Change', _fmtCurrency(sale.change)),
      ],
    );

pw.Widget _buildQr(pw.MemoryImage? qrImage) => pw.Center(
      child: qrImage != null
          ? pw.Column(
              children: [
                pw.SizedBox(height: 4),
                pw.Image(qrImage, width: 50, height: 50),
              ],
            )
          : pw.SizedBox(),
    );

pw.Widget _buildFooter() => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          'Thank you for your purchase',
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
          ),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'Returns accepted within 7 days with receipt',
          style: pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
          textAlign: pw.TextAlign.center,
        ),
      ],
    );

// ── Helpers ─────────────────────────────────────────────────────────

pw.Widget _infoLine(String text) => pw.Text(
      text,
      style: const pw.TextStyle(fontSize: 9),
    );

pw.Widget _totalRow(String label, String value) => pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
        pw.Text(value, style: const pw.TextStyle(fontSize: 9)),
      ],
    );

pw.Widget _totalRowBold(String label, String value) => pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );

String _fmtCurrency(num value) => '\$${value.toStringAsFixed(2)}';

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
