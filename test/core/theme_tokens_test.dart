// P0/P1 UI audit — design-token and semantic-color guards.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/core/theme/app_border_radius.dart';
import 'package:minierp_app/core/theme/app_colors.dart';
import 'package:minierp_app/core/theme/app_motion.dart';
import 'package:minierp_app/core/theme/app_theme.dart';
import 'package:minierp_app/core/theme/status_colors.dart';

void main() {
  group('brand surfaces', () {
    test('light theme uses the documented surfaces and border', () {
      final theme = AppTheme.light;
      expect(theme.scaffoldBackgroundColor, AppColors.lightBackground);
      expect(theme.colorScheme.surface, AppColors.lightSurface);
      expect(theme.colorScheme.primary, AppColors.lightPrimary);
      expect(theme.colorScheme.outlineVariant, AppColors.lightBorder);
    });

    test('dark theme uses the documented forest surfaces', () {
      final theme = AppTheme.dark;
      expect(theme.scaffoldBackgroundColor, AppColors.darkBackground);
      expect(theme.colorScheme.surface, AppColors.darkSurface);
      expect(theme.colorScheme.primary, AppColors.darkPrimary);
      expect(theme.colorScheme.outlineVariant, AppColors.darkBorder);
    });
  });

  group('shape tokens', () {
    test('dialogs use the 12px design radius', () {
      final shape = AppTheme.light.dialogTheme.shape;
      expect(shape, isA<RoundedRectangleBorder>());
      expect(
        (shape! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(12),
      );
      expect(AppBorderRadius.xl, 12);
    });
  });

  group('numeric typography', () {
    test('the bundled Inter family is applied to the text theme', () {
      expect(AppTheme.light.textTheme.bodyMedium?.fontFamily, 'Inter');
    });

    test('core text styles use tabular figures', () {
      final textTheme = AppTheme.light.textTheme;
      for (final style in [
        textTheme.bodySmall,
        textTheme.bodyMedium,
        textTheme.bodyLarge,
        textTheme.titleSmall,
        textTheme.titleMedium,
        textTheme.titleLarge,
        textTheme.labelMedium,
        textTheme.labelLarge,
      ]) {
        expect(style, isNotNull);
        expect(
          style!.fontFeatures?.any((feature) => feature.feature == 'tnum'),
          isTrue,
          reason: 'Every core text style should render tabular digits',
        );
      }
    });
  });

  group('semantic colors', () {
    testWidgets('warning is amber and distinct from info in both themes', (
      tester,
    ) async {
      late StatusColors light;
      late StatusColors dark;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) {
              light = StatusColors.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) {
              dark = StatusColors.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(light.warning, AppColors.warningLight);
      expect(dark.warning, AppColors.warningDark);
      expect(light.warning, isNot(light.info));
      expect(dark.warning, isNot(dark.info));
    });
  });

  group('motion budget', () {
    testWidgets('app durations collapse when animations are disabled', (
      tester,
    ) async {
      late Duration reduced;
      late Duration normal;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              reduced = AppMotion.duration(
                context,
                const Duration(milliseconds: 200),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: Builder(
            builder: (context) {
              normal = AppMotion.duration(
                context,
                const Duration(milliseconds: 200),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(reduced, Duration.zero);
      expect(normal, const Duration(milliseconds: 200));
    });
  });
}
