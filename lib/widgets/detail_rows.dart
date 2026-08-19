// Shared detail-dialog row widgets — the read-only detail dialogs
// (customer, supplier, item, purchase order, statement) all render the
// same two building blocks: a label:value info grid and a row of labeled
// value tiles. Extract them so the dialogs only supply the data.

import 'package:flutter/material.dart';

import 'detail_labels.dart' show detailSectionLabel;
import 'package:minierp_app/core/theme/app_border_radius.dart';

/// A label:value info grid — each row is a fixed-width label (the same
/// [detailSectionLabel] used by the dialogs) beside the value.
class DetailInfoRows extends StatelessWidget {
  const DetailInfoRows({super.key, required this.rows, this.labelWidth = 150});

  /// (label, value) pairs, rendered in order.
  final List<(String, String)> rows;

  /// Label column width (the item dialog uses 140, the others 150).
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: labelWidth,
                  child: detailSectionLabel(context, label),
                ),
                Expanded(
                  child: Text(
                    value,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One labeled tile in a [DetailTiles] row — an optional emphasized weight
/// and an optional accent color (e.g. the error red used for negative
/// balances).
class DetailTile {
  const DetailTile(
    this.label,
    this.value, {
    this.emphasize = false,
    this.color,
  });

  final String label;
  final String value;

  /// Renders the value at w700 instead of w500.
  final bool emphasize;

  /// Optional value color (e.g. `scheme.error` for a negative balance).
  final Color? color;
}

/// A row of labeled value tiles — the balance/credit/pricing tiles shared
/// by the detail dialogs and the statement dialog.
class DetailTiles extends StatelessWidget {
  const DetailTiles({super.key, required this.tiles});

  final List<DetailTile> tiles;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          for (final tile in tiles)
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: AppBorderRadius.smRadius,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tile.label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tile.value,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: tile.emphasize
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: tile.color,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
