// API validation harness — PORTING.md §0/§2/§7.
//
// Boots nothing itself: it expects the bundled server running on
// localhost:3011 (default dev login admin/admin123 — `cd server && npm
// run build && npm start`).
//
// Run:  dart run tool/api_validation.dart
//
// What it validates against REAL API responses:
//   1. Model fidelity — every response row parses through the ported
//      Dart `fromJson` without error (items, customers, invoices,
//      ledger entries, payments, suppliers).
//   2. Calculation parity — the ported `calculations/` functions must
//      reproduce the server's stored numbers:
//        · line amount  (calcItemLine)   == invoice_items.amount
//        · invoice total (calculateTotal) == invoices.total_amount
//          (the server stores totals computed by the web client's
//          invoiceCalculations.ts — the 1:1 source of the Dart port)
//        · ledger balance (calculateLedgerTotals) == /customers/:id/balance
//   3. Loose-item math — applyLineFieldUpdate against real rate +
//      precision settings.
//
// Exit code 0 = all checks passed; 1 = at least one failure.
// Known parity caveat (documented in the port READMEs): the server's
// `roundCurrency` uses the `e+2` trick while Dart rounds with
// `(x*100).round()/100` — they can differ at exact half-cent
// boundaries, so line/total checks use a small tolerance.
//
// This is a CLI harness — `print` output is the product.
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:minierp_app/data/models/customer.dart';
import 'package:minierp_app/data/models/invoice.dart';
import 'package:minierp_app/data/models/item.dart';
import 'package:minierp_app/data/models/ledger_entry.dart';
import 'package:minierp_app/data/models/payment.dart';
import 'package:minierp_app/data/models/supplier.dart';
import 'package:minierp_app/features/customers/calculations/customer_calculations.dart';
import 'package:minierp_app/features/sales/calculations/invoice_calculations.dart';
import 'package:minierp_app/features/sales/calculations/invoice_line_calc.dart';
import 'package:minierp_app/features/sales/models/sales_forms.dart';

const String _baseUrl = 'http://localhost:3011/api';
const String _username = 'admin';
const String _password = 'admin123';

class _Report {
  int passed = 0;
  int failed = 0;
  final List<String> lines = [];

  void ok(String name) {
    passed++;
    lines.add('  ✓ $name');
  }

  void fail(String name, [String? why]) {
    failed++;
    lines.add('  ✗ $name${why == null ? '' : ' — $why'}');
  }

  void info(String message) => lines.add('    · $message');
}

/// Unwraps `{success: true, data}`; passes bare bodies through.
Object? unwrap(Response<dynamic> response) {
  final body = response.data;
  if (body is Map<String, dynamic> && body['success'] == true) {
    return body['data'];
  }
  return body;
}

Options _auth(String token) =>
    Options(headers: {'Authorization': 'Bearer $token'});

Future<Object?> _getJson(Dio dio, String token, String path,
    [Map<String, dynamic>? query]) async {
  final response = await dio.get(path, queryParameters: query, options: _auth(token));
  return unwrap(response);
}

/// 'none' → flat(0) — a no-op discount, safe for both calculation paths.
DiscountType _discountType(String? value) {
  if (value == 'percentage') return DiscountType.percentage;
  return DiscountType.flat;
}

/// Local mirror of `CustomerBalance` (customer_repository.dart) — keep the
/// camelCase fields in sync with that class. Defined inline because
/// importing the repository would transitively pull in
/// `flutter_secure_storage` (dart:ffi), which the `dart run` JIT kernel
/// compiler crashes on. Same camelCase shape as `GET /customers/:id/balance`.
class _CustomerBalance {
  const _CustomerBalance({required this.customerId, required this.customerName, required this.currentBalance});

  factory _CustomerBalance.fromJson(Map<String, dynamic> json) => _CustomerBalance(
        customerId: json['customerId'] as int? ?? 0,
        customerName: json['customerName'] as String? ?? '',
        currentBalance: (json['currentBalance'] as num?) ?? 0,
      );

  final int customerId;
  final String customerName;
  final num currentBalance;
}

T? _tryParseRow<T>(Object? row, T Function(Map<String, dynamic>) fromJson) {
  if (row is! Map<String, dynamic>) return null;
  try {
    return fromJson(row);
  } catch (_) {
    return null;
  }
}

Future<void> main() async {
  final report = _Report();
  final dio = Dio(BaseOptions(
    baseUrl: _baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    // Don't throw on non-2xx — let unwrap()/shape checks turn server
    // errors into report.fail() instead of killing the harness mid-run.
    validateStatus: (_) => true,
  ));

  print('MiniERP API validation — ${DateTime.now()}');
  print('Server: $_baseUrl  (expects the bundled server, admin/admin123)\n');

  /* ── 0. Auth ─────────────────────────────────────────────────── */

  String token = '';
  try {
    final login = await dio.post('/auth/login',
        data: {'username': _username, 'password': _password});
    final data = unwrap(login);
    if (data is Map<String, dynamic>) {
      token = data['token'] as String? ?? '';
      final user = data['user'];
      if (token.isNotEmpty &&
          user is Map<String, dynamic> &&
          user['role'] == 'admin') {
        report.ok('login → token + admin user in body (PORTING.md §0 tweak)');
      } else {
        report.fail('login body carries token+user', data.toString());
      }
    } else {
      report.fail('login', 'unexpected body: ${login.data}');
    }
  } on DioException catch (e) {
    report.fail('login / server reachable', e.toString());
    _finish(report);
    return;
  }
  if (token.isEmpty) {
    _finish(report);
    return;
  }

  final me = await _getJson(dio, token, '/auth/me');
  if (me is Map<String, dynamic> && me['username'] == _username) {
    report.ok('GET /auth/me restore works');
  } else {
    report.fail('GET /auth/me', 'expected username $_username, got $me');
  }

  /* ── 1. Items ────────────────────────────────────────────────── */

  print('\n== Models: Inventory ==');
  final itemsJson = await _getJson(dio, token, '/inventory/items', {'limit': 100});
  final items = <Item>[];
  if (itemsJson is List) {
    var badRows = 0;
    for (final row in itemsJson) {
      final item = _tryParseRow(row, Item.fromJson);
      if (item == null) {
        badRows++;
      } else {
        items.add(item);
      }
    }
    if (badRows == 0) {
      report.ok('Item.fromJson parses ${items.length} rows');
    } else {
      report.fail('Item.fromJson', '$badRows rows failed');
    }
    if (items.isNotEmpty) {
      final first = items.first;
      report.info('sample: ${first.itemCode} «${first.itemName}» stock=${first.currentStock} '
          'saleType=${first.saleType.value} category=${first.category}');
    }
    // Loose-item derivation math against real rate/precision settings.
    final loose = items.where((i) => i.saleType == SaleType.loose).toList();
    report.info('loose items in dataset: ${loose.length}');
    for (final item in loose.take(3)) {
      final rate = item.standardSellingPrice ?? item.standardPrice ?? 0;
      if (rate <= 0) continue;
      final result = applyLineFieldUpdate(
        CalcItemLineInput(
          saleType: SaleType.loose,
          quantity: 0,
          amount: 100,
          rate: rate,
          qtyDecimalPrecision: item.qtyDecimalPrecision,
          roundingStep: item.roundingStep,
        ),
        LineField.amount,
        100,
      );
      final step = (item.roundingStep != null && item.roundingStep! > 0)
          ? item.roundingStep!
          : math.pow(10, -(item.qtyDecimalPrecision ?? 0)).toDouble();
      final roundTrip = (result.quantity * rate - 100).abs();
      // Derived qty is a step-multiple, so the round-trip error is bounded
      // by half a step in quantity units (step × rate / 2).
      final tolerance = step * rate / 2 + 0.001;
      if (roundTrip <= tolerance) {
        report.ok('loose math ${item.itemCode}: amount 100 @ rate=$rate → '
            'qty=${result.quantity} (err=${roundTrip.toStringAsFixed(4)} ≤ '
            'bound=${tolerance.toStringAsFixed(4)})');
      } else {
        report.fail('loose math ${item.itemCode}',
            'qty=${result.quantity} × rate=$rate ≠ 100 (err=$roundTrip > tol=$tolerance)');
      }
    }
  } else {
    report.fail('/inventory/items', 'expected list, got ${itemsJson.runtimeType}');
  }

  if (items.isNotEmpty) {
    final detail = await _getJson(dio, token, '/inventory/items/${items.first.id}');
    final parsed = _tryParseRow(detail, Item.fromJson);
    if (parsed != null) {
      report.ok('GET /inventory/items/:id bare detail parses');
    } else {
      report.fail('GET /inventory/items/:id', 'bare detail did not parse');
    }
  }

  /* ── 2. Customers: model + ledger/balance parity ─────────────── */

  print('\n== Models + calculations: Customers ==');
  final customersResp =
      await dio.get('/customers', queryParameters: {'page': 1, 'limit': 10}, options: _auth(token));
  final customersBody = customersResp.data;
  final customersJson = unwrap(customersResp);
  final customers = <Customer>[];
  if (customersJson is List) {
    var bad = 0;
    for (final row in customersJson) {
      final c = _tryParseRow(row, Customer.fromJson);
      if (c == null) {
        bad++;
      } else {
        customers.add(c);
      }
    }
    if (bad == 0) {
      report.ok('Customer.fromJson parses ${customers.length} rows');
    } else {
      report.fail('Customer.fromJson', '$bad rows failed');
    }
    final pagination =
        customersBody is Map<String, dynamic> ? customersBody['pagination'] : null;
    if (pagination is Map<String, dynamic> && pagination['totalItems'] is num) {
      report.ok('pagination block parsed (totalItems=${pagination['totalItems']})');
    } else {
      report.fail('pagination block', 'missing on GET /customers');
    }
  } else {
    report.fail('GET /customers', 'expected list, got ${customersJson.runtimeType}');
  }

  if (customers.isNotEmpty) {
    final id = customers.first.id;
    final ledgerJson = await _getJson(dio, token, '/customers/$id/ledger');
    final ledger = <LedgerEntry>[];
    if (ledgerJson is List) {
      for (final row in ledgerJson) {
        final e = _tryParseRow(row, LedgerEntry.fromJson);
        if (e != null) ledger.add(e);
      }
    }
    if (ledger.isNotEmpty) {
      report.ok('LedgerEntry.fromJson parses ${ledger.length} entries');
    } else {
      report.fail('customer ledger', 'customer $id has no ledger rows');
    }

    final balanceJson = await _getJson(dio, token, '/customers/$id/balance');
    _CustomerBalance? balance;
    if (balanceJson is Map<String, dynamic>) {
      balance = _tryParseRow(balanceJson, _CustomerBalance.fromJson);
    }
    if (balance != null) {
      report.ok('CustomerBalance DTO parses');
    } else {
      report.fail('customer balance', 'balance endpoint failed');
    }

    if (ledger.isNotEmpty && balance != null) {
      final totals = calculateLedgerTotals(ledger);
      final diff = (totals.balance - balance.currentBalance).abs();
      if (diff <= 0.01) {
        report.ok('calculateLedgerTotals == /balance '
            '(${totals.balance} vs ${balance.currentBalance})');
      } else {
        report.fail('calculateLedgerTotals',
            'ledger balance ${totals.balance} ≠ server balance ${balance.currentBalance}');
      }
    }

    // computeCustomerMetrics against the customer's real invoices.
    try {
      final customerInvoicesJson =
          await _getJson(dio, token, '/invoices', {'limit': 50});
      final customerInvoices = <Invoice>[];
      if (customerInvoicesJson is List) {
        for (final row in customerInvoicesJson) {
          final inv = _tryParseRow(row, Invoice.fromJson);
          if (inv != null && inv.customerId == id) customerInvoices.add(inv);
        }
      }
      final metrics = computeCustomerMetrics(customerInvoices, ledger, customers.first);
      report.ok('computeCustomerMetrics on ${customerInvoices.length} invoices '
          '(invoiced=${metrics.totalInvoiced}, paid=${metrics.totalPaid}, '
          'outstanding=${metrics.totalOutstanding}, '
          'overdue=${metrics.overdueInvoicesCount})');
    } catch (e) {
      report.fail('computeCustomerMetrics', e.toString());
    }
  }

  /* ── 3. Invoices: line + total parity ────────────────────────── */

  print('\n== Calculations: Invoice lines & totals vs server ==');
  final invoicesResp =
      await dio.get('/invoices', queryParameters: {'limit': 50}, options: _auth(token));
  final invoicesJson = unwrap(invoicesResp);
  final invoices = <Invoice>[];
  if (invoicesJson is List) {
    var bad = 0;
    for (final row in invoicesJson) {
      final inv = _tryParseRow(row, Invoice.fromJson);
      if (inv == null) {
        bad++;
      } else {
        invoices.add(inv);
      }
    }
    if (bad == 0) {
      report.ok('Invoice.fromJson parses ${invoices.length} list rows');
    } else {
      report.fail('Invoice.fromJson', '$bad rows failed');
    }
  } else {
    report.fail('GET /invoices', 'expected list, got ${invoicesJson.runtimeType}');
  }

  final invoiceIds = invoices.take(6).map((i) => i.id).toList();
  var detailsChecked = 0;
  var lineMismatches = 0;
  var totalMismatches = 0;
  var taxCases = 0;
  var discountCases = 0;
  var itemScopeCases = 0;
  for (final id in invoiceIds) {
    final detailJson = await _getJson(dio, token, '/invoices/$id');
    final inv = _tryParseRow(detailJson, Invoice.fromJson);
    if (inv == null) {
      report.fail('GET /invoices/$id', 'detail did not parse');
      continue;
    }
    detailsChecked++;
    final items = inv.items;
    if (items == null || items.isEmpty) {
      report.info('INV ${inv.invoiceNo} (id=$id, ${inv.status}): no line items — skipped');
      continue;
    }

    // 3a. Per-line amount: calcItemLine(packed) vs stored amount.
    var lineFails = 0;
    var lineTotal = 0;
    for (final item in items) {
      lineTotal++;
      final calc = calcItemLine(CalcItemLineInput(
        saleType: SaleType.packed,
        quantity: item.quantity,
        rate: item.unitPrice,
      ));
      if ((calc.amount - item.amount).abs() > 0.011) lineFails++;
    }
    if (lineFails == 0) {
      report.ok('INV ${inv.invoiceNo}: calcItemLine matches all $lineTotal line amounts');
    } else {
      lineMismatches += lineFails;
      report.fail('INV ${inv.invoiceNo}',
          '$lineFails/$lineTotal line amounts differ from server (rounding edge or bug)');
    }

    if (items.any((item) => item.taxRate > 0)) taxCases++;
    if (inv.discountScope == 'item') itemScopeCases++;

    // 3b. Invoice total: calculateTotal vs stored total_amount.
    final lines = [
      for (final item in items)
        InvoiceFormItem(
          id: item.id,
          itemId: item.itemId.toString(),
          quantity: item.quantity,
          rate: item.unitPrice,
          tax: item.taxRate,
          discount: Discount(
            type: _discountType(item.discountType),
            value: item.discountValue,
          ),
        ),
    ];
    final scope = inv.discountScope == 'item' ? DiscountScope.item : DiscountScope.invoice;
    final invoiceDiscount = Discount(
      type: _discountType(inv.discountType),
      value: inv.discountValue ?? 0,
    );
    final subtotal = calculateSubtotal(lines);
    final tax = calculateTax(lines, discountScope: scope);
    final discount = calculateDiscount(lines, scope, invoiceDiscount);
    final dartTotal = calculateTotal(lines, scope, invoiceDiscount);
    final diff = (dartTotal - inv.totalAmount).abs();

    if (lines.any((l) => l.discount.value > 0) || (inv.discountValue ?? 0) > 0) {
      discountCases++;
    }
    report.info('INV ${inv.invoiceNo} ${inv.status} scope=$scope — '
        'subtotal=$subtotal tax=$tax discount=$discount | dart=$dartTotal server=${inv.totalAmount} diff=$diff');
    if (diff <= 0.06) {
      report.ok('INV ${inv.invoiceNo}: calculateTotal matches server (diff=${diff.toStringAsFixed(3)})');
    } else {
      totalMismatches++;
      report.fail('INV ${inv.invoiceNo}',
          'dart total $dartTotal vs server ${inv.totalAmount} (diff $diff)');
    }

    // 3c. Paid/balance invariant (model parse correctness).
    final balDiff = (inv.balanceAmount - (inv.totalAmount - inv.paidAmount)).abs();
    if (balDiff > 0.011) {
      report.fail('INV ${inv.invoiceNo}', 'balance ${inv.balanceAmount} ≠ total−paid '
          '${inv.totalAmount}−${inv.paidAmount}');
    }
  }
  report.info('invoice details checked: $detailsChecked, '
      'line mismatches: $lineMismatches, total mismatches: $totalMismatches');
  report.info('coverage: invoices with tax>0: $taxCases, discount>0: '
      '$discountCases, item-scope discounts: $itemScopeCases — a 0 here means '
      'that code path was NOT exercised by this dataset');

  /* ── 4. Payments & suppliers ─────────────────────────────────── */

  print('\n== Models: Payments & Suppliers ==');
  final paymentsJson = await _getJson(dio, token, '/payments', {'limit': 10});
  if (paymentsJson is List) {
    var bad = 0;
    for (final row in paymentsJson) {
      if (_tryParseRow(row, Payment.fromJson) == null) bad++;
    }
    if (bad == 0) {
      report.ok('Payment.fromJson parses ${paymentsJson.length} rows');
    } else {
      report.fail('Payment.fromJson', '$bad rows failed');
    }
  } else {
    report.fail('GET /payments', 'expected list, got ${paymentsJson.runtimeType}');
  }

  final suppliersJson = await _getJson(dio, token, '/suppliers', {'limit': 10});
  if (suppliersJson is List) {
    var bad = 0;
    for (final row in suppliersJson) {
      if (_tryParseRow(row, Supplier.fromJson) == null) bad++;
    }
    if (bad == 0) {
      report.ok('Supplier.fromJson parses ${suppliersJson.length} rows');
    } else {
      report.fail('Supplier.fromJson', '$bad rows failed');
    }
  } else {
    report.fail('GET /suppliers', 'expected list, got ${suppliersJson.runtimeType}');
  }

  /* ── 5. Misc pure-function smoke ─────────────────────────────── */

  print('\n== Misc ==');
  final invoiceNo = generateInvoiceNo();
  final re = RegExp(r'^INV-\d{4}-\d{6}$');
  if (re.hasMatch(invoiceNo)) {
    report.ok('generateInvoiceNo → $invoiceNo');
  } else {
    report.fail('generateInvoiceNo', invoiceNo);
  }

  _finish(report);
}

Future<void> _finish(_Report report) async {
  final rule = '─' * 60;
  print('\n$rule');
  print(report.lines.join('\n'));
  print(rule);
  print('Result: ${report.passed} passed, ${report.failed} failed');
  exit(report.failed == 0 ? 0 : 1);
}
