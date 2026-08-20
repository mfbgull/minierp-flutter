import 'package:flutter/material.dart';

import '../../data/models/search_result.dart' show SearchAction, SearchResult;
import 'search_registry.dart' show entityIcon;

String _prettyKey(String k) => k
    .replaceAll('_', ' ')
    .replaceAllMapped(RegExp(r'\b\w'), (m) => m[0] ?? '');

class SearchActionPanel extends StatelessWidget {
  const SearchActionPanel({
    super.key,
    required this.result,
    required this.onAction,
  });

  final SearchResult result;
  final void Function(SearchAction) onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = entityIcon[result.type] ?? Icons.label_outline;

    final metaRows = [
      for (final e in result.metadata.entries.take(4))
        if (e.value != null && e.value.toString().isNotEmpty)
          MapEntry(_prettyKey(e.key), e.value.toString()),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 28, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (result.subtitle.isNotEmpty)
                      Text(
                        result.subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (metaRows.isNotEmpty) ...[
            const SizedBox(height: 16),
            for (final r in metaRows)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(
                        r.key,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        r.value,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
          ],
          const Divider(),
          const SizedBox(height: 8),
          Text(
            'ACTIONS',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          if (result.actions.isEmpty)
            Text(
              'No actions available',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            for (final a in result.actions)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    onPressed: () => onAction(a),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(a.label),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
