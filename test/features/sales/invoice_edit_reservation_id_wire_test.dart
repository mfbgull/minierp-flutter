// GLM (PR #41 follow-up): reservation_id AND the invoice-item id on the
// invoice-edit wire.
//
// REAL wire contract test for the EDIT path, driven against the shape the
// server returns: `getInvoice` returns the bare invoice row with `items[]`,
// each item carrying its `id` and (nullable) `reservation_id` (PR #41 head
// f3b4c5f6: `InvoiceModel.getItems` selects `ii.reservation_id`; the id comes
// from the existing invoice-item row). This test drives the real
// InvoiceRepository through a Dio HttpClientAdapter:
//
//   * GET /invoices/:id       — the invoice the form loads (two same-item
//                              lines, each with its own id + reservation_id)
//   * PUT /invoices/:id       — the edit the form posts
//
// and asserts the actual method, path, and per-line `id` + `reservation_id` in
// the PUT body. No fake repository, no source-text assertion, no manual
// fromJson.
//
// The lines serve the two ids OPPOSITE to their order (and one test serves the
// two lines themselves reversed), so a positional (index-based) emission would
// put the wrong id/reservation_id on each line; the assertions require each
// line's own ids, which can only come from decoding them off the GET response.
//
// Two extra cases cover the amendments PI asked for:
//   * changing a line's ITEM keeps that line's original id + reservation_id;
//   * a NEWLY added line OMITS `id` (it has no row yet) while the retained
//     line keeps its original id.

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
import 'package:minierp_app/features/sales/line_cells.dart' show DescriptionCell;
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
              standardSellingPrice: 25,
            ),
            // A SECOND item so a test can change a line's item (id 1 → id 2),
            // which is the case that must keep the line's original id.
            Item(
              id: 2,
              itemCode: 'ITM-2',
              itemName: 'Gadget',
              unitOfMeasure: 'Nos',
              currentStock: 10,
              sellableQty: 10,
              isFinishedGood: true,
              standardSellingPrice: 40,
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
  final adapter = await _pumpEditOnly(tester, lines: lines);
  await _save(tester);
  return adapter;
}

/// Pump the edit form over the wire adapter but DO NOT save — a test that
/// changes the form (adds a line, changes an item) starts here, mutates the
/// UI, then calls `_save` itself.
Future<_EditWireAdapter> _pumpEditOnly(
  WidgetTester tester, {
  List<_Line> lines = _linesInLoadOrder,
}) async {
  final adapter = _EditWireAdapter(lines);
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = adapter;
  await _pumpEdit(tester, dio, _editShell());
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
      // Each line must carry the DB id it was loaded with (the server matches
      // by id) — NOT the other line's.
      expect(first['id'], 1, reason: 'line 1 keeps its own id');
      expect(second['id'], 2, reason: 'line 2 keeps its own id');
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

      // Build id → quantity from the ACTUAL wire payload, keyed by BOTH the
      // preserved row id and the reservation id, so a positional emission
      // would break at least one of the pairs.
      final byRowId = <Object?, num>{};
      final byReservation = <int?, num>{};
      for (final raw in items) {
        final line = raw as Map<String, dynamic>;
        byRowId[line['id']] = line['quantity'] as num;
        byReservation[line['reservation_id'] as int?] = line['quantity'] as num;
      }
      // Loaded pairing regardless of position: (id 1, qty 2) → 102 and
      // (id 2, qty 3) → 101.
      expect(byRowId[1], 2, reason: 'row id 1 stays on the qty-2 line');
      expect(byRowId[2], 3, reason: 'row id 2 stays on the qty-3 line');
      expect(
        byReservation[102],
        2,
        reason: 'reservation 102 stays on qty-2 line',
      );
      expect(
        byReservation[101],
        3,
        reason: 'reservation 101 stays on qty-3 line',
      );
    },
  );

  testWidgets(
    'GET decode + PUT: changing a line\'s ITEM keeps that line\'s original id '
    'and reservation_id, and the payload order does not shift them',
    (tester) async {
      // Serve the two same-item lines reversed, then change the FIRST loaded
      // line's item (Widget → Gadget) via the real UI, and save. The changed
      // line must still carry its own id + reservation_id; the untouched line
      // keeps its own.
      final adapter = await _pumpEditOnly(
        tester,
        lines: const [_Line(11, 2, 102), _Line(12, 3, 101)],
      );

      // Change the first row's item to Gadget (id 2). Tapping the description
      // cell opens the item dropdown; type to filter then select.
      await tester.tap(find.byType(DescriptionCell).first);
      await tester.pump();
      final editor = find.descendant(
        of: find.byType(DescriptionCell).first,
        matching: find.byType(TextField),
      );
      await tester.enterText(editor, 'Gad');
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.text('Gadget').first);
      await tester.pumpAndSettle();
      await _save(tester);

      final items = _putItems(adapter)['items']! as List<dynamic>;
      expect(items, hasLength(2), reason: 'still two lines');

      // Map each emitted line by its (preserved) id.
      final byId = <Object?, Map<String, dynamic>>{};
      for (final raw in items) {
        final line = raw as Map<String, dynamic>;
        byId[line['id']] = line;
      }
      // Line id 11 changed item to Gadget but KEEPS its id and reservation.
      expect(byId[11], isNotNull, reason: 'changed line keeps id 11');
      expect(byId[11]!['item_id'], 2, reason: 'line 11 now sells Gadget');
      expect(byId[11]!['reservation_id'], 102);
      // Line id 12 was untouched: same item, id, reservation.
      expect(byId[12], isNotNull, reason: 'untouched line keeps id 12');
      expect(byId[12]!['item_id'], 1);
      expect(byId[12]!['reservation_id'], 101);
    },
  );

  testWidgets(
    'GET decode + PUT: a NEWLY added line omits id, while the retained line '
    'keeps its original id',
    (tester) async {
      // Serve a single existing line (id 11), then add a brand-new line and
      // give it an item. The new line has no DB id yet, so it must OMIT the
      // `id` key; the retained line must keep id 11.
      final adapter = await _pumpEditOnly(
        tester,
        lines: const [_Line(11, 2, 102)],
      );

      // Add a second line and select an item for it.
      final addButton = find.text('Add Item');
      await tester.ensureVisible(addButton);
      await tester.pumpAndSettle();
      await tester.tap(addButton);
      await tester.pumpAndSettle();
      // The new line autofocuses its description cell, opening the dropdown.
      final editor = find.descendant(
        of: find.byType(DescriptionCell).last,
        matching: find.byType(TextField),
      );
      await tester.enterText(editor, 'Gad');
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.text('Gadget').first);
      await tester.pumpAndSettle();
      await _save(tester);

      final items = _putItems(adapter)['items']! as List<dynamic>;
      expect(items, hasLength(2), reason: 'retained + new line');

      final retained = items
          .cast<Map<String, dynamic>>()
          .firstWhere((l) => l['item_id'] == 1);
      final added = items
          .cast<Map<String, dynamic>>()
          .firstWhere((l) => l['item_id'] == 2);

      // Retained line keeps its id and reservation.
      expect(retained['id'], 11, reason: 'retained line keeps id 11');
      expect(retained['reservation_id'], 102);
      // New line must NOT carry an id (it has no DB row yet).
      expect(
        added.containsKey('id'),
        isFalse,
        reason: 'a newly added line must omit id',
      );
      expect(added['reservation_id'], isNull);
    },
  );
}
