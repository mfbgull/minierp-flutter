// Thermal (80mm) payment receipt PDF — PORTING.md §12. Generates a narrow
// receipt PDF for thermal printers using the `pdf` package. The layout
// mirrors the React reference `ThermalPaymentReceipt.tsx`:
//   header (company name + contact)
//   PAYMENT RECEIPT title + receipt number + date
//   customer/supplier name
//   balance trail (previous balance, payment, new balance)
//   payment details (method, reference)
//   invoice allocations table
//   footer (thank-you + contact)
//
// Labels are English like the reference template.

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/models/invoice.dart' show CompanyInfo;
import '../../data/models/payment.dart' show Payment;
import '../sales/models/sales_forms.dart' show defaultCompany;

/// Page width for 80mm thermal paper (~226.77pt).
const double _kThermalWidth = 226.77;

/// Accent color — the DESIGN.md emerald.
const PdfColor _accent = PdfColor.fromInt(0xFF059669);

/// Builds the thermal (80mm) payment-receipt PDF bytes for [payment].
/// [company] overrides the default company block; [entityName] overrides
/// the customer/supplier name shown on the receipt; [previousBalance]
/// and [allocations] show the balance trail and invoice allocations.
Future<Uint8List> buildThermalPaymentReceiptPdf(
  Payment payment, {
  CompanyInfo? company,
  String? entityName,
  num previousBalance = 0,
  List<PaymentAllocation>? allocations,
}) async {
  final usedCompany = company ?? defaultCompany;
  final doc = pw.Document();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat(
        _kThermalWidth,
        PdfPageFormat.a4.height,
        marginAll: 12,
      ),
      margin: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      build: (context) => [
        _buildHeader(usedCompany),
        _buildDivider(),
        _buildReceiptInfo(payment),
        _buildDivider(),
        _buildCustomerInfo(payment, entityName),
        _buildDivider(),
        _buildBalanceTrail(payment, previousBalance),
        _buildDivider(),
        _buildPaymentDetails(payment),
        if (allocations != null && allocations.isNotEmpty) ...[
          _buildDivider(),
          _buildAllocations(allocations, payment),
        ],
        _buildDividerDouble(),
        _buildFooter(usedCompany, payment),
      ],
    ),
  );

  return doc.save();
}

/// Invoice allocation line.
class PaymentAllocation {
  const PaymentAllocation({
    required this.invoiceNo,
    required this.amount,
  });

  final String invoiceNo;
  final num amount;
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

// ── Receipt Info ────────────────────────────────────────────────────

pw.Widget _buildReceiptInfo(Payment payment) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Center(
        child: pw.Text(
          'PAYMENT RECEIPT',
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: _accent,
          ),
          textAlign: pw.TextAlign.center,
        ),
      ),
      pw.SizedBox(height: 4),
      _infoLine('Receipt: ${payment.paymentNo.isEmpty ? 'N/A' : payment.paymentNo}'),
      _infoLine('Date: ${_fmtDate(payment.paymentDate)}'),
    ],
  );
}

// ── Customer Info ───────────────────────────────────────────────────

pw.Widget _buildCustomerInfo(Payment payment, String? entityName) {
  final isSupplier = payment.supplierId != null;
  final resolvedName = entityName?.trim().isNotEmpty == true
      ? entityName!
      : isSupplier
          ? (payment.supplierName?.trim().isNotEmpty == true
              ? payment.supplierName!
              : 'Supplier #${payment.supplierId}')
          : payment.customerName?.trim().isNotEmpty == true
              ? payment.customerName!
              : 'Customer #${payment.customerId}';

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        resolvedName,
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
      ),
    ],
  );
}

// ── Balance Trail ───────────────────────────────────────────────────

pw.Widget _buildBalanceTrail(Payment payment, num previousBalance) {
  final paymentAmount = payment.amount;
  final currentBalance = previousBalance - paymentAmount;

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _totalRow('Prev Balance', _fmtCurrency(previousBalance)),
      _totalRow('Payment', '-${_fmtCurrency(paymentAmount)}'),
      _totalRowBold('New Balance', _fmtCurrency(currentBalance)),
    ],
  );
}

// ── Payment Details ─────────────────────────────────────────────────

pw.Widget _buildPaymentDetails(Payment payment) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _infoLine('Method: ${payment.paymentMethod}'),
      if (payment.referenceNo != null && payment.referenceNo!.trim().isNotEmpty)
        _infoLine('Ref: ${payment.referenceNo}'),
    ],
  );
}

// ── Allocations ─────────────────────────────────────────────────────

pw.Widget _buildAllocations(List<PaymentAllocation> allocations, Payment payment) {
  final isSupplier = payment.supplierId != null;
  final label = isSupplier ? 'PO' : 'INVOICE';
  final totalAmount = allocations.fold<num>(0, (s, a) => s + a.amount);

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      // Header
      pw.Row(
        children: [
          pw.Expanded(
            flex: 3,
            child: pw.Text(
              label,
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
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
      // Allocation rows
      for (final a in allocations)
        pw.Row(
          children: [
            pw.Expanded(
              flex: 3,
              child: pw.Text(
                a.invoiceNo,
                style: pw.TextStyle(fontSize: 9),
              ),
            ),
            pw.Expanded(
              flex: 2,
              child: pw.Text(
                _fmtCurrency(a.amount),
                style: pw.TextStyle(fontSize: 9),
                textAlign: pw.TextAlign.right,
              ),
            ),
          ],
        ),
      pw.SizedBox(height: 2),
      _totalRowBold('Total', _fmtCurrency(totalAmount)),
    ],
  );
}

// ── Footer ──────────────────────────────────────────────────────────

pw.Widget _buildFooter(CompanyInfo company, Payment payment) {
  final isSupplier = payment.supplierId != null;
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.Text(
        isSupplier ? 'Payment recorded.' : 'Thank you for your payment!',
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
