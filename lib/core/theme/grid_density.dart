import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-selectable data density for PlutoGrid screens (DESIGN.md §Data
/// Density Options). Reports and CRUD lists share the same preference so a
/// dense screen stays readable for the person using it.
enum GridDensity {
  compact(rowHeight: 32, headerHeight: 36, fontSize: 13, horizontalPadding: 8),
  standard(rowHeight: 40, headerHeight: 40, fontSize: 14),
  comfortable(
    rowHeight: 48,
    headerHeight: 48,
    fontSize: 14,
    horizontalPadding: 12,
  );

  const GridDensity({
    required this.rowHeight,
    required this.headerHeight,
    required this.fontSize,
    this.horizontalPadding,
  });

  final double rowHeight;
  final double headerHeight;
  final double fontSize;

  /// Null keeps PlutoGrid's own cell padding.
  final double? horizontalPadding;
}

/// Persisted grid density — local-only, like the theme mode.
final gridDensityProvider =
    StateNotifierProvider<GridDensityNotifier, GridDensity>(
      (ref) => GridDensityNotifier(),
    );

class GridDensityNotifier extends StateNotifier<GridDensity> {
  GridDensityNotifier() : super(GridDensity.standard) {
    _restore();
  }

  static const _prefsKey = 'grid_density';

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      for (final density in GridDensity.values) {
        if (density.name == saved) {
          state = density;
          break;
        }
      }
    } on Exception {
      // Defaults are valid when preferences are unavailable.
    }
  }

  Future<void> setDensity(GridDensity density) async {
    if (density == state) return;
    state = density;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, density.name);
    } on Exception {
      // The in-memory choice still applies for this session.
    }
  }
}

/// Exposes the selected density to widgets that cannot read Riverpod
/// directly (notably [plutoGridConfigurationFor], which takes a context).
/// It sits above the router so every screen inherits the same value.
class GridDensityScope extends InheritedWidget {
  const GridDensityScope({
    super.key,
    required this.density,
    required super.child,
  });

  final GridDensity density;

  static GridDensity of(BuildContext context) =>
      maybeOf(context) ?? GridDensity.standard;

  static GridDensity? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GridDensityScope>()?.density;

  @override
  bool updateShouldNotify(GridDensityScope oldWidget) =>
      density != oldWidget.density;
}
