import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/features/auth/change_password_screen.dart';

import '../../test_helpers.dart';

void main() {
  for (final entry in {
    'short': 'short123',
    'long': 'x' * 73,
    'unicode': '\u{1f600}' * 20,
  }.entries) {
    testWidgets('${entry.key} password is rejected before any HTTP write', (
      tester,
    ) async {
      final requests = <RequestOptions>[];
      final dio = createFakeDio({});
      dio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            handler.next(options);
          },
        ),
      );
      await tester.pumpWidget(
        buildTestable(const ChangePasswordScreen(), dio: dio),
      );
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Current-password-123');
      await tester.enterText(fields.at(1), entry.value);
      await tester.enterText(fields.at(2), entry.value);

      final submit = find.byIcon(Icons.lock_reset);
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(
        tester.state<FormFieldState<String>>(fields.at(1)).hasError,
        isTrue,
      );
      expect(requests, isEmpty);
    });
  }
}
