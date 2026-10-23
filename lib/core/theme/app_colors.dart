import 'package:flutter/material.dart';

/// Brand and semantic colors from `docs/DESIGN.md`.
///
/// The M3 [ColorScheme] is still generated from the emerald seed, then the
/// documented surfaces, primary, border and semantic roles are overlaid so
/// the shipped UI and the design spec share one source of truth.
abstract final class AppColors {
  // Light — clean professional.
  static const Color lightBackground = Color(0xFFFAFBFC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceMuted = Color(0xFFF3F4F6);
  static const Color lightBorder = Color(0xFFE5E7EB);
  static const Color lightText = Color(0xFF111827);
  static const Color lightTextSecondary = Color(0xFF6B7280);
  static const Color lightPrimary = Color(0xFF059669);
  static const Color lightPrimaryHover = Color(0xFF047857);
  static const Color lightPrimaryLight = Color(0xFFD1FAE5);
  static const Color lightSecondary = Color(0xFF475569);

  // Dark — Supabase-inspired forest.
  static const Color darkBackground = Color(0xFF0A0F0D);
  static const Color darkSurface = Color(0xFF111916);
  static const Color darkSurfaceLow = Color(0xFF0E1512);
  static const Color darkSurfaceElevated = Color(0xFF1A2820);
  static const Color darkBorder = Color(0xFF2D3D36);
  static const Color darkText = Color(0xFFECFEED);
  static const Color darkTextSecondary = Color(0xFF86EFAC);
  static const Color darkPrimary = Color(0xFF10B981);
  static const Color darkPrimaryHover = Color(0xFF34D399);
  static const Color darkPrimaryDim = Color(0xFF065F46);
  static const Color darkSecondary = Color(0xFF86EFAC);

  // Semantic roles.
  static const Color successLight = Color(0xFF10B981);
  static const Color successDark = Color(0xFF34D399);
  static const Color warningLight = Color(0xFFF59E0B);
  static const Color warningDark = Color(0xFFFBBF24);
  static const Color errorLight = Color(0xFFEF4444);
  static const Color errorDark = Color(0xFFFB7185);
}
