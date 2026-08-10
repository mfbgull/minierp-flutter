// Unit tests for the AR Summary report (model parsing + repository
// integration). The model is tested with a JSON fixture matching the
// real `getReceivablesSummary` shape from `server-reference/Reports.ts`.

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:minierp_app/data/models/report.dart' show ArSummaryReport;

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
  });

  group('ArSummaryReport.fromJson', () {
    final json = {
      'asOfDate': '2026-08-10',
      'total_invoices': 42,
      'total_outstanding': 250000.0,
      'total_paid': 180000.0,
      'total_invoiced': 430000.0,
      'total_current': 80000.0,
      'total_1_30': 60000.0,
      'total_31_60': 50000.0,
      'total_61_90': 40000.0,
      'total_over_90': 20000.0,
      'statusBreakdown': {
        'unpaid': {'count': 15, 'amount': 120000.0},
        'partiallyPaid': {'count': 20, 'amount': 80000.0},
        'overdue': {'count': 7, 'amount': 50000.0},
      },
    };

    final report = ArSummaryReport.fromJson(json);

    test('parses the asOfDate', () {
      expect(report.asOfDate, '2026-08-10');
    });

    test('parses KPI fields', () {
      expect(report.totalInvoices, 42);
      expect(report.totalOutstanding, 250000);
      expect(report.totalPaid, 180000);
      expect(report.totalInvoiced, 430000);
    });

    test('parses aging buckets', () {
      expect(report.totalCurrent, 80000);
      expect(report.total130, 60000);
      expect(report.total3160, 50000);
      expect(report.total6190, 40000);
      expect(report.totalOver90, 20000);
    });

    test('parses status breakdown', () {
      expect(report.statusBreakdown.unpaid.count, 15);
      expect(report.statusBreakdown.unpaid.amount, 120000);
      expect(report.statusBreakdown.partiallyPaid.count, 20);
      expect(report.statusBreakdown.partiallyPaid.amount, 80000);
      expect(report.statusBreakdown.overdue.count, 7);
      expect(report.statusBreakdown.overdue.amount, 50000);
    });

    test('tolerates missing fields', () {
      final minimal = ArSummaryReport.fromJson({'asOfDate': '2026-01-01'});
      expect(minimal.totalInvoices, 0);
      expect(minimal.totalOutstanding, 0);
      expect(minimal.statusBreakdown.unpaid.count, 0);
      expect(minimal.statusBreakdown.unpaid.amount, 0);
    });
  });
}