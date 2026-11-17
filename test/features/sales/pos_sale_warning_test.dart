// POS sale warnings — server warning strings must reach the user on a
// successful sale.
//
// The server already emits `warnings: string[]` on the invoice-create
// response (ACCT-006, invoiceController.ts:279) and the BUG-013 R1/R2 owner
// decisions require damaged/under-coverage stock warnings to ride the same
// existing field on the sale/invoice response (DECISIONS.md D28/D28a). The
// POS client parsed only `data` and dropped `warnings` silently.
//
// These are real request/response widget tests: a Dio HttpClientAdapter
// serves the enveloped 201 the POS controller actually sends
// ({success, message, data, warnings}) and the real PosRepository parse and
// PosScreen UI run against it. The warning string is displayed verbatim —
// the server authors the wording, the client adds none.
//
// The warning may ride the envelope top level or inside `data` (the ACCT-006
// precedent merges it into the top-level object); the client accepts both.
// PI owns the server field placement — confirmed location pins the final
// contract (coordinator question raised).

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:minierp_app/data/repositories/repository_client.dart';
import 'package:minierp_app/features/sales/pos_models.dart';
import 'package:minierp_app/features/sales/pos_providers.dart';
import 'package:minierp_app/features/sales/pos_screen.dart';
import 'package:minierp_app/l10n/app_localizations.dart';

const String _warningText =
    'Item Test Item: sale consumed DAMAGED stock at reduced value — verify.';

PosItem _testItem() => PosItem(
      id: 1,
      itemCode: 'ITEM001',
      itemName: 'Test Item',
      unitOfMeasure: 'Nos',
      standardSellingPrice: 100.0,
      currentStock: 50,
    );

PosWarehouse _testWarehouse() => const PosWarehouse(
      id: 1,
      warehouseCode: 'WH-MAIN',
      warehouseName: 'Main Warehouse',
    );

/// The enveloped 201 the POS controller sends on a completed sale
/// (posController.ts). [warningsAtData] moves the warnings inside `data` to
/// pin both accepted locations of the existing `warnings: string[]` field.
Map<String, Object> _saleBody({
  required bool withWarnings,
  bool warningsAtData = false,
}) {
  final warnings = withWarnings ? [_warningText] : null;
  return <String, Object>{
    'success': true,
    'message': 'POS sale completed successfully',
    'data': <String, Object>{
      'transaction_no': 'POS-0007',
      'sale_date': '2026-11-17',
      'warehouse_id': 1,
      'warehouse_name': 'Main Warehouse',
      'customer_name': 'Walk-in',
      'items': <Object>[
        <String, Object>{
          'sale_id': 7,
          'sale_no': 'S-0007',
          'item_code': 'ITEM001',
          'item_name': 'Test Item',
          'unit_of_measure': 'Nos',
          'quantity': 1,
          'unit_price': 100.0,
          'line_total': 100.0,
        },
      ],
      'subtotal': 100.0,
      'total': 100.0,
      'cash_received': 100.0,
      'change': 0.0,
      'items_count': 1,
      'sale_ids': <Object>[7],
      if (withWarnings && warningsAtData) 'warnings': warnings!,
    },
    if (withWarnings && !warningsAtData) 'warnings': warnings!,
  };
}

/// Serves the POS routes hermetically: the sale POST returns the canned 201
/// body; the screen's incidental reads return empty successes.
class _PosAdapter implements HttpClientAdapter {
  _PosAdapter(this.saleBody);

  final Object saleBody;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final path = options.uri.path;
    if (path.endsWith('/pos/sale')) {
      return Future.value(
        ResponseBody.fromString(
          jsonEncode(saleBody),
          201,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      );
    }
    // Transactions / tax-rates / any other read: empty enveloped success.
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

/// Pumps the real [PosScreen] against the real repository stack, with only
/// the network hermetic. The warehouse is pre-selected (the user-picks-a-
/// warehouse step is not what these tests exercise).
Future<void> _pumpPos(
  WidgetTester tester, {
  required Map<String, Object> saleBody,
}) async {
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = _PosAdapter(saleBody);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        repositoryClientProvider.overrideWithValue(RepositoryClient(dio)),
        posCatalogProvider.overrideWith((ref) => [_testItem()]),
        posWarehousesProvider.overrideWith((ref) => [_testWarehouse()]),
        posWarehouseProvider.overrideWith((ref) => 1),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: PosScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Adds the item to the cart and completes the sale through the real UI.
Future<void> _completeSale(WidgetTester tester) async {
  await tester.tap(find.text('Test Item').first);
  await tester.pumpAndSettle();
  expect(find.text('Cart (1 items)'), findsOneWidget);

  await tester.tap(find.text('Complete Sale'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a successful sale with warnings shows them verbatim '
      '(envelope-level warnings)', (tester) async {
    await _pumpPos(tester, saleBody: _saleBody(withWarnings: true));
    await _completeSale(tester);

    // The receipt dialog stays the normal success dialog, and the server's
    // warning string is displayed verbatim (no client-authored wording).
    expect(find.text('Sale Completed'), findsOneWidget);
    expect(find.textContaining(_warningText), findsOneWidget);
  });

  testWidgets('a successful sale with data-level warnings shows them too '
      '(ACCT-006 merge shape)', (tester) async {
    await _pumpPos(
      tester,
      saleBody: _saleBody(withWarnings: true, warningsAtData: true),
    );
    await _completeSale(tester);

    expect(find.text('Sale Completed'), findsOneWidget);
    expect(find.textContaining(_warningText), findsOneWidget);
  });

  testWidgets('a normal successful sale shows no warning UI',
      (tester) async {
    await _pumpPos(tester, saleBody: _saleBody(withWarnings: false));
    await _completeSale(tester);

    // Normal success remains normal: the dialog appears with no warning
    // rows and no warning text.
    expect(find.text('Sale Completed'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    expect(find.textContaining('DAMAGED'), findsNothing);
  });
}
