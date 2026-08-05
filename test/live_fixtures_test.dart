import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/data/models/customer.dart';
import 'package:minierp_app/data/models/invoice.dart';
import 'package:minierp_app/data/models/item.dart';
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
///
/// NOTE: list endpoints wrap rows in `{success, data}` while
/// `GET /api/invoices/:id` returns the bare object — repositories must
/// handle both (see lib/data/models/README.md).
void main() {
  Map<String, dynamic> loadFixture(String name) {
    final raw = File('test/fixtures/$name').readAsStringSync();
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  group('live fixtures', () {
    test('fixture files are all present and valid JSON', () {
      for (final name in [
        'customers.json',
        'items.json',
        'suppliers.json',
        'invoices.json',
        'invoice_detail.json',
      ]) {
        expect(File('test/fixtures/$name').existsSync(), isTrue,
            reason: 'missing fixture $name');
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
      expect(items.any((i) => i.saleType == SaleType.loose), isTrue,
          reason: 'expected at least one loose-sale item');
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
}
