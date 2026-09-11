import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';

/// Whether a row moves money/value into or out of the business. Purely a
/// presentation-layer classification: a row's model maps to exactly one
/// direction and voided/cancelled/draft rows are always [neutral]
/// (nothing realized).
enum MoneyDirection { inflow, outflow, neutral }

/// Light theme: solid green/red-100 tints (already used across the app's
/// status badges). Dark theme: green/red at 15% alpha so the onSurface
/// text stays readable over the dark surface. [MoneyDirection.neutral]
/// renders transparent so PlutoGrid's own row striping shows through.
Color moneyRowTint(BuildContext context, MoneyDirection direction) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return _tint(direction, dark);
}

/// Global on/off switch for money-direction row tinting (green = money
/// into the business, red = money out). One shared preference like the
/// theme mode; default ON, toggled from any in-scope screen's toolbar
/// FilterChip and applied everywhere at once.
final moneyDirectionTintProvider =
    StateNotifierProvider<MoneyDirectionTintNotifier, bool>(
      (ref) => MoneyDirectionTintNotifier(),
    );

class MoneyDirectionTintNotifier extends StateNotifier<bool> {
  MoneyDirectionTintNotifier() : super(true) {
    _restore();
  }

  static const _prefsKey = 'money_row_tinting';

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_prefsKey) ?? true;
  }

  /// Toggles tinting on/off and persists the choice across sessions.
  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, enabled);
  }
}

/// The toolbar FilterChip shown on every in-scope screen. Watches the
/// shared provider so toggling on any screen updates every colored
/// screen immediately.
Widget moneyTintFilterChip(
  BuildContext context,
  WidgetRef ref, {
  required AppLocalizations l10n,
}) {
  final enabled = ref.watch(moneyDirectionTintProvider);
  return FilterChip(
    label: Text(l10n.commonBenefitColors),
    selected: enabled,
    onSelected: (value) =>
        ref.read(moneyDirectionTintProvider.notifier).setEnabled(value),
  );
}

/// Builds the PlutoGrid rowColorCallback for an in-scope screen.
///
/// [directionOf] maps a row (via its hidden 'data' cell or typed cells)
/// to a [MoneyDirection]. The returned closure reads the toggle
/// provider at invocation time — not capture time — because PlutoGrid
/// copies rowColorCallback into its state manager once at mount and
/// never updates it; only the value it reads can change. When tinting
/// is off every row renders transparent (matching how the items screen
/// handles non-low-stock rows).
PlutoRowColorCallback moneyRowColorCallback(
  BuildContext context,
  WidgetRef ref,
  MoneyDirection Function(PlutoRow row) directionOf,
) {
  // PlutoGrid captures rowColorCallback into its state manager once at
  // mount and never re-reads the widget field, so the only way the tint
  // stays correct across theme switches is to resolve everything the
  // closure needs at invocation time: the toggle via ref.read, and the
  // brightness via Theme.of on this still-mounted screen context.
  // Theme.of re-resolves the inherited theme on every call, so a light/
  // dark switch (which rebuilds the grid) repaints with fresh colors.
  return (rowContext) {
    if (!ref.read(moneyDirectionTintProvider)) {
      return Colors.transparent;
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    return _tint(directionOf(rowContext.row), dark);
  };
}

Color _tint(MoneyDirection direction, bool dark) {
  if (direction == MoneyDirection.neutral) return Colors.transparent;
  return switch (direction) {
    MoneyDirection.inflow =>
      dark ? Colors.green.withValues(alpha: 0.15) : const Color(0xFFDCFCE7),
    MoneyDirection.outflow =>
      dark ? Colors.red.withValues(alpha: 0.15) : const Color(0xFFFEE2E2),
    _ => Colors.transparent,
  };
}
