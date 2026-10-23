import 'package:flutter/material.dart';

import 'app_border_radius.dart';
import 'app_colors.dart';

/// M3 theme — generates the full tonal palette from a single seed color,
/// then overlays the brand surfaces and semantic roles from DESIGN.md.
abstract final class AppTheme {
  static const Color _seedColor = Color(0xFF059669);

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final baseScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: brightness,
    );
    final colorScheme = isDark
        ? baseScheme.copyWith(
            primary: AppColors.darkPrimary,
            onPrimary: const Color(0xFF04120C),
            primaryContainer: AppColors.darkPrimaryDim,
            onPrimaryContainer: AppColors.darkText,
            secondary: AppColors.darkSecondary,
            onSecondary: const Color(0xFF04120C),
            surface: AppColors.darkSurface,
            onSurface: AppColors.darkText,
            onSurfaceVariant: AppColors.darkTextSecondary,
            outlineVariant: AppColors.darkBorder,
            error: AppColors.errorDark,
            onError: const Color(0xFF3B0A13),
            surfaceContainerLowest: AppColors.darkBackground,
            surfaceContainerLow: AppColors.darkSurfaceLow,
            surfaceContainer: AppColors.darkSurface,
            surfaceContainerHigh: AppColors.darkSurfaceElevated,
            surfaceContainerHighest: AppColors.darkSurfaceElevated,
          )
        : baseScheme.copyWith(
            primary: AppColors.lightPrimary,
            onPrimary: Colors.white,
            primaryContainer: AppColors.lightPrimaryLight,
            onPrimaryContainer: const Color(0xFF064E3B),
            secondary: AppColors.lightSecondary,
            onSecondary: Colors.white,
            surface: AppColors.lightSurface,
            onSurface: AppColors.lightText,
            onSurfaceVariant: AppColors.lightTextSecondary,
            outlineVariant: AppColors.lightBorder,
            error: AppColors.errorLight,
            onError: Colors.white,
            surfaceContainerLowest: AppColors.lightSurface,
            surfaceContainerLow: AppColors.lightBackground,
            surfaceContainer: AppColors.lightSurfaceMuted,
            surfaceContainerHigh: AppColors.lightSurfaceMuted,
            surfaceContainerHighest: AppColors.lightSurfaceMuted,
          );

    final baseTextTheme = ThemeData(
      brightness: brightness,
      useMaterial3: true,
    ).textTheme;
    final textTheme = _withTabularFigures(
      baseTextTheme,
    ).apply(fontFamily: 'Inter');

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: isDark
          ? AppColors.darkBackground
          : AppColors.lightBackground,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppBorderRadius.card,
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: AppBorderRadius.textField),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppBorderRadius.textField,
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppBorderRadius.textField,
          borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style:
            FilledButton.styleFrom(
              shape: const RoundedRectangleBorder(
                borderRadius: AppBorderRadius.smRadius,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ).copyWith(
              side: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.focused)) {
                  return BorderSide(color: colorScheme.onPrimary, width: 2);
                }
                return null;
              }),
            ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            OutlinedButton.styleFrom(
              shape: const RoundedRectangleBorder(
                borderRadius: AppBorderRadius.smRadius,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ).copyWith(
              side: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.focused)) {
                  return BorderSide(color: colorScheme.primary, width: 2);
                }
                return null;
              }),
            ),
      ),
      textButtonTheme: TextButtonThemeData(
        style:
            TextButton.styleFrom(
              shape: const RoundedRectangleBorder(
                borderRadius: AppBorderRadius.smRadius,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ).copyWith(
              side: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.focused)) {
                  return BorderSide(color: colorScheme.primary, width: 2);
                }
                return null;
              }),
            ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: AppBorderRadius.dialog,
        ),
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(
          borderRadius: AppBorderRadius.smRadius,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      // The M3 NavigationRail defaults to a 256px extended width; the
      // previous custom rail was 180px. Keep 180 so module grids keep
      // their viewport width (spec 3.2 — same width, M3 look).
      navigationRailTheme: const NavigationRailThemeData(minExtendedWidth: 180),
      splashFactory: InkSparkle.splashFactory,
    );
  }

  /// Every core text style gets tabular digits so money and quantity
  /// columns align across tables, cards and dialogs.
  static TextTheme _withTabularFigures(TextTheme theme) {
    TextStyle? tabular(TextStyle? style) =>
        style?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

    return theme.copyWith(
      displayLarge: tabular(theme.displayLarge),
      displayMedium: tabular(theme.displayMedium),
      displaySmall: tabular(theme.displaySmall),
      headlineLarge: tabular(theme.headlineLarge),
      headlineMedium: tabular(theme.headlineMedium),
      headlineSmall: tabular(theme.headlineSmall),
      titleLarge: tabular(theme.titleLarge),
      titleMedium: tabular(theme.titleMedium),
      titleSmall: tabular(theme.titleSmall),
      bodyLarge: tabular(theme.bodyLarge),
      bodyMedium: tabular(theme.bodyMedium),
      bodySmall: tabular(theme.bodySmall),
      labelLarge: tabular(theme.labelLarge),
      labelMedium: tabular(theme.labelMedium),
      labelSmall: tabular(theme.labelSmall),
    );
  }
}
