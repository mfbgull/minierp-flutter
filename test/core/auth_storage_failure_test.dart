import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/core/auth/auth_notifier.dart';
import 'package:minierp_app/features/auth/login_screen.dart';

import '../test_helpers.dart';

class _FailingStorage extends FakeTokenStorage {
  _FailingStorage(this.failRefresh);
  final bool failRefresh;

  @override
  Future<void> writeToken(String value) async {
    if (!failRefresh) throw StateError('private access token');
    await super.writeToken(value);
  }

  @override
  Future<void> writeRefreshToken(String value) async {
    if (failRefresh) throw StateError('private refresh token');
    await super.writeRefreshToken(value);
  }
}

void main() {
  for (final failRefresh in [false, true]) {
    testWidgets(
      'login reports session storage failure instead of authenticating (refresh=$failRefresh)',
      (tester) async {
        final storage = _FailingStorage(failRefresh);
        final dio = createFakeDio({
          '/auth/login': successEnvelope({
            'token': 'private access token',
            'refreshToken': 'private refresh token',
            'user': {'id': 1, 'username': 'test-user', 'role': 'admin'},
          }),
        });
        await tester.pumpWidget(
          buildTestable(const LoginScreen(), dio: dio, tokenStorage: storage),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField).at(0), 'test-user');
        await tester.enterText(
          find.byType(TextFormField).at(1),
          'test-password',
        );
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Could not save your session. Check secure storage and sign in again.',
          ),
          findsOneWidget,
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(LoginScreen)),
        );
        expect(container.read(authProvider).isAuthenticated, isFalse);
        expect(storage.token, isNull);
        expect(storage.refreshToken, isNull);
        expect(find.textContaining('private access token'), findsNothing);
        expect(find.textContaining('private refresh token'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
