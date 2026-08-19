import 'package:flutter/material.dart';

/// M3 standard border radius tokens — single source of truth for corner
/// rounding across the app.
abstract final class AppBorderRadius {
  static const double none = 0;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 28;
  static const double full = 999;

  static const BorderRadius noneRadius = BorderRadius.zero;
  static const BorderRadius xsRadius = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius smRadius = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdRadius = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgRadius = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlRadius = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius fullRadius = BorderRadius.all(Radius.circular(full));

  static const BorderRadius dialog = xlRadius;
  static const BorderRadius card = mdRadius;
  static const BorderRadius textField = xsRadius;
  static const BorderRadius badge = fullRadius;
}
