// Server-side pagination bar for the PlutoGrid list screens (PORTING.md
// §6): PlutoGrid's built-in footer paginates client-side, so paged
// endpoints (customers today, suppliers/POs/payments next) get this bar
// instead — page indicator, total count, per-page selector, prev/next.

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

class ServerPaginationBar extends StatelessWidget {
  const ServerPaginationBar({
    super.key,
    required this.page,
    required this.totalPages,
    required this.totalItems,
    required this.hasNext,
    required this.hasPrev,
    required this.limit,
    required this.onPageChanged,
    required this.onLimitChanged,
    required this.itemLabel,
  });

  final int page;
  final int totalPages;
  final int totalItems;
  final bool hasNext;
  final bool hasPrev;
  final int limit;
  final ValueChanged<int> onPageChanged;

  /// Changing the per-page size — callers reset to page 1.
  final ValueChanged<int> onLimitChanged;

  /// Localized plural label for the row type, e.g. `l10n.customersCustomers`.
  final String itemLabel;

  static const List<int> pageSizes = [10, 25, 50, 100];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(8),
        ),
      ),
      child: Row(
        children: [
          Text(
            '${l10n.commonPage} $page ${l10n.commonOf} $totalPages',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(width: 12),
          Text(
            '· $totalItems $itemLabel',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const Spacer(),
          Text(
            l10n.commonPerpage,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(width: 4),
          DropdownButton<int>(
            // Guard: DropdownButton asserts in debug if the value isn't in
            // the items list — a future caller's non-standard limit falls
            // back to showing the first size.
            value: pageSizes.contains(limit) ? limit : pageSizes.first,
            isDense: true,
            underline: const SizedBox.shrink(),
            items: [
              for (final size in pageSizes)
                DropdownMenuItem(value: size, child: Text('$size')),
            ],
            onChanged: (v) {
              if (v != null && v != limit) onLimitChanged(v);
            },
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: l10n.commonPrevious,
            icon: const Icon(Icons.chevron_left),
            visualDensity: VisualDensity.compact,
            onPressed: hasPrev ? () => onPageChanged(page - 1) : null,
          ),
          IconButton(
            tooltip: l10n.commonNext,
            icon: const Icon(Icons.chevron_right),
            visualDensity: VisualDensity.compact,
            onPressed: hasNext ? () => onPageChanged(page + 1) : null,
          ),
        ],
      ),
    );
  }
}
