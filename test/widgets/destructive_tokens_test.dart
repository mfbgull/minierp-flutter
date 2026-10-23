// P2 UI audit — destructive actions must use the error/onError pair so
// dark-mode buttons and toasts keep their danger signal and contrast.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/core/theme/app_theme.dart';
import 'package:minierp_app/widgets/app_toast.dart';
import 'package:minierp_app/widgets/confirm_dialog.dart';

Widget harness(Widget child) => MaterialApp(theme: AppTheme.dark, home: child);

void main() {
  testWidgets('destructive confirm uses onError foreground', (tester) async {
    await tester.pumpWidget(
      harness(
        Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showConfirmDialog(
                context,
                title: 'Delete',
                message: 'Delete this record?',
                confirmLabel: 'Delete',
                destructive: true,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Delete'),
    );
    final style = button.style!;
    expect(style.backgroundColor?.resolve({}), AppTheme.dark.colorScheme.error);
    expect(
      style.foregroundColor?.resolve({}),
      AppTheme.dark.colorScheme.onError,
    );
  });

  testWidgets('error toast uses onError text', (tester) async {
    await tester.pumpWidget(
      harness(
        Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () =>
                  showAppToast(context, 'Save failed', isError: true),
              child: const Text('show'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('show'));
    await tester.pump();

    final snack = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snack.backgroundColor, AppTheme.dark.colorScheme.error);
    final text = tester.widget<Text>(find.text('Save failed'));
    expect(text.style?.color, AppTheme.dark.colorScheme.onError);
  });
}
