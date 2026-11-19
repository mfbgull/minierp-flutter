// GLM (PR #41 follow-up): reservation_id on the invoice-edit wire.
//
// REAL wire contract test for the EDIT path, now run against the shape the
// server actually returns after PI's field landed (PR #41 head f3b4c5f6:
// `InvoiceModel.getItems` selects `ii.reservation_id`, and `getInvoice`
// returns the bare invoice row with `items[]`). This test drives the real
// InvoiceRepository through a Dio HttpClientAdapter:
//
//   * GET /invoices/:id       — the two-line invoice the form loads (same item,
//                              two lines, each with its own reservation_id)
//   * PUT /invoices/:id       — the edit the form posts
//
// and asserts the actual method, path, and per-line reservation_id in the
// PUT body. No fake repository, no source-text assertion, no manual fromJson.
//
// Both tests serve the ids OPPOSITE to the line order (and the second serves
// the two lines themselves reversed), so a positional (index-based) emission
// would put the wrong id on each line; the assertions require each line's own
// id, which can only come from decoding `reservation_id` off the GET response.

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

/// One line of the two-line same-item fixture: quantity, unit price, and the
/// reservation id the server links to that line. The id deliberately does NOT
/// track the line's position, so a positional (index-based) client would put
/// the wrong id on each line.
class _Line {
  const _Line(this.id, this.quantity, this.reservationId);
  final int id;
  final int quantity;
  final int? reservationId;
}

/// Two lines of ONE item (item_id 1), served in the given order. The first
/// (default) order pairs line 1 → reservation 102 and line 2 → reservation
/// 101, i.e. the reservation ids run opposite to the line order.
const List<_Line> _linesInLoadOrder = [
  _Line(1, 2, 102),
  _Line(2, 3, 101),
];

/// The exact bare shape the server's `getInvoice` sends after PI's field
/// landed: the invoice row + `items[]`, each item carrying `reservation_id`
/// (nullable) alongside the columns `InvoiceModel.getItems` selects.
Map<String, Object> _invoiceDetail(List<_Line> lines) => <String, Object>{
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
        for (final line in lines)
          <String, Object?>{
            'id': line.id,
            'invoice_id': 42,
            'item_id': 1,
            'item_name': 'Widget',
            'item_code': 'ITM-1',
            'quantity': line.quantity,
            'unit_price': 100,
            'amount': line.quantity * 100,
            'tax_rate': 0,
            'discount_type': 'none',
            'discount_value': 0,
            'returned_qty': 0,
            'reservation_id': line.reservationId,
          },
      ],
    };

/// Serves the invoice detail (`GET /invoices/:id`), accepts the edit
/// (`PUT /invoices/:id`), and captures both requests for assertions.
class _EditWireAdapter implements HttpClientAdapter {
  _EditWireAdapter([this.lines = _linesInLoadOrder]);

  /// The lines the `GET /invoices/:id` returns, in this exact order.
  final List<_Line> lines;

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
          jsonEncode(_invoiceDetail(lines)),
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
          jsonEncode(_invoiceDetail(lines)),
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

Future<_EditWireAdapter> _pumpAndSave(
  WidgetTester tester, {
  List<_Line> lines = _linesInLoadOrder,
}) async {
  final adapter = _EditWireAdapter(lines);
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = adapter;
  await _pumpEdit(tester, dio, _editShell());
  await _save(tester);
  return adapter;
}

/// The exact `GET /invoices/:id` body the server would send for these lines
/// (kept here as the single source of truth the adapter also serves), so the
/// test can assert the client decoded the ids we actually served.
Map<String, dynamic> _putItems(_EditWireAdapter adapter) {
  final body = adapter.putRequest!.data! as Map<String, dynamic>;
  return {'items': body['items'] as List<dynamic>};
}

void main() {
  testWidgets(
    'GET decode + PUT: each same-item line keeps its own reservation_id '
    '(loaded order: line 1 → 102, line 2 → 101)',
    (tester) async {
      final adapter = await _pumpAndSave(tester);

      // The form actually hit GET /invoices/:id (the real edit load path).
      expect(
        adapter.getRequest,
        isNotNull,
        reason: 'the edit form must GET /invoices/:id to load its lines',
      );
      expect(adapter.getRequest!.method, 'GET');
      expect(adapter.getRequest!.uri.path, endsWith('/invoices/42'));

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
    'GET decode + PUT: the id follows ITS line, not the position, when the '
    'server returns the same two lines in the opposite order',
    (tester) async {
      // Same two lines, but served reversed. If the client bound ids by index
      // (or re-derived them from position) the ids would land on the wrong
      // lines here; bound to the row they must follow their own quantity.
      final adapter = await _pumpAndSave(
        tester,
        lines: const [_Line(2, 3, 101), _Line(1, 2, 102)],
      );

      final items =
          _putItems(adapter)['items']! as List<dynamic>;
      expect(items, hasLength(2));

      // Build id → quantity from the ACTUAL wire payload.
      final idToQty = <int?, num>{};
      for (final raw in items) {
        final line = raw as Map<String, dynamic>;
        idToQty[line['reservation_id'] as int?] = line['quantity'] as num;
      }
      // Loaded pairing regardless of position: (id 1, qty 2) → 102 and
      // (id 2, qty 3) → 101.
      expect(idToQty[102], 2, reason: 'reservation 102 stays on qty-2 line');
      expect(idToQty[101], 3, reason: 'reservation 101 stays on qty-3 line');
    },
  );
}
