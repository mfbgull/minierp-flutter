import 'package:flutter/material.dart';

/// Design tokens from docs/DESIGN.md (PORTING.md §8) — source of truth is
/// styles/variables.css in the reference kit.
abstract final class AppTheme {
  // Light palette
  static const Color _bgLight = Color(0xFFFAFBFC);
  static const Color _surfaceLight = Color(0xFFFFFFFF);
  static const Color _borderLight = Color(0xFFE5E7EB);
  static const Color _textPrimaryLight = Color(0xFF111827);
  static const Color _textSecondaryLight = Color(0xFF6B7280);
  static const Color _accentLight = Color(0xFF059669);
  static const Color _errorLight = Color(0xFFEF4444);

  // Dark palette
  static const Color _bgDark = Color(0xFF0A0F0D);
  static const Color _surfaceDark = Color(0xFF111916);
  static const Color _surfaceElevatedDark = Color(0xFF1A2820);
  static const Color _borderDark = Color(0xFF2D3D36);
  static const Color _textPrimaryDark = Color(0xFFECFEED);
  static const Color _textSecondaryDark = Color(0xFF86EFAC);
  static const Color _accentDark = Color(0xFF10B981);
  static const Color _errorDark = Color(0xFFEF4444);

  static ThemeData get light => _build(
        brightness: Brightness.light,
        background: _bgLight,
        surface: _surfaceLight,
        border: _borderLight,
        textPrimary: _textPrimaryLight,
        textSecondary: _textSecondaryLight,
        accent: _accentLight,
        error: _errorLight,
      );

  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        background: _bgDark,
        surface: _surfaceDark,
        border: _borderDark,
        textPrimary: _textPrimaryDark,
        textSecondary: _textSecondaryDark,
        accent: _accentDark,
        error: _errorDark,
        elevatedSurface: _surfaceElevatedDark,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
    required Color accent,
    required Color error,
    Color? elevatedSurface,
  }) {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: surface,
      secondary: textSecondary,
      onSecondary: textPrimary,
      error: error,
      onError: surface,
      surface: surface,
      onSurface: textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      dividerColor: border,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: elevatedSurface ?? surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: accent, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      textTheme: ThemeData(brightness: brightness).textTheme.apply(
            bodyColor: textPrimary,
            displayColor: textPrimary,
          ),
    );
  }
}
