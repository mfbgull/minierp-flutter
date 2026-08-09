import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/data/models/bom.dart';
import 'package:minierp_app/data/models/customer.dart';
import 'package:minierp_app/data/models/dashboard_summary.dart';
import 'package:minierp_app/data/models/invoice.dart';
import 'package:minierp_app/data/models/item.dart';
import 'package:minierp_app/data/models/production.dart';
import 'package:minierp_app/data/models/report.dart';
import 'package:minierp_app/data/models/supplier.dart';

/// Parses the real API payloads captured from the bundled live server
/// (test/fixtures/*.json) through the Dart models.
///
/// Regenerate fixtures against a running server (PORTING.md §0, admin /
/// admin123) with:
///   GET /api/customers?page=1&limit=50   -> customers.json
///   GET /api/inventory/items             -> items.json
///   GET /api/suppliers?page=1&limit=50   -> suppliers.json
///   GET /api/invoices                    -> invoices.json
///   GET /api/invoices/:id                -> invoice_detail.json
///   GET /api/reports/ar-aging            -> ar_aging.json
///   GET /api/reports/sales-summary?...   -> sales_summary.json
///   GET /api/reports/low-stock           -> low_stock.json
///   GET /api/reports/stock-level         -> stock_level.json
///   GET /api/reports/stock-valuation     -> stock_valuation.json
///   GET /api/reports/sales-by-customer?... -> sales_by_customer.json
///                                          (saved as the bare data array)
///   GET /api/reports/dso?...               -> dso.json
///   GET /api/reports/cash-flow?...         -> cash_flow.json
///   GET /api/reports/profit-loss?...       -> profit_loss.json
///   GET /api/reports/inventory-movement?... -> inventory_movement.json
///   GET /api/reports/purchase-summary?...   -> purchase_summary.json
///   GET /api/reports/top-debtors?limit=10   -> top_debtors.json
///                                          (saved as the bare data array)
///   GET /api/dashboard/top-customers?limit=5 -> dashboard_top_customers.json
///   GET /api/dashboard/sales-summary?period=week -> dashboard_sales_summary.json
///   GET /api/dashboard/expense-summary?period=month -> dashboard_expense_summary.json
///   GET /api/dashboard/production-status  -> dashboard_production_status.json
///   GET /api/dashboard/stock-movement-summary?days=30
///                                          -> dashboard_stock_movement_summary.json
///   GET /api/dashboard/kpi?metric=stock_health -> dashboard_kpi.json
///   GET /api/dashboard/ar-summary          -> dashboard_ar_summary.json
///
/// NOTE: list endpoints wrap rows in `{success, data}` while
/// `GET /api/invoices/:id` returns the bare object — repositories must
/// handle both (see lib/data/models/README.md).
void main() {
  Map<String, dynamic> loadFixture(String name) {
    final raw = File('test/fixtures/$name').readAsStringSync();
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  /// Bare-array payloads (`GET /boms`, `GET /productions`).
  List<dynamic> loadFixtureList(String name) {
    final raw = File('test/fixtures/$name').readAsStringSync();
    return jsonDecode(raw) as List<dynamic>;
  }

  group('live fixtures', () {
    test('fixture files are all present and valid JSON', () {
      for (final name in [
        'customers.json',
        'items.json',
        'suppliers.json',
        'invoices.json',
        'invoice_detail.json',
        'boms.json',
        'bom_detail.json',
        'productions.json',
        'production_detail.json',
        'ar_aging.json',
        'sales_summary.json',
        'low_stock.json',
        'stock_level.json',
        'stock_valuation.json',
        'sales_by_customer.json',
        'dso.json',
        'cash_flow.json',
        'profit_loss.json',
        'inventory_movement.json',
        'purchase_summary.json',
        'top_debtors.json',
        'dashboard_top_customers.json',
        'dashboard_sales_summary.json',
        'dashboard_expense_summary.json',
        'dashboard_production_status.json',
        'dashboard_stock_movement_summary.json',
        'dashboard_kpi.json',
        'dashboard_ar_summary.json',
      ]) {
        expect(
          File('test/fixtures/$name').existsSync(),
          isTrue,
          reason: 'missing fixture $name',
        );
        // Throws on invalid JSON.
        jsonDecode(File('test/fixtures/$name').readAsStringSync());
      }
    });

    test('customers.json parses every row', () {
      final json = loadFixture('customers.json');
      final rows = json['data'] as List;
      final customers = [
        for (final r in rows) Customer.fromJson(r as Map<String, dynamic>),
      ];

      expect(customers, isNotEmpty);
      expect(customers.length, rows.length);
      for (final c in customers) {
        expect(c.id, greaterThan(0));
        expect(c.customerCode, isNotEmpty);
        expect(c.customerName, isNotEmpty);
      }
      // Spot-check the first row's computed/flag fields.
      final first = customers.first;
      expect(first.creditUtilizationPercent, isNotNull);
      expect(first.currentBalance, isNotNull);
      expect(first.isActive, anyOf(isTrue, isFalse));
    });

    test('items.json parses every row incl. rack_no and sale_type', () {
      final json = loadFixture('items.json');
      final rows = json['data'] as List;
      final items = [
        for (final r in rows) Item.fromJson(r as Map<String, dynamic>),
      ];

      expect(items, isNotEmpty);
      expect(items.length, rows.length);
      for (final i in items) {
        expect(i.id, greaterThan(0));
        expect(i.itemCode, isNotEmpty);
        expect(i.itemName, isNotEmpty);
      }
      // rack_no is an empty column in this snapshot (key present, all null)
      // — assert key presence and parse-safety, not non-null values.
      expect(rows.first, contains('rack_no'));
      for (final i in items) {
        expect(i.rackNo, anyOf(isNull, isA<String>()));
      }
      // sale_type arrives with both packed and loose values.
      expect(items.any((i) => i.saleType == SaleType.packed), isTrue);
      expect(
        items.any((i) => i.saleType == SaleType.loose),
        isTrue,
        reason: 'expected at least one loose-sale item',
      );
      // 0/1 int flags must parse to bools.
      expect(items.first.isRawMaterial, isA<bool>());
    });

    test('suppliers.json parses every row', () {
      final json = loadFixture('suppliers.json');
      final rows = json['data'] as List;
      final suppliers = [
        for (final r in rows) Supplier.fromJson(r as Map<String, dynamic>),
      ];

      expect(suppliers, isNotEmpty);
      expect(suppliers.length, rows.length);
      for (final s in suppliers) {
        expect(s.id, greaterThan(0));
        expect(s.supplierName, isNotEmpty);
      }
      expect(suppliers.first.isActive, isA<bool>());
    });

    test('invoices.json parses every row incl. line items', () {
      final json = loadFixture('invoices.json');
      final rows = json['data'] as List;
      final invoices = [
        for (final r in rows) Invoice.fromJson(r as Map<String, dynamic>),
      ];

      expect(invoices, isNotEmpty);
      expect(invoices.length, rows.length);
      for (final inv in invoices) {
        expect(inv.id, greaterThan(0));
        expect(inv.invoiceNo, isNotEmpty);
        expect(inv.status, isNotEmpty);
        expect(InvoiceStatus.tryParse(inv.status), isNotNull);
        // Server getAll embeds items on every row.
        expect(inv.items, isNotNull);
        for (final line in inv.items ?? const <InvoiceItem>[]) {
          expect(line.itemId, greaterThan(0));
          expect(line.quantity, isNotNull);
        }
      }
    });

    test('invoice_detail.json parses the bare (unwrapped) detail object', () {
      final detail = loadFixture('invoice_detail.json'); // NO {success,data}
      final inv = Invoice.fromJson(detail);

      expect(inv.id, greaterThan(0));
      expect(inv.invoiceNo, isNotEmpty);
      expect(inv.items, isNotNull);
      expect(inv.items, isNotEmpty);
      // Detail adds customer_* fields that list rows lack.
      expect(inv.customerName, isNotEmpty);
      // returned_amount/return_fee columns land on detail (invoice 163
      // has returned_amount 0 / return_fee 0 in this snapshot).
      expect(inv.returnedAmount, 0);
      expect(inv.returnFee, 0);
    });
  });

  test('productions.json parses every bare list row', () {
    // GET /productions returns a bare array (no {success,data}).
    final rows = loadFixtureList('productions.json');
    final productions = [
      for (final r in rows) Production.fromJson(r as Map<String, dynamic>),
    ];
    expect(productions, isNotEmpty);
    expect(productions.length, rows.length);
    for (final p in productions) {
      expect(p.id, greaterThan(0));
      expect(p.productionNo, isNotEmpty);
      expect(p.outputItemId, greaterThan(0));
      expect(p.outputQuantity, greaterThan(0));
      expect(p.productionDate, isNotEmpty);
      expect(p.overheadCost, isNotNull);
      expect(p.batchNo, isNotNull);
      expect(p.outputItemName, isNotEmpty);
      expect(p.finishedGoodsWarehouseName, isNotEmpty);
    }
    // The server fills the FIFO-costed financials.
    expect(productions.first.unitCost, greaterThan(0));
    expect(productions.first.totalBatchCost, greaterThan(0));
  });

  test('production_detail.json parses inputs (bare detail object)', () {
    final detail = loadFixture('production_detail.json');
    final p = Production.fromJson(detail);
    expect(p.id, greaterThan(0));
    expect(p.inputs, isNotEmpty);
    for (final input in p.inputs) {
      expect(input.itemId, greaterThan(0));
      expect(input.quantity, greaterThan(0));
      expect(input.itemName, isNotEmpty);
      expect(input.warehouseName, isNotEmpty);
    }
  });

  test('boms.json parses every bare list row incl. aggregates', () {
    final rows = loadFixtureList('boms.json');
    final boms = [
      for (final r in rows) Bom.fromJson(r as Map<String, dynamic>),
    ];
    expect(boms, isNotEmpty);
    expect(boms.length, rows.length);
    for (final b in boms) {
      expect(b.id, greaterThan(0));
      expect(b.bomNo, isNotEmpty);
      expect(b.finishedItemId, greaterThan(0));
      expect(b.isActive, isA<bool>());
      expect(b.itemCount, greaterThan(0));
      expect(b.totalMaterialCost, isNotNull);
    }
  });

  test('bom_detail.json parses items + line costs', () {
    final detail = loadFixture('bom_detail.json');
    final bom = BomDetail.fromJson(detail);
    expect(bom.id, greaterThan(0));
    expect(bom.items, isNotEmpty);
    for (final item in bom.items) {
      expect(item.itemId, greaterThan(0));
      expect(item.quantity, greaterThan(0));
      expect(item.standardCost, isNotNull);
      expect(item.lineCost, isNotNull);
    }
    expect(bom.totalMaterialCost, greaterThan(0));
  });

  test('ar_aging.json parses buckets + summary', () {
    final json = loadFixture('ar_aging.json');
    final report = ArAgingReport.fromJson(json['data'] as Map<String, dynamic>);

    expect(report.asOfDate, isNotEmpty);
    expect(report.buckets, isNotEmpty);
    for (final b in report.buckets) {
      expect(b.customerName, isNotEmpty);
      expect(b.customerCode, isNotEmpty);
      expect(b.totalOutstanding, greaterThanOrEqualTo(0));
    }
    // Bucket column totals tie to the server's summary block (float-safe
    // equality in case regenerated fixtures carry decimal amounts).
    expect(report.summary.totalReceivables, greaterThan(0));
    final summed = report.buckets.fold<num>(
      0,
      (acc, b) => acc + b.totalOutstanding,
    );
    expect(report.summary.totalReceivables, closeTo(summed, 0.01));
  });

  test('sales_summary.json parses period + stats + rows', () {
    final json = loadFixture('sales_summary.json');
    final report = SalesSummaryReport.fromJson(
      json['data'] as Map<String, dynamic>,
    );

    expect(report.period, isNotNull);
    expect(report.period!.startDate, isNotEmpty);
    expect(report.period!.endDate, isNotEmpty);
    expect(report.summary.totalInvoices, greaterThan(0));
    expect(report.summary.totalSales, greaterThan(0));
    expect(report.sales, isNotEmpty);
    expect(report.sales.length, report.summary.totalInvoices);
    for (final row in report.sales) {
      expect(row.invoiceNo, isNotEmpty);
      expect(row.customerName, isNotEmpty);
      expect(row.totalSales, greaterThan(0));
    }
  });

  test('low_stock.json parses every bare list row', () {
    final rows = loadFixtureList('low_stock.json');
    final items = [
      for (final r in rows)
        LowStockReportRow.fromJson(r as Map<String, dynamic>),
    ];
    expect(items, isNotEmpty);
    expect(items.length, rows.length);
    for (final it in items) {
      expect(it.id, greaterThan(0));
      expect(it.itemName, isNotEmpty);
      expect(it.currentStock, isNotNull);
      expect(it.minimumStock, isNotNull);
      expect(it.shortage, isNotNull);
      expect(it.stockStatus, isNotEmpty);
    }
  });

  test('stock_level.json parses rows + summary tie-out', () {
    final json = loadFixture('stock_level.json');
    final report = StockLevelReport.fromJson(
      json['data'] as Map<String, dynamic>,
    );

    expect(report.rows, isNotEmpty);
    for (final row in report.rows) {
      expect(row.id, greaterThan(0));
      expect(row.itemCode, isNotEmpty);
      expect(row.itemName, isNotEmpty);
      expect(row.stockStatus, isNotEmpty);
    }
    // Summary status counts partition the row set exactly.
    expect(report.summary.totalItems, report.rows.length);
    expect(
      report.summary.inStock +
          report.summary.lowStock +
          report.summary.outOfStock,
      report.summary.totalItems,
    );
  });

  test('stock_valuation.json parses rows + summary tie-out', () {
    final json = loadFixture('stock_valuation.json');
    final report = StockValuationReport.fromJson(
      json['data'] as Map<String, dynamic>,
    );

    expect(report.rows, isNotEmpty);
    for (final row in report.rows) {
      expect(row.id, greaterThan(0));
      expect(row.itemName, isNotEmpty);
      expect(row.valuationMethod, isNotEmpty);
    }
    // Batch + legacy counts partition the row set; total value ties to
    // the summed row values (float-safe in case of decimal costs).
    expect(report.summary.totalItems, report.rows.length);
    expect(
      report.summary.batchTrackedItems + report.summary.legacyItems,
      report.summary.totalItems,
    );
    final summedValue = report.rows.fold<num>(
      0,
      (acc, r) => acc + r.totalValue,
    );
    expect(report.summary.totalValue, closeTo(summedValue, 0.01));
  });

  test('sales_by_customer.json parses every bare list row', () {
    final rows = loadFixtureList('sales_by_customer.json');
    final customers = [
      for (final r in rows)
        SalesByCustomerRow.fromJson(r as Map<String, dynamic>),
    ];
    expect(customers, isNotEmpty);
    expect(customers.length, rows.length);
    for (final c in customers) {
      expect(c.customerName, isNotEmpty);
      expect(c.customerCode, isNotEmpty);
      expect(c.totalInvoices, greaterThan(0));
      expect(c.totalSales, greaterThan(0));
      expect(c.lastPurchaseDate, isNotEmpty);
    }
  });

  test('dso.json parses the DSO metric + period', () {
    final json = loadFixture('dso.json');
    final metric = DSOMetric.fromJson(json['data'] as Map<String, dynamic>);

    expect(metric.dso, greaterThan(0));
    expect(metric.totalSales, greaterThan(0));
    expect(metric.totalAR, greaterThanOrEqualTo(0));
    expect(metric.startDate, isNotEmpty);
    expect(metric.endDate, isNotEmpty);
    // totalSales mirrors totalCreditSales on the server.
    expect(metric.totalSales, closeTo(metric.totalCreditSales, 0.01));
  });

  test('cash_flow.json parses inflow/outflow/net', () {
    final json = loadFixture('cash_flow.json');
    final report = CashFlowReport.fromJson(
      json['data'] as Map<String, dynamic>,
    );

    expect(report.startDate, isNotEmpty);
    expect(report.endDate, isNotEmpty);
    expect(report.totalInflow, greaterThanOrEqualTo(0));
    expect(report.totalOutflow, greaterThanOrEqualTo(0));
    // net = inflow - outflow (float-safe).
    expect(
      report.netCashFlow,
      closeTo(report.totalInflow - report.totalOutflow, 0.01),
    );
  });

  test('profit_loss.json parses the P&L breakdown + margins', () {
    final json = loadFixture('profit_loss.json');
    final report = ProfitLossReport.fromJson(
      json['data'] as Map<String, dynamic>,
    );

    expect(report.startDate, isNotEmpty);
    expect(report.totalRevenue, greaterThan(0));
    expect(report.grossProfit, report.totalRevenue - report.totalCogs);
    expect(report.expenses, isNotEmpty);
    for (final e in report.expenses) {
      expect(e.category, isNotEmpty);
      expect(e.total, greaterThan(0));
    }
    // Total expenses equals the sum of the category breakdown.
    final summed = report.expenses.fold<num>(0, (acc, e) => acc + e.total);
    expect(report.totalExpenses, closeTo(summed, 0.01));
    // net = gross - expenses.
    expect(
      report.netProfit,
      closeTo(report.grossProfit - report.totalExpenses, 0.01),
    );
  });

  test('inventory_movement.json parses movements + summary', () {
    final json = loadFixture('inventory_movement.json');
    final report = InventoryMovementReport.fromJson(
      json['data'] as Map<String, dynamic>,
    );

    expect(report.rows, isNotEmpty);
    for (final r in report.rows) {
      expect(r.movementNo, isNotEmpty);
      expect(r.itemName, isNotEmpty);
      expect(r.movementType, isNotEmpty);
    }
    // Summary is computed by the server from the row set.
    expect(report.summary.totalInbound, greaterThanOrEqualTo(0));
    expect(report.summary.totalOutbound, greaterThanOrEqualTo(0));
    expect(
      report.summary.netMovement,
      report.summary.totalInbound - report.summary.totalOutbound,
    );
  });

  test('purchase_summary.json parses POs + stats tie-out', () {
    final json = loadFixture('purchase_summary.json');
    final report = PurchaseSummaryReport.fromJson(
      json['data'] as Map<String, dynamic>,
    );

    expect(report.rows, isNotEmpty);
    for (final r in report.rows) {
      expect(r.purchaseOrderNumber, isNotEmpty);
      expect(r.supplierName, isNotEmpty);
      expect(r.poId, greaterThan(0));
    }
    // Period totals tie to the row set.
    expect(report.summary.totalOrders, report.rows.length);
    final summedCost = report.rows.fold<num>(0, (acc, r) => acc + r.totalCost);
    expect(report.summary.totalCost, closeTo(summedCost, 0.01));
  });

  test('top_debtors.json parses every bare list row', () {
    final rows = loadFixtureList('top_debtors.json');
    final debtors = [
      for (final r in rows) TopDebtorRow.fromJson(r as Map<String, dynamic>),
    ];
    expect(debtors, isNotEmpty);
    expect(debtors.length, rows.length);
    for (final d in debtors) {
      expect(d.customerName, isNotEmpty);
      expect(d.totalOutstanding, greaterThan(0));
      expect(d.totalInvoiced, greaterThanOrEqualTo(0));
    }
    // Rows are ordered by outstanding descending.
    for (var i = 1; i < debtors.length; i++) {
      expect(
        debtors[i - 1].totalOutstanding >= debtors[i].totalOutstanding,
        isTrue,
        reason: 'top debtors must be sorted by outstanding desc',
      );
    }
  });

  // ── Dashboard block endpoints (PORTING.md §10) ─────────────────────

  test('dashboard_top_customers.json parses rows sorted by revenue', () {
    final json = loadFixture('dashboard_top_customers.json');
    final rows = json['data'] as List;
    final customers = [
      for (final r in rows) TopCustomer.fromJson(r as Map<String, dynamic>),
    ];

    expect(customers, isNotEmpty);
    expect(customers.length, rows.length);
    for (final c in customers) {
      expect(c.totalRevenue, greaterThanOrEqualTo(0));
      expect(c.invoiceCount, greaterThanOrEqualTo(0));
    }
    // Rows are ordered by revenue descending (server GROUP BY ... ORDER
    // BY total_revenue DESC).
    for (var i = 1; i < customers.length; i++) {
      expect(
        customers[i - 1].totalRevenue >= customers[i].totalRevenue,
        isTrue,
        reason: 'top customers must be sorted by revenue desc',
      );
    }
  });

  test('dashboard_top_customers tolerates a null customer_name', () {
    final json = loadFixture('dashboard_top_customers.json');
    final rows = json['data'] as List;
    // This snapshot groups invoices by customer_name; a row with NULL
    // customer_name is legal (asString → '').
    for (final r in rows) {
      final c = TopCustomer.fromJson(r as Map<String, dynamic>);
      expect(c.customerName, isA<String>());
    }
  });

  test('dashboard_sales_summary.json parses period totals', () {
    final json = loadFixture('dashboard_sales_summary.json');
    final row = SalesSummaryResult.fromJson(
      json['data'] as Map<String, dynamic>,
    );

    expect(row.periodTotal, greaterThan(0));
    expect(row.count, greaterThan(0));
  });

  test('dashboard_expense_summary.json parses period totals', () {
    final json = loadFixture('dashboard_expense_summary.json');
    final row = ExpenseSummaryResult.fromJson(
      json['data'] as Map<String, dynamic>,
    );

    expect(row.periodTotal, greaterThanOrEqualTo(0));
    expect(row.count, greaterThanOrEqualTo(0));
  });

  test(
    'dashboard_production_status.json parses counts that partition total',
    () {
      final json = loadFixture('dashboard_production_status.json');
      final row = ProductionStatusResult.fromJson(
        json['data'] as Map<String, dynamic>,
      );

      expect(row.total, greaterThan(0));
      // active + completed + cancelled partition the total (cancelled is
      // hard-coded 0 on the server).
      expect(row.active + row.completed + row.cancelled, row.total);
    },
  );

  test('dashboard_stock_movement_summary.json parses net tie-out', () {
    final json = loadFixture('dashboard_stock_movement_summary.json');
    final row = StockMovementSummaryResult.fromJson(
      json['data'] as Map<String, dynamic>,
    );

    expect(row.inboundQty, greaterThanOrEqualTo(0));
    expect(row.outboundQty, greaterThanOrEqualTo(0));
    // net = inbound - outbound (server sums positive/negative legs).
    expect(row.net, closeTo(row.inboundQty - row.outboundQty, 0.01));
  });

  test('dashboard_kpi.json parses the gauge', () {
    final json = loadFixture('dashboard_kpi.json');
    final row = KpiResult.fromJson(json['data'] as Map<String, dynamic>);

    expect(row.metric, isNotEmpty);
    expect(row.label, isNotEmpty);
    expect(row.unit, isNotEmpty);
    expect(row.value, isA<num>());
  });

  test('dashboard_ar_summary.json parses buckets within the AR total', () {
    final json = loadFixture('dashboard_ar_summary.json');
    final row = ArSummaryResult.fromJson(json['data'] as Map<String, dynamic>);

    expect(row.totalAr, greaterThan(0));
    expect(row.customerCount, greaterThan(0));
    final bucketSum =
        row.currentAmount +
        row.amount130 +
        row.amount3160 +
        row.amount6190 +
        row.amountOver90;
    // Buckets can't exceed the total; an invoice with a NULL due_date
    // lands in total_ar but in no aging bucket, so <= is the invariant.
    expect(bucketSum, lessThanOrEqualTo(row.totalAr));
    expect(bucketSum, greaterThan(0));
  });
}
