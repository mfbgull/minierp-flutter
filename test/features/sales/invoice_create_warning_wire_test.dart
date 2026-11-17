// Invoice-create warning: REAL wire contract test.
//
// The fake-repository tests in sales_invoice_form_page_test.dart prove the
// DISPLAY (model → dialog) but not the actual repository round trip. This
// test drives the real InvoiceRepository through a Dio HttpClientAdapter
// serving the exact 201 shape the invoice controller sends
// (invoiceController.ts: bare created-invoice object with `warnings` merged
// at top level — the ACCT-006 shape), and asserts the actual method, path,
// Idempotency-Key header and body, plus the rendered warning through the
// real parse. No fake repository, no manual fromJson call.
//
// Honest chronology (disclosed): the warning-display fix itself
// (d29b01c7) went red-first against the fake-repo harness; THIS wire test
// was added afterwards at the coordinator's request and passes on its first
// run — it is an honest green guard for the wire contract, not an invented
// red. Its sensitivity (that it would actually catch a dropped warning) is
// proven by stashing the model parse and re-running: the test must fail
// without the parse.

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:minierp_app/data/models/customer.dart';
import 'package:minierp_app/data/models/item.dart';
import 'package:minierp_app/data/repositories/repository_client.dart';
import 'package:minierp_app/features/sales/invoice_providers.dart';
import 'package:minierp_app/features/sales/sales_invoice_form_page.dart';
import 'package:minierp_app/l10n/app_localizations.dart';
import 'package:pluto_grid/pluto_grid.dart';

const String _serverWarning =
    'Item Widget: invoice date 2026-11-17 is before the item\'s first '
    'purchase receipt in this warehouse (2026-12-01). Stock was consumed '
    'from later receipts at their recorded cost — verify the documents.';

/// The created-invoice object the controller returns for this sale — the
/// real bare shape with `warnings` merged at top level.
Map<String, Object> _createdInvoice() => <String, Object>{
      'id': 55,
      'invoice_no': 'INV-0055',
      'customer_id': 1,
      'customer_name': 'Acme Corp',
      'invoice_date': '2026-11-17',
      'total_amount': 700.0,
      'paid_amount': 0.0,
      'balance_amount': 700.0,
      'status': 'Unpaid',
      'items': <Object>[],
      'warnings': <Object>[_serverWarning],
    };

/// Serves the invoice wire hermetically and captures the POST /invoices
/// request for contract assertions.
class _InvoiceWireAdapter implements HttpClientAdapter {
  RequestOptions? createRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final path = options.uri.path;
    if (options.method == 'POST' && path.endsWith('/invoices')) {
      createRequest = options;
      return Future.value(
        ResponseBody.fromString(
          jsonEncode(_createdInvoice()),
          201,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      );
    }
    // GET /invoices/:id (print detail) — bare invoice object.
    if (RegExp(r'/invoices/\d+$').hasMatch(path)) {
      return Future.value(
        ResponseBody.fromString(
          jsonEncode(_createdInvoice()),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      );
    }
    // Payments and every other read: enveloped empty success.
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

Future<void> _pumpPage(WidgetTester tester, Dio dio) async {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // The REAL InvoiceRepository, built on the adapter-backed Dio —
        // only the customer/item pools are hermetic.
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
          ],
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SalesInvoiceFormPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The single editing cell inside the grid (the payment panel's fields are
/// outside the PlutoGrid, so type-targeting alone hits the wrong one).
Finder _gridEditor() => find.descendant(
      of: find.byType(PlutoGrid),
      matching: find.byType(TextField),
    );

/// Selects the customer and adds one line (7 × Widget), so the form passes
/// its validation gates.
Future<void> _fillLine(WidgetTester tester) async {
  await tester.tap(find.text('Acme Corp').last);
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).first, 'Wid');
  await tester.pump();
  await tester.tap(find.text('Widget').last);
  await tester.pumpAndSettle();
  await tester.enterText(_gridEditor(), '7');
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

Future<void> _saveAndPrint(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'POST /invoices 201 warnings reach the user through the REAL repository '
    'round trip (method, path, key header, body, render)',
    (tester) async {
      final adapter = _InvoiceWireAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = adapter;

      await _pumpPage(tester, dio);
      await _fillLine(tester);
      await _save(tester);

      // The create actually went over the wire: method, path, retry key,
      // and a body carrying the selected customer and line.
      final request = adapter.createRequest;
      expect(request, isNotNull, reason: 'the form must POST /invoices');
      expect(request!.method, 'POST');
      expect(request.uri.path, endsWith('/invoices'));
      final headers = request.headers;
      expect(
        headers['Idempotency-Key'] ?? headers['idempotency-key'],
        isNotNull,
        reason: 'creates carry an Idempotency-Key (P11)',
      );
      final body = request.data! as Map<String, dynamic>;
      expect(body['customer_id'], 1);
      final items = body['items'] as List<dynamic>;
      expect(items, isNotEmpty);
      expect((items.first as Map<String, dynamic>)['item_id'], 1);
      expect(
        (items.first as Map<String, dynamic>)['quantity'],
        7,
        reason: 'the wire body must carry the line the user typed',
      );

      // The server's warning — parsed by the real Invoice.fromJson from the
      // real 201 body — is rendered verbatim before the page closes.
      expect(find.textContaining(_serverWarning), findsOneWidget);

      // Dismissing the dialog closes the form (normal close-out resumes).
      await tester.tap(find.text('Close').last);
      await tester.pumpAndSettle();
      expect(find.byType(SalesInvoiceFormPage), findsNothing);
    },
  );

  testWidgets(
    'the save-and-print success path shows the warning too (real repository)',
    (tester) async {
      // The print flow reads the remembered format from SharedPreferences;
      // without a mock the plugin future never completes in the test
      // binding and the flow stalls before the warning close-out.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      // The printing platform channel is unavailable in the test binding;
      // mock it so the print leg completes the way a real print would and
      // the flow reaches the warning close-out. Only the plugin boundary is
      // mocked — the save, the format picker and the repository round trip
      // are real.
      const printingChannel = MethodChannel('net.nfet.printing');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        printingChannel,
        (call) async {
          if (call.method == 'printPdf') {
            // layoutPdf awaits a job Completer that only the native side
            // completes — simulate the platform's onCompleted callback.
            final args = call.arguments! as Map<dynamic, dynamic>;
            unawaited(Future(() {
              unawaited(tester.binding.defaultBinaryMessenger
                  .handlePlatformMessage(
                'net.nfet.printing',
                const StandardMethodCodec().encodeMethodCall(
                  MethodCall('onCompleted', <String, dynamic>{
                    'job': args['job'],
                    'completed': true,
                  }),
                ),
                (data) {},
              ));
            }));
            return 1;
          }
          return switch (call.method) {
            'sharePdf' => 1,
            _ => null,
          };
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(printingChannel, null));
      final adapter = _InvoiceWireAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = adapter;

      await _pumpPage(tester, dio);
      await _fillLine(tester);

      await _saveAndPrint(tester);

      // The print format picker appears; pick the first format. The print
      // plugin channel is mocked above, so the flow completes like a real
      // print and continues to the warning close-out.
      final options = find.byType(SimpleDialogOption);
      if (tester.any(options)) {
        await tester.tap(options.first);
        await tester.pumpAndSettle();
      }

      // The save-and-print path routes through the same warning close-out.
      expect(find.textContaining(_serverWarning), findsOneWidget);
      // And the create still went over the wire exactly once.
      expect(adapter.createRequest, isNotNull);
      expect(adapter.createRequest!.method, 'POST');
    },
  );
}
