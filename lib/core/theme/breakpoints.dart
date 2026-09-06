/// Responsive width breakpoints for the MiniERP layout.
///
/// Used by [AppShell] and [ScreenToolbar] to adapt between compact,
/// medium, and expanded layouts.  Values mirror the Material 3
/// compact/medium/expanded window classes.
abstract class Breakpoints {
  /// Below this width the navigation rail shows icons only.
  static const double compact = 600;

  /// At this width the navigation rail switches to extended (labels).
  static const double medium = 900;

  /// At this width additional wide-screen affordances activate.
  static const double expanded = 1200;
}
