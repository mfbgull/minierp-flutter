// GridStatusBar — the AG-Grid-style status/hint bar shown beneath the
// read-only PlutoGrid screens (the Flutter counterpart of the web app's
// keyboard affordances). States the arrow-key cell navigation and the
// Enter/F2 open-detail shortcuts registered via [rowDetailShortcutActions],
// so mouse users discover the keyboard paths they mirror.

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// A slim status bar with two keycap hints: `↑ ↓ ← →` (navigate cells) and
/// `Enter / F2` (open the focused row's detail). Self-contained — reads its
/// own labels from [AppLocalizations] — so every grid can drop it in with
/// the same instance.
class GridStatusBar extends StatelessWidget {
  const GridStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      // minHeight (not a rigid height) so a large accessibility text scale
      // grows the bar instead of clipping the hints.
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        // A top border joins the bar to the grid's bottom edge, matching
        // AG-Grid's attached status bar look.
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Center(
        heightFactor: 1,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Hint(keycap: '↑ ↓ ← →', label: l10n.commonNavigate),
            const SizedBox(width: 24),
            _Hint(keycap: 'Enter / F2', label: l10n.commonOpen),
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.keycap, required this.label});

  /// The literal keys, rendered in a small keycap (e.g. `Enter / F2`).
  final String keycap;

  /// The localized action the keys perform (e.g. "Navigate", "Open").
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Text(
            keycap,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}
