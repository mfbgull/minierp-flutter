// BUG-008 — the refund-claim receipts list.
//
// A claim row opens the receipts that settled it (GET /supplier-refunds with
// the claim_id filter) so the user can void a wrong one. The void button
// shows only with the `supplier_refunds.void` permission and only on a POSTED
// receipt; a voided receipt stays listed for audit.
//
// The void flow itself (dialog + 409 cash blockers) is covered by
// refund_claim_write_off_test.dart and cash_blockers_write_path_test.dart.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:minierp_app/core/auth/auth_notifier.dart';
import 'package:minierp_app/data/models/auth_user.dart';
import 'package:minierp_app/data/repositories/auth_repository.dart'
    show AuthRepository;
import 'package:minierp_app/data/repositories/purchase_repository.dart'
    show RefundClaim;
import 'package:minierp_app/data/repositories/repository_client.dart';
import 'package:minierp_app/features/purchases/refund_claim_receipts_dialog.dart';
import 'package:minierp_app/l10n/app_localizations.dart';

import '../test_helpers.dart' show FakeTokenStorage;

class _TestAuth extends AuthNotifier {
  _TestAuth(Dio dio, AuthUser user)
    : super(AuthRepository(RepositoryClient(dio)), FakeTokenStorage()) {
    state = AuthState(status: AuthStatus.authenticated, user: user);
  }
  @override
  Future<void> restoreSession() async {}
}

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

Map<String, dynamic> _receipt({
  required int id,
  required String no,
  required String status,
  num amount = 40,
}) => {
  'id': id,
  'refund_no': no,
  'refund_date': '2026-08-05',
  'supplier_id': 3,
  'supplier_name': 'Acme Traders',
  'credit_note_id': null,
  'credit_no': null,
  'return_id': null,
  'amount': amount,
  'payment_method': 'cash',
  'reference_no': null,
  'status': status,
  'voided_at': null,
  'voided_by': null,
  'voided_reason': null,
  'created_by': 1,
  'created_at': '2026-08-05 10:00:00',
};

Object _page(List<Map<String, dynamic>> rows) => {
  'success': true,
  'data': rows,
  'pagination': {
    'currentPage': 1,
    'totalPages': 1,
    'totalItems': rows.length,
    'hasNext': false,
    'hasPrev': false,
  },
};

void main() {
  late Dio dio;
  late _Adapter adapter;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test'));
  });

  const claim = RefundClaim(
    id: 42,
    claimNo: 'RFC-0042',
    supplierId: 3,
    supplierName: 'Acme Traders',
    claimDate: '2026-11-01',
    amount: 800,
    receivedAmount: 100,
    writtenOffAmount: 0,
    remaining: 700,
    status: 'PARTIAL',
  );

  AuthUser user({bool canVoid = true, bool admin = false}) => AuthUser(
    id: 1,
    username: 'tester',
    role: admin ? 'admin' : 'accountant',
    permissions: [
      const Permission(module: 'supplier_refunds', action: 'read'),
      if (canVoid) const Permission(module: 'supplier_refunds', action: 'void'),
    ],
  );

  Widget host(Widget child, AuthUser authUser) => ProviderScope(
    overrides: [
      repositoryClientProvider.overrideWithValue(RepositoryClient(dio)),
      authProvider.overrideWith((ref) => _TestAuth(dio, authUser)),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );

  Future<void> openDialog(WidgetTester tester) async {
    final context = tester.element(find.byType(Scaffold));
    unawaited(showRefundClaimReceiptsDialog(context, claim: claim));
    await tester.pumpAndSettle();
  }

  testWidgets('lists the receipts for the claim via the claim_id filter',
      (tester) async {
    adapter = _Adapter(
      (_) async => _json(
        _page([
          _receipt(id: 7, no: 'SR-0007', status: 'POSTED', amount: 40),
          _receipt(id: 8, no: 'SR-0008', status: 'VOIDED', amount: 60),
        ]),
      ),
    );
    dio.httpClientAdapter = adapter;

    await tester.pumpWidget(host(const SizedBox(), user()));
    await openDialog(tester);

    final request = adapter.lastRequest!;
    expect(request.path, '/supplier-refunds');
    expect(request.queryParameters['claim_id'], 42);

    expect(find.text('SR-0007'), findsOneWidget);
    expect(find.text('SR-0008'), findsOneWidget);
  });

  testWidgets('shows the empty message when the claim has no receipts',
      (tester) async {
    adapter = _Adapter((_) async => _json(_page([])));
    dio.httpClientAdapter = adapter;

    await tester.pumpWidget(host(const SizedBox(), user()));
    await openDialog(tester);

    expect(find.textContaining('No refund receipts'), findsOneWidget);
  });

  testWidgets('offers a void button on a POSTED receipt when permitted',
      (tester) async {
    adapter = _Adapter(
      (_) async => _json(
        _page([_receipt(id: 7, no: 'SR-0007', status: 'POSTED')]),
      ),
    );
    dio.httpClientAdapter = adapter;

    await tester.pumpWidget(host(const SizedBox(), user(canVoid: true)));
    await openDialog(tester);

    expect(find.byIcon(Icons.undo), findsOneWidget);
  });

  testWidgets('hides the void button without the void permission',
      (tester) async {
    adapter = _Adapter(
      (_) async => _json(
        _page([_receipt(id: 7, no: 'SR-0007', status: 'POSTED')]),
      ),
    );
    dio.httpClientAdapter = adapter;

    await tester.pumpWidget(host(const SizedBox(), user(canVoid: false)));
    await openDialog(tester);

    // The row is visible; only the action is gone.
    expect(find.text('SR-0007'), findsOneWidget);
    expect(find.byIcon(Icons.undo), findsNothing);
  });

  testWidgets('a voided receipt keeps no void button but stays listed',
      (tester) async {
    adapter = _Adapter(
      (_) async => _json(
        _page([_receipt(id: 8, no: 'SR-0008', status: 'VOIDED')]),
      ),
    );
    dio.httpClientAdapter = adapter;

    await tester.pumpWidget(host(const SizedBox(), user(canVoid: true)));
    await openDialog(tester);

    expect(find.text('SR-0008'), findsOneWidget);
    expect(find.byIcon(Icons.undo), findsNothing);
  });

  testWidgets('a failed load shows the message and a retry', (tester) async {
    adapter = _Adapter(
      (options) async => _json(
        {
          'error': {'message': 'Server unavailable'},
        },
        status: 500,
      ),
    );
    dio.httpClientAdapter = adapter;

    await tester.pumpWidget(host(const SizedBox(), user()));
    await openDialog(tester);

    expect(find.textContaining('Server unavailable'), findsOneWidget);
    expect(find.textContaining('Retry'), findsOneWidget);
  });
}
