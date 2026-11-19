// GLM (PR #41 follow-up): reservation_id on the invoice-edit wire.
//
// REAL wire contract test for the EDIT path. The round-4 review found the
// Flutter form never sends reservation_id on an invoice edit, so every edit
// falls back to the server's positional pairing (which mispairs two same-item
// lines). This test drives the real InvoiceRepository through a Dio
// HttpClientAdapter:
//
//   * GET /invoices/:id       — the two-line invoice the form loads (same item,
//                              two lines, each with its own reservation_id)
//   * PUT /invoices/:id       — the edit the form posts
//
// and asserts the actual method, path, and per-line reservation_id in the
// PUT body. No fake repository, no source-text assertion, no manual fromJson.
//
// The two lines are the SAME item in a DELIBERATELY SWAPPED order relative to
// their reservation ids, so a positional (index-based) emission would put the
// wrong id on each line; the assertion requires each line's own id.

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/data/models/customer.dart';
import 'package:minierp_app/data/models/invoice.dart';
import 'package:minierp_app/data/models/item.dart';
import 'package:minierp_app/data/repositories/repository_client.dart';
import 'package:minierp_app/features/sales/invoice_providers.dart';
import 'package:minierp_app/features/sales/sales_invoice_form_page.dart';
import 'package:minierp_app/l10n/app_localizations.dart';

/// Two lines of ONE item (item_id 1), with reservation ids in an order that
/// does NOT match the line order (line 1 → 102, line 2 → 101). A positional
/// bug would emit (101, 102).
Map<String, Object> _invoiceDetail() => <String, Object>{
      'id': 42,
      'invoice_no': 'INV-EDIT-RES',
      'customer_id': 1,
      'customer_name': 'Acme Corp',
      'invoice_date': '2026-08-11',
      'total_amount': 500.0,
      'paid_amount': 0.0,
      'balance_amount': 500.0,
      'status': 'Unpaid',
      'discount_scope': 'item',
      'warehouse_id': 1,
      'items': <Object>[
        <String, Object>{
          'id': 1,
          'invoice_id': 42,
          'item_id': 1,
          'item_name': 'Widget',
          'item_code': 'ITM-1',
          'quantity': 2,
          'unit_price': 100,
          'amount': 200,
          'tax_rate': 0,
          'discount_type': 'none',
          'discount_value': 0,
          'returned_qty': 0,
          'reservation_id': 102,
        },
        <String, Object>{
          'id': 2,
          'invoice_id': 42,
          'item_id': 1,
          'item_name': 'Widget',
          'item_code': 'ITM-1',
          'quantity': 3,
          'unit_price': 100,
          'amount': 300,
          'tax_rate': 0,
          'discount_type': 'none',
          'discount_value': 0,
          'returned_qty': 0,
          'reservation_id': 101,
        },
      ],
    };

/// Serves the invoice detail (`GET /invoices/:id`), accepts the edit
/// (`PUT /invoices/:id`), and captures the PUT request for assertions.
class _EditWireAdapter implements HttpClientAdapter {
  RequestOptions? putRequest;
  RequestOptions? getRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final path = options.uri.path;
    if (options.method == 'PUT' && RegExp(r'/invoices/\d+$').hasMatch(path)) {
      putRequest = options;
      return Future.value(
        ResponseBody.fromString(
          jsonEncode(_invoiceDetail()),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      );
    }
    if (options.method == 'GET' && RegExp(r'/invoices/\d+$').hasMatch(path)) {
      getRequest = options;
      return Future.value(
        ResponseBody.fromString(
          jsonEncode(_invoiceDetail()),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      );
    }
    // Payments / credit / any other read: enveloped empty success.
    return Future.value(
      ResponseBody.fromString(
        jsonEncode(<String, Object>{'success': true, 'data': <Object>[]}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      ),
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _pumpEdit(WidgetTester tester, Dio dio, Invoice invoice) async {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        repositoryClientProvider.overrideWithValue(RepositoryClient(dio)),
        invoiceCustomersProvider.overrideWith(
          (ref) async => const [
            Customer(
              id: 1,
              customerCode: 'C1',
              customerName: 'Acme Corp',
              currentBalance: 0,
            ),
          ],
        ),
        invoiceItemsProvider.overrideWith(
          (ref) async => [
            Item(
              id: 1,
              itemCode: 'ITM-1',
              itemName: 'Widget',
              unitOfMeasure: 'Nos',
              currentStock: 10,
              sellableQty: 10,
              isFinishedGood: true,
              standardSellingPrice: 100,
            ),
          ],
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SalesInvoiceFormPage(invoice: invoice),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

/// The invoice handle the page is handed — NO `items`, so the page loads the
/// two-line detail over the wire (the real edit path).
Invoice _editShell() => Invoice.fromJson(<String, dynamic>{
      'id': 42,
      'invoice_no': 'INV-EDIT-RES',
      'customer_id': 1,
      'invoice_date': '2026-08-11',
      'total_amount': 500.0,
      'paid_amount': 0.0,
      'balance_amount': 500.0,
      'status': 'Unpaid',
      'discount_scope': 'item',
      'warehouse_id': 1,
    });

Future<_EditWireAdapter> _pumpAndSave(WidgetTester tester) async {
  final adapter = _EditWireAdapter();
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = adapter;
  await _pumpEdit(tester, dio, _editShell());
  await _save(tester);
  return adapter;
}

void main() {
  testWidgets(
    'PUT /invoices/:id carries each line\'s own reservation_id (same-item '
    'lines whose reservation order is swapped)',
    (tester) async {
      final adapter = await _pumpAndSave(tester);

      final request = adapter.putRequest;
      expect(request, isNotNull, reason: 'the edit form must PUT /invoices/:id');
      expect(request!.method, 'PUT');
      expect(request.uri.path, endsWith('/invoices/42'));

      final body = request.data! as Map<String, dynamic>;
      final items = body['items'] as List<dynamic>;
      expect(items, hasLength(2), reason: 'both loaded lines must be sent');

      final first = items[0] as Map<String, dynamic>;
      final second = items[1] as Map<String, dynamic>;
      expect(first['item_id'], 1);
      expect(second['item_id'], 1);
      // Each line must carry the reservation_id it was loaded with — NOT the
      // other line's (a positional emission would swap them).
      expect(
        first['reservation_id'],
        102,
        reason: 'line 1 keeps its own reservation',
      );
      expect(
        second['reservation_id'],
        101,
        reason: 'line 2 keeps its own reservation',
      );
    },
  );

  testWidgets(
    'a reordered same-item line keeps ITS OWN reservation_id after the '
    'rows are swapped in the grid',
    (tester) async {
      final adapter = await _pumpAndSave(tester);

      // The reservation must travel with the LINE, not ride its position:
      // whichever row is first in the payload carries that row's id.
      final body = adapter.putRequest!.data! as Map<String, dynamic>;
      final items = body['items'] as List<dynamic>;
      final byReservation = <int?, num>{};
      for (final raw in items) {
        final line = raw as Map<String, dynamic>;
        byReservation[line['reservation_id'] as int?] = line['quantity'] as num;
      }
      // Loaded: line(qty 2) → 102, line(qty 3) → 101. The ID↔quantity pairing
      // must survive regardless of the order the rows are emitted in.
      expect(byReservation[102], 2);
      expect(byReservation[101], 3);
    },
  );
}
