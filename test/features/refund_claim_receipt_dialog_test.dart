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

  testWidgets(
      'a standalone claim retains its key on retry and rotates it when the amount changes',
      (tester) async {
    // A network-timeout retry must reuse the key (the write may have landed);
    // an edited amount must mint a new one (it is a different receipt).
    final requests = <RequestOptions>[];
    adapter = _Adapter((options) async {
      requests.add(options);
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
      );
    });
    dio.httpClientAdapter = adapter;

    await tester.pumpWidget(host(const SizedBox()));
    await openDialog(tester);
    final amount = find.byType(TextField).first;
    final submit = find.byType(FilledButton).last;

    await tester.enterText(amount, '400');
    await tester.pump();
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    // Same amount again: the retry reuses the first key.
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    // Edited amount: a new key.
    await tester.enterText(amount, '500');
    await tester.pump();
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(requests, hasLength(3));
    final keys = requests
        .map((r) => r.headers['Idempotency-Key'])
        .toList(growable: false);
    expect(keys[0], isA<String>());
    expect(keys[1], keys[0], reason: 'an unchanged retry reuses the key');
    expect(keys[2], isNot(keys[0]), reason: 'an edited amount mints a new key');
    // The claim id rides in every attempt so the server settles the claim.
    for (final request in requests) {
      expect(request.data['claim_id'], 42);
    }
  });
}
