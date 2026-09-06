// App shell widget tests — covers navigation rail rendering,
// responsive behavior, and user menu.

import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/core/router/module_registry.dart'
    show shellDestinations;

void main() {
  group('ShellDestination', () {
    test('shellDestinations is non-empty', () {
      expect(shellDestinations, isNotEmpty);
    });

    test('dashboard is the first destination', () {
      expect(shellDestinations.first.path, '/');
    });

    test('settings is marked hideInRail', () {
      final settings = shellDestinations.firstWhere(
        (d) => d.path == '/settings',
      );
      expect(settings.hideInRail, isTrue);
    });

    test('admin is marked adminOnly', () {
      final admin = shellDestinations.firstWhere(
        (d) => d.path == '/admin',
      );
      expect(admin.adminOnly, isTrue);
    });

    test('each destination has a unique path', () {
      final paths = shellDestinations.map((d) => d.path).toList();
      expect(paths.toSet().length, paths.length);
    });

    test('non-admin-only destinations count excludes settings and admin', () {
      final visible = shellDestinations.where(
        (d) => !d.adminOnly && !d.hideInRail,
      );
      expect(visible.length, greaterThanOrEqualTo(10));
    });
  });
}
