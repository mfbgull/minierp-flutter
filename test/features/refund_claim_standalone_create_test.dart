// UX-5 — the standalone claim creation screen.
//
// A supplier can owe money with no purchase return behind it (a short payment,
// an agreed charge). The server endpoint `POST /supplier-refunds/claims` and
// the repository method `createClaim` both existed, but NO screen called them,
// so the capability was unreachable from the app. Gull chose Option A
// (2026-11-26): build the screen.
//
// This test drives the real claims screen the way a user would: press
// "Record refund claim", pick the supplier, type the expected amount, save.
// It asserts the exact request that goes on the wire, because a claim moves no
// cash and no GL — the request body IS the whole effect.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/core/auth/auth_notifier.dart';
import 'package:minierp_app/data/models/auth_user.dart';
import 'package:minierp_app/data/models/supplier.dart' show Supplier;
import 'package:minierp_app/data/repositories/auth_repository.dart'
    show AuthRepository;
import 'package:minierp_app/data/repositories/repository_client.dart';
import 'package:minierp_app/features/purchases/refund_claims_screen.dart';
import 'package:minierp_app/l10n/app_localizations.dart';
import 'package:minierp_app/widgets/searchable_select.dart';

import '../test_helpers.dart';

class _TestAuth extends AuthNotifier {
  _TestAuth(Dio dio, AuthUser user)
    : super(AuthRepository(RepositoryClient(dio)), FakeTokenStorage()) {
    state = AuthState(status: AuthStatus.authenticated, user: user);
  }

  @override
  Future<void> restoreSession() async {}
}

AuthUser _creator({required bool canCreate}) => AuthUser(
  id: 1,
  username: 'tester',
  role: 'accountant',
  permissions: [
    const Permission(module: 'supplier_refunds', action: 'read'),
    if (canCreate)
      const Permission(module: 'supplier_refunds', action: 'create'),
  ],
);

Map<String, dynamic> _claimsScreenResponses() => {
  '/supplier-refunds/claims': pagedEnvelope([]),
  '/supplier-refunds/claims/due': {
    'success': true,
    'data': <Object?>[],
    'total_due': 0,
  },
  '/suppliers': pagedEnvelope([
    {
      'id': 42,
      'supplier_code': 'SUP-42',
      'supplier_name': 'Acme Supplies',
      'is_active': true,
    },
  ]),
};

Widget _host(Dio dio, AuthUser user) => ProviderScope(
  overrides: [
    // The auth notifier's base class builds its own repository from the
    // dioProvider chain, so point that same client at the fake Dio as well.
    // Without this, the data providers would reach the real ApiClient.
    repositoryClientProvider.overrideWithValue(RepositoryClient(dio)),
    authProvider.overrideWith((ref) => _TestAuth(dio, user)),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const Scaffold(body: RefundClaimsScreen()),
  ),
);

/// Walks the dialog: open, pick the supplier through the shared picker,
/// confirm the picker, then optionally type an amount.
Future<void> _openAndFill(
  WidgetTester tester, {
  String? amount,
  bool pickSupplier = true,
}) async {
  await tester.tap(find.text('Record refund claim').first);
  await tester.pumpAndSettle();

  if (pickSupplier) {
    await tester.tap(find.text('Select supplier'));
    await tester.pumpAndSettle();
    // The picker's option list is a SearchableSelect: the menu opens on a
    // tap of the control, and only then are the supplier rows in the tree.
    await tester.tap(find.byType(SearchableSelect<Supplier>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acme Supplies').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
  }

  if (amount != null) {
    await tester.enterText(
      find.byKey(const Key('claim-standalone-amount')),
      amount,
    );
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets(
    'records a standalone claim: supplier, date, amount and an Idempotency-Key go on the wire',
    (tester) async {
      final posts = <RequestOptions>[];
      final dio = createFakeDio(_claimsScreenResponses());
      dio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.method == 'POST') posts.add(options);
            handler.next(options);
          },
        ),
      );

      await tester.pumpWidget(_host(dio, _creator(canCreate: true)));
      await tester.pumpAndSettle();

      // The screen must offer the action at all — this is the whole finding.
      expect(
        find.text('Record refund claim'),
        findsWidgets,
        reason: 'UX-5: no control on the claims screen creates a claim',
      );

      await _openAndFill(tester, amount: '250');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(posts, hasLength(1), reason: 'one claim, one POST');
      final sent = posts.single;
      expect(sent.path, '/supplier-refunds/claims');

      final key = sent.headers['Idempotency-Key'];
      expect(key, isNotNull, reason: 'the route is key-mandatory');
      expect((key as String).isNotEmpty, isTrue);

      final body = sent.data as Map<String, dynamic>;
      expect(body['supplier_id'], 42);
      expect(body['amount'], 250);
      expect(
        (body['claim_date'] as String).length,
        10,
        reason: 'claim_date must be an ISO yyyy-mm-dd date',
      );
    },
  );

  testWidgets('refuses a missing amount before anything is sent', (
    tester,
  ) async {
    final posts = <RequestOptions>[];
    final dio = createFakeDio(_claimsScreenResponses());
    dio.interceptors.insert(
      0,
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.method == 'POST') posts.add(options);
          handler.next(options);
        },
      ),
    );

    await tester.pumpWidget(_host(dio, _creator(canCreate: true)));
    await tester.pumpAndSettle();

    await _openAndFill(tester);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(posts, isEmpty, reason: 'an empty amount must not reach the server');
  });

  testWidgets('refuses a zero amount before anything is sent', (
    tester,
  ) async {
    final posts = <RequestOptions>[];
    final dio = createFakeDio(_claimsScreenResponses());
    dio.interceptors.insert(
      0,
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.method == 'POST') posts.add(options);
          handler.next(options);
        },
      ),
    );

    await tester.pumpWidget(_host(dio, _creator(canCreate: true)));
    await tester.pumpAndSettle();

    await _openAndFill(tester, amount: '0');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(posts, isEmpty, reason: 'a zero amount must not reach the server');
  });

  testWidgets(
    'is hidden from a user without supplier_refunds create permission',
    (tester) async {
      final dio = createFakeDio(_claimsScreenResponses());

      await tester.pumpWidget(_host(dio, _creator(canCreate: false)));
      await tester.pumpAndSettle();

      expect(
        find.text('Record refund claim'),
        findsNothing,
        reason: 'the button must follow the same permission as the server',
      );
    },
  );
}
