// Thermal (80mm) personal-loan repayment receipt PDF.
//
// Layout:
//   - company header
//   - REPAYMENT RECEIPT title + loan no + borrower
//   - Payment History table (Date | Receipt# | Amount)
//   - totals and new balance
//   - footer
//
// Labels are English to match the existing thermal templates.
// Urdu/RTL PDF text needs an arabic-shaping font and is out of scope.

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/models/invoice.dart' show CompanyInfo;
import '../../features/sales/models/sales_forms.dart' show defaultCompany;
import 'personal_loan_models.dart';

/// Page width for 80mm thermal paper (~226.77pt).
const double _kThermalWidth = 226.77;

/// Accent color matching the app theme.
const PdfColor _accent = PdfColor.fromInt(0xFF059669);

/// Builds the thermal (80mm) repayment-receipt PDF bytes for [repayment].
///
/// [loan] provides the borrower/balance context. [company] overrides the
/// default company block. [allRepayments] should be ordered ASC by date.
Future<Uint8List> buildThermalRepaymentReceiptPdf(
  PersonalLoan loan,
  PersonalLoanRepayment repayment, {
  CompanyInfo? company,
  List<PersonalLoanRepayment>? allRepayments,
}) async {
  final usedCompany = company ?? defaultCompany;
  final history = allRepayments ?? <PersonalLoanRepayment>[repayment];
  final totals = _historyTotals(loan, history);
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
        _buildReceiptInfo(loan, repayment, totals.currentReceiptNo),
        _buildDivider(),
        _buildBorrowerInfo(loan),
        _buildDivider(),
        _buildPaymentHistory(loan, repayment, history),
        _buildDivider(),
        _buildTotals(totals, loan.amount),
        _buildDivider(),
        _buildNewBalance(totals.newBalance),
        _buildDividerDouble(),
        _buildFooter(usedCompany),
      ],
    ),
  );

  return doc.save();
}

class _HistoryTotals {
  const _HistoryTotals({
    required this.totalPaid,
    required this.newBalance,
    required this.currentReceiptNo,
  });

  final num totalPaid;
  final num newBalance;
  final String currentReceiptNo;
}

_HistoryTotals _historyTotals(
  PersonalLoan loan,
  List<PersonalLoanRepayment> history,
) {
  var running = loan.amount;
  num totalPaid = 0;
  String currentReceiptNo = 'RPT-${history.length.toString().padLeft(3, '0')}';
  for (var i = 0; i < history.length; i++) {
    final r = history[i];
    totalPaid += r.amount;
    running -= r.amount;
    if (r.id == history.last.id) {
      currentReceiptNo = 'RPT-${(i + 1).toString().padLeft(3, '0')}';
    }
  }
  return _HistoryTotals(
    totalPaid: totalPaid,
    newBalance: running.clamp(0, loan.amount),
    currentReceiptNo: currentReceiptNo,
  );
}

// ── Sections ─────────────────────────────────────────────────────────

pw.Widget _buildHeader(CompanyInfo company) {
  final name = company.name.trim().isEmpty ? 'Mini ERP' : company.name.trim();
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.Text(
        name,
        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
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

pw.Widget _buildReceiptInfo(
  PersonalLoan loan,
  PersonalLoanRepayment repayment,
  String receiptNo,
) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Center(
        child: pw.Text(
          'REPAYMENT RECEIPT',
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: _accent,
          ),
          textAlign: pw.TextAlign.center,
        ),
      ),
      pw.SizedBox(height: 4),
      _infoLine('Loan: ${loan.loanNo.isEmpty ? 'N/A' : loan.loanNo}'),
      _infoLine('Receipt: $receiptNo'),
    ],
  );
}

pw.Widget _buildBorrowerInfo(PersonalLoan loan) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        loan.borrowerName.isEmpty ? 'Borrower' : loan.borrowerName,
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
      ),
      if (loan.borrowerType != null && loan.borrowerType!.isNotEmpty)
        pw.Text(
          'Type: ${loan.borrowerType}',
          style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
    ],
  );
}

pw.Widget _buildPaymentHistory(
  PersonalLoan loan,
  PersonalLoanRepayment repayment,
  List<PersonalLoanRepayment> allRepayments,
) {
  final header = pw.Row(
    children: [
      pw.Expanded(
        flex: 3,
        child: pw.Text(
          'Date',
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        ),
      ),
      pw.Expanded(
        flex: 2,
        child: pw.Text(
          'Receipt#',
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        ),
      ),
      pw.Expanded(
        flex: 2,
        child: pw.Text(
          'Amount',
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        ),
      ),
    ],
  );

  final rows = <pw.Widget>[];
  for (var i = 0; i < allRepayments.length; i++) {
    final r = allRepayments[i];
    final isCurrent = r.id == repayment.id;
    rows.add(
      pw.Row(
        children: [
          pw.Expanded(
            flex: 3,
            child: pw.Text(
              _fmtDateShort(r.paymentDate),
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: isCurrent ? pw.FontWeight.bold : null,
              ),
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Text(
              'RPT-${(i + 1).toString().padLeft(3, '0')}',
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: isCurrent ? pw.FontWeight.bold : null,
              ),
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Text(
              _fmtCurrency(r.amount),
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: isCurrent ? pw.FontWeight.bold : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        'Payment History',
        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 2),
      header,
      pw.SizedBox(height: 2),
      ...rows,
    ],
  );
}

pw.Widget _buildTotals(_HistoryTotals totals, num borrowed) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _totalRow('Total Paid', _fmtCurrency(totals.totalPaid)),
      _totalRow('Total Borrowed', _fmtCurrency(-borrowed)),
    ],
  );
}

pw.Widget _buildNewBalance(num newBalance) {
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(
        'New Balance',
        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      ),
      pw.Text(
        _fmtCurrency(newBalance),
        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      ),
    ],
  );
}

pw.Widget _buildFooter(CompanyInfo company) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.Text(
        'Thank you.',
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

// ── Helpers ──────────────────────────────────────────────────────────

pw.Widget _infoLine(String text) => pw.Text(
  text,
  style: pw.TextStyle(fontSize: 9),
);

pw.Widget _buildDivider() => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(vertical: 4),
  child: pw.Container(height: 0.5, color: PdfColors.grey400),
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

String _fmtDateShort(String iso) {
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return iso;
  return '${parsed.month}-${parsed.day}-${parsed.year}';
}

String _fmtCurrency(num value) {
  final symbol = 'Rs.';
  final text = value.abs().toStringAsFixed(2);
  final padded = text.padLeft(10);
  return value < 0 ? '-$symbol $padded' : '$symbol $padded';
}
