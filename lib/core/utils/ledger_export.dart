// Shared ledger export helpers — CSV / A4-landscape PDF builders used by
// the customer and supplier detail Ledger tabs (and the ledger dialogs'
// export buttons). Generalized from the customer module so both entity
// types reuse one implementation: callers pass the entity name for the
// title line and an optional [LedgerExportLabels] for localized column
// headers (defaults to the customer keys; the supplier tab passes its
// own `suppliersLedger*` keys).
//
// The builders are pure functions (no context, no plugins) so the row
// logic is unit-testable in isolation; the save/print plumbing lives in
// the tabs. The rows mirror the ledger table: Date | Type | Reference |
// Description | Debit | Credit | Balance with a Totals row (debit/credit/
// net) appended.

import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/models/ledger_entry.dart' show LedgerEntry;
import '../../l10n/app_localizations.dart';
import 'csv_export.dart' show sanitizeCsvCell;
import 'formatters.dart';

/// Localized column labels for the ledger export (the rows' header set).
class LedgerExportLabels {
  const LedgerExportLabels({
    required this.type,
    required this.debit,
    required this.credit,
    required this.balance,
    required this.totals,
  });

  final String type;
  final String debit;
  final String credit;
  final String balance;
  final String totals;

  /// Customer-module defaults (customersLedger* keys).
  factory LedgerExportLabels.customer(AppLocalizations l10n) =>
      LedgerExportLabels(
        type: l10n.customersLedgerType,
        debit: l10n.customersLedgerDebit,
        credit: l10n.customersLedgerCredit,
        balance: l10n.customersBalance,
        totals: l10n.customersLedgerTotals,
      );

  /// Supplier-module labels (suppliersLedger* keys).
  factory LedgerExportLabels.supplier(AppLocalizations l10n) =>
      LedgerExportLabels(
        type: l10n.suppliersLedgerType,
        debit: l10n.suppliersLedgerDebit,
        credit: l10n.suppliersLedgerCredit,
        balance: l10n.suppliersBalance,
        totals: l10n.suppliersLedgerTotals,
      );
}

/// Precomputed export rows + totals for [ledger].
class LedgerExportData {
  const LedgerExportData({required this.rows, required this.totals});

  final List<List<String>> rows;

  /// (totalDebit, totalCredit, netBalance).
  final (double, double, double) totals;
}

LedgerExportData prepareLedgerExport(
  AppLocalizations l10n,
  List<LedgerEntry> ledger, {
  LedgerExportLabels? labels,
}) {
  var debit = 0.0;
  var credit = 0.0;
  final rows = <List<String>>[];
  for (final entry in ledger) {
    debit += entry.debit;
    credit += entry.credit;
    rows.add([
      entry.transactionDate.isEmpty
          ? '—'
          : Formatters.date(entry.transactionDate),
      sanitizeCsvCell(entry.transactionType),
      sanitizeCsvCell(entry.referenceNo),
      sanitizeCsvCell(entry.description),
      entry.debit > 0 ? Formatters.currency(entry.debit) : '',
      entry.credit > 0 ? Formatters.currency(entry.credit) : '',
      Formatters.currency(entry.balance),
    ]);
  }
  return LedgerExportData(
    rows: rows,
    totals: (debit, credit, debit - credit),
  );
}

/// Builds the CSV text (title + generated line + header + rows + totals).
/// [titleLabel] is the ledger title (`Customer Ledger` / `Supplier
/// Ledger`); [entityName] is appended for the entity being exported.
String buildLedgerCsv(
  AppLocalizations l10n,
  List<LedgerEntry> ledger, {
  String? entityName,
  String titleLabel = 'Customer Ledger',
  LedgerExportLabels? labels,
}) {
  final effective = labels ?? LedgerExportLabels.customer(l10n);
  final data = prepareLedgerExport(l10n, ledger, labels: effective);
  final headers = [
    l10n.commonDate,
    effective.type,
    l10n.fieldsReference,
    l10n.commonDescription,
    effective.debit,
    effective.credit,
    effective.balance,
  ];
  final totals = data.totals;
  final csv = Csv().encode([
    ['$titleLabel${entityName == null ? '' : ' - $entityName'}'],
    ['Generated: ${DateTime.now().toIso8601String().split('T').first}'],
    const [],
    headers,
    ...data.rows,
    [
      '',
      '',
      '',
      effective.totals,
      Formatters.currency(totals.$1),
      Formatters.currency(totals.$2),
      Formatters.currency(totals.$3),
    ],
  ]);
  return csv;
}

/// Builds the A4-landscape ledger PDF bytes (title, generated line,
/// header row, data rows, totals row — web `exportToPDF` equivalent).
Future<Uint8List> buildLedgerPdf(
  AppLocalizations l10n,
  List<LedgerEntry> ledger, {
  String? entityName,
  String titleLabel = 'Customer Ledger',
  LedgerExportLabels? labels,
}) async {
  final effective = labels ?? LedgerExportLabels.customer(l10n);
  final data = prepareLedgerExport(l10n, ledger, labels: effective);
  final totals = data.totals;
  final headers = [
    l10n.commonDate,
    effective.type,
    l10n.fieldsReference,
    l10n.commonDescription,
    effective.debit,
    effective.credit,
    effective.balance,
  ];
  final rows = [
    ...data.rows,
    [
      '',
      '',
      '',
      effective.totals,
      Formatters.currency(totals.$1),
      Formatters.currency(totals.$2),
      Formatters.currency(totals.$3),
    ],
  ];

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => [
        pw.Text(
          '$titleLabel${entityName == null ? '' : ' - $entityName'}',
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromInt(0xFF059669),
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'Generated: ${DateTime.now().toIso8601String().split('T').first}',
          style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: rows,
          headerStyle: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
          headerDecoration: pw.BoxDecoration(
            color: PdfColor.fromInt(0xFF059669),
          ),
          cellStyle: const pw.TextStyle(fontSize: 8),
          cellAlignments: {
            4: pw.Alignment.centerRight,
            5: pw.Alignment.centerRight,
            6: pw.Alignment.centerRight,
          },
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          oddRowDecoration: pw.BoxDecoration(color: PdfColors.grey100),
        ),
      ],
    ),
  );
  return doc.save();
}
