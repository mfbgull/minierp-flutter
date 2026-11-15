import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:minierp/core/app_version.dart';

/// `kAppVersion` is a hand-maintained mirror of `pubspec.yaml`. If the two
/// drift, `X-Client-Version` silently reports the wrong build — make that
/// fail here instead of on a production request.
void main() {
  test('kAppVersion matches the pubspec version (build suffix excluded)', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^version:\s*(\S+)', multiLine: true)
        .firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml has no version: line');

    // pubspec carries a `+build` suffix; the wire version does not.
    final pubspecVersion = match!.group(1)!.split('+').first;
    expect(kAppVersion, pubspecVersion);
  });
}
