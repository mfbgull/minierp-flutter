import 'package:flutter/material.dart';

/// The app logo, bundled as `assets/logo.png` (rendered from the committed
/// `logo.png`; corners floodfilled to alpha so it sits on any surface).
///
/// Replaces the generic Material glyph the shell rail used to show — the
/// sidebar mark is brand, not a stock icon (app_logo_test pins the bundle).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
  }
}
