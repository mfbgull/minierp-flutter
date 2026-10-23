import 'package:flutter/material.dart';

/// Motion helpers that honor the OS reduced-motion preference.
///
/// Product-owned animations (snap, crossfade, bar transitions) route their
/// durations through [duration]; framework animations follow the platform
/// setting on their own.
abstract final class AppMotion {
  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);

  static Duration duration(BuildContext context, Duration base) =>
      reduced(context) ? Duration.zero : base;
}
