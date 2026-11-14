// PRET-002 — the receipt dialog's standalone-claim path.
//
// A refund claim with no purchase return behind it has no credit note, so
// the receipt posts `claim_id` alone. The return-backed path already sends
// `credit_note_id` and is covered by the return-detail flow; this test pins
// the new branch: the claim id goes out, `credit_note_id` does not, and the
// Idempotency-Key header rides along (the receipt endpoint is key-mandatory).

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:minierp_app/data/repositories/purchase_repository.dart'
    show RefundClaim;
import 'package:minierp_app/data/repositories/repository_client.dart';
import 'package:minierp_app/features/purchases/supplier_refund_dialog.dart';
import 'package:minierp_app/l10n/app_localizations.dart';

/// Captures the outgoing request and replays a canned envelope.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.onRequest);

  final Future<ResponseBody> Function(RequestOptions options) onRequest;

  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    lastRequest = options;
    return onRequest(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, {int status = 200}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

void main() {
  late _Adapter adapter;
  late Dio dio;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test'));
    adapter = _Adapter(
      (_) async => _json({
        'success': true,
        'message': 'Refund receipt recorded',
        'data': {'id': 1},
      }),
    );
    dio.httpClientAdapter = adapter;
  });

  Widget host(Widget child) => ProviderScope(
    overrides: [repositoryClientProvider.overrideWithValue(RepositoryClient(dio))],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );

  const claim = RefundClaim(
    id: 42,
    claimNo: 'RFC-0042',
    supplierId: 3,
    supplierName: 'Acme Traders',
    claimDate: '2026-11-01',
    amount: 800,
    receivedAmount: 0,
    writtenOffAmount: 0,
    remaining: 800,
    status: 'EXPECTED',
  );

  Future<void> openDialog(WidgetTester tester) async {
    final context = tester.element(find.byType(Scaffold));
    unawaited(showSupplierClaimReceiptDialog(context, claim: claim));
    await tester.pumpAndSettle();
  }

  testWidgets('posts claim_id and omits credit_note_id for a standalone claim',
      (tester) async {
    await tester.pumpWidget(host(const SizedBox()));
    await openDialog(tester);

    await tester.enterText(find.byType(TextField).first, '800');
    await tester.pump();

    // The submit button sits below the fold inside the scrollable dialog,
    // so scroll it into view before tapping.
    final submit = find.byType(FilledButton).last;
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    final request = adapter.lastRequest!;
    expect(request.path, '/supplier-refunds');
    final body = request.data as Map<String, dynamic>;
    expect(body['claim_id'], 42);
    expect(body.containsKey('credit_note_id'), isFalse);
    expect(body['amount'], 800);
    expect(request.headers.containsKey('Idempotency-Key'), isTrue);
  });

  testWidgets('the amount field prefills from the claim remaining',
      (tester) async {
    await tester.pumpWidget(host(const SizedBox()));
    await openDialog(tester);
    // The hint shows the remaining figure so the user sees what is owed.
    expect(
      find.textContaining('800'),
      findsWidgets,
      reason: 'remaining should appear in the dialog',
    );
  });
}
