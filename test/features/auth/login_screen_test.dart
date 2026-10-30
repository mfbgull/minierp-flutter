// P0/P1 UI audit — release builds must not advertise default
// credentials; the password field needs a reveal control; login errors
// must be announced.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/features/auth/login_screen.dart';
import 'package:minierp_app/widgets/app_logo.dart';

import '../../test_helpers.dart';

void main() {
  testWidgets('login does not show default credentials', (tester) async {
    await tester.pumpWidget(buildTestable(const LoginScreen()));
    await tester.pumpAndSettle();

    expect(find.textContaining('admin123'), findsNothing);
    expect(find.textContaining('Default login'), findsNothing);
    // Branding: the login card must show the app logo, not a generic
    // Material glyph (app_logo regression net for the login brand slot).
    expect(find.byType(AppLogo), findsOneWidget);
    expect(tester.widget<AppLogo>(find.byType(AppLogo)).size, 48);
  });

  testWidgets('password visibility can be toggled', (tester) async {
    await tester.pumpWidget(buildTestable(const LoginScreen()));
    await tester.pumpAndSettle();

    TextField passwordField() =>
        tester.widget<TextField>(find.byType(TextField).last);

    expect(passwordField().obscureText, isTrue);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();

    expect(passwordField().obscureText, isFalse);
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
  });

  testWidgets('login error banner is a live region', (tester) async {
    await tester.pumpWidget(
      buildTestable(
        const Scaffold(body: LoginErrorBanner(message: 'Invalid login')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Invalid login'), findsOneWidget);
    final liveRegions = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .where((widget) => widget.properties.liveRegion == true);
    expect(liveRegions, isNotEmpty);
  });
}
