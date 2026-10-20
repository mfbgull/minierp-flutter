import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/core/utils/recoverable_failure.dart';

void main() {
  test(
    'recovery diagnostics identify the operation without exposing error contents',
    () {
      final messages = <String>[];
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) messages.add(message);
      };
      addTearDown(() => debugPrint = original);
      reportRecoverableFailure(
        'session.write_token',
        StateError('secret-token-and-password'),
      );
      expect(messages.join(), contains('session.write_token'));
      expect(messages.join(), contains('StateError'));
      expect(messages.join(), isNot(contains('secret-token-and-password')));
    },
  );
}
